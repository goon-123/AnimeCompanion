import Foundation

/// Legacy five-source selections remain readable for backup compatibility; bulk search uses MangaBulkSearch.
public struct MangaSearchPreferences: Equatable, Sendable {
    public static let storageKey = "manga.search.sources.v1"
    public static let limit = 5
    public private(set) var sourceIDs: [String]
    public init(sourceIDs: [String] = []) {
        var seen = Set<String>()
        self.sourceIDs = Array(sourceIDs.filter { !$0.isEmpty && $0.utf8.count <= 2048 && seen.insert($0).inserted }.prefix(Self.limit))
    }
    public init(saved: String?) {
        guard let saved, saved.utf8.count <= 32768, let data = saved.data(using: .utf8),
              let ids = try? JSONDecoder().decode([String].self, from: data) else { self.init(); return }
        self.init(sourceIDs: ids)
    }
    public var saved: String { String(data: try! JSONEncoder().encode(sourceIDs), encoding: .utf8)! }
    public func sources(in installations: [InstalledMangaExtension], allowMature: Bool) -> [MangaSourceReference] {
        let available = installations.filter { $0.enabled && (allowMature || !$0.descriptor.adult) }
            .flatMap { entry in entry.sources.map { MangaSourceReference(installation: entry, source: $0) } }
        return sourceIDs.compactMap { id in available.first { $0.id == id } }
    }
}
