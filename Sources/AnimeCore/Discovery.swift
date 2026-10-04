import Foundation

public enum DiscoveryCategory: String, Hashable, Sendable {
    case trending, seasonal, upcoming
    public func label(season: SeasonSelection) -> String {
        switch self {
        case .trending: return "Trending"
        case .seasonal: return season == .current() ? "Popular this season" : "Popular · " + season.label
        case .upcoming: return "Upcoming · " + season.advanced(by: 1).label
        }
    }
}
public enum DiscoverySort: String, CaseIterable, Hashable, Sendable {
    case trending = "TRENDING_DESC", popularity = "POPULARITY_DESC", rating = "SCORE_DESC"
    case newest = "START_DATE_DESC", title = "TITLE_ROMAJI"
    public var label: String {
        switch self {
        case .trending: return "Trending"
        case .popularity: return "Popularity"
        case .rating: return "AniList rating"
        case .newest: return "Newest"
        case .title: return "Title"
        }
    }
}
public struct DiscoveryFilters: Hashable, Sendable {
    public var search = ""
    public var genre: String?
    public var year: Int?
    public var season: AnimeSeason?
    public var format: String?
    public var status: String?
    public var sort = DiscoverySort.popularity

    public init(category: DiscoveryCategory, selection: SeasonSelection = .current()) {
        switch category {
        case .trending: sort = .trending
        case .seasonal: year = selection.year; season = selection.season
        case .upcoming:
            let next = selection.advanced(by: 1)
            year = next.year; season = next.season; status = "NOT_YET_RELEASED"
        }
    }
    public func variables(page: Int) -> [String: QueryValue] {
        var result: [String: QueryValue] = ["page": .int(max(1, page)), "sort": .string(sort.rawValue)]
        let text = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { result["search"] = .string(text) }
        if let genre, !genre.isEmpty { result["genre"] = .string(genre) }
        if let year { result["year"] = .int(year) }
        if let season { result["season"] = .string(season.rawValue) }
        if let format { result["format"] = .string(format) }
        if let status { result["status"] = .string(status) }
        return result
    }
}
