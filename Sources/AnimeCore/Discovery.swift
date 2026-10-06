import Foundation

public enum DiscoveryGenres {
    public static let all = ["Action", "Adventure", "Comedy", "Drama", "Ecchi", "Fantasy", "Horror", "Mecha", "Music", "Mystery", "Psychological", "Romance", "Sci-Fi", "Slice of Life", "Sports", "Supernatural", "Thriller"]
}

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
    public var minimumScore = 0
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
        if minimumScore > 0 { result["minimumScore"] = .int(min(100, minimumScore) - 1) }
        return result
    }
}

public enum DiscoveryDubFilter: String, Codable, CaseIterable, Sendable {
    case all, available, airing, scheduled, notReported
    public var label: String {
        switch self {
        case .all: return "All anime"
        case .available: return "Dub available"
        case .airing: return "Airing dubs"
        case .scheduled: return "Scheduled dubs"
        case .notReported: return "No dub reported"
        }
    }
    public var explanation: String {
        switch self {
        case .all: return "Show every title, including unknown dub availability."
        case .available: return "English episodes are released or a complete or partial dub is reported. Counts may still be unknown."
        case .airing: return "A dub is available and has another scheduled, estimated or delayed episode."
        case .scheduled: return "The source verifies a future English episode date. Estimates and indefinite delays are excluded."
        case .notReported: return "The dub index has no English listing and no release or announcement is known. This does not confirm that a dub will never be made."
        }
    }
    public func matches(progress: LibraryDubProgress?, next: ReleaseEvent?, now: Date = Date()) -> Bool {
        if self == .all { return true }
        guard let progress else { return false }
        let available = (progress.released ?? 0) > 0 || progress.availability == .dubbed || progress.availability == .partial
        switch self {
        case .all: return true
        case .available: return available
        case .airing: return available && (next?.certainty == .delayed || (next?.date.map { $0 > now } ?? false))
        case .scheduled: return next?.certainty == .verified && (next?.date.map { $0 > now } ?? false)
        case .notReported: return progress.availability == .notReported && !progress.announced && (progress.released ?? 0) == 0
        }
    }
}

/// One automatically saved selection shared by Explore shelves and category pages.
public struct DiscoveryPreferences: Codable, Equatable, Sendable {
    public var dub: DiscoveryDubFilter = .all
    public var minimumScore = 0
    public var hideCompleted = false
    public init() {}
    public var isActive: Bool { dub != .all || minimumScore > 0 || hideCompleted }
    public var summary: String {
        var parts: [String] = []
        if dub != .all { parts.append(dub.label) }
        if minimumScore > 0 { parts.append(String(format: "%.1f+ ★", Double(min(100, max(0, minimumScore))) / 10)) }
        if hideCompleted { parts.append("Hide completed") }
        return parts.isEmpty ? "All anime" : parts.joined(separator: " · ")
    }
    public func matches(anime: Anime, progress: LibraryDubProgress?, next: ReleaseEvent?, entry: LibraryEntry?, now: Date = Date()) -> Bool {
        if hideCompleted && entry?.status == .completed { return false }
        if minimumScore > 0 && (anime.averageScore ?? -1) < min(100, max(0, minimumScore)) { return false }
        return dub.matches(progress: progress, next: next, now: now)
    }
}
