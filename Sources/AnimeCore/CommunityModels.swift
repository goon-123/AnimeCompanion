import Foundation

public enum CommunitySource: String, CaseIterable, Identifiable, Sendable {
    case reddit, aniList, myAnimeList
    public var id: String { rawValue }
    public var title: String {
        switch self { case .reddit: return "Reddit · r/anime"; case .aniList: return "AniList"; case .myAnimeList: return "MyAnimeList" }
    }
}

public enum CommunityFilter: String, CaseIterable, Identifiable, Sendable {
    case general, season, myShows, episodes
    public var id: String { rawValue }
    public var title: String {
        switch self { case .general: return "General Anime"; case .season: return "This Season"; case .myShows: return "My Shows"; case .episodes: return "Episode Discussions" }
    }
}

public enum CommunityThreadSort: String, CaseIterable, Identifiable, Sendable {
    case active, newest, comments
    public var id: String { rawValue }
    public var title: String { self == .active ? "Active" : (self == .newest ? "Newest" : "Most replies") }
    public var aniListValue: String { self == .active ? "REPLIED_AT_DESC" : (self == .newest ? "ID_DESC" : "REPLY_COUNT_DESC") }
}

public enum CommunityCommentSort: String, CaseIterable, Identifiable, Sendable {
    case oldest, newest
    public var id: String { rawValue }
    public var title: String { self == .oldest ? "Oldest first" : "Newest first" }
    public var aniListValue: String { self == .oldest ? "ID" : "ID_DESC" }
}

public struct CommunityMedia: Decodable, Hashable, Sendable {
    public let id: Int
    public let type: String?
    public let title: AnimeTitle?
    public let isAdult: Bool?
    public var name: String { title?.english ?? title?.romaji ?? title?.userPreferred ?? "Anime #\(id)" }
}

public struct CommunityThread: Identifiable, Hashable, Sendable {
    public let source: CommunitySource
    public let threadID: Int
    public let title: String
    public let author: String?
    public let activityAt: Date?
    public let commentCount: Int?
    public let media: [CommunityMedia]
    public let url: URL
    public var id: String { "\(source.rawValue)-\(threadID)" }
    public var episode: Int? { CommunityEpisodeTitle.parse(title)?.episode }
    public var mentionsEpisode: Bool { CommunityEpisodeTitle.mentionsEpisode(title) }
    public init(source: CommunitySource, threadID: Int, title: String, author: String?, activityAt: Date?, commentCount: Int?, media: [CommunityMedia] = [], url: URL) {
        self.source = source; self.threadID = threadID; self.title = title; self.author = author
        self.activityAt = activityAt; self.commentCount = commentCount; self.media = media; self.url = url
    }
    /// A topic title itself can spoil an episode. Never use it as a preview for unknown/unwatched progress.
    public func previewTitle(progress: [Int: Int], mappedEpisode: Int? = nil, mediaID: Int? = nil) -> String {
        guard mentionsEpisode else { return title }
        let number = mappedEpisode ?? episode
        let ids = mediaID.map { [$0] } ?? media.filter { $0.type == "ANIME" }.map(\.id)
        let watched = number.map { n in !ids.isEmpty && ids.allSatisfy { (progress[$0] ?? 0) >= n } } ?? false
        if watched { return title }
        return number.map { "Episode \($0) discussion · Preview hidden" } ?? "Episode discussion · Preview hidden"
    }
}

public struct CommunityComment: Identifiable, Hashable, Sendable {
    public let id: Int
    public let author: String
    public let body: String
    public let createdAt: Date?
    public let score: Int?
    public let replies: [CommunityComment]
    public init(id: Int, author: String, body: String, createdAt: Date?, score: Int?, replies: [CommunityComment] = []) {
        self.id = id; self.author = author; self.body = body; self.createdAt = createdAt; self.score = score; self.replies = replies
    }
}

public struct CommunityThreadPage: Sendable {
    public let threads: [CommunityThread]
    public let hasNextPage: Bool
    public init(threads: [CommunityThread], hasNextPage: Bool) { self.threads = threads; self.hasNextPage = hasNextPage }
}

public struct CommunityCommentPage: Sendable {
    public let title: String
    public let body: String?
    public let comments: [CommunityComment]
    public let hasNextPage: Bool
    public let media: [CommunityMedia]?
    public init(title: String, body: String?, comments: [CommunityComment], hasNextPage: Bool, media: [CommunityMedia]? = nil) {
        self.title = title; self.body = body; self.comments = comments; self.hasNextPage = hasNextPage; self.media = media
    }
}

/// Conservative single-episode grammar. Ranges, decimals, specials and multiple episode references
/// remain unverified; neither a substring search nor an inferred season offset is a match.
public enum CommunityEpisodeTitle {
    public struct Parsed: Equatable, Sendable { public let episode: Int; public let titlePrefix: String }
    private static let marker = #"(?i)\b(?:episodes?|eps?\.?)\s*[#:]?\s*(\d{1,5})(?!\d)"#
    public static func mentionsEpisode(_ title: String) -> Bool {
        title.range(of: #"(?i)\b(?:episodes?|eps?\.?)\s*[#:]?\s*\d"#, options: .regularExpression) != nil
    }
    public static func parse(_ title: String) -> Parsed? {
        guard let regex = try? NSRegularExpression(pattern: marker) else { return nil }
        let range = NSRange(title.startIndex..., in: title)
        let matches = regex.matches(in: title, range: range)
        guard matches.count == 1, let match = matches.first,
              let digits = Range(match.range(at: 1), in: title), let number = Int(title[digits]), number > 0,
              let whole = Range(match.range, in: title) else { return nil }
        let suffix = String(title[whole.upperBound...])
        guard suffix.range(of: #"^\s*(?:[-–—/&,]|and\b|to\b|\.)\s*\d"#, options: [.regularExpression, .caseInsensitive]) == nil else { return nil }
        return Parsed(episode: number, titlePrefix: String(title[..<whole.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines))
    }
    public static func normalized(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: #"[^\p{L}\p{N}]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    public static func aliases(for anime: Anime) -> [String] {
        var seen = Set<String>()
        return ([anime.title?.english, anime.title?.romaji, anime.title?.userPreferred].compactMap { $0 } + (anime.synonyms ?? []))
            .map(normalized).filter { !$0.isEmpty && seen.insert($0).inserted }
    }
    public static func hasExactTitlePrefix(_ thread: CommunityThread, anime: Anime) -> Bool {
        guard let parsed = parse(thread.title) else { return false }
        return aliases(for: anime).contains(normalized(parsed.titlePrefix))
    }
    public static func hasExactMedia(_ thread: CommunityThread, animeID: Int) -> Bool {
        let ids = Set(thread.media.filter { $0.type == "ANIME" }.map(\.id))
        return ids == [animeID]
    }
    public static func matches(_ thread: CommunityThread, anime: Anime, episode: Int, offset: Int = 0) -> Bool {
        let mapped = episode.addingReportingOverflow(offset)
        guard episode > 0, !mapped.overflow, let parsed = parse(thread.title), parsed.episode == mapped.partialValue else { return false }
        switch thread.source {
        case .aniList: return hasExactMedia(thread, animeID: anime.id)
        case .myAnimeList: return hasExactTitlePrefix(thread, anime: anime) // Still requires visible user confirmation: MAL omits media IDs.
        case .reddit: return false // Browser search is deliberately never represented as a verified match.
        }
    }
}

/// Official website URLs only. No unauthenticated JSON, scraping, mirrors or embedded third-party readers.
public enum CommunityBrowserLinks {
    public static func reddit(filter: CommunityFilter, anime: Anime? = nil, episode: Int? = nil) -> URL {
        var parts = URLComponents(string: "https://www.reddit.com/r/anime/search/")!
        var query: String
        if let anime {
            let names = [anime.title?.romaji, anime.title?.english, anime.title?.userPreferred].compactMap { $0 }
            let unique = Array(Set(names)).sorted().map { "\"\($0.replacingOccurrences(of: "\"", with: ""))\"" }
            query = "(" + unique.joined(separator: " OR ") + ")"
            if let episode { query += " \"Episode \(episode)\" flair_name:Episode" }
        } else {
            switch filter {
            case .episodes: query = "flair_name:Episode"
            case .season: query = "flair_name:Episode"
            case .general: query = "flair_name:Discussion"
            case .myShows: query = "flair_name:Discussion"
            }
        }
        parts.queryItems = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "restrict_sr", value: "on"),
                            URLQueryItem(name: "sort", value: "new"), URLQueryItem(name: "t", value: filter == .season ? "month" : "all")]
        return parts.url!
    }
    public static func myAnimeList(anime: Anime?) -> URL {
        if let id = anime?.idMal, id > 0 { return URL(string: "https://myanimelist.net/anime/\(id)/_/forum")! }
        return URL(string: "https://myanimelist.net/forum/?board=1")!
    }
}

// AniList DTOs stay internal; childComments is a Json scalar and must NOT have a GraphQL selection set.
struct AniListCommunityUser: Decodable, Sendable { let name: String? }
struct AniListCommunityThread: Decodable, Sendable {
    let id: Int
    let title: String?
    let body: String?
    let user: AniListCommunityUser?
    let replyCount: Int?
    let repliedAt: Int?
    let createdAt: Int?
    let mediaCategories: [CommunityMedia]?
    var value: CommunityThread {
        CommunityThread(source: .aniList, threadID: id, title: title ?? "Untitled discussion", author: user?.name,
            activityAt: (repliedAt ?? createdAt).map { Date(timeIntervalSince1970: Double($0)) }, commentCount: replyCount,
            media: mediaCategories ?? [], url: URL(string: "https://anilist.co/forum/thread/\(id)")!)
    }
}

struct AniListCommunityComment: Decodable, Sendable {
    let id: Int
    let comment: String?
    let user: AniListCommunityUser?
    let createdAt: Int?
    let likeCount: Int?
    let childComments: [AniListCommunityComment]?
    func value(depth: Int = 0) -> CommunityComment {
        CommunityComment(id: id, author: user?.name ?? "Deleted user", body: comment ?? "[Comment unavailable]",
            createdAt: createdAt.map { Date(timeIntervalSince1970: Double($0)) }, score: likeCount,
            replies: depth < 30 ? (childComments ?? []).map { $0.value(depth: depth + 1) } : [])
    }
}

struct AniListCommunityThreadResult: Decodable, Sendable {
    struct ThreadPage: Decodable, Sendable { let pageInfo: PageInfo?; let threads: [AniListCommunityThread]? }
    let Page: ThreadPage
}
struct AniListCommunityCommentResult: Decodable, Sendable {
    struct CommentPage: Decodable, Sendable { let pageInfo: PageInfo?; let threadComments: [AniListCommunityComment]? }
    let Thread: AniListCommunityThread?
    let Page: CommentPage
}
