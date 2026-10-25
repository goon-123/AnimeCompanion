import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Only reads image metadata; article bodies remain on the original publisher's website.
public enum NewsImageMetadata {
    private static func matches(_ pattern: String, in value: String) -> [NSTextCheckingResult] {
        (try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]))
            .map { $0.matches(in: value, range: NSRange(value.startIndex..., in: value)) } ?? []
    }
    private static func attributes(_ tag: String) -> [String: String] {
        var result: [String: String] = [:]
        for match in matches(#"([a-zA-Z_:][a-zA-Z0-9_:.-]*)\s*=\s*["']([^"']*)["']"#, in: tag) {
            guard let key = Range(match.range(at: 1), in: tag), let value = Range(match.range(at: 2), in: tag) else { continue }
            result[String(tag[key]).lowercased()] = TextSanitizer.plain(String(tag[value]))
        }
        return result
    }
    private static func imageURL(_ value: String?, relativeTo base: URL) -> URL? {
        guard let value, let url = URL(string: value, relativeTo: base)?.absoluteURL,
              url.scheme == "https", url.host != nil, url.user == nil, url.password == nil else { return nil }
        return url
    }
    public static func image(in html: String, relativeTo base: URL, allowInline: Bool = false) -> URL? {
        var twitter: URL?
        for match in matches(#"<meta\b[^>]*>"#, in: html) {
            guard let range = Range(match.range, in: html) else { continue }
            let attrs = attributes(String(html[range]))
            let name = (attrs["property"] ?? attrs["name"] ?? "").lowercased()
            if name == "og:image", let url = imageURL(attrs["content"], relativeTo: base) { return url }
            if name == "twitter:image" { twitter = imageURL(attrs["content"], relativeTo: base) }
        }
        if let twitter { return twitter }
        if allowInline {
            for match in matches(#"<img\b[^>]*>"#, in: html) {
                guard let range = Range(match.range, in: html) else { continue }
                let attrs = attributes(String(html[range]))
                if let url = imageURL(attrs["src"] ?? attrs["data-src"], relativeTo: base) { return url }
            }
        }
        return nil
    }
}

public final class RSSParser: NSObject, XMLParserDelegate {
    private let source: NewsSource
    private var articles: [NewsArticle] = []
    private var item: [String: String] = [:]
    private var field = ""
    private var elements: [String] = []
    private var categories: [String] = []
    private var category = ""
    private var insideItem = false
    private var imageURL: URL?
    private var openedRSS = false
    private var closedRSS = false
    private init(source: NewsSource) { self.source = source }
    public static func parse(_ data: Data, source: NewsSource = .animeNewsNetwork) throws -> [NewsArticle] {
        guard data.count <= 2_000_000 else { throw ServiceError.message("The news feed is too large.") }
        let delegate = RSSParser(source: source)
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse(), parser.parserError == nil, delegate.openedRSS, delegate.closedRSS, !delegate.insideItem else {
            throw ServiceError.message("The news feed could not be read.")
        }
        var seen = Set<String>()
        return delegate.articles.filter { seen.insert($0.id).inserted }.sorted {
            ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast)
        }
    }
    public func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        if name == "rss" { openedRSS = true }
        if name == "item" { insideItem = true; item = [:]; imageURL = nil; elements = []; categories = []; category = "" }
        guard insideItem else { return }
        elements.append(name)
        field = elements.first(where: { ["title", "link", "guid", "pubDate", "description", "content:encoded", "category"].contains($0) }) ?? ""
        if name == "category" { category = "" }
        if (name == "media:thumbnail" || name == "media:content" || name == "enclosure"),
           let value = attributes["url"], let url = URL(string: value), url.scheme == "https", url.host != nil, url.user == nil, url.password == nil,
           (name != "enclosure" || attributes["type"]?.hasPrefix("image/") == true) { imageURL = url }
    }
    public func parser(_ parser: XMLParser, foundCharacters string: String) {
        if insideItem { if field == "category" { category += string } else { item[field, default: ""] += string } }
    }
    public func parser(_ parser: XMLParser, foundCDATA data: Data) {
        if insideItem, let text = String(data: data, encoding: .utf8) { self.parser(parser, foundCharacters: text) }
    }
    public func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if name == "rss" { closedRSS = true }
        if insideItem {
            if name == "category" {
                let text = TextSanitizer.plain(category)
                if !text.isEmpty && !categories.contains(text) { categories.append(String(text.prefix(100))) }
            }
            if !elements.isEmpty { elements.removeLast() }
            field = elements.first(where: { ["title", "link", "guid", "pubDate", "description", "content:encoded", "category"].contains($0) }) ?? ""
        }
        guard name == "item" else { return }
        insideItem = false
        guard let raw = item["link"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: raw), source.accepts(url),
              let title = item["title"]?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else { return }
        var headlineID: Int?
        if source == .liveChart {
            guard let rawID = item["guid"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let id = URL(string: rawID), id.scheme == "https", id.user == nil, id.password == nil,
                  id.port == nil || id.port == 443,
                  ["livechart.me", "www.livechart.me"].contains(id.host?.lowercased() ?? ""),
                  id.path.range(of: #"^/headlines/[1-9][0-9]*$"#, options: .regularExpression) != nil,
                  let number = Int(id.lastPathComponent) else { return }
            headlineID = number
        }
        let date = Self.parseDate(item["pubDate"] ?? "")
        let image = imageURL
            ?? NewsImageMetadata.image(in: item["description"] ?? "", relativeTo: url, allowInline: true)
            ?? NewsImageMetadata.image(in: item["content:encoded"] ?? "", relativeTo: url, allowInline: true)
        let excerpt = TextSanitizer.plain(item["description"] ?? "")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        let summary = excerpt.isEmpty ? nil : String(excerpt.prefix(500))
        articles.append(NewsArticle(title: TextSanitizer.plain(title), url: url, publishedAt: date, imageURL: image, source: source, headlineID: headlineID,
                                    summary: summary, categories: Array(categories.prefix(20))))
    }
    private static func parseDate(_ value: String) -> Date? {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(secondsFromGMT: 0)
        for format in ["EEE, dd MMM yyyy HH:mm:ss Z", "EEE, d MMM yyyy HH:mm:ss Z", "dd MMM yyyy HH:mm:ss Z"] {
            f.dateFormat = format
            if let date = f.date(from: value.trimmingCharacters(in: .whitespacesAndNewlines)) { return date }
        }
        return SourceDates.parse(value)
    }
}

public struct NewsSnapshot: Sendable {
    public let articles: [NewsArticle]
    public let unavailableSources: [String]
    public let updatedAt: Date
    public let isStale: Bool
    public init(articles: [NewsArticle], unavailableSources: [String], updatedAt: Date = Date(), isStale: Bool = false) {
        self.articles = articles; self.unavailableSources = unavailableSources
        self.updatedAt = updatedAt; self.isStale = isStale
    }
}
private struct NewsCachedFeed: Codable, Sendable {
    let source: NewsSource
    let updatedAt: Date
    let articles: [NewsArticle]
}
private struct NewsFeedResult: Sendable {
    let source: NewsSource
    let articles: [NewsArticle]?
}

public actor NewsClient {
    public static let feedURL = NewsSource.animeNewsNetwork.feedURL
    public static var defaultDirectory: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("AnimeCompanion-News", isDirectory: true)
    }
    private let transport: any HTTPTransport
    private let directory: URL?
    private let series: SeriesNewsClient
    private let requests = RequestCoalescer<String, NewsSnapshot>()
    private var feeds: [NewsSource: NewsCachedFeed] = [:]
    private var restored = false
    private var cached: (Date, NewsSnapshot)?
    private var images: [String: (Date, URL?)] = [:]
    private var imageTasks: [String: Task<URL?, Never>] = [:]
    public init(transport: any HTTPTransport = URLSessionTransport(), directory: URL? = NewsClient.defaultDirectory) {
        self.transport = transport; self.directory = directory
        self.series = SeriesNewsClient(transport: transport, directory: directory)
    }

    public func seriesSnapshot(for anime: Anime, refresh: Bool = false) async throws -> SeriesNewsSnapshot {
        try await series.snapshot(for: anime, refresh: refresh)
    }
    public func cachedSeriesSnapshot(for anime: Anime) async -> SeriesNewsSnapshot? {
        await series.cachedSnapshot(for: anime)
    }

    /// Restore headlines immediately; the view can display them while fresh feeds load.
    public func cachedSnapshot(now: Date = Date()) -> NewsSnapshot? {
        if !restored {
            restored = true
            if let file = directory?.appendingPathComponent("feeds-v1.json"),
               let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 3_000_000,
               let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode([NewsCachedFeed].self, from: data) {
                for feed in saved where feed.updatedAt <= now && now.timeIntervalSince(feed.updatedAt) < 7 * 86400 {
                    feeds[feed.source] = NewsCachedFeed(source: feed.source, updatedAt: feed.updatedAt,
                        articles: Array(feed.articles.filter { $0.source == feed.source && feed.source.accepts($0.url) }.prefix(120)))
                }
            }
        }
        feeds = feeds.filter { $0.value.updatedAt <= now && now.timeIntervalSince($0.value.updatedAt) < 7 * 86400 }
        guard !feeds.isEmpty else { return nil }
        let unavailable = NewsSource.allCases.filter { feeds[$0] == nil || now.timeIntervalSince(feeds[$0]!.updatedAt) >= 900 }.map(\.label)
        return makeSnapshot(unavailable: unavailable, stale: !unavailable.isEmpty)
    }

    public func snapshot(refresh: Bool = false) async throws -> NewsSnapshot {
        if !refresh, let (date, snapshot) = cached, Date().timeIntervalSince(date) < 900 { return snapshot }
        if !refresh, let saved = cachedSnapshot(), saved.unavailableSources.isEmpty {
            cached = (saved.updatedAt, saved); return saved
        }
        return try await requests.value(for: "feeds") { try await self.fetchSnapshot() }
    }
    private func fetchSnapshot() async throws -> NewsSnapshot {
        _ = cachedSnapshot()
        let transport = self.transport
        var results: [NewsFeedResult] = []
        await withTaskGroup(of: NewsFeedResult.self) { group in
            for source in NewsSource.allCases {
                group.addTask {
                    do {
                        var request = URLRequest(url: source.feedURL); request.timeoutInterval = 20
                        request.setValue("AnimeCompanion/1.1 RSS reader", forHTTPHeaderField: "User-Agent")
                        let (data, response) = try await transport.data(for: request)
                        try HTTPValidation.check(response)
                        return NewsFeedResult(source: source, articles: try RSSParser.parse(data, source: source))
                    } catch { return NewsFeedResult(source: source, articles: nil) }
                }
            }
            for await result in group { results.append(result) }
        }
        try Task.checkCancellation()
        let now = Date()
        for result in results {
            if let articles = result.articles {
                feeds[result.source] = NewsCachedFeed(source: result.source, updatedAt: now, articles: Array(articles.prefix(120)))
            }
        }
        guard !feeds.isEmpty else { throw ServiceError.message("The news sources are temporarily unavailable. Pull to refresh.") }
        let failed = results.filter { $0.articles == nil }.map { $0.source.label }.sorted()
        let result = makeSnapshot(unavailable: failed, stale: results.contains { $0.articles == nil && feeds[$0.source] != nil })
        cached = (now, result)
        if let directory, let data = try? JSONEncoder().encode(Array(feeds.values)), data.count <= 3_000_000 {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? data.write(to: directory.appendingPathComponent("feeds-v1.json"), options: .atomic)
        }
        return result
    }
    private func makeSnapshot(unavailable: [String], stale: Bool) -> NewsSnapshot {
        let articles = feeds.values.flatMap(\.articles).sorted {
            let a = $0.publishedAt ?? .distantPast, b = $1.publishedAt ?? .distantPast
            return a == b ? $0.id < $1.id : a > b
        }
        return NewsSnapshot(articles: articles, unavailableSources: unavailable.sorted(),
                            updatedAt: feeds.values.map(\.updatedAt).max() ?? Date(), isStale: stale)
    }
    public func articles(refresh: Bool = false) async throws -> [NewsArticle] { try await snapshot(refresh: refresh).articles }

    public func thumbnail(for article: NewsArticle) async -> URL? {
        if let image = article.imageURL { return image }
        // LiveChart supplies its own feed thumbnails. Do not fetch social/video
        // pages just to look for image metadata when an enclosure is absent.
        guard article.source != .liveChart else { return nil }
        guard article.source.accepts(article.url) else { return nil }
        if let (date, image) = images[article.id], Date().timeIntervalSince(date) < 7 * 86400 { return image }
        if let task = imageTasks[article.id] { return await task.value }
        let transport = self.transport
        let task = Task<URL?, Never> {
            do {
                var request = URLRequest(url: article.url); request.timeoutInterval = 12
                request.setValue("AnimeCompanion/1.1 RSS reader", forHTTPHeaderField: "User-Agent")
                let (data, response) = try await transport.data(for: request)
                try HTTPValidation.check(response)
                guard data.count <= 2_000_000, let html = String(data: data, encoding: .utf8) else { return nil }
                return NewsImageMetadata.image(in: html, relativeTo: article.url)
            } catch { return nil }
        }
        imageTasks[article.id] = task
        let image = await task.value
        images[article.id] = (Date(), image); imageTasks[article.id] = nil
        if images.count > 400 { images = images.filter { Date().timeIntervalSince($0.value.0) < 86400 } }
        return image
    }
}
