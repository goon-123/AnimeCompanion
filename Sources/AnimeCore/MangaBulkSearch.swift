import Foundation

public enum MangaBulkSearchEvent: Sendable {
    case started(MangaSourceReference)
    case results(MangaSourceReference, SourceMangaPage)
    case failed(MangaSourceReference, String)
}

/// Streams independent first pages while keeping active source requests bounded.
public enum MangaBulkSearch {
    public static let pinnedOnlyKey = "manga.search.pinnedOnly.v1"

    public static func sources(in installations: [InstalledMangaExtension], allowMature: Bool,
                               pinned: Set<String>, pinnedOnly: Bool) -> [MangaSourceReference] {
        var seen = Set<String>()
        return installations.filter { $0.enabled && (allowMature || !$0.descriptor.adult) }
            .flatMap { entry in entry.sources.map { MangaSourceReference(installation: entry, source: $0) } }
            .filter { (!pinnedOnly || pinned.contains($0.id)) && seen.insert($0.id).inserted }
            .sorted {
                if pinned.contains($0.id) != pinned.contains($1.id) { return pinned.contains($0.id) }
                let order = $0.name.localizedStandardCompare($1.name)
                if order != .orderedSame { return order == .orderedAscending }
                if $0.language != $1.language { return $0.language < $1.language }
                return $0.id < $1.id
            }
    }

    @MainActor
    public static func run(query: String, sources: [MangaSourceReference],
                           search: @escaping @MainActor @Sendable (MangaSourceReference, String) async throws -> SourceMangaPage,
                           receive: @MainActor (MangaBulkSearchEvent) -> Void) async {
        let text = String(query.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))
        guard !text.isEmpty, !Task.isCancelled else { return }
        var seen = Set<String>()
        var iterator = sources.filter { seen.insert($0.id).inserted }.makeIterator()
        await withTaskGroup(of: MangaBulkSearchEvent.self) { group in
            @MainActor func enqueue(_ source: MangaSourceReference) {
                receive(.started(source))
                group.addTask {
                    do {
                        try Task.checkCancellation()
                        let page = try await search(source, text)
                        try Task.checkCancellation()
                        var urls = Set<String>()
                        return .results(source, .init(mangas: page.mangas.filter {
                            !$0.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && urls.insert($0.url).inserted
                        }, hasNext: page.hasNext))
                    } catch { return .failed(source, error.localizedDescription) }
                }
            }
            for _ in 0..<2 { if let source = iterator.next() { enqueue(source) } }
            for await event in group {
                guard !Task.isCancelled else { group.cancelAll(); return }
                receive(event)
                if let source = iterator.next() { enqueue(source) }
            }
        }
    }
}
