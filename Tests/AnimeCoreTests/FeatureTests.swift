import XCTest
@testable import AnimeCore
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class FeatureTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2000)
    private func anime(_ json: String) throws -> Anime { try JSONDecoder().decode(Anime.self, from: Data(json.utf8)) }
    private func history(_ json: String) throws -> [RawDubFeedItem] { try JSONDecoder().decode([RawDubFeedItem].self, from: Data(json.utf8)) }

    func testDubRatioUsesReleasedOriginalEpisodesAndIgnoresFutureHistory() throws {
        let title = try anime(#"{"id":10,"idMal":20,"episodes":26,"status":"RELEASING","nextAiringEpisode":{"episode":13,"airingAt":3000}}"#)
        let records = try history(#"[{"id":10,"episode":{"aired":6,"airedAt":1000}},{"id":10,"episode":{"aired":7,"airedAt":3000}},{"id":99,"episode":{"aired":25,"airedAt":1000}}]"#)
        let snapshot = DubSnapshot(upcoming: [], history: records)
        let progress = LibraryDubProgress(anime: title, snapshot: snapshot, index: nil, now: now)
        XCTAssertEqual(title.releasedEpisodeCount(at: now), 12)
        XCTAssertEqual(progress.released, 6)
        XCTAssertEqual(progress.label(for: title, now: now), "Dub 6/12 released")
        XCTAssertFalse(progress.completeListing)
    }
    func testCompleteDubListingsAndMissingCountsRemainDistinct() throws {
        let finished = try anime(#"{"id":10,"idMal":20,"episodes":26,"status":"FINISHED"}"#)
        let complete = LibraryDubProgress(anime: finished, snapshot: nil, index: DubIndex(dubbed: [20], partial: []), now: now)
        XCTAssertEqual(complete.released, 26)
        XCTAssertTrue(complete.completeListing)
        let partial = LibraryDubProgress(anime: finished, snapshot: nil, index: DubIndex(dubbed: [], partial: [20]), now: now)
        XCTAssertNil(partial.released)
        XCTAssertEqual(partial.label(for: finished), "Partial dub · episodes not listed")
        let unavailable = LibraryDubProgress(anime: finished, snapshot: nil, index: nil, now: now)
        XCTAssertEqual(unavailable.label(for: finished), "Dub status unknown")
        let absent = LibraryDubProgress(anime: finished, snapshot: nil, index: DubIndex(dubbed: [], partial: []), now: now)
        XCTAssertEqual(absent.label(for: finished), "No dub reported yet")
    }
    func testAnnouncedDubDoesNotBecomeAnAvailableEpisodeCount() throws {
        let title = try anime(#"{"id":10,"episodes":12,"status":"RELEASING"}"#)
        let planned = try JSONDecoder().decode([RawDubItem].self, from: Data(#"[{"episodeNumber":1,"episodeDate":3000,"media":{"media":{"id":10}}}]"#.utf8))
        let progress = LibraryDubProgress(anime: title, snapshot: DubSnapshot(upcoming: planned, history: []), index: nil, now: now)
        XCTAssertNil(progress.released)
        XCTAssertEqual(progress.label(for: title), "Dub announced · episodes not listed")
        XCTAssertNil(title.releasedEpisodeCount(at: now))
    }
    func testNewsImagesHandleAttributeOrderRelativeURLsAndUnsafeSchemes() throws {
        let base = URL(string: "https://animecorner.me/story/")!
        let html = #"<meta content='/cover.jpg?size=1&amp;v=2' property='og:image'><meta name='twitter:image' content='https://cdn.example.com/fallback.jpg'>"#
        XCTAssertEqual(NewsImageMetadata.image(in: html, relativeTo: base)?.absoluteString, "https://animecorner.me/cover.jpg?size=1&v=2")
        XCTAssertNil(NewsImageMetadata.image(in: #"<meta property='og:image' content='javascript:alert(1)'>"#, relativeTo: base))
        XCTAssertEqual(NewsImageMetadata.image(in: #"<img src='https://cdn.example.com/cover.png'>"#, relativeTo: base, allowInline: true)?.host, "cdn.example.com")
    }
    func testRSSAddsPublisherThumbnailsAndRejectsAnotherHost() throws {
        let rss = """
        <rss xmlns:media="http://search.yahoo.com/mrss/"><channel>
          <item><title>A &amp; B</title><link>https://crunchyroll.com/news/a?utm_source=reader</link>
          <media:thumbnail url="https://a.storyblok.com/cover.png"/><pubDate>Sun, 04 Oct 2026 13:00:00 GMT</pubDate></item>
          <item><title>Bad</title><link>https://crunchyroll.com.attacker.example/news/b</link></item>
        </channel></rss>
        """
        let articles = try RSSParser.parse(Data(rss.utf8), source: .crunchyroll)
        XCTAssertEqual(articles.count, 1)
        XCTAssertEqual(articles[0].title, "A & B")
        XCTAssertEqual(articles[0].source, .crunchyroll)
        XCTAssertEqual(articles[0].imageURL?.absoluteString, "https://a.storyblok.com/cover.png")
        XCTAssertEqual(articles[0].id, "https://crunchyroll.com/news/a")
    }
    func testNewsKeepsWorkingWhenOnePublisherFails() async throws {
        let ann = "<rss><channel><item><title>ANN</title><link>https://www.animenewsnetwork.com/news/a</link></item></channel></rss>"
        let cr = "<rss><channel><item><title>CR</title><link>https://crunchyroll.com/news/b</link><media:thumbnail xmlns:media=\"http://search.yahoo.com/mrss/\" url=\"https://a.storyblok.com/b.jpg\"/></item></channel></rss>"
        let client = NewsClient(transport: FeedTransport([
            NewsSource.animeNewsNetwork.feedURL: (200, ann), NewsSource.crunchyroll.feedURL: (200, cr),
            NewsSource.animeCorner.feedURL: (503, "")
        ]))
        let snapshot = try await client.snapshot()
        XCTAssertEqual(Set(snapshot.articles.map(\.source)), Set([.animeNewsNetwork, .crunchyroll]))
        XCTAssertEqual(snapshot.unavailableSources, ["Anime Corner"])
        XCTAssertEqual(snapshot.articles.first(where: { $0.source == .crunchyroll })?.imageURL?.host, "a.storyblok.com")
    }
    func testPopularNewsUsesLocalOpensWithinTheSelectedPeriod() {
        let current = Date(timeIntervalSince1970: 2_000_000)
        let a = NewsArticle(title: "A", url: URL(string: "https://animecorner.me/a")!, publishedAt: nil, imageURL: nil, source: .animeCorner)
        let b = NewsArticle(title: "B", url: URL(string: "https://animecorner.me/b")!, publishedAt: nil, imageURL: nil, source: .animeCorner)
        var history = NewsReadingHistory()
        history.record(a, at: current.addingTimeInterval(-15 * 86400))
        history.record(a, at: current.addingTimeInterval(-10 * 86400))
        history.record(b, at: current.addingTimeInterval(-86400))
        XCTAssertEqual(history.popular(in: .week, now: current).map(\.article.title), ["B"])
        XCTAssertEqual(history.popular(in: .month, now: current).first?.article.title, "A")
        XCTAssertEqual(history.popular(in: .month, now: current).first?.opens, 2)
    }
    func testDiscoveryFiltersPreserveCategoryAndSearchSemantics() throws {
        let selection = SeasonSelection(season: .fall, year: 2026)
        let upcoming = DiscoveryFilters(category: .upcoming, selection: selection)
        let vars = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(upcoming.variables(page: 2))) as? [String: Any])
        XCTAssertEqual(vars["year"] as? Int, 2027)
        XCTAssertEqual(vars["season"] as? String, "WINTER")
        XCTAssertEqual(vars["status"] as? String, "NOT_YET_RELEASED")
        XCTAssertEqual(vars["page"] as? Int, 2)
        var trending = DiscoveryFilters(category: .trending)
        trending.search = "  Cowboy Bebop  "
        trending.genre = "Action"; trending.format = "TV"; trending.sort = .rating
        let search = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(trending.variables(page: 0))) as? [String: Any])
        XCTAssertEqual(search["page"] as? Int, 1)
        XCTAssertEqual(search["search"] as? String, "Cowboy Bebop")
        XCTAssertEqual(search["genre"] as? String, "Action")
        XCTAssertEqual(search["format"] as? String, "TV")
        XCTAssertEqual(search["sort"] as? String, "SCORE_DESC")
        XCTAssertNil(search["year"])
        XCTAssertNil(search["season"])
        XCTAssertTrue(AniListQueries.browse.contains("isAdult: $isAdult"))
    }
}

private actor FeedTransport: HTTPTransport {
    let feeds: [URL: (Int, String)]
    init(_ feeds: [URL: (Int, String)]) { self.feeds = feeds }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard let url = request.url, let (status, body) = feeds[url] else { throw ServiceError.invalidResponse }
        return (Data(body.utf8), HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

