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
    public var displayTitle: String { title?.english ?? title?.userPreferred ?? title?.romaji ?? "Anime #\(id)" }
    public var coverURL: URL? { URL(string: coverImage?.extraLarge ?? coverImage?.large ?? coverImage?.medium ?? "") }
    public var synopsis: String { TextSanitizer.plain(description ?? "Synopsis not available.") }
    public init(id: Int, title: String) {
        self.id = id; self.title = AnimeTitle(english: title)
        idMal = nil; coverImage = nil; bannerImage = nil; description = nil; episodes = nil
        duration = nil; format = nil; status = nil; season = nil; seasonYear = nil
        averageScore = nil; genres = nil; isAdult = nil; nextAiringEpisode = nil
        airingSchedule = nil; studios = nil; characters = nil; relations = nil; trailer = nil
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
}
public struct RelationEdge: Codable, Hashable, Sendable { public let relationType: String?; public let node: RelatedAnime? }
public struct RelationConnection: Codable, Hashable, Sendable { public let edges: [RelationEdge]? }
public struct Trailer: Codable, Hashable, Sendable {
    public let id: String?
    public let site: String?
    public var url: URL? {
        guard site == "youtube", let id, id.range(of: "^[a-zA-Z0-9_-]+$", options: .regularExpression) != nil else { return nil }
        return URL(string: "https://www.youtube.com/watch?v=\(id)")
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
    public let media: Anime?
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

public struct NewsArticle: Identifiable, Hashable, Sendable {
    public let title: String
    public let url: URL
    public let publishedAt: Date?
    public let imageURL: URL?
    public var id: String { url.absoluteString }
    public init(title: String, url: URL, publishedAt: Date?, imageURL: URL?) {
        self.title = title; self.url = url; self.publishedAt = publishedAt; self.imageURL = imageURL
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
