import XCTest
@testable import AnimeCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class SeriesNewsTests: XCTestCase {
    private func anime(_ english: String = "Moonlit Relay Season 3", romaji: String? = "Tsukikage Relay 3rd Season", id: Int = 1) throws -> Anime {
        var titles = ["english": english]
        if let romaji { titles["romaji"] = romaji }
        return try JSONDecoder().decode(Anime.self, from: JSONSerialization.data(withJSONObject: ["id": id, "title": titles]))
    }
    private func story(_ title: String) -> NewsArticle {
        NewsArticle(title: title, url: URL(string: "https://animecorner.me/owned")!, publishedAt: nil, imageURL: nil, source: .animeCorner)
    }
    func testSeriesSeasonAliasesMatchBaseTitlesOrdinalsAndOtherSeasons() throws {
        let series = try anime()
        for headline in ["Moonlit Relay reveals a new season", "Moonlit Relay's 3rd Season announces cast", "Moonlit Relay Season 2 trailer", "Tsukikage Relay cast returns"] {
            XCTAssertTrue(AnimeUpdates.headline(story(headline), matches: series), headline)
        }
        XCTAssertFalse(AnimeUpdates.headline(story("Moonlit Relays announces cast"), matches: series))
        XCTAssertFalse(AnimeUpdates.headline(story("Another Relay Season 3"), matches: series))
        XCTAssertEqual(NewsFeed.matchingTitles(story("Moonlit Relay returns"), library: [NewsLibraryTitle(anime: series)]), [series.displayTitle])
    }
    func testSuffixRemovalPreservesIntrinsicNumbersAndAvoidsAmbiguousShortNames() throws {
        let series = try anime("Sector 86 Season 3 Part 2", romaji: nil)
        XCTAssertTrue(AnimeUpdates.headline(story("Sector 86 returns"), matches: series))
        XCTAssertFalse(AnimeUpdates.headline(story("Sector 87 returns"), matches: series))
        XCTAssertFalse(AnimeUpdates.headline(story("Sector returns"), matches: series))
        XCTAssertEqual(AnimeUpdates.headlineSearchTerms(for: try anime("Hero 3", romaji: nil)), ["hero 3"])
        XCTAssertEqual(AnimeUpdates.headlineSearchTerms(for: try anime("AI Season 2", romaji: nil)), ["ai season 2"])
        XCTAssertTrue(AnimeUpdates.headline(story("Moonlit Relay trailer"), matches: try anime("Moonlit Relay: The Final Season Part 2", romaji: nil)))
    }
    func testSearchUsesBaseEnglishAndRomajiWithSafeQueryEncoding() throws {
        let series = try anime("The Moonlit Relay Season 3")
        XCTAssertEqual(AnimeUpdates.headlineSearchTerms(for: series), ["moonlit relay", "tsukikage relay"])
        let url = try XCTUnwrap(SeriesNewsClient.searchURL(for: "moonlit relay & sky"))
        XCTAssertEqual(url.host, "animecorner.me"); XCTAssertEqual(url.path, "/")
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(items, [URLQueryItem(name: "s", value: "moonlit relay & sky")])
        XCTAssertNil(SeriesNewsClient.searchURL(for: ""))
        XCTAssertTrue(AnimeUpdates.headline(story("Moonlit Relay returns"), matches: series))
    }
    func testSearchParserReadsOnlyListingMetadataAndValidPublisherLinks() throws {
        let html = """
        <section class="ac-search-shell"><form class="ac-search-form"><input name="s" value="moonlit relay"></form>
        <div class="ac-archive-grid"><article class="ac-archive-card">
        <span data-bgset="https://static.animecorner.me/owned.png"></span><div class="ac-archive-card__body">
        <h2><a href="https://animecorner.me/owned">Moonlit Relay &amp; the new cast</a></h2>
        <time>September 1, 2026</time><p>Owned <b>short</b> listing excerpt.</p></div></article>
        <article class="ac-archive-card"><h2><a href="https://animecorner.me.attacker.example/owned">Unsafe title</a></h2></article>
        </div></section><article><h2><a href="https://animecorner.me/sidebar">Unrelated sidebar</a></h2></article>
        """
        let articles = try SeriesNewsParser.parse(Data(html.utf8), searchTerm: "moonlit relay")
        XCTAssertEqual(articles.count, 1)
        let item = try XCTUnwrap(articles.first)
        XCTAssertEqual(item.title, "Moonlit Relay & the new cast")
        XCTAssertEqual(item.summary, "Owned short listing excerpt.")
        XCTAssertEqual(item.imageURL?.absoluteString, "https://static.animecorner.me/owned.png")
        XCTAssertEqual(item.publishedAt, SourceDates.parse("2026-09-01T00:00:00Z"))
    }
    func testSearchParserDistinguishesAnEmptySearchFromIgnoredQueriesAndChangedMarkup() throws {
        let empty = "<section class='ac-search-shell'><form class='ac-search-form'><input name='s' value='moonlit relay'></form><div class='ac-search-empty'></div></section>"
        XCTAssertTrue(try SeriesNewsParser.parse(Data(empty.utf8), searchTerm: "moonlit relay").isEmpty)
        XCTAssertThrowsError(try SeriesNewsParser.parse(Data(empty.utf8), searchTerm: "different series"))
        XCTAssertThrowsError(try SeriesNewsParser.parse(Data(empty.replacingOccurrences(of: "ac-search-empty", with: "changed-markup").utf8), searchTerm: "moonlit relay"))
        let changedCards = empty.replacingOccurrences(of: "<div class='ac-search-empty'></div>", with: "<div class='ac-archive-grid'><article class='ac-archive-card'><h3>Changed listing contract</h3></article></div>")
        XCTAssertThrowsError(try SeriesNewsParser.parse(Data(changedCards.utf8), searchTerm: "moonlit relay"))
        XCTAssertThrowsError(try SeriesNewsParser.parse(Data("<html>Please wait</html>".utf8), searchTerm: "moonlit relay"))
        XCTAssertThrowsError(try SeriesNewsParser.parse(Data(repeating: 32, count: 2_000_001), searchTerm: "moonlit relay"))
    }
    func testArchiveFindsOlderStoriesAbsentFromMainFeedsAndRejectsUnrelatedSearchResults() async throws {
        let transport = SeriesNewsTestTransport()
        await transport.set("moonlit relay", titles: ["Moonlit Relay cast returns", "Unrelated fantasy announcement"])
        await transport.set("tsukikage relay", titles: ["Tsukikage Relay trailer arrives"])
        let client = NewsClient(transport: transport, directory: nil)
        let series = try anime()
        let recent = try await client.snapshot()
        XCTAssertTrue(recent.articles.filter { AnimeUpdates.headline($0, matches: series) }.isEmpty)
        let archive = try await client.seriesSnapshot(for: series)
        XCTAssertEqual(Set(archive.articles.map(\.title)), ["Moonlit Relay cast returns", "Tsukikage Relay trailer arrives"])
        XCTAssertFalse(archive.unavailable)
        let mainAgain = try await client.snapshot()
        XCTAssertEqual(mainAgain.articles, recent.articles, "A series search cannot replace the global feed")
        XCTAssertTrue(archive.articles.allSatisfy { $0.source == .animeCorner && $0.publishedAt! < Date().addingTimeInterval(-86400) })
    }
    func testArchiveCacheRestoresAndFailedRefreshKeepsStories() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let series = try anime(romaji: nil), transport = SeriesNewsTestTransport()
        await transport.set("moonlit relay", titles: ["Moonlit Relay returns"])
        let first = SeriesNewsClient(transport: transport, directory: directory)
        let initial = try await first.snapshot(for: series)
        let restored = SeriesNewsClient(transport: transport, directory: directory)
        let saved = await restored.cachedSnapshot(for: series)
        XCTAssertEqual(saved?.articles, initial.articles)
        _ = try await restored.snapshot(for: series)
        let freshCount = await transport.searchCount; XCTAssertEqual(freshCount, 1)
        await transport.fail("moonlit relay")
        let offline = try await restored.snapshot(for: series, refresh: true)
        XCTAssertEqual(offline.articles, initial.articles); XCTAssertEqual(offline.updatedAt, initial.updatedAt)
        XCTAssertTrue(offline.unavailable); XCTAssertTrue(offline.isStale)
        _ = try await restored.snapshot(for: series)
        let failedCount = await transport.searchCount; XCTAssertEqual(failedCount, 2, "Automatic retry is cooled down")
    }
    func testPartialArchiveFailureKeepsSuccessfulAliasAndRecentFeedsWorkDuringTotalOutage() async throws {
        let transport = SeriesNewsTestTransport(), series = try anime()
        await transport.set("moonlit relay", titles: ["Moonlit Relay returns"])
        let client = NewsClient(transport: transport, directory: nil)
        let partial = try await client.seriesSnapshot(for: series)
        XCTAssertEqual(partial.articles.count, 1); XCTAssertTrue(partial.unavailable)
        await transport.fail("moonlit relay")
        let offline = try await client.seriesSnapshot(for: series, refresh: true)
        XCTAssertEqual(offline.articles, partial.articles)
        let recent = try await client.snapshot()
        XCTAssertFalse(recent.articles.isEmpty)
    }
    func testSuccessfulEmptySearchIsCachedAndManualRefreshCanReplaceOldResults() async throws {
        let transport = SeriesNewsTestTransport(), series = try anime(romaji: nil)
        await transport.set("moonlit relay", titles: ["Moonlit Relay returns"])
        let client = SeriesNewsClient(transport: transport, directory: nil)
        _ = try await client.snapshot(for: series)
        await transport.set("moonlit relay", titles: [])
        let empty = try await client.snapshot(for: series, refresh: true)
        XCTAssertTrue(empty.articles.isEmpty); XCTAssertFalse(empty.unavailable)
        _ = try await client.snapshot(for: series)
        let count = await transport.searchCount; XCTAssertEqual(count, 2)
    }
    func testConcurrentSearchesCoalesceAndUnknownTitlesDoNotRequestAllNews() async throws {
        let transport = SeriesNewsTestTransport(), series = try anime(romaji: nil)
        await transport.set("moonlit relay", titles: ["Moonlit Relay returns"])
        let client = SeriesNewsClient(transport: transport, directory: nil)
        async let a = client.snapshot(for: series)
        async let b = client.snapshot(for: series, refresh: true)
        let (one, two) = try await (a, b)
        XCTAssertEqual(one.articles, two.articles)
        let unknown = try JSONDecoder().decode(Anime.self, from: Data(#"{"id":2}"#.utf8))
        let empty = try await client.snapshot(for: unknown)
        XCTAssertTrue(empty.articles.isEmpty)
        let count = await transport.searchCount; XCTAssertEqual(count, 1)
    }
    func testCachedResultsExpireAndCorruptCacheIsIgnored() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let transport = SeriesNewsTestTransport(), series = try anime(romaji: nil)
        await transport.set("moonlit relay", titles: ["Moonlit Relay returns"])
        let client = SeriesNewsClient(transport: transport, directory: directory)
        _ = try await client.snapshot(for: series)
        let expired = await client.cachedSnapshot(for: series, now: Date().addingTimeInterval(8 * 86400))
        XCTAssertNil(expired)
        try Data("not JSON".utf8).write(to: directory.appendingPathComponent("series-v1.json"))
        let corrupt = SeriesNewsClient(transport: transport, directory: directory)
        let snapshot = await corrupt.cachedSnapshot(for: series)
        XCTAssertNil(snapshot)
    }
}

private actor SeriesNewsTestTransport: HTTPTransport {
    private var titles: [String: [String]] = [:]
    var searchCount = 0
    func set(_ term: String, titles: [String]) { self.titles[term] = titles }
    func fail(_ term: String) { titles[term] = nil }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let url = request.url!
        let term = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "s" }?.value
        let source = NewsSource.allCases.first { $0.feedURL == url }
        let values: [String]?
        if let term { searchCount += 1; values = titles[term] }
        else { values = source == nil ? nil : ["Unrelated recent headline"] }
        try await Task.sleep(for: .milliseconds(30))
        let host = source == .crunchyroll ? "crunchyroll.com" : source == .animeNewsNetwork ? "animenewsnetwork.com" : "animecorner.me"
        let items = (values ?? []).map { title in
            let slug = NewsFeed.normalized(title).replacingOccurrences(of: " ", with: "-")
            return "<item><title>\(title)</title><link>https://\(host)/\(slug)</link><guid>https://www.livechart.me/headlines/900001</guid><pubDate>Tue, 01 Sep 2026 12:00:00 +0000</pubDate></item>"
        }.joined()
        let body: String
        if let term {
            body = "<section class='ac-search-shell'><form class='ac-search-form'><input name='s' value='\(term)'></form><div class='ac-archive-grid'>" + (values ?? []).map { title in
                let slug = NewsFeed.normalized(title).replacingOccurrences(of: " ", with: "-")
                return "<article class='ac-archive-card'><div class='ac-archive-card__body'><h2><a href='https://animecorner.me/\(slug)'>\(title)</a></h2><time>September 1, 2026</time><p>Owned publisher listing excerpt.</p></div></article>"
            }.joined() + "</div>" + ((values ?? []).isEmpty ? "<div class='ac-search-empty'></div>" : "") + "</section>"
        } else { body = "<rss><channel>\(items)</channel></rss>" }
        return (Data(body.utf8), HTTPURLResponse(url: url, statusCode: values == nil ? 503 : 200, httpVersion: nil, headerFields: nil)!)
    }
}
