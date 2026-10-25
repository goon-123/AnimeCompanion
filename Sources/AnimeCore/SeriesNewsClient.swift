import Foundation
import SwiftSoup
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct SeriesNewsSnapshot: Sendable {
    public let articles: [NewsArticle]
    public let updatedAt: Date?
    public let unavailable: Bool
    public let isStale: Bool
}

/// Searches a publisher's title-specific listings rather than just its latest feed.
/// Results remain separate from the main News cache and must match a series title locally.
public actor SeriesNewsClient {
    private struct Record: Codable, Sendable {
        let key: String
        let articles: [NewsArticle]
        let updatedAt: Date?
        let attemptedAt: Date
        let unavailable: Bool
        var snapshot: SeriesNewsSnapshot {
            SeriesNewsSnapshot(articles: articles, updatedAt: updatedAt, unavailable: unavailable,
                               isStale: unavailable && !articles.isEmpty)
        }
    }
    private let transport: any HTTPTransport
    private let directory: URL?
    private let requests = RequestCoalescer<String, SeriesNewsSnapshot>()
    private var records: [String: Record] = [:]
    private var restored = false

    public init(transport: any HTTPTransport = URLSessionTransport(), directory: URL? = NewsClient.defaultDirectory) {
        self.transport = transport; self.directory = directory
    }

    public static func searchURL(for term: String) -> URL? {
        guard !term.isEmpty, term.count <= 200 else { return nil }
        // This publisher's RSS route ignores search terms. Its public search page
        // supplies actual title matches; only listing metadata is parsed below.
        var parts = URLComponents(string: "https://animecorner.me/")!
        // Search words tolerate publisher punctuation; the returned headline must still
        // contain a complete normalized title phrase before it can enter the results.
        parts.queryItems = [URLQueryItem(name: "s", value: term)]
        return parts.url
    }
    public static func publisherSearchURL(for anime: Anime) -> URL? {
        guard let term = AnimeUpdates.headlineSearchTerms(for: anime).first else { return nil }
        var parts = URLComponents(string: "https://animecorner.me/")!
        parts.queryItems = [URLQueryItem(name: "s", value: term)]
        return parts.url
    }

    public func cachedSnapshot(for anime: Anime, now: Date = Date()) -> SeriesNewsSnapshot? {
        restore(now: now)
        guard let record = records[key(for: anime)] else { return nil }
        return record.snapshot
    }

    public func snapshot(for anime: Anime, refresh: Bool = false) async throws -> SeriesNewsSnapshot {
        restore(now: Date())
        let key = key(for: anime)
        let terms = AnimeUpdates.headlineSearchTerms(for: anime)
        guard !terms.isEmpty else {
            return SeriesNewsSnapshot(articles: [], updatedAt: nil, unavailable: true, isStale: false)
        }
        if !refresh, let saved = records[key], Date().timeIntervalSince(saved.attemptedAt) < (saved.unavailable ? 300 : 900) {
            return saved.snapshot
        }
        return try await requests.value(for: key) { try await self.fetch(anime, key: key, terms: terms) }
    }

    private func key(for anime: Anime) -> String {
        "\(anime.id)|" + AnimeUpdates.headlineSearchTerms(for: anime).joined(separator: "|")
    }

    private func fetch(_ anime: Anime, key: String, terms: [String]) async throws -> SeriesNewsSnapshot {
        let transport = self.transport
        var found: [NewsArticle] = [], failed = false, succeeded = false
        await withTaskGroup(of: [NewsArticle]?.self) { group in
            for term in terms {
                group.addTask {
                    do {
                        guard let url = Self.searchURL(for: term) else { return nil }
                        var request = URLRequest(url: url); request.timeoutInterval = 15
                        request.setValue("text/html", forHTTPHeaderField: "Accept")
                        request.setValue("AnimeCompanion/1.1 RSS reader", forHTTPHeaderField: "User-Agent")
                        let (data, response) = try await transport.data(for: request)
                        try HTTPValidation.check(response)
                        guard let finalURL = response.url, NewsSource.animeCorner.accepts(finalURL) else { return nil }
                        return try SeriesNewsParser.parse(data, searchTerm: term).filter { AnimeUpdates.headline($0, matches: anime) }
                    } catch { return nil }
                }
            }
            for await articles in group {
                if let articles { found += articles; succeeded = true } else { failed = true }
            }
        }
        try Task.checkCancellation()
        let now = Date()
        // An unavailable alias must not erase the successful stories of a prior search.
        let old = records[key]
        if failed { found += old?.articles ?? [] }
        var seen = Set<String>()
        let articles = Array(found.sorted {
            let a = $0.publishedAt ?? .distantPast, b = $1.publishedAt ?? .distantPast
            return a == b ? $0.id < $1.id : a > b
        }.filter { seen.insert(NewsFeed.storyKey($0)).inserted }.prefix(40))
        let updatedAt = failed ? (old?.updatedAt ?? (succeeded ? now : nil)) : now
        let record = Record(key: key, articles: articles, updatedAt: updatedAt,
                            attemptedAt: now, unavailable: failed)
        records[key] = record
        records = Dictionary(uniqueKeysWithValues: records.values.sorted { $0.attemptedAt > $1.attemptedAt }.prefix(40).map { ($0.key, $0) })
        persist()
        return record.snapshot
    }

    private func restore(now: Date) {
        if !restored {
            restored = true
            if let file = directory?.appendingPathComponent("series-v1.json"),
               let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 2_000_000,
               let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode([Record].self, from: data) {
                for record in saved.prefix(40) {
                    records[record.key] = Record(key: record.key,
                        articles: Array(record.articles.filter { $0.source == .animeCorner && $0.source.accepts($0.url) }.prefix(40)),
                        updatedAt: record.updatedAt, attemptedAt: record.attemptedAt, unavailable: record.unavailable)
                }
            }
        }
        records = records.filter {
            let date = $0.value.updatedAt ?? $0.value.attemptedAt
            return $0.value.attemptedAt <= now && date <= now && now.timeIntervalSince(date) < 7 * 86400
        }
    }
    private func persist() {
        guard let directory, let data = try? JSONEncoder().encode(Array(records.values)), data.count <= 2_000_000 else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: directory.appendingPathComponent("series-v1.json"), options: .atomic)
    }
}

/// Reads search cards only. No article body or embedded script is evaluated or retained.
public enum SeriesNewsParser {
    public static func parse(_ data: Data, searchTerm: String) throws -> [NewsArticle] {
        guard data.count <= 2_000_000, let html = String(data: data, encoding: .utf8) else { throw ServiceError.invalidResponse }
        let document = try SwiftSoup.parse(html)
        // Require the publisher's search surface and an echoed matching query. A
        // home page, challenge, or changed contract must not become a successful empty result.
        guard let shell = try document.select(".ac-search-shell").first(),
              let input = try shell.select(".ac-search-form input[name=s]").first(),
              NewsFeed.normalized(try input.attr("value")) == NewsFeed.normalized(searchTerm) else {
            throw ServiceError.invalidResponse
        }
        let cards = try shell.select(".ac-archive-grid article.ac-archive-card")
        let emptySearch = try shell.select(".ac-search-empty").first() != nil
        guard !cards.isEmpty() || emptySearch else { throw ServiceError.invalidResponse }
        var articles: [NewsArticle] = [], seen = Set<String>()
        for card in cards {
            guard let link = try card.select("h2 a[href]").first(),
                  let url = URL(string: try link.attr("href")), NewsSource.animeCorner.accepts(url) else { continue }
            let title = try link.text().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, seen.insert(url.absoluteString).inserted else { continue }
            let time = try card.select("time").first()
            let rawDate = try time?.attr("datetime") ?? ""
            let date = rawDate.isEmpty ? listingDate(try time?.text() ?? "") : SourceDates.parse(rawDate)
            let excerpt = try card.select(".ac-archive-card__body > p").text()
            let rawImage = try card.select("[data-bgset]").first()?.attr("data-bgset")
                ?? card.select("img[src]").first()?.attr("src")
            let image = rawImage.flatMap { URL(string: $0) }.flatMap { value -> URL? in
                value.scheme == "https" && value.host != nil && value.user == nil && value.password == nil ? value : nil
            }
            articles.append(NewsArticle(title: String(title.prefix(500)), url: url, publishedAt: date, imageURL: image, source: .animeCorner,
                summary: excerpt.isEmpty ? nil : String(excerpt.prefix(500))))
            if articles.count == 40 { break }
        }
        guard cards.isEmpty() || !articles.isEmpty else { throw ServiceError.invalidResponse }
        return articles
    }
    private static func listingDate(_ value: String) -> Date? {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "MMMM d, yyyy"
        return formatter.date(from: value)
    }
}
