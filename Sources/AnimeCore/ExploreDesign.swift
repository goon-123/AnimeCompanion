import Foundation

public enum ExploreDesign: String, CaseIterable, Identifiable, Sendable {
    case discover, posterGrid, classic
    public static let storageKey = "explore.design"
    public var id: String { rawValue }
    public init(preference: String?) { self = preference.flatMap(Self.init(rawValue:)) ?? .discover }
    public var title: String {
        switch self { case .discover: return "Discovery shelves"; case .posterGrid: return "Mixed poster grid"; case .classic: return "Classic sections" }
    }
    public var symbol: String {
        switch self { case .discover: return "rectangle.stack"; case .posterGrid: return "square.grid.2x2"; case .classic: return "rectangle.2.swap" }
    }
    public var detail: String {
        switch self {
        case .discover: return "One home for anime, manga and novels, with mixed discoveries and curated shelves."
        case .posterGrid: return "A single wall of stories with a format badge on every poster."
        case .classic: return "The original Anime / Manga & Novels switch and separate discovery pages."
        }
    }
}

/// Provider-scoped identities keep adaptations and their source material distinct.
public enum ExploreStory: Identifiable, Sendable {
    case anime(Anime), reading(MangaBakaSeries)
    public var id: String {
        switch self { case .anime(let value): return "anilist:\(value.id)"; case .reading(let value): return "mangabaka:\(value.id)" }
    }
    public var title: String {
        switch self { case .anime(let value): return value.displayTitle; case .reading(let value): return value.displayTitle }
    }
    public var format: String {
        switch self { case .anime: return "Anime"; case .reading(let value): return value.formatLabel }
    }
    public static func mix(anime: [Anime], reading: [MangaBakaSeries], novels: [MangaBakaSeries] = [], includeAdult: Bool) -> [Self] {
        var seen = Set<String>()
        let shows = anime.filter { includeAdult || $0.isAdult != true }.map(Self.anime)
        let books = (reading + novels).filter { $0.isVisible(includeAdult: includeAdult) }
        let buckets = [shows, books.filter { $0.type != "novel" }.map(Self.reading), books.filter { $0.type == "novel" }.map(Self.reading)]
        var result: [Self] = []
        for index in 0..<(buckets.map(\.count).max() ?? 0) {
            for bucket in buckets where index < bucket.count {
                let value = bucket[index]
                if seen.insert(value.id).inserted { result.append(value) }
            }
        }
        return result
    }
}
