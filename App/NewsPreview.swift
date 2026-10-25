#if DEBUG
import Foundation
import AnimeCore

/// Owned news metadata, served through the real RSS parser without account or publisher requests.
enum NewsPreview {
    static var active: Bool { ProcessInfo.processInfo.arguments.contains("--ui-news-preview") }
    static func resetIfNeeded() {
        guard active, !ProcessInfo.processInfo.arguments.contains("--ui-news-keep-state") else { return }
        for key in ["news.reader.v1", "news.preferences.v1", "news.readingHistory", "news.compact", "news.unreadOnly"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
        var history = NewsReadingHistory()
        if let article = articles.last { history.record(article) }
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(String(data: data, encoding: .utf8), forKey: "news.readingHistory")
        }
    }
    static var articles: [NewsArticle] {
        let values: [(NewsSource, String, String, String, String)] = [
            (.animeNewsNetwork, "harbor-dub", "Phase 2 tracked title announces an English dub", "A new English cast joins the returning adventure. The publisher shares its first details.", "Dubs"),
            (.animeNewsNetwork, "moonlit-season", "Moonlit Relay reveals its second season", "The original team returns for another story beneath the city lights.", "Announcements"),
            (.crunchyroll, "summer-trailer", "Summer Signal trailer and new visual arrive", "A first look at the seaside story, with a new trailer and character artwork.", "Trailers"),
            (.crunchyroll, "glass-cast", "Glass Harbor English cast announced", "Meet the voices behind the new English dub.", "Dubs"),
            (.animeCorner, "lantern-manga", "Paper Lantern manga announces final volume", "The illustrated mystery reaches its final volume this winter.", "Manga"),
            (.animeCorner, "harbor-studio", "Studio Harbor expands its animation team", "The independent studio introduces a new training program.", "Industry"),
            (.liveChart, "duplicate", "Phase 2 tracked title announces an English dub", "An official announcement shared by the publisher.", "Dubs"),
            (.liveChart, "night-panel", "Night Festival announces convention panel", "Creators join a conversation about the next chapter of the series.", "Events")
        ]
        return values.enumerated().map { index, value in
            let domain = value.0 == .animeNewsNetwork ? "www.animenewsnetwork.com" : value.0 == .crunchyroll ? "www.crunchyroll.com" : value.0 == .animeCorner ? "animecorner.me" : "official.example.com"
            let url = value.1 == "duplicate" ? "https://www.animenewsnetwork.com/news/harbor-dub" : "https://\(domain)/news/\(value.1)"
            return NewsArticle(title: value.2, url: URL(string: url)!, publishedAt: Date().addingTimeInterval(-Double(index + 1) * 900),
                imageURL: URL(string: "https://catalog-preview.invalid/banner/news-\(index).png"), source: value.0,
                headlineID: value.0 == .liveChart ? 990000 + index : nil, summary: value.3, categories: [value.4])
        }
    }
}
struct NewsPreviewTransport: HTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        if let url = request.url, url.host == "animecorner.me", let term = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "s" })?.value {
            let active = ProcessInfo.processInfo.arguments.contains("--ui-news-series-preview")
            let titles = active ? ["Moonlit Relay Season 2 English dub announced", "Tsukikage Relay announces new cast"] : []
            let items = titles.enumerated().map { index, title in
                """
                <article class="ac-archive-card"><div class="ac-archive-card__body">
                <h2><a href="https://animecorner.me/relay-archive-\(index)">\(title)</a></h2>
                <time>September 1, 2026</time><p>Owned listing excerpt from the series archive.</p>
                </div></article>
                """
            }.joined()
            let empty = titles.isEmpty ? "<div class='ac-search-empty'></div>" : ""
            let body = "<section class='ac-search-shell'><form class='ac-search-form'><input name='s' value='\(term)'></form><div class='ac-archive-grid'>\(items)</div>\(empty)</section>"
            let failed = ProcessInfo.processInfo.arguments.contains("--ui-news-series-failed")
            try await Task.sleep(for: .milliseconds(150))
            return (Data(body.utf8), HTTPURLResponse(url: url, statusCode: failed ? 503 : 200, httpVersion: nil, headerFields: nil)!)
        }
        guard let url = request.url, let source = NewsSource.allCases.first(where: { $0.feedURL == url }) else { throw ServiceError.invalidResponse }
        try await Task.sleep(for: .milliseconds(150))
        let items = NewsPreview.articles.filter { $0.source == source }.map { article in
            """
            <item><title><![CDATA[\(article.title)]]></title><link>\(article.url.absoluteString)</link>
            <guid>https://www.livechart.me/headlines/\(article.headlineID ?? 1)</guid>
            <pubDate>\(article.publishedAt!.ISO8601Format())</pubDate><description><![CDATA[<p>\(article.summary!)</p>]]></description>
            <category>\(article.categories!.first!)</category><enclosure type="image/png" url="\(article.imageURL!.absoluteString)"/></item>
            """
        }.joined()
        let status = ProcessInfo.processInfo.arguments.contains("--ui-news-partial") && source == .animeCorner ? 503 : 200
        return (Data("<rss version='2.0'><channel>\(items)</channel></rss>".utf8),
                HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}
#endif
