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
    private var insideItem = false
    private var imageURL: URL?
    private var openedRSS = false
    private var closedRSS = false
    private init(source: NewsSource) { self.source = source }
    public static func parse(_ data: Data, source: NewsSource = .animeNewsNetwork) throws -> [NewsArticle] {
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
        if name == "item" { insideItem = true; item = [:]; imageURL = nil }
        guard insideItem else { return }
        field = name
        if (name == "media:thumbnail" || name == "media:content" || name == "enclosure"),
           let value = attributes["url"], let url = URL(string: value), url.scheme == "https",
           (name != "enclosure" || attributes["type"]?.hasPrefix("image/") == true) { imageURL = url }
    }
    public func parser(_ parser: XMLParser, foundCharacters string: String) {
        if insideItem { item[field, default: ""] += string }
    }
    public func parser(_ parser: XMLParser, foundCDATA data: Data) {
        if insideItem, let text = String(data: data, encoding: .utf8) { item[field, default: ""] += text }
    }
    public func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if name == "rss" { closedRSS = true }
        guard name == "item" else { return }
        insideItem = false
        guard let raw = item["link"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: raw), source.accepts(url),
              let title = item["title"]?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else { return }
        let date = Self.parseDate(item["pubDate"] ?? "")
        let image = imageURL
            ?? NewsImageMetadata.image(in: item["description"] ?? "", relativeTo: url, allowInline: true)
            ?? NewsImageMetadata.image(in: item["content:encoded"] ?? "", relativeTo: url, allowInline: true)
        articles.append(NewsArticle(title: TextSanitizer.plain(title), url: url, publishedAt: date, imageURL: image, source: source))
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
    public init(articles: [NewsArticle], unavailableSources: [String]) {
        self.articles = articles; self.unavailableSources = unavailableSources
    }
}
private struct NewsFeedResult: Sendable {
    let source: NewsSource
    let articles: [NewsArticle]?
}

public actor NewsClient {
    public static let feedURL = NewsSource.animeNewsNetwork.feedURL
    private let transport: any HTTPTransport
    private var cached: (Date, NewsSnapshot)?
    private var images: [String: (Date, URL?)] = [:]
    private var imageTasks: [String: Task<URL?, Never>] = [:]
    public init(transport: any HTTPTransport = URLSessionTransport()) { self.transport = transport }

    public func snapshot(refresh: Bool = false) async throws -> NewsSnapshot {
        if !refresh, let (date, snapshot) = cached, Date().timeIntervalSince(date) < 900 { return snapshot }
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
        guard results.contains(where: { $0.articles != nil }) else { throw ServiceError.message("The news sources are temporarily unavailable. Pull to refresh.") }
        var seen = Set<String>()
        let articles = results.flatMap { $0.articles ?? [] }.filter { seen.insert($0.id).inserted }.sorted {
            let a = $0.publishedAt ?? .distantPast, b = $1.publishedAt ?? .distantPast
            return a == b ? $0.id < $1.id : a > b
        }
        let result = NewsSnapshot(articles: articles, unavailableSources: results.filter { $0.articles == nil }.map { $0.source.label }.sorted())
        cached = (Date(), result)
        return result
    }
    public func articles(refresh: Bool = false) async throws -> [NewsArticle] { try await snapshot(refresh: refresh).articles }

    public func thumbnail(for article: NewsArticle) async -> URL? {
        if let image = article.imageURL { return image }
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
