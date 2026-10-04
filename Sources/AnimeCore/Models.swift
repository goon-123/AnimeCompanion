import Foundation

public enum AnimeSeason: String, Codable, CaseIterable, Sendable {
    case winter = "WINTER", spring = "SPRING", summer = "SUMMER", fall = "FALL"
    public var label: String { rawValue.capitalized }
}

public struct SeasonSelection: Hashable, Sendable {
    public var season: AnimeSeason
    public var year: Int
    public init(season: AnimeSeason, year: Int) { self.season = season; self.year = year }
    public var label: String { "\(season.label) \(year)" }
    public static func current(at date: Date = Date(), calendar: Calendar = .current) -> Self {
        let month = calendar.component(.month, from: date)
        return Self(season: [.winter, .spring, .summer, .fall][(month - 1) / 3],
                    year: calendar.component(.year, from: date))
    }
    public func advanced(by quarters: Int) -> Self {
        let seasons = AnimeSeason.allCases
        let current = seasons.firstIndex(of: season) ?? 0
        let total = year * 4 + current + quarters
        return Self(season: seasons[((total % 4) + 4) % 4], year: Int(floor(Double(total) / 4)))
    }
}

public struct Anime: Codable, Identifiable, Hashable, Sendable {
    public let id: Int
    public let idMal: Int?
    public let title: AnimeTitle?
    public let coverImage: AnimeImage?
    public let bannerImage: String?
    public let description: String?
    public let episodes: Int?
    public let duration: Int?
    public let format: String?
    public let status: String?
    public let season: AnimeSeason?
    public let seasonYear: Int?
    public let averageScore: Int?
    public let genres: [String]?
    public let isAdult: Bool?
    public let nextAiringEpisode: AiringEpisode?
    public let airingSchedule: SourceAiringConnection?
    public let studios: StudioConnection?
    public let characters: CharacterConnection?
    public let relations: RelationConnection?
    public let trailer: Trailer?
    public let startDate: AnimeDate?
    public let endDate: AnimeDate?
    public let popularity: Int?
    public let favourites: Int?
    public let rankings: [AnimeRank]?
    public let staff: StaffConnection?
    public let recommendations: RecommendationConnection?
    public let reviews: ReviewConnection?
    public let externalLinks: [AnimeExternalLink]?
    public var displayTitle: String { title?.english ?? title?.userPreferred ?? title?.romaji ?? "Anime #\(id)" }
    public var coverURL: URL? { URL(string: coverImage?.extraLarge ?? coverImage?.large ?? coverImage?.medium ?? "") }
    public var synopsis: String { TextSanitizer.plain(description ?? "Synopsis not available.") }
    /// Already broadcast episodes, distinct from the season's planned episode total.
    public func releasedEpisodeCount(at now: Date = Date()) -> Int? {
        if status == "NOT_YET_RELEASED" { return 0 }
        if status == "FINISHED", let episodes, episodes > 0 { return episodes }
        guard let next = nextAiringEpisode else { return nil }
        let count = max(0, next.episode - (next.date > now ? 1 : 0))
        return episodes.flatMap { $0 > 0 ? min(count, $0) : nil } ?? count
    }
    public init(id: Int, title: String) {
        self.id = id; self.title = AnimeTitle(english: title)
        idMal = nil
        coverImage = nil; bannerImage = nil; description = nil; episodes = nil
        duration = nil; format = nil; status = nil; season = nil; seasonYear = nil
        averageScore = nil; genres = nil; isAdult = nil; nextAiringEpisode = nil
        airingSchedule = nil; studios = nil; characters = nil; relations = nil; trailer = nil
        startDate = nil; endDate = nil; popularity = nil; favourites = nil; rankings = nil
        staff = nil; recommendations = nil; reviews = nil; externalLinks = nil
    }
}

public struct AnimeTitle: Codable, Hashable, Sendable {
    public let romaji: String?
    public let english: String?
    public let userPreferred: String?
    public init(english: String) { self.english = english; romaji = nil; userPreferred = nil }
}
public struct AnimeImage: Codable, Hashable, Sendable {
    public let extraLarge: String?
    public let large: String?
    public let medium: String?
}
public struct AiringEpisode: Codable, Hashable, Sendable {
    public let airingAt: Int
    public let episode: Int
    public var date: Date { Date(timeIntervalSince1970: Double(airingAt)) }
}
public struct Studio: Codable, Hashable, Identifiable, Sendable { public let id: Int; public let name: String }
public struct StudioConnection: Codable, Hashable, Sendable { public let nodes: [Studio]? }
public struct AnimeCharacter: Codable, Hashable, Identifiable, Sendable {
    public let id: Int
    public let name: CharacterName?
    public let image: CharacterImage?
}
public struct CharacterName: Codable, Hashable, Sendable { public let full: String? }
public struct CharacterImage: Codable, Hashable, Sendable { public let medium: String? }
public struct CharacterConnection: Codable, Hashable, Sendable { public let nodes: [AnimeCharacter]? }
public struct RelatedAnime: Codable, Hashable, Identifiable, Sendable {
    public let id: Int
    public let title: AnimeTitle?
    public let type: String?
    public let coverImage: AnimeImage?
    public let isAdult: Bool?
    public var displayTitle: String { title?.english ?? title?.userPreferred ?? title?.romaji ?? "Anime #\(id)" }
    public var coverURL: URL? { URL(string: coverImage?.extraLarge ?? coverImage?.large ?? coverImage?.medium ?? "") }
}
public struct RelationEdge: Codable, Hashable, Sendable { public let relationType: String?; public let node: RelatedAnime? }
public struct RelationConnection: Codable, Hashable, Sendable { public let edges: [RelationEdge]? }
public struct Trailer: Codable, Hashable, Sendable {
    public let id: String?
    public let site: String?
    public let thumbnail: String?
    public var url: URL? {
        guard let id, id.range(of: "^[a-zA-Z0-9_-]+$", options: .regularExpression) != nil else { return nil }
        if site == "youtube" { return URL(string: "https://www.youtube.com/watch?v=\(id)") }
        if site == "dailymotion" { return URL(string: "https://www.dailymotion.com/video/\(id)") }
        return nil
    }
}

public struct AnimeDate: Codable, Hashable, Sendable {
    public let year: Int?
    public let month: Int?
    public let day: Int?
    public var label: String {
        guard let year, year > 0 else { return "Not announced" }
        guard let month, (1...12).contains(month) else { return String(year) }
        let formatter = DateFormatter(); formatter.locale = .current
        let name = formatter.shortMonthSymbols[month - 1]
        if let day, (1...31).contains(day) { return "\(name) \(day), \(year)" }
        return "\(name) \(year)"
    }
}
public struct AnimeRank: Codable, Hashable, Identifiable, Sendable {
    public let id: Int
    public let rank: Int
    public let type: String
    public let context: String
    public let year: Int?
    public let season: AnimeSeason?
    public let allTime: Bool?
    public var label: String {
        let period = allTime == true ? "All time" : [season?.label, year.map(String.init)].compactMap { $0 }.joined(separator: " ")
        return "#\(rank) · \(context.capitalized)" + (period.isEmpty ? "" : " · \(period)")
    }
}
public struct AnimeStaff: Codable, Hashable, Identifiable, Sendable {
    public let id: Int
    public let name: CharacterName?
    public let image: AnimeImage?
}
public struct StaffEdge: Codable, Hashable, Sendable {
    public let id: Int?
    public let role: String?
    public let node: AnimeStaff?
}
public struct StaffConnection: Codable, Hashable, Sendable { public let edges: [StaffEdge]? }
public struct AnimeRecommendation: Codable, Hashable, Identifiable, Sendable {
    public let id: Int
    public let mediaRecommendation: RelatedAnime?
}
public struct RecommendationConnection: Codable, Hashable, Sendable { public let nodes: [AnimeRecommendation]? }
public struct AnimeReview: Codable, Hashable, Identifiable, Sendable {
    public let id: Int
    public let summary: String?
    public let score: Int?
    public let siteUrl: String?
}
public struct ReviewConnection: Codable, Hashable, Sendable { public let nodes: [AnimeReview]? }
public struct AnimeExternalLink: Codable, Hashable, Identifiable, Sendable {
    public let id: Int
    public let site: String
    public let url: String?
    public let isDisabled: Bool?
    public var safeURL: URL? {
        guard isDisabled != true, let url, let parsed = URL(string: url), parsed.scheme?.lowercased() == "https", parsed.host != nil else { return nil }
        return parsed
    }
}

public enum LibraryStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case watching = "CURRENT", planning = "PLANNING", completed = "COMPLETED"
    case paused = "PAUSED", dropped = "DROPPED", rewatching = "REPEATING"
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .watching: return "Watching"
        case .planning: return "Planning"
        case .completed: return "Completed"
        case .paused: return "Paused"
        case .dropped: return "Dropped"
        case .rewatching: return "Rewatching"
        }
    }
}
public struct LibraryEntry: Codable, Identifiable, Hashable, Sendable {
    public let id: Int
    public let mediaId: Int
    public var status: LibraryStatus?
    public var progress: Int?
    public let score: Double?
    public let updatedAt: Int?
    public let repeatCount: Int?
    public let media: Anime?
    private enum CodingKeys: String, CodingKey {
        case id, mediaId, status, progress, score, updatedAt, media
        case repeatCount = "repeat"
    }
    public var progressValue: Int { progress ?? 0 }
    public static func clampedProgress(_ progress: Int, total: Int?) -> Int {
        guard let total, total > 0 else { return max(0, progress) }
        return max(0, min(progress, total))
    }
}
public struct Viewer: Codable, Identifiable, Sendable {
    public let id: Int
    public let name: String
    public let avatar: ViewerAvatar?
}
public struct ViewerAvatar: Codable, Sendable { public let large: String? }

public enum ReleaseKind: String, CaseIterable, Sendable { case sub, dub }
public enum ScheduleCertainty: String, Sendable { case broadcast, recorded, verified, unverified, delayed }
public struct ReleaseEvent: Identifiable, Hashable, Sendable {
    public let anime: Anime
    public let episode: Int
    public let kind: ReleaseKind
    public let date: Date?
    public let certainty: ScheduleCertainty
    public let note: String?
    public var id: String { "\(anime.id)-\(episode)-\(kind.rawValue)" }
    public init(anime: Anime, episode: Int, kind: ReleaseKind, date: Date?, certainty: ScheduleCertainty, note: String? = nil) {
        self.anime = anime; self.episode = episode; self.kind = kind
        self.date = date; self.certainty = certainty; self.note = note
    }
}
public enum DubAvailability: String, Sendable {
    case unknown, notReported, partial, dubbed
    public var label: String {
        switch self {
        case .unknown: return "Dub status unknown"
        case .notReported: return "No English dub reported"
        case .partial: return "Partially dubbed"
        case .dubbed: return "English dub reported"
        }
    }
}

public enum NewsSource: String, CaseIterable, Codable, Sendable {
    case animeNewsNetwork, crunchyroll, animeCorner
    public var label: String {
        switch self {
        case .animeNewsNetwork: return "Anime News Network"
        case .crunchyroll: return "Crunchyroll"
        case .animeCorner: return "Anime Corner"
        }
    }
    public var feedURL: URL {
        switch self {
        case .animeNewsNetwork: return URL(string: "https://www.animenewsnetwork.com/news/rss.xml")!
        case .crunchyroll: return URL(string: "https://cr-news-api-service.prd.crunchyrollsvc.com/v1/en-US/rss")!
        case .animeCorner: return URL(string: "https://animecorner.me/feed/")!
        }
    }
    public func accepts(_ url: URL) -> Bool {
        guard url.scheme == "https", url.user == nil, url.password == nil, let host = url.host?.lowercased() else { return false }
        let domain: String
        switch self {
        case .animeNewsNetwork: domain = "animenewsnetwork.com"
        case .crunchyroll: domain = "crunchyroll.com"
        case .animeCorner: domain = "animecorner.me"
        }
        return host == domain || host.hasSuffix("." + domain)
    }
}

public struct NewsArticle: Identifiable, Hashable, Codable, Sendable {
    public let title: String
    public let url: URL
    public let publishedAt: Date?
    public let imageURL: URL?
    public let source: NewsSource
    public var id: String {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url.absoluteString }
        parts.fragment = nil
        let query = parts.queryItems?.filter { !$0.name.hasPrefix("utm_") && $0.name != "fbclid" }
        parts.queryItems = query?.isEmpty == false ? query : nil
        return parts.url?.absoluteString ?? url.absoluteString
    }
    public init(title: String, url: URL, publishedAt: Date?, imageURL: URL?, source: NewsSource = .animeNewsNetwork) {
        self.title = title; self.url = url; self.publishedAt = publishedAt; self.imageURL = imageURL; self.source = source
    }
    public func withImage(_ image: URL?) -> Self {
        Self(title: title, url: url, publishedAt: publishedAt, imageURL: image ?? imageURL, source: source)
    }
}

public enum TextSanitizer {
    public static func plain(_ value: String) -> String {
        var result = value.replacingOccurrences(of: "(?i)<br\\s*/?>|</p>", with: "\n", options: .regularExpression)
        result = result.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        for (entity, replacement) in [("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&nbsp;", " ")] {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
