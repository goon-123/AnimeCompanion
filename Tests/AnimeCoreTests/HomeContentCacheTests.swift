import XCTest
@testable import AnimeCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class HomeContentCacheTests: XCTestCase {
    private let selection = SeasonSelection(season: .winter, year: 2027)
    private func directory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    func testPublicHomeSnapshotsSurviveRelaunchAndRetainArtworkAndPreviews() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let media = try JSONDecoder().decode(CommunityMedia.self, from: Data(#"{"id":9,"type":"ANIME","title":{"english":"Known series"},"coverImage":{"large":"https://example.com/poster.jpg"}}"#.utf8))
        let thread = CommunityThread(source: .aniList, threadID: 4, title: "Episode 2", author: "Viewer", activityAt: Date(), commentCount: 5,
            media: [media], url: URL(string: "https://anilist.co/forum/thread/4")!, body: "<p>Opening preview</p>")
        let cache = HomeContentCache(directory: folder)
        let saved = await cache.save(HomeContentSnapshot(CommunityThreadPage(threads: [thread], hasNextPage: true)), key: HomeCommunityClient.cacheKey(mediaIDs: [42], includeAdult: false))
        XCTAssertTrue(saved)
        let restored = await HomeContentCache(directory: folder).load(CommunityThreadPage.self, key: HomeCommunityClient.cacheKey(mediaIDs: [42], includeAdult: false))
        XCTAssertEqual(restored?.value.threads, [thread]); XCTAssertEqual(restored?.value.hasNextPage, true)
        XCTAssertEqual(restored?.value.threads.first?.media.first?.coverURL?.lastPathComponent, "poster.jpg")
        XCTAssertTrue(thread.hidesPreview(progress: [:]))
    }
    func testStaleSnapshotDisplaysUntilExpiryAndCorruptionCanBeReplaced() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let cache = HomeContentCache(directory: folder)
        let now = Date(); let snapshot = HomeContentSnapshot([Anime(id: 1, title: "Saved")], savedAt: now.addingTimeInterval(-3600))
        await cache.save(snapshot, key: "lineup")
        let stale = await cache.load([Anime].self, key: "lineup", now: now)
        XCTAssertTrue(try XCTUnwrap(stale).needsRefresh(at: now))
        let expired = await cache.load([Anime].self, key: "lineup", now: now.addingTimeInterval(7 * 86400))
        XCTAssertNil(expired)
        let file = folder.appendingPathComponent("lineup.json")
        try Data("broken".utf8).write(to: file)
        let corrupt = await HomeContentCache(directory: folder).load([Anime].self, key: "lineup")
        XCTAssertNil(corrupt)
        await cache.save(HomeContentSnapshot([Anime(id: 2, title: "Fresh")]), key: "lineup")
        let replaced = await HomeContentCache(directory: folder).load([Anime].self, key: "lineup")
        XCTAssertEqual(replaced?.value.first?.id, 2)
    }
    func testMultipleWidgetsShareOneRequestAndFreshLineupSurvivesClientRecreation() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let transport = HomeCacheTransport()
        let api = AniListClient(transport: transport, minimumRequestInterval: 0)
        let client = HomeCatalogClient(api: api, cache: HomeContentCache(directory: folder))
        async let countdown = client.season(selection, includeAdult: false)
        async let premieres = client.season(selection, includeAdult: false)
        async let returning = client.season(selection, includeAdult: false)
        let values = try await [countdown, premieres, returning]
        XCTAssertEqual(values.map { $0.value.first?.id }, [42, 42, 42])
        let count = await transport.count; XCTAssertEqual(count, 1)
        let relaunched = HomeCatalogClient(api: api, cache: HomeContentCache(directory: folder))
        _ = try await relaunched.season(selection, includeAdult: false)
        let stillOne = await transport.count; XCTAssertEqual(stillOne, 1)
        _ = try await relaunched.season(selection, includeAdult: true)
        let separateFilter = await transport.count; XCTAssertEqual(separateFilter, 2)
        _ = try await relaunched.season(selection, includeAdult: true, refresh: true)
        let manualRefresh = await transport.count; XCTAssertEqual(manualRefresh, 3)
    }
    func testOfflineRefreshPreservesUsableSavedCommunity() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let cache = HomeContentCache(directory: folder)
        let thread = CommunityThread(source: .aniList, threadID: 4, title: "Saved conversation", author: nil, activityAt: nil, commentCount: 4,
            url: URL(string: "https://anilist.co/forum/thread/4")!)
        await cache.save(HomeContentSnapshot(CommunityThreadPage(threads: [thread], hasNextPage: false), savedAt: Date().addingTimeInterval(-3600)), key: HomeCommunityClient.cacheKey(mediaIDs: [42], includeAdult: false))
        let client = HomeCommunityClient(api: AniListClient(transport: HomeCacheTransport(offline: true), minimumRequestInterval: 0), cache: cache)
        do { _ = try await client.feed(mediaIDs: [42], includeAdult: false); XCTFail("Expected offline failure") } catch {}
        let retained = await client.cached(mediaIDs: [42], includeAdult: false)
        XCTAssertEqual(retained?.value.threads.map(\.threadID), [4])
    }
    func testDiskHistoryIsBoundedAndUnavailableDiskStillServesMemory() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let cache = HomeContentCache(directory: folder)
        for index in 0..<20 { await cache.save(HomeContentSnapshot([Anime(id: index, title: "Saved")]), key: "season-\(index)") }
        XCTAssertLessThanOrEqual(try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).count, 16)
        let memory = HomeContentCache(directory: nil)
        await memory.save(HomeContentSnapshot([Anime(id: 9, title: "Memory")]), key: "offline")
        let restored = await memory.load([Anime].self, key: "offline")
        XCTAssertEqual(restored?.value.first?.id, 9)
    }
}

private actor HomeCacheTransport: HTTPTransport {
    private(set) var count = 0
    let offline: Bool
    init(offline: Bool = false) { self.offline = offline }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        count += 1
        if offline { throw URLError(.notConnectedToInternet) }
        let bytes = Data(#"{"data":{"Page":{"media":[{"id":42,"title":{"english":"Winter premiere"},"startDate":{"year":2027,"month":1,"day":8}}],"pageInfo":{"hasNextPage":false}}}}"#.utf8)
        return (bytes, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}
