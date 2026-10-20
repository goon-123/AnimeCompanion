import Foundation

/// A source's `hasNext` is a hint, not proof that it advances its catalog.
/// Pause on an empty/repeated page instead of creating an automatic request loop.
public struct MangaCatalogPagination: Sendable {
    public enum Continuation: Equatable, Sendable { case more, end, stalled }
    public private(set) var mangas: [SourceManga] = []
    public private(set) var page = 0
    public private(set) var continuation = Continuation.more
    private var seen = Set<String>()

    public init() {}
    public mutating func append(_ result: SourceMangaPage) {
        let additions = result.mangas.filter { !$0.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && seen.insert($0.url).inserted }
        mangas += additions
        page += 1
        continuation = !result.hasNext ? .end : additions.isEmpty ? .stalled : .more
    }
}

/// Titles are search suggestions only; anime and source manga IDs are unrelated.
public enum MangaSearchTitles {
    public static func suggestions(for anime: Anime) -> [String] {
        var seen = Set<String>()
        return [anime.title?.english, anime.title?.userPreferred, anime.title?.romaji]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)).inserted }
    }
}
