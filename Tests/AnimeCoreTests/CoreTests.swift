import XCTest
@testable import AnimeCore
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class CoreTests: XCTestCase {
    private func fixture(_ name: String, _ ext: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: ext))
        return try Data(contentsOf: url)
    }
    func testSeasonRolloverAndLocalTimezone() throws {
        XCTAssertEqual(SeasonSelection(season: .fall, year: 2026).advanced(by: 1), SeasonSelection(season: .winter, year: 2027))
        XCTAssertEqual(SeasonSelection(season: .winter, year: 2026).advanced(by: -1), SeasonSelection(season: .fall, year: 2025))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let date = try XCTUnwrap(SourceDates.parse("2026-10-01T01:00:00Z"))
        XCTAssertEqual(SeasonSelection.current(at: date, calendar: calendar).season, .summer)
    }
    func testProgressBoundsIncludingUnknownEpisodeCount() {
        XCTAssertEqual(LibraryEntry.clampedProgress(-1, total: nil), 0)
        XCTAssertEqual(LibraryEntry.clampedProgress(1200, total: nil), 1200)
        XCTAssertEqual(LibraryEntry.clampedProgress(15, total: 12), 12)
        XCTAssertEqual(LibraryEntry.clampedProgress(15, total: 0), 15)
    }
    func testDubNormalizationKeepsActualDatesAndNoInventedRecurrence() throws {
        let current = try JSONDecoder().decode([RawDubItem].self, from: fixture("dub-current", "json"))
        let history = try JSONDecoder().decode([RawDubFeedItem].self, from: fixture("dub-history", "json"))
        let now = try XCTUnwrap(SourceDates.parse("2026-10-04T20:00:00Z"))
        let events = DubSnapshot(upcoming: current, history: history).events(now: now)
        XCTAssertEqual(events.count, 5)
        let recorded = try XCTUnwrap(events.first { $0.anime.id == 100 && $0.episode == 3 })
        XCTAssertEqual(recorded.date, SourceDates.parse("2026-10-03T15:00:00Z"))
        XCTAssertEqual(recorded.certainty, .recorded)
        XCTAssertFalse(events.contains { $0.episode == 99 })
        XCTAssertFalse(events.contains { $0.episode == 6 })
        let delayed = try XCTUnwrap(events.first { $0.anime.id == 101 })
        XCTAssertNil(delayed.date)
        XCTAssertEqual(delayed.certainty, .delayed)
        XCTAssertEqual(events.first { $0.anime.id == 102 }?.certainty, .unverified)
    }
    func testDubIndexDoesNotConfuseMissingMALIdWithNoDub() throws {
        let data = Data("{\"dubbed\":[1,2],\"partial\":[2,3]}".utf8)
        let index = try JSONDecoder().decode(DubIndex.self, from: data)
        XCTAssertEqual(index.availability(malId: nil), .unknown)
        XCTAssertEqual(index.availability(malId: 1), .dubbed)
        XCTAssertEqual(index.availability(malId: 2), .partial)
        XCTAssertEqual(index.availability(malId: 3), .partial)
        XCTAssertEqual(index.availability(malId: 4), .notReported)
        XCTAssertThrowsError(try JSONDecoder().decode(DubIndex.self, from: Data("{\"new_schema\":[]}".utf8)))
        let legacy = try JSONDecoder().decode(DubIndex.self, from: Data("[1,2]".utf8))
        XCTAssertEqual(legacy.availability(malId: 1), .dubbed)
    }
    func testRSSHandlesCDATAOffsetDatesDuplicatesAndUnsafeLinks() throws {
        let items = try RSSParser.parse(fixture("news", "xml"))
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items.first?.title, "Test & announcement")
        XCTAssertEqual(items.first?.publishedAt, SourceDates.parse("2026-10-03T17:00:00Z"))
        XCTAssertNil(items.first?.imageURL)
        XCTAssertThrowsError(try RSSParser.parse(Data("<rss><broken>".utf8)))
    }
    func testCallbackRequiresCorrectRedirectAndBearerToken() throws {
        let expected = try XCTUnwrap(URL(string: "animecompanion://oauth/anilist"))
        let valid = try XCTUnwrap(URL(string: "animecompanion://oauth/anilist#access_token=test-token&token_type=Bearer&expires_in=3600"))
        let now = Date(timeIntervalSince1970: 1000)
        let token = try OAuthCallback.parse(valid, expectedRedirect: expected, now: now)
        XCTAssertEqual(token.accessToken, "test-token")
        XCTAssertEqual(token.expiresAt, Date(timeIntervalSince1970: 4600))
        XCTAssertThrowsError(try OAuthCallback.parse(URL(string: "animecompanion://attacker/anilist#access_token=x&token_type=Bearer")!, expectedRedirect: expected))
        XCTAssertThrowsError(try OAuthCallback.parse(URL(string: "animecompanion://oauth/anilist#access_token=x&access_token=y&token_type=Bearer")!, expectedRedirect: expected))
        XCTAssertThrowsError(try OAuthCallback.parse(URL(string: "animecompanion://oauth/anilist#access_token=x&token_type=Bearer&expires_in=0")!, expectedRedirect: expected))
    }
    func testTimestampFormatsAndInvalidValues() throws {
        let seconds = try JSONDecoder().decode(SourceTimestamp.self, from: Data("1000".utf8))
        XCTAssertEqual(seconds.date, Date(timeIntervalSince1970: 1000))
        let millis = try JSONDecoder().decode(SourceTimestamp.self, from: Data("1800000000000".utf8))
        XCTAssertEqual(millis.date, Date(timeIntervalSince1970: 1800000000))
        let bad = try JSONDecoder().decode(SourceTimestamp.self, from: Data("\"unknown\"".utf8))
        XCTAssertNil(bad.date)
    }
    func testAniListPublicRequestsDoNotNeedCredentials() async throws {
        let transport = MockTransport([.json("{\"data\":{\"Page\":{\"media\":[],\"pageInfo\":{\"hasNextPage\":false}}}}")])
        let api = AniListClient(transport: transport, minimumRequestInterval: 0)
        _ = try await api.search("Test")
        let requests = await transport.recorded()
        XCTAssertNil(requests.first?.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(requests.first?.httpMethod, "POST")
        let payload = try JSONSerialization.jsonObject(with: XCTUnwrap(requests.first?.httpBody)) as? [String: Any]
        XCTAssertEqual((payload?["variables"] as? [String: Any])?["search"] as? String, "Test")
    }
    func testEcchiGenreReachesTheBrowseRequestAndCanBeCleared() async throws {
        XCTAssertTrue(DiscoveryGenres.all.contains("Ecchi"))
        let transport = MockTransport([.json(#"{"data":{"Page":{"media":[]}}}"#)])
        let api = AniListClient(transport: transport, minimumRequestInterval: 0)
        var filters = DiscoveryFilters(category: .trending)
        filters.genre = "Ecchi"
        _ = try await api.browse(filters)
        let requests = await transport.recorded()
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(requests.first?.httpBody)) as? [String: Any])
        XCTAssertEqual((payload["variables"] as? [String: Any])?["genre"] as? String, "Ecchi")
        XCTAssertNil(requests.first?.value(forHTTPHeaderField: "Authorization"))
        filters.genre = nil
        XCTAssertNil(filters.variables(page: 1)["genre"])
    }
    func testCollectionIncludesCustomListsAndDeduplicatesMedia() async throws {
        let entry = "{\"id\":55,\"mediaId\":100,\"status\":\"CURRENT\",\"progress\":7}"
        let custom = "{\"id\":56,\"mediaId\":101,\"status\":\"PAUSED\",\"progress\":4}"
        let response = "{\"data\":{\"MediaListCollection\":{\"lists\":[{\"entries\":[\(entry)]},{\"entries\":[\(entry),\(custom)]}]}}}"
        let transport = MockTransport([.json(response)])
        let api = AniListClient(transport: transport, minimumRequestInterval: 0)
        let entries = try await api.library(userId: 999, token: "test-token")
        XCTAssertEqual(entries.map(\.mediaId), [100,101])
        let requests = await transport.recorded()
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
        let payload = try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any]
        XCTAssertEqual((payload?["variables"] as? [String: Any])?["userId"] as? Int, 999)
    }
    func testMutationUsesListEntryIdAndPreservesServerConfirmedProgress() async throws {
        let response = "{\"data\":{\"SaveMediaListEntry\":{\"id\":55,\"mediaId\":100,\"status\":\"CURRENT\",\"progress\":8}}}"
        let transport = MockTransport([.json(response)])
        let api = AniListClient(transport: transport, minimumRequestInterval: 0)
        let entry = try await api.save(mediaId: 100, entryId: 55, progress: 8, status: .watching, token: "test-token")
        XCTAssertEqual(entry.progressValue, 8)
        let requests = await transport.recorded()
        let payload = try JSONSerialization.jsonObject(with: XCTUnwrap(requests.first?.httpBody)) as? [String: Any]
        let vars = try XCTUnwrap(payload?["variables"] as? [String: Any])
        XCTAssertEqual(vars["id"] as? Int, 55)
        XCTAssertEqual(vars["mediaId"] as? Int, 100)
    }
    func testUnauthorizedAndRateLimitAreExplicitErrors() async throws {
        let transport = MockTransport([.json("{}", status: 401), .json("{}", status: 429, headers: ["Retry-After":"15"])])
        let api = AniListClient(transport: transport, minimumRequestInterval: 0)
        do { _ = try await api.viewer(token: "invalid"); XCTFail("Expected rejection") }
        catch { XCTAssertEqual(error as? ServiceError, .unauthorized) }
        do { _ = try await api.search("Test"); XCTFail("Expected rejection") }
        catch { XCTAssertEqual(error as? ServiceError, .rateLimited(15)) }
    }
    func testPublicCacheAvoidsDuplicateRequests() async throws {
        let transport = MockTransport([.json("{\"data\":{\"Page\":{\"media\":[]}}}")])
        let api = AniListClient(transport: transport, minimumRequestInterval: 0)
        _ = try await api.search("Test"); _ = try await api.search("Test")
        let requests = await transport.recorded(); XCTAssertEqual(requests.count, 1)
    }
    func testAiringPaginationIncludesEpisodesAcrossPages() async throws {
        let first = "{\"data\":{\"Page\":{\"pageInfo\":{\"hasNextPage\":true},\"airingSchedules\":[{\"airingAt\":1000,\"episode\":1,\"media\":{\"id\":1}}]}}}"
        let second = "{\"data\":{\"Page\":{\"pageInfo\":{\"hasNextPage\":false},\"airingSchedules\":[{\"airingAt\":2000,\"episode\":2,\"media\":{\"id\":2}}]}}}"
        let transport = MockTransport([.json(first), .json(second)])
        let api = AniListClient(transport: transport, minimumRequestInterval: 0)
        let events = try await api.airings(in: DateInterval(start: Date(timeIntervalSince1970: 0), duration: 3000))
        XCTAssertEqual(events.count, 2)
        let requests = await transport.recorded(); XCTAssertEqual(requests.count, 2)
    }
    func testCapturedUpstreamSchemasWhenProvided() throws {
        guard let path = ProcessInfo.processInfo.environment["LIVE_FIXTURE_DIR"] else { throw XCTSkip("Captured upstream files are optional") }
        let root = URL(fileURLWithPath: path)
        let current = try JSONDecoder().decode([RawDubItem].self, from: Data(contentsOf: root.appendingPathComponent("dub-schedule.json")))
        let history = try JSONDecoder().decode([RawDubFeedItem].self, from: Data(contentsOf: root.appendingPathComponent("dub-feed.json")))
        let index = try JSONDecoder().decode(DubIndex.self, from: Data(contentsOf: root.appendingPathComponent("dub-index.json")))
        let news = try RSSParser.parse(Data(contentsOf: root.appendingPathComponent("news.xml")))
        XCTAssertFalse(current.isEmpty); XCTAssertFalse(history.isEmpty); XCTAssertFalse(index.dubbed.isEmpty); XCTAssertFalse(news.isEmpty)
        let events = DubSnapshot(upcoming: current, history: history).events()
        XCTAssertEqual(events.count, Set(events.map(\.id)).count)
        XCTAssertFalse(events.filter { $0.certainty == .delayed && $0.date == nil }.isEmpty)
    }
}

private actor MockTransport: HTTPTransport {
    struct Response: Sendable {
        let data: Data; let status: Int; let headers: [String: String]
        static func json(_ value: String, status: Int = 200, headers: [String: String] = [:]) -> Self {
            Self(data: Data(value.utf8), status: status, headers: headers)
        }
    }
    private var queue: [Response]
    private var requests: [URLRequest] = []
    init(_ queue: [Response]) { self.queue = queue }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard !queue.isEmpty else { throw ServiceError.message("Unexpected extra request") }
        let next = queue.removeFirst()
        return (next.data, HTTPURLResponse(url: request.url!, statusCode: next.status, httpVersion: nil, headerFields: next.headers)!)
    }
    func recorded() -> [URLRequest] { requests }
}
