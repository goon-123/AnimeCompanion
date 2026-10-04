import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public final class RSSParser: NSObject, XMLParserDelegate {
    private var articles: [NewsArticle] = []
    private var item: [String: String] = [:]
    private var field = ""
    private var insideItem = false
    private var imageURL: URL?
    private var openedRSS = false
    private var closedRSS = false
    public static func parse(_ data: Data) throws -> [NewsArticle] {
        let delegate = RSSParser()
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
        guard let raw = item["link"]?.trimmingCharacters(in: .whitespacesAndNewlines), let url = URL(string: raw),
              url.scheme == "https", let host = url.host?.lowercased(),
              host == "animenewsnetwork.com" || host.hasSuffix(".animenewsnetwork.com"),
              let title = item["title"], !title.isEmpty else { return }
        let date = Self.parseDate(item["pubDate"] ?? "")
        articles.append(NewsArticle(title: TextSanitizer.plain(title), url: url, publishedAt: date, imageURL: imageURL))
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

public actor NewsClient {
    public static let feedURL = URL(string: "https://www.animenewsnetwork.com/news/rss.xml")!
    private let transport: any HTTPTransport
    private var cached: (Date, [NewsArticle])?
    public init(transport: any HTTPTransport = URLSessionTransport()) { self.transport = transport }
    public func articles(refresh: Bool = false) async throws -> [NewsArticle] {
        if !refresh, let (date, items) = cached, Date().timeIntervalSince(date) < 900 { return items }
        var request = URLRequest(url: Self.feedURL); request.timeoutInterval = 25
        let (data, response) = try await transport.data(for: request)
        try HTTPValidation.check(response)
        let articles = try RSSParser.parse(data)
        cached = (Date(), articles)
        return articles
    }
}
