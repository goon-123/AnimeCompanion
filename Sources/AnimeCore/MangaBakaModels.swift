import Foundation

public enum MangaBakaFormat: String, CaseIterable, Codable, Sendable {
    case manga, novel, manhwa, manhua, oel, other
    public var label: String {
        switch self {
        case .manga: return "Manga"
        case .novel: return "Novels"
        case .manhwa: return "Manhwa"
        case .manhua: return "Manhua"
        case .oel: return "OEL"
        case .other: return "Other"
        }
    }
    public var detail: String {
        switch self {
        case .manga: return "Japanese comics"
        case .novel: return "Light & web novels"
        case .manhwa: return "Korean comics"
        case .manhua: return "Chinese comics"
        case .oel: return "Original English comics"
        case .other: return "More illustrated stories"
        }
    }
}

public enum MangaBakaShelf: String, CaseIterable, Codable, Sendable {
    case trending, rising, hiddenGems, popular, topRated, newReleases, recentlyAdded, recommended
    public var label: String {
        switch self {
        case .trending: return "Trending this week"
        case .rising: return "Rising in libraries"
        case .hiddenGems: return "Hidden gems"
        case .popular: return "Most popular"
        case .topRated: return "Highest rated"
        case .newReleases: return "New releases"
        case .recentlyAdded: return "Recently added"
        case .recommended: return "For you"
        }
    }
    public var isCurated: Bool { self == .rising || self == .hiddenGems || self == .recommended }
    public var sort: String {
        switch self {
        case .trending: return "trending_7d"
        case .topRated: return "score_desc"
        case .newReleases: return "published_start_date_desc"
        case .recentlyAdded: return "latest"
        default: return "popularity_asc"
        }
    }
}

public struct MangaBakaQuery: Hashable, Sendable {
    public var shelf: MangaBakaShelf
    public var format: MangaBakaFormat?
    public var text: String
    public var status: String?
    public init(shelf: MangaBakaShelf = .popular, format: MangaBakaFormat? = nil, text: String = "", status: String? = nil) {
        self.shelf = shelf; self.format = format; self.text = text; self.status = status
    }
}

private enum MBKey: String, CodingKey {
    case id, title, titles, language, traits, cover, raw, url, x1, x150, x250, x350, authors, artists, description, year
    case type, status, rating, genres, tags, name, source, links, data, results, pagination, next, page, count, limit
    case series, legacySeries = "Series", state, note, picture, nickname, published
    case startDate = "start_date"
    case isPrimary = "is_primary", nativeTitle = "native_title", romanizedTitle = "romanized_title"
    case contentRating = "content_rating", totalChapters = "total_chapters", finalVolume = "final_volume"
    case coverImage = "cover_image", mediaType = "media_type", publishedYear = "published_year", genresV2 = "genres_v2"
    case seriesID = "series_id", chapter = "progress_chapter", volume = "progress_volume", isPrivate = "is_private"
    case updatedAt = "updated_at", preferredUsername = "preferred_username", ratingSteps = "rating_steps"
}

private extension KeyedDecodingContainer {
    func mbString(_ key: Key) -> String? {
        if let value = try? decode(String.self, forKey: key) { return value }
        if let value = try? decode(Int.self, forKey: key) { return String(value) }
        return nil
    }
    func mbNumber(_ key: Key) -> Double? {
        let value = (try? decode(Double.self, forKey: key)) ?? mbString(key).flatMap(Double.init)
        return value?.isFinite == true ? value : nil
    }
    func mbInt(_ key: Key) -> Int? {
        if let value = try? decode(Int.self, forKey: key) { return value }
        guard let value = mbNumber(key), value >= Double(Int32.min), value <= Double(Int32.max), value.rounded() == value else { return nil }
        return Int(value)
    }
}

public struct MangaBakaTitle: Decodable, Hashable, Sendable {
    public let title: String
    public let language: String
    public let primary: Bool
    public let traits: [String]
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: MBKey.self)
        title = c.mbString(.title) ?? ""; language = c.mbString(.language) ?? ""
        primary = (try? c.decode(Bool.self, forKey: .isPrimary)) ?? false
        traits = (try? c.decode([String].self, forKey: .traits)) ?? []
    }
}

private struct MBCoverValue: Decodable, Hashable, Sendable {
    let value: String?
    init(from decoder: Decoder) throws {
        if let text = try? decoder.singleValueContainer().decode(String.self) { value = text; return }
        let c = try decoder.container(keyedBy: MBKey.self)
        value = c.mbString(.x1) ?? c.mbString(.url)
    }
}
private struct MBCover: Decodable, Hashable, Sendable {
    let x150: MBCoverValue?, x250: MBCoverValue?, x350: MBCoverValue?, raw: MBCoverValue?
}
private struct MBProvider: Decodable {
    let present: Bool
    init(from decoder: Decoder) throws { present = try decoder.container(keyedBy: MBKey.self).mbString(.id) != nil }
}
public struct MangaBakaTag: Decodable, Hashable, Sendable {
    public let id: Int?
    public let name: String
    public init(from decoder: Decoder) throws {
        if let text = try? decoder.singleValueContainer().decode(String.self) { id = nil; name = text; return }
        let c = try decoder.container(keyedBy: MBKey.self)
        id = c.mbInt(.id); name = c.mbString(.name) ?? ""
    }
}

public struct MangaBakaSeries: Decodable, Hashable, Identifiable, Sendable {
    public let id: Int
    public let title: String
    public let nativeTitle: String?
    public let titles: [MangaBakaTitle]
    public let type: String
    public let status: String
    public let contentRating: String?
    public let rating: Double?
    public let synopsis: String
    public let year: Int?
    public let authors: [String]
    public let artists: [String]
    public let totalChapters: Double?
    public let finalVolume: Double?
    public let links: [String]
    public let genres: [MangaBakaTag]
    public let providers: [String]
    private let cover: MBCover?
    private let coverImage: String?

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: MBKey.self)
        // Personal recommendation responses can wrap their catalog record.
        if c.contains(.series) { self = try c.decode(Self.self, forKey: .series); return }
        guard let value = c.mbInt(.id) ?? c.mbInt(.seriesID), value > 0 else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Missing MangaBaka series identity"))
        }
        id = value; title = c.mbString(.title) ?? c.mbString(.romanizedTitle) ?? ""
        nativeTitle = c.mbString(.nativeTitle); titles = (try? c.decode([MangaBakaTitle].self, forKey: .titles)) ?? []
        type = c.mbString(.type) ?? c.mbString(.mediaType) ?? "other"; status = c.mbString(.status) ?? "unknown"
        contentRating = c.mbString(.contentRating); rating = c.mbNumber(.rating)
        synopsis = TextSanitizer.plain(c.mbString(.description) ?? "")
        let published = try? c.nestedContainer(keyedBy: MBKey.self, forKey: .published)
        year = c.mbInt(.year) ?? c.mbInt(.publishedYear) ?? published?.mbString(.startDate).flatMap { Int($0.prefix(4)) }
        authors = (try? c.decode([String].self, forKey: .authors)) ?? []
        artists = (try? c.decode([String].self, forKey: .artists)) ?? []
        totalChapters = c.mbNumber(.totalChapters); finalVolume = c.mbNumber(.finalVolume)
        links = (try? c.decode([String].self, forKey: .links)) ?? []
        genres = (try? c.decode([MangaBakaTag].self, forKey: .genres)) ?? (try? c.decode([MangaBakaTag].self, forKey: .genresV2)) ?? []
        cover = (try? c.decode(MBCover.self, forKey: .cover)) ?? (try? c.decode(MBCover.self, forKey: .coverImage))
        coverImage = c.mbString(.coverImage)
        let sources = (try? c.decode([String: MBProvider].self, forKey: .source)) ?? [:]
        let labels = ["anilist": "AniList", "anime_planet": "Anime-Planet", "anime_news_network": "Anime News Network", "kitsu": "Kitsu", "manga_updates": "MangaUpdates", "my_anime_list": "MyAnimeList", "shikimori": "Shikimori"]
        providers = sources.filter { $0.value.present }.keys.map { labels[$0] ?? $0 }.sorted()
    }
    public var displayTitle: String {
        for language in ["en", "ja-Latn", "ja", "ko-Latn", "ko", "zh-Latn", "zh"] {
            let candidates = titles.filter { $0.language == language && !$0.title.isEmpty }
            if let best = candidates.first(where: \.primary) ?? candidates.first(where: { $0.traits.contains("official") }) ?? candidates.first { return best.title }
        }
        return !title.isEmpty ? title : titles.first?.title ?? "Untitled series"
    }
    public var formatLabel: String { MangaBakaFormat(rawValue: type)?.label ?? type.capitalized }
    public var websiteURL: URL { URL(string: "https://mangabaka.org/\(id)")! }
    public var coverURL: URL? { [cover?.x350?.value, cover?.x250?.value, cover?.x150?.value, cover?.raw?.value, coverImage].compactMap { $0 }.compactMap(Self.publicURL).first }
    public var searchTitles: [String] {
        var seen = Set<String>()
        return Array(([displayTitle, title, nativeTitle ?? ""] + titles.map(\.title)).filter {
            !$0.isEmpty && seen.insert($0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)).inserted
        }.prefix(5))
    }
    public func isVisible(includeAdult: Bool) -> Bool { includeAdult || ["safe", "suggestive"].contains(contentRating ?? "") }
    public static func publicURL(_ value: String) -> URL? {
        guard let url = URL(string: value), url.scheme == "https", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443, let host = url.host, SeanimeNetworkPolicy.publicHost(host) != nil else { return nil }
        return url
    }
}

public struct MangaBakaPage<Item: Decodable & Sendable>: Decodable, Sendable {
    public let items: [Item]
    public let total: Int?
    public let page: Int
    public let hasNext: Bool
    public let hasPagination: Bool
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: MBKey.self)
        if c.contains(.data) { items = try c.decode([Item].self, forKey: .data) }
        else { items = try c.decode([Item].self, forKey: .results) }
        if let p = try? c.nestedContainer(keyedBy: MBKey.self, forKey: .pagination) {
            hasPagination = true
            total = p.mbInt(.count); page = max(1, p.mbInt(.page) ?? 1)
            hasNext = !(p.mbString(.next) ?? "").isEmpty
        } else { total = nil; page = 1; hasNext = false; hasPagination = false }
    }
    func withLibraryPaging(requestedPage: Int, limit: Int) -> Self {
        Self(items: items, total: total, page: requestedPage, hasNext: hasPagination ? hasNext : items.count >= limit, hasPagination: hasPagination)
    }
    private init(items: [Item], total: Int?, page: Int, hasNext: Bool, hasPagination: Bool) {
        self.items = items; self.total = total; self.page = page; self.hasNext = hasNext; self.hasPagination = hasPagination
    }
}

public enum MangaBakaReadingStatus: String, CaseIterable, Sendable {
    case reading, planToRead = "plan_to_read", completed, paused, dropped, rereading, considering
    public var label: String { self == .planToRead ? "Plan to read" : rawValue.capitalized }
}

public struct MangaBakaLibraryEntry: Decodable, Identifiable, Sendable {
    public let seriesID: Int?
    public let series: MangaBakaSeries?
    public let state: String
    public let chapter: Double?
    public let volume: Double?
    public let rating: Int?
    public let note: String?
    public let isPrivate: Bool
    public let updatedAt: String?
    public var id: Int { seriesID ?? series?.id ?? 0 }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: MBKey.self)
        series = try c.decodeIfPresent(MangaBakaSeries.self, forKey: c.contains(.series) ? .series : .legacySeries)
        seriesID = c.mbInt(.seriesID) ?? series?.id
        if let series, let seriesID, series.id != seriesID { throw MangaBakaError.invalidResponse }
        state = c.mbString(.state) ?? "unknown"; chapter = c.mbNumber(.chapter); volume = c.mbNumber(.volume)
        rating = c.mbInt(.rating); note = c.mbString(.note)
        isPrivate = (try? c.decode(Bool.self, forKey: .isPrivate)) ?? true
        updatedAt = c.mbString(.updatedAt)
    }
    private init(copy: Self, series: MangaBakaSeries) {
        self.series = series; seriesID = series.id; state = copy.state; chapter = copy.chapter; volume = copy.volume
        rating = copy.rating; note = copy.note; isPrivate = copy.isPrivate; updatedAt = copy.updatedAt
    }
    public func attaching(_ series: MangaBakaSeries) throws -> Self {
        guard seriesID == nil || seriesID == series.id else { throw MangaBakaError.invalidResponse }
        return Self(copy: self, series: series)
    }
}

public struct MangaBakaProfile: Decodable, Sendable {
    public let id: String
    public let name: String
    public let ratingSteps: Int
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: MBKey.self)
        guard let value = c.mbString(.id), !value.isEmpty else { throw MangaBakaError.invalidResponse }
        id = value; name = c.mbString(.nickname) ?? c.mbString(.preferredUsername) ?? "MangaBaka reader"
        ratingSteps = max(1, c.mbInt(.ratingSteps) ?? 1)
    }
}

public struct MangaBakaLibraryUpdate: Encodable, Sendable {
    public let state: String
    public let chapter: Double?
    public let volume: Double?
    public let rating: Int?
    public let note: String?
    public let isPrivate: Bool
    public init(state: String, chapter: Double?, volume: Double?, rating: Int?, note: String?, isPrivate: Bool) throws {
        guard MangaBakaReadingStatus(rawValue: state) != nil,
              chapter.map({ $0.isFinite && $0 >= 0 && $0 <= 10_000_000 }) ?? true,
              volume.map({ $0.isFinite && $0 >= 0 && $0 <= 1_000_000 }) ?? true,
              rating.map({ (0...100).contains($0) }) ?? true else { throw MangaBakaError.message("Check the reading status, progress and rating.") }
        self.state = state; self.chapter = chapter; self.volume = volume; self.rating = rating
        self.note = note; self.isPrivate = isPrivate
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: MBKey.self)
        try c.encode(state, forKey: .state); try c.encode(isPrivate, forKey: .isPrivate)
        try c.encode(chapter, forKey: .chapter); try c.encode(volume, forKey: .volume)
        try c.encode(rating, forKey: .rating); try c.encode(note, forKey: .note)
    }
}
