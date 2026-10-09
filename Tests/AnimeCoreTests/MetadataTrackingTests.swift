import XCTest
@testable import AnimeCore
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class MetadataTrackingTests: XCTestCase {
    func testLiveChartURLsValidateHostAndKeepSearchEncoding() throws {
        XCTAssertEqual(LiveChartURL.animeID(LiveChartURL.anime(3418)), 3418)
        for value in ["http://www.livechart.me/anime/1", "https://livechart.me.evil.test/anime/1", "https://user@livechart.me/anime/1", "https://www.livechart.me/anime/0", "https://www.livechart.me/anime/1/extra"] {
            XCTAssertNil(LiveChartURL.animeID(try XCTUnwrap(URL(string: value))))
        }
        let title = "A&B + #1 / 日本語"
        let parts = try XCTUnwrap(URLComponents(url: LiveChartURL.search(title), resolvingAgainstBaseURL: false))
        XCTAssertEqual(parts.queryItems?.first?.value, title)
        XCTAssertEqual(LiveChartURL.season(SeasonSelection(season: .fall, year: 2026)).path, "/fall-2026/tv")
    }
    func testMappingsRejectAmbiguousSeasonsMalformedRowsAndMissingIDs() throws {
        let index = try LiveChartMappingIndex(tsv: Data("title\tanilist\tlivechart\nCowboy\t1\t3418\nAgain\t1\t3418\nSplit A\t10\t20\nSplit B\t11\t20\nConflict A\t30\t40\nConflict B\t30\t41\nUnknown\t50\t\nMalformed\textra\t99\t100\n".utf8))
        XCTAssertEqual(index.liveChartID(aniListID: 1), 3418)
        XCTAssertEqual(index.aniListID(liveChartID: 3418), 1)
        XCTAssertNil(index.aniListID(liveChartID: 20))
        XCTAssertNil(index.liveChartID(aniListID: 10))
        XCTAssertNil(index.liveChartID(aniListID: 30))
        XCTAssertNil(index.aniListID(liveChartID: 40))
        XCTAssertNil(index.liveChartID(aniListID: 50))
        XCTAssertNil(index.liveChartID(aniListID: 99))
        XCTAssertThrowsError(try LiveChartMappingIndex(tsv: Data("<html>Verification required</html>".utf8)))
    }
    func testMappingDownloadsAreSharedAndContainNoAccountData() async throws {
        let transport = MetadataTransport([.text("title\tanilist\tlivechart\nCowboy\t1\t3418\n")])
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".tsv")
        defer { try? FileManager.default.removeItem(at: path) }
        let client = LiveChartClient(transport: transport, cacheFile: path)
        async let forward = client.liveChartID(aniListID: 1)
        async let reverse = client.aniListID(liveChartID: 3418)
        let result = try await (forward, reverse)
        XCTAssertEqual(result.0, 3418); XCTAssertEqual(result.1, 1)
        let requests = await transport.recorded()
        XCTAssertEqual(requests.count, 1)
        XCTAssertNil(requests.first?.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(requests.first?.url, LiveChartClient.mappingURL)
    }
    func testAdultSwitchUsesFalseOrNoFilterForAllBrowseQueries() async throws {
        let page = #"{"data":{"Page":{"media":[]}}}"#
        let details = #"{"data":{"Media":{"id":1}}}"#
        let explore = #"{"data":{"seasonal":{},"trending":{},"upcoming":{}}}"#
        let responses = [page, page, page, details, explore, page, page, page, details, explore].map { MetadataTransport.Response.text($0) }
        let transport = MetadataTransport(responses)
        let api = AniListClient(transport: transport, minimumRequestInterval: 0)
        for includeAdult in [false, true] {
            _ = try await api.search("A", includeAdult: includeAdult)
            _ = try await api.seasonal(.current(), page: 1, includeAdult: includeAdult)
            _ = try await api.browse(DiscoveryFilters(category: .trending), includeAdult: includeAdult)
            _ = try await api.details(id: 1, includeAdult: includeAdult)
            _ = try await api.explore(.current(), includeAdult: includeAdult)
        }
        let requests = await transport.recorded()
        XCTAssertEqual(requests.count, 10, "Adult and non-adult requests must not share a cache key.")
        for (index, request) in requests.enumerated() {
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
            let vars = try XCTUnwrap(body["variables"] as? [String: Any])
            if index < 5 { XCTAssertEqual(vars["isAdult"] as? Bool, false) }
            else { XCTAssertNil(vars["isAdult"], "Enabling adult content must keep regular anime too.") }
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        }
    }
    func testAdultAndSafeExploreDiskCachesStaySeparate() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let response = try JSONDecoder().decode(ExploreResponse.self, from: Data(#"{"seasonal":{"media":[{"id":1} ]},"trending":{},"upcoming":{}}"#.utf8))
        let season = SeasonSelection(season: .fall, year: 2026)
        let cache = ExploreCache(directory: directory)
        await cache.save(ExploreSnapshot(response: response, selection: season, includeAdult: true))
        let safe = await cache.load(season)
        XCTAssertNil(safe)
        await cache.save(ExploreSnapshot(response: response, selection: season))
        let restarted = ExploreCache(directory: directory)
        let adult = await restarted.load(season, includeAdult: true)
        let regular = await restarted.load(season)
        XCTAssertEqual(adult?.includesAdult, true); XCTAssertEqual(regular?.includesAdult, false)
        XCTAssertFalse(try XCTUnwrap(adult).isUsable(for: season))
    }
    func testQuickTrackingMovesPlanningPausedAndDroppedToWatching() throws {
        for status in [LibraryStatus.planning, .paused, .dropped] {
            let entry = try makeEntry(status: status, progress: 3)
            let edit = TrackingEdit.next(entry: entry, total: 12, automaticallyComplete: true)
            XCTAssertEqual(edit.progress, 4); XCTAssertEqual(edit.status, .watching)
            XCTAssertNil(edit.scoreRaw); XCTAssertNil(edit.notes); XCTAssertNil(edit.repeatCount)
        }
    }
    func testFinalEpisodeCompletesRewatchExactlyOnceAndSettingCanDisableIt() throws {
        let entry = try makeEntry(status: .rewatching, progress: 11, repeats: 2)
        let edit = TrackingEdit.next(entry: entry, total: 12, automaticallyComplete: true)
        XCTAssertEqual(edit.status, .completed); XCTAssertEqual(edit.repeatCount, 3)
        let disabled = TrackingEdit.next(entry: entry, total: 12, automaticallyComplete: false)
        XCTAssertEqual(disabled.status, .rewatching); XCTAssertNil(disabled.repeatCount)
        let unknown = TrackingEdit.next(entry: entry, total: nil, automaticallyComplete: true)
        XCTAssertEqual(unknown.status, .rewatching); XCTAssertNil(unknown.repeatCount)
    }
    func testEditorValidatesBoundsAndCompletesKnownTotals() throws {
        XCTAssertThrowsError(try TrackingEdit(progress: -1, status: .watching).validated(total: nil))
        XCTAssertThrowsError(try TrackingEdit(progress: 13, status: .watching).validated(total: 12))
        XCTAssertThrowsError(try TrackingEdit(progress: 1, status: .watching, scoreRaw: 101).validated(total: 12))
        XCTAssertThrowsError(try TrackingEdit(progress: 1, status: .watching, notes: String(repeating: "a", count: 6001)).validated(total: 12))
        XCTAssertThrowsError(try TrackingEdit(progress: 1, status: .watching, repeatCount: -1).validated(total: 12))
        XCTAssertEqual(try TrackingEdit(progress: 1000, status: .watching).validated(total: nil).progress, 1000)
        XCTAssertEqual(try TrackingEdit(progress: 5, status: .completed).validated(total: 12).progress, 12)
    }
    func testQuickSaveOmitsUneditedScoreNotesAndRewatchCount() async throws {
        let transport = MetadataTransport([.text(#"{"data":{"SaveMediaListEntry":{"id":55,"mediaId":1,"status":"CURRENT","progress":8,"score":85,"notes":"Existing notes","repeat":2}}}"#)])
        let api = AniListClient(transport: transport, minimumRequestInterval: 0)
        let saved = try await api.save(mediaId: 1, entryId: 55, progress: 8, status: .watching, token: "fixture-token")
        XCTAssertEqual(saved.score, 85); XCTAssertEqual(saved.notes, "Existing notes"); XCTAssertEqual(saved.repeatCount, 2)
        let requests = await transport.recorded()
        let vars = try variables(try XCTUnwrap(requests.first))
        XCTAssertNil(vars["scoreRaw"]); XCTAssertNil(vars["notes"]); XCTAssertNil(vars["repeat"])
    }
    func testEditorCanExplicitlyClearFieldsAndDeleteRequiresConfirmation() async throws {
        let transport = MetadataTransport([
            .text(#"{"data":{"SaveMediaListEntry":{"id":55,"mediaId":1,"status":"CURRENT","progress":8}}}"#),
            .text(#"{"data":{"DeleteMediaListEntry":{"deleted":false}}}"#),
            .text(#"{"data":{"DeleteMediaListEntry":{"deleted":true}}}"#)
        ])
        let api = AniListClient(transport: transport, minimumRequestInterval: 0)
        _ = try await api.save(mediaId: 1, entryId: 55, progress: 8, status: .watching, token: "fixture-token", scoreRaw: 0, notes: "", repeatCount: 0)
        do { try await api.delete(entryId: 55, token: "fixture-token"); XCTFail("An unconfirmed deletion must fail.") } catch {}
        try await api.delete(entryId: 55, token: "fixture-token")
        let requests = await transport.recorded()
        let vars = try variables(requests[0])
        XCTAssertEqual(vars["scoreRaw"] as? Int, 0); XCTAssertEqual(vars["notes"] as? String, ""); XCTAssertEqual(vars["repeat"] as? Int, 0)
        XCTAssertEqual(try variables(requests[2])["id"] as? Int, 55)
    }
    func testDetailsPullToRefreshBypassesCachedMetadata() async throws {
        let transport = MetadataTransport([.text(#"{"data":{"Media":{"id":1,"episodes":12}}}"#), .text(#"{"data":{"Media":{"id":1,"episodes":13}}}"#)])
        let api = AniListClient(transport: transport, minimumRequestInterval: 0)
        _ = try await api.details(id: 1)
        let cached = try await api.details(id: 1)
        let fresh = try await api.details(id: 1, refresh: true)
        XCTAssertEqual(cached.episodes, 12); XCTAssertEqual(fresh.episodes, 13)
        let requests = await transport.recorded(); XCTAssertEqual(requests.count, 2)
    }
    private func makeEntry(status: LibraryStatus, progress: Int, repeats: Int = 0) throws -> LibraryEntry {
        try JSONDecoder().decode(LibraryEntry.self, from: Data("{\"id\":55,\"mediaId\":1,\"status\":\"\(status.rawValue)\",\"progress\":\(progress),\"repeat\":\(repeats)}".utf8))
    }
    private func variables(_ request: URLRequest) throws -> [String: Any] {
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        return try XCTUnwrap(payload["variables"] as? [String: Any])
    }
}

private actor MetadataTransport: HTTPTransport {
    struct Response: Sendable {
        let data: Data
        static func text(_ value: String) -> Self { Self(data: Data(value.utf8)) }
    }
    private var responses: [Response]
    private var requests: [URLRequest] = []
    init(_ responses: [Response]) { self.responses = responses }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard !responses.isEmpty else { throw ServiceError.message("Unexpected request") }
        return (responses.removeFirst().data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
    func recorded() -> [URLRequest] { requests }
}
