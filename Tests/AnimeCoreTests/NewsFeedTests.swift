import XCTest
@testable import AnimeCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class NewsFeedTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func story(_ slug: String, _ title: String, source: NewsSource = .animeNewsNetwork, age: Double = 0, summary: String? = nil) -> NewsArticle {
        let domain = source == .crunchyroll ? "www.crunchyroll.com" : source == .animeCorner ? "animecorner.me" : "www.animenewsnetwork.com"
        return NewsArticle(title: title, url: URL(string: "https://\(domain)/news/\(slug)")!, publishedAt: now.addingTimeInterval(-age), imageURL: nil, source: source, summary: summary)
    }
    private func feed(_ articles: [NewsArticle], query: NewsFeedQuery = NewsFeedQuery(), preferences: NewsPreferences = NewsPreferences(),
                      reader: NewsReaderState = NewsReaderState(), history: NewsReadingHistory = NewsReadingHistory(),
                      library: [NewsLibraryTitle] = []) -> [NewsArticle] {
        NewsFeed.articles(articles, query: query, preferences: preferences, reader: reader, history: history, library: library, now: now)
    }
    func testLegacyBookmarksDecodeAndEnrichmentRetainsRSSMetadata() throws {
        let old = Data(#"{"title":"Legacy","url":"https://animecorner.me/a","source":"animeCorner"}"#.utf8)
        let article = try JSONDecoder().decode(NewsArticle.self, from: old)
        XCTAssertNil(article.summary); XCTAssertNil(article.categories)
        let rich = NewsArticle(title: "Rich", url: article.url, publishedAt: now, imageURL: nil, source: .animeCorner,
                               summary: "An excerpt", categories: ["Manga", "Novels"])
        let copy = rich.withImage(URL(string: "https://cdn.example.com/cover.png"))
        XCTAssertEqual(copy.summary, rich.summary); XCTAssertEqual(copy.categories, rich.categories)
        XCTAssertEqual(copy.id, rich.id)
        XCTAssertEqual(try JSONDecoder().decode(NewsArticle.self, from: JSONEncoder().encode(copy)), copy)
    }
    func testRSSPreservesNestedTextSeparateCategoriesAndShortPlainExcerpt() throws {
        let xml = """
        <rss><channel><item><title>A <b>new</b> manga</title><link>https://animecorner.me/owned</link>
        <description><![CDATA[<p>Publisher <b>excerpt</b> &amp; details.</p>]]></description>
        <category>Manga</category><category>Light Novels</category><category>Manga</category></item></channel></rss>
        """
        let article = try XCTUnwrap(RSSParser.parse(Data(xml.utf8), source: .animeCorner).first)
        XCTAssertEqual(article.title, "A new manga")
        XCTAssertEqual(article.summary, "Publisher excerpt & details.")
        XCTAssertEqual(article.categories, ["Manga", "Light Novels"])
        XCTAssertTrue(NewsTopic.manga.matches(article))
        let long = xml.replacingOccurrences(of: "Publisher <b>excerpt</b> &amp; details.", with: String(repeating: "word ", count: 400))
        XCTAssertLessThanOrEqual(try XCTUnwrap(RSSParser.parse(Data(long.utf8), source: .animeCorner).first?.summary).count, 500)
    }
    func testTopicBoundariesDoNotMatchUnrelatedWordFragments() {
        XCTAssertTrue(NewsTopic.dubs.matches(story("dub", "English cast revealed")))
        XCTAssertTrue(NewsTopic.trailers.matches(story("visual", "A new visual arrives")))
        XCTAssertFalse(NewsTopic.dubs.matches(story("other", "Undubbed show in Dublin")))
        XCTAssertFalse(NewsTopic.events.matches(story("other", "A panelist discusses prevention")))
        XCTAssertFalse(NewsTopic.manga.matches(story("other", "The novelist returns")))
    }
    func testSearchPublisherTopicDateAndReadFiltersCompose() {
        let a = story("a", "Harbor English dub", source: .crunchyroll, age: 60, summary: "The returning cast")
        let b = story("b", "Harbor manga", age: 10)
        let old = story("old", "Harbor English dub", source: .crunchyroll, age: 40 * 86400, summary: "Returning cast")
        var query = NewsFeedQuery(); query.source = .crunchyroll; query.topic = .dubs; query.text = "returning CAST"; query.timeRange = .week
        XCTAssertEqual(feed([b, old, a], query: query).map(\.id), [a.id])
        var reader = NewsReaderState(); reader.markRead(a, at: now); query.unreadOnly = true
        XCTAssertTrue(feed([b, old, a], query: query, reader: reader).isEmpty)
        reader.markUnread(a)
        XCTAssertEqual(feed([b, old, a], query: query, reader: reader).map(\.id), [a.id])
    }
    func testForYouUsesTitleAliasesAndFollowedTopicsWithoutFallbackStories() {
        let matched = story("a", "Sōlo Leveling announces a new season")
        let dubbed = story("b", "A different show reveals its English dub")
        let unrelated = story("c", "Solo Levelings studio opens an office")
        var query = NewsFeedQuery(); query.collection = .forYou
        let library = [NewsLibraryTitle(title: "Ore dake Level Up na Ken", aliases: ["Solo Leveling"])]
        XCTAssertEqual(feed([matched, dubbed, unrelated], query: query, library: library).count, 2)
        var preferences = NewsPreferences(); preferences.followedTopics = []
        XCTAssertEqual(feed([matched, dubbed, unrelated], query: query, preferences: preferences, library: library).map(\.id), [matched.id])
        XCTAssertTrue(feed([unrelated], query: query, preferences: preferences).isEmpty)
        XCTAssertEqual(NewsFeed.matchingTitles(matched, library: library), ["Ore dake Level Up na Ken"])
    }
    func testCanonicalDeduplicationHonorsSourceSelectionBeforeCollapsingLinks() {
        let a = story("shared", "Shared announcement")
        let duplicate = NewsArticle(title: "Official announcement", url: URL(string: "https://animenewsnetwork.com/news/shared?utm_source=livechart&fbclid=1#story")!,
                                    publishedAt: now.addingTimeInterval(-60), imageURL: nil, source: .liveChart, headlineID: 7)
        XCTAssertEqual(feed([duplicate, a]).map(\.source), [.animeNewsNetwork])
        var query = NewsFeedQuery(); query.source = .liveChart
        XCTAssertEqual(feed([duplicate, a], query: query).map(\.source), [.liveChart])
        var preferences = NewsPreferences(); preferences.enabledSources.remove(.animeNewsNetwork)
        XCTAssertEqual(feed([duplicate, a], preferences: preferences).map(\.source), [.liveChart])
        var reader = NewsReaderState(); reader.toggleSaved(a); reader.markRead(a, at: now)
        XCTAssertTrue(reader.isSaved(duplicate)); XCTAssertTrue(reader.isRead(duplicate))
        reader.toggleSaved(duplicate); XCTAssertTrue(reader.saved.isEmpty)
    }
    func testBookmarksSurviveFeedRemovalDisabledPublisherAndMutedPhrase() throws {
        let a = story("a", "Harbor manga", summary: "Saved publisher excerpt")
        var reader = NewsReaderState(); reader.toggleSaved(a)
        reader = try JSONDecoder().decode(NewsReaderState.self, from: JSONEncoder().encode(reader))
        var preferences = NewsPreferences(); preferences.enabledSources = []; preferences.mutedKeywords = ["harbor"]
        var query = NewsFeedQuery(); query.collection = .saved
        XCTAssertEqual(feed([], query: query, preferences: preferences, reader: reader), [a])
        XCTAssertTrue(feed([a], preferences: preferences).isEmpty)
        query.text = "excerpt"
        XCTAssertEqual(feed([], query: query, preferences: preferences, reader: reader), [a])
    }
    func testHistoryMigrationIsIdempotentAndMarkUnreadDoesNotEraseHistory() throws {
        let a = story("a", "A")
        var history = NewsReadingHistory(); history.record(a, at: now)
        var reader = NewsReaderState(); reader.migrate(history)
        XCTAssertTrue(reader.isRead(a)); reader.markUnread(a); reader.migrate(history)
        XCTAssertFalse(reader.isRead(a)); XCTAssertEqual(history.reads.count, 1)
        var query = NewsFeedQuery(); query.collection = .history; query.unreadOnly = true
        XCTAssertEqual(feed([], query: query, reader: reader, history: history), [a])
        let decoded = try JSONDecoder().decode(NewsReaderState.self, from: JSONEncoder().encode(reader))
        XCTAssertFalse(decoded.isRead(a)); XCTAssertTrue(decoded.migratedHistory)
    }
    func testHistoryOrdersLastOpenAndCollapsesRepeatedOpens() {
        let old = story("old", "Old publication", age: 5000), fresh = story("new", "Fresh publication")
        var history = NewsReadingHistory()
        history.record(old, at: now.addingTimeInterval(-30)); history.record(fresh, at: now.addingTimeInterval(-20)); history.record(old, at: now)
        var query = NewsFeedQuery(); query.collection = .history
        XCTAssertEqual(feed([], query: query, history: history).map(\.id), [old.id, fresh.id])
    }
    func testTimeRangesAndUnreadSortingAreDeterministic() {
        let a = story("a", "Read"), b = story("b", "Unread", age: 10)
        var state = NewsReaderState(); state.markRead(a, at: now)
        var query = NewsFeedQuery(); query.sort = .unreadFirst
        XCTAssertEqual(feed([a, b], query: query, reader: state).map(\.id), [b.id, a.id])
        query.sort = .oldest
        XCTAssertEqual(feed([a, b], query: query).map(\.id), [b.id, a.id])
        XCTAssertFalse(NewsTimeRange.week.includes(nil, now: now))
        XCTAssertFalse(NewsTimeRange.week.includes(now.addingTimeInterval(1), now: now))
        XCTAssertTrue(NewsTimeRange.all.includes(nil, now: now))
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: -7 * 3600)!
        XCTAssertTrue(NewsTimeRange.today.includes(calendar.startOfDay(for: now), now: now, calendar: calendar))
        XCTAssertFalse(NewsTimeRange.today.includes(calendar.startOfDay(for: now).addingTimeInterval(-1), now: now, calendar: calendar))
    }
    func testCacheRestoresAcrossClientsAndKeepsFailedPublisherAlongsideFreshNews() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let transport = NewsTestTransport()
        await transport.set(.animeNewsNetwork, title: "Cached ANN", slug: "old")
        let first = NewsClient(transport: transport, directory: directory)
        _ = try await first.snapshot()
        let restored = NewsClient(transport: transport, directory: directory)
        let saved = await restored.cachedSnapshot()
        XCTAssertEqual(saved?.articles.first?.title, "Cached ANN")
        await transport.failAll()
        await transport.set(.crunchyroll, title: "Fresh CR", slug: "new")
        let partial = try await restored.snapshot(refresh: true)
        XCTAssertEqual(Set(partial.articles.map(\.title)), Set(["Cached ANN", "Fresh CR"]))
        XCTAssertTrue(partial.isStale); XCTAssertTrue(partial.unavailableSources.contains("Anime News Network"))
        await transport.failAll()
        let offline = try await restored.snapshot(refresh: true)
        XCTAssertEqual(offline.articles.count, 2); XCTAssertTrue(offline.isStale); XCTAssertEqual(offline.unavailableSources.count, 4)
        await transport.set(.animeNewsNetwork, title: "Replacement ANN", slug: "replacement")
        let replacement = try await restored.snapshot(refresh: true)
        XCTAssertFalse(replacement.articles.contains { $0.title == "Cached ANN" })
        XCTAssertTrue(replacement.articles.contains { $0.title == "Replacement ANN" })
    }
    func testFreshCacheSkipsRequestsAndExplicitRefreshBypassesIt() async throws {
        let transport = NewsTestTransport(); await transport.succeedAll()
        let client = NewsClient(transport: transport, directory: nil)
        _ = try await client.snapshot(); _ = try await client.snapshot()
        let initial = await transport.count; XCTAssertEqual(initial, 4)
        _ = try await client.snapshot(refresh: true)
        let refreshed = await transport.count; XCTAssertEqual(refreshed, 8)
    }
    func testSimultaneousCallersShareOneBatchAndAnEmptyOutageThrows() async throws {
        let transport = NewsTestTransport(); await transport.succeedAll()
        let client = NewsClient(transport: transport, directory: nil)
        async let a = client.snapshot(); async let b = client.snapshot(refresh: true)
        let snapshots = try await (a, b)
        XCTAssertEqual(snapshots.0.articles, snapshots.1.articles)
        let count = await transport.count; XCTAssertEqual(count, 4)
        let empty = NewsClient(transport: NewsTestTransport(), directory: nil)
        do { _ = try await empty.snapshot(); XCTFail("Expected an unavailable-feed error") }
        catch { XCTAssertTrue(error.localizedDescription.contains("temporarily unavailable")) }
    }
    func testCorruptCacheIsIgnored() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("invalid".utf8).write(to: directory.appendingPathComponent("feeds-v1.json"))
        let client = NewsClient(transport: NewsTestTransport(), directory: directory)
        let saved = await client.cachedSnapshot(); XCTAssertNil(saved)
    }
}

private actor NewsTestTransport: HTTPTransport {
    var count = 0
    private var responses: [NewsSource: String] = [:]
    func set(_ source: NewsSource, title: String, slug: String) {
        let host = source == .crunchyroll ? "crunchyroll.com" : source == .animeCorner ? "animecorner.me" : "www.animenewsnetwork.com"
        responses[source] = """
        <rss><channel><item><title>\(title)</title><link>https://\(host)/news/\(slug)</link>
        <guid>https://www.livechart.me/headlines/5</guid></item></channel></rss>
        """
    }
    func succeedAll() { for source in NewsSource.allCases { set(source, title: source.label, slug: source.rawValue) } }
    func failAll() { responses = [:] }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        count += 1
        guard let url = request.url, let source = NewsSource.allCases.first(where: { $0.feedURL == url }) else { throw ServiceError.invalidResponse }
        let body = responses[source]
        try await Task.sleep(for: .milliseconds(30))
        return (Data((body ?? "").utf8), HTTPURLResponse(url: url, statusCode: body == nil ? 503 : 200, httpVersion: nil, headerFields: nil)!)
    }
}
