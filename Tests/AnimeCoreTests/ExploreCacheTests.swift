import XCTest
@testable import AnimeCore

final class ExploreCacheTests: XCTestCase {
    private let selection = SeasonSelection(season: .fall, year: 2026)
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func directory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    private func snapshot(id: Int = 1, selection: SeasonSelection? = nil, savedAt: Date? = nil) -> ExploreSnapshot {
        let page = MediaPage(media: [Anime(id: id, title: "Saved title")], pageInfo: PageInfo(hasNextPage: true))
        return ExploreSnapshot(response: ExploreResponse(seasonal: page, trending: page, upcoming: page),
            selection: selection ?? self.selection, savedAt: savedAt ?? now)
    }
    func testCatalogSurvivesNewInstanceAndStaysWithItsSeason() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let original = ExploreCache(directory: folder)
        let saved = await original.save(snapshot())
        XCTAssertTrue(saved)
        let relaunched = ExploreCache(directory: folder)
        let restored = await relaunched.load(selection, now: now)
        XCTAssertEqual(restored?.response.trending.media?.first?.id, 1)
        XCTAssertEqual(restored?.response.seasonal.pageInfo?.hasNextPage, true)
        XCTAssertEqual(restored?.savedAt, now)
        let differentSeason = await relaunched.load(selection.advanced(by: 1), now: now)
        XCTAssertNil(differentSeason)
    }
    func testFreshnessAndExpiryPermitStaleDisplayWhileRefreshing() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let item = snapshot()
        XCTAssertFalse(item.needsRefresh(at: now.addingTimeInterval(299)))
        XCTAssertTrue(item.needsRefresh(at: now.addingTimeInterval(300)))
        let cache = ExploreCache(directory: folder)
        await cache.save(item)
        let stale = await ExploreCache(directory: folder).load(selection, now: now.addingTimeInterval(3600))
        XCTAssertNotNil(stale)
        let expired = await cache.load(selection, now: now.addingTimeInterval(7 * 86400))
        XCTAssertNil(expired)
        XCTAssertFalse(snapshot(savedAt: now.addingTimeInterval(3600)).isUsable(for: selection, at: now))
    }
    func testRefreshReplacesTheSavedCatalog() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let cache = ExploreCache(directory: folder)
        await cache.save(snapshot(id: 1))
        await cache.save(snapshot(id: 2, savedAt: now.addingTimeInterval(60)))
        let restored = await ExploreCache(directory: folder).load(selection, now: now.addingTimeInterval(90))
        XCTAssertEqual(restored?.response.trending.media?.map(\.id), [2])
        XCTAssertEqual(restored?.savedAt, now.addingTimeInterval(60))
    }
    func testCorruptAndUnsupportedCacheAreIgnoredAndRecoverable() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let cache = ExploreCache(directory: folder)
        await cache.save(snapshot())
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).first)
        try Data("{broken".utf8).write(to: file)
        let corrupt = await ExploreCache(directory: folder).load(selection, now: now)
        XCTAssertNil(corrupt)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot())) as? [String: Any])
        object["version"] = 999
        try JSONSerialization.data(withJSONObject: object).write(to: file)
        let unsupported = await ExploreCache(directory: folder).load(selection, now: now)
        XCTAssertNil(unsupported)
        await cache.save(snapshot(id: 3))
        let recovered = await ExploreCache(directory: folder).load(selection, now: now)
        XCTAssertEqual(recovered?.response.trending.media?.first?.id, 3)
    }
    func testUnavailableDiskStillKeepsAnInMemoryCatalog() async throws {
        let file = directory(); defer { try? FileManager.default.removeItem(at: file) }
        try Data("not a directory".utf8).write(to: file)
        let cache = ExploreCache(directory: file)
        let persisted = await cache.save(snapshot())
        XCTAssertFalse(persisted)
        let usable = await cache.load(selection, now: now)
        XCTAssertEqual(usable?.response.trending.media?.first?.id, 1)
    }
    func testSavedSeasonHistoryIsBounded() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let cache = ExploreCache(directory: folder)
        for offset in 0..<8 {
            let saved = await cache.save(snapshot(id: offset, selection: selection.advanced(by: offset)))
            XCTAssertTrue(saved)
        }
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        XCTAssertLessThanOrEqual(files.count, 6)
    }
}
