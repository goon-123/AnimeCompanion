import Foundation

public enum NewsTopic: String, CaseIterable, Codable, Sendable {
    case all, announcements, dubs, trailers, manga, industry, events, reviews
    public var label: String {
        switch self {
        case .all: return "All stories"
        case .announcements: return "Announcements"
        case .dubs: return "English dubs"
        case .trailers: return "Trailers & visuals"
        case .manga: return "Manga & novels"
        case .industry: return "Industry"
        case .events: return "Events"
        case .reviews: return "Reviews"
        }
    }
    public var symbol: String {
        switch self {
        case .all: return "newspaper"
        case .announcements: return "megaphone"
        case .dubs: return "waveform"
        case .trailers: return "play.rectangle"
        case .manga: return "book.closed"
        case .industry: return "building.2"
        case .events: return "ticket"
        case .reviews: return "star.bubble"
        }
    }
    /// Convenience filters inferred from publisher headlines/categories, not verified classifications.
    public func matches(_ article: NewsArticle) -> Bool {
        guard self != .all else { return true }
        let text = NewsFeed.normalized(([article.title] + (article.categories ?? [])).joined(separator: " "))
        let words: [String]
        switch self {
        case .all: return true
        case .announcements: words = ["announced", "announces", "announcement", "reveals", "confirmed", "new anime", "season 2", "season 3", "premiere", "adaptation"]
        case .dubs: words = ["dub", "dubs", "dubbed", "dubbing", "english cast"]
        case .trailers: words = ["trailer", "trailers", "teaser", "visual", "visuals", "promotional video", "promo video"]
        case .manga: words = ["manga", "manhwa", "manhua", "webtoon", "novel", "novels", "light novel"]
        case .industry: words = ["industry", "studio", "studios", "licensing", "license", "licenses", "acquires", "acquisition", "box office", "business", "animator", "animators"]
        case .events: words = ["event", "events", "convention", "anime expo", "anime japan", "animejapan", "festival", "concert", "panel"]
        case .reviews: words = ["review", "reviews", "reviewed"]
        }
        return words.contains { NewsFeed.containsPhrase($0, in: text) }
    }
}

public enum NewsCollection: String, CaseIterable, Sendable {
    case latest, forYou, saved, history
    public var label: String {
        switch self { case .latest: return "Latest"; case .forYou: return "For You"; case .saved: return "Saved"; case .history: return "History" }
    }
}
public enum NewsSort: String, CaseIterable, Sendable {
    case newest, oldest, unreadFirst
    public var label: String { switch self { case .newest: return "Newest first"; case .oldest: return "Oldest first"; case .unreadFirst: return "Unread first" } }
}
public enum NewsTimeRange: String, CaseIterable, Sendable {
    case all, today, week, month
    public var label: String { switch self { case .all: return "Any time"; case .today: return "Today"; case .week: return "Last 7 days"; case .month: return "Last 30 days" } }
    public func includes(_ date: Date?, now: Date, calendar: Calendar = .current) -> Bool {
        guard self != .all else { return true }
        guard let date, date <= now else { return false }
        let start = self == .today ? calendar.startOfDay(for: now)
            : now.addingTimeInterval(-Double(self == .week ? 7 : 30) * 86400)
        return date >= start
    }
}

public struct NewsPreferences: Codable, Sendable {
    public var enabledSources: Set<NewsSource> = Set(NewsSource.allCases)
    public var followedTopics: Set<NewsTopic> = [.dubs]
    public var mutedKeywords: [String] = []
    public init() {}
}

/// Device-local reading status and metadata bookmarks survive feed changes and relaunches.
public struct NewsReaderState: Codable, Sendable {
    public private(set) var saved: [NewsArticle] = []
    public private(set) var readDates: [String: Date] = [:]
    public private(set) var migratedHistory = false
    public init() {}
    public func isSaved(_ article: NewsArticle) -> Bool { saved.contains { NewsFeed.storyKey($0) == NewsFeed.storyKey(article) } }
    public func isRead(_ article: NewsArticle) -> Bool { readDates[NewsFeed.storyKey(article)] != nil }
    public mutating func markRead(_ article: NewsArticle, at date: Date = Date()) {
        readDates[NewsFeed.storyKey(article)] = date
        if readDates.count > 2000 {
            let newest = readDates.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.prefix(2000)
            readDates = Dictionary(uniqueKeysWithValues: newest.map { ($0.key, $0.value) })
        }
    }
    public mutating func markUnread(_ article: NewsArticle) { readDates[NewsFeed.storyKey(article)] = nil }
    public mutating func toggleSaved(_ article: NewsArticle) {
        if isSaved(article) { saved.removeAll { NewsFeed.storyKey($0) == NewsFeed.storyKey(article) } }
        else { saved.insert(article, at: 0); saved = Array(saved.prefix(250)) }
    }
    public mutating func migrate(_ history: NewsReadingHistory) {
        guard !migratedHistory else { return }
        for read in history.reads.sorted(by: { $0.date < $1.date }) { markRead(read.article, at: read.date) }
        migratedHistory = true
    }
}

public struct NewsLibraryTitle: Sendable {
    public let title: String
    public let aliases: [String]
    public init(title: String, aliases: [String] = []) { self.title = title; self.aliases = aliases }
    public init(anime: Anime) {
        title = anime.displayTitle
        aliases = [anime.title?.english, anime.title?.romaji, anime.title?.userPreferred].compactMap { $0 }
    }
    public func matches(_ article: NewsArticle) -> Bool {
        let text = NewsFeed.normalized(article.title)
        return ([title] + aliases).contains { NewsFeed.containsPhrase($0, in: text) }
    }
}

public struct NewsFeedQuery: Sendable {
    public var collection: NewsCollection = .latest
    public var topic: NewsTopic = .all
    public var source: NewsSource?
    public var text = ""
    public var unreadOnly = false
    public var timeRange: NewsTimeRange = .all
    public var sort: NewsSort = .newest
    public init() {}
}

public enum NewsFeed {
    public static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }
    static func containsPhrase(_ phrase: String, in normalizedText: String) -> Bool {
        let phrase = normalized(phrase)
        return !phrase.isEmpty && (" " + normalizedText + " ").contains(" " + phrase + " ")
    }
    /// LiveChart can curate a link already supplied by a publisher. Keep one story in the feed.
    public static func storyKey(_ article: NewsArticle) -> String {
        guard var parts = URLComponents(url: article.url, resolvingAgainstBaseURL: false) else { return article.id }
        parts.fragment = nil
        parts.host = parts.host?.lowercased().replacingOccurrences(of: #"^www\."#, with: "", options: .regularExpression)
        let tracking = Set(["fbclid", "gclid", "mc_cid", "mc_eid"])
        let query = parts.queryItems?.filter { !$0.name.lowercased().hasPrefix("utm_") && !tracking.contains($0.name.lowercased()) }
        parts.queryItems = query?.isEmpty == false ? query?.sorted { $0.name == $1.name ? ($0.value ?? "") < ($1.value ?? "") : $0.name < $1.name } : nil
        return parts.url?.absoluteString ?? article.id
    }
    public static func matchingTitles(_ article: NewsArticle, library: [NewsLibraryTitle]) -> [String] {
        var seen = Set<String>()
        return library.filter { $0.matches(article) && seen.insert($0.title).inserted }.map(\.title)
    }
    public static func articles(_ articles: [NewsArticle], query: NewsFeedQuery, preferences: NewsPreferences,
                                reader: NewsReaderState, history: NewsReadingHistory, library: [NewsLibraryTitle],
                                now: Date = Date()) -> [NewsArticle] {
        let personal = query.collection == .saved || query.collection == .history
        let input: [NewsArticle]
        switch query.collection {
        case .saved: input = reader.saved
        case .history: input = history.reads.sorted { $0.date > $1.date }.map(\.article)
        default: input = articles
        }
        let search = normalized(query.text).split(separator: " ").map(String.init)
        let sorted = input.sorted {
            if query.sort == .unreadFirst, reader.isRead($0) != reader.isRead($1) { return !reader.isRead($0) }
            let a = $0.publishedAt ?? .distantPast, b = $1.publishedAt ?? .distantPast
            if a == b { return $0.id < $1.id }
            return query.sort == .oldest ? a < b : a > b
        }
        var seen = Set<String>()
        return (query.collection == .history ? input : sorted).filter { article in
            guard article.source.accepts(article.url),
                  personal || preferences.enabledSources.contains(article.source),
                  query.source == nil || query.source == article.source,
                  query.topic.matches(article), query.timeRange.includes(article.publishedAt, now: now),
                  !query.unreadOnly || query.collection == .history || !reader.isRead(article) else { return false }
            let text = normalized(([article.title, article.summary ?? "", article.source.label] + (article.categories ?? [])).joined(separator: " "))
            guard search.allSatisfy({ text.contains($0) }) else { return false }
            if !personal && preferences.mutedKeywords.contains(where: { containsPhrase($0, in: text) }) { return false }
            if query.collection == .forYou && !library.contains(where: { $0.matches(article) })
                && !preferences.followedTopics.contains(where: { $0 != .all && $0.matches(article) }) { return false }
            return seen.insert(storyKey(article)).inserted
        }
    }
}
