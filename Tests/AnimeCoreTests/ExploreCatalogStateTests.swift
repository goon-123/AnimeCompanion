import XCTest
@testable import AnimeCore

final class ExploreCatalogStateTests: XCTestCase {
    private let season = SeasonSelection(season: .fall, year: 2026)
    private let now = Date(timeIntervalSince1970: 10_000)
    private func response(_ id: Int) throws -> ExploreResponse {
        try JSONDecoder().decode(ExploreResponse.self, from: Data("{\"seasonal\":{\"media\":[{\"id\":\(id)}]},\"trending\":{},\"upcoming\":{}}".utf8))
    }
    func testFreshSavedCatalogSkipsNetworkUntilExplicitRefresh() throws {
        var state = ExploreCatalogState()
        let attempt = try XCTUnwrap(state.begin(season, includeAdult: false, refresh: false))
        let snapshot = ExploreSnapshot(response: try response(1), selection: season, savedAt: now)
        XCTAssertTrue(state.restore(snapshot, for: attempt, now: now))
        state.finish(attempt)
        XCTAssertFalse(state.loading); XCTAssertEqual(state.savedAt, now)
        XCTAssertNil(state.begin(season, includeAdult: false, refresh: false))
        XCTAssertNotNil(state.begin(season, includeAdult: false, refresh: true))
        XCTAssertEqual(state.response?.seasonal.media?.first?.id, 1)
    }
    func testStaleSavedCatalogRemainsVisibleWhenNetworkFailsAndCanBeRetried() throws {
        var state = ExploreCatalogState()
        let attempt = try XCTUnwrap(state.begin(season, includeAdult: false, refresh: false))
        let snapshot = ExploreSnapshot(response: try response(1), selection: season, savedAt: now.addingTimeInterval(-600))
        XCTAssertFalse(state.restore(snapshot, for: attempt, now: now))
        state.fail("Offline", for: attempt); state.finish(attempt)
        XCTAssertEqual(state.response?.seasonal.media?.first?.id, 1)
        XCTAssertEqual(state.error, "Offline"); XCTAssertFalse(state.loading)
        XCTAssertNotNil(state.begin(season, includeAdult: false, refresh: false))
        XCTAssertNil(state.error)
    }
    func testChangingSeasonRejectsEveryOldCompletionErrorAndFinish() throws {
        var state = ExploreCatalogState()
        let old = try XCTUnwrap(state.begin(season, includeAdult: false, refresh: false))
        let current = try XCTUnwrap(state.begin(season.advanced(by: 1), includeAdult: false, refresh: false))
        XCTAssertFalse(state.complete(try response(1), for: old))
        state.fail("Old error", for: old); state.finish(old)
        XCTAssertTrue(state.loading); XCTAssertNil(state.error)
        XCTAssertTrue(state.complete(try response(2), for: current)); state.finish(current)
        XCTAssertEqual(state.response?.seasonal.media?.first?.id, 2)
        XCTAssertFalse(state.loading)
    }
    func testContentPolicyChangeClearsOldResultsAndRejectsMismatchedSavedCatalog() throws {
        var state = ExploreCatalogState()
        let old = try XCTUnwrap(state.begin(season, includeAdult: true, refresh: false))
        XCTAssertTrue(state.complete(try response(1), for: old)); state.finish(old)
        let current = try XCTUnwrap(state.begin(season, includeAdult: false, refresh: false))
        XCTAssertNil(state.response); XCTAssertNil(state.loadedKey)
        let adultSnapshot = ExploreSnapshot(response: try response(1), selection: season, savedAt: now, includeAdult: true)
        XCTAssertFalse(state.restore(adultSnapshot, for: current, now: now)); XCTAssertNil(state.response)
        XCTAssertFalse(state.complete(try response(1), for: old))
    }
    func testCancelledAttemptCanRestartAndCannotPublishAfterItFinishes() throws {
        var state = ExploreCatalogState()
        let cancelled = try XCTUnwrap(state.begin(season, includeAdult: false, refresh: false))
        state.finish(cancelled)
        XCTAssertFalse(state.complete(try response(1), for: cancelled))
        XCTAssertNotNil(state.begin(season, includeAdult: false, refresh: false))
        XCTAssertTrue(state.loading)
    }
    func testExplicitRefreshDoesNotAcceptEvenFreshSavedCatalogAsFinal() throws {
        var state = ExploreCatalogState()
        let attempt = try XCTUnwrap(state.begin(season, includeAdult: false, refresh: true))
        let snapshot = ExploreSnapshot(response: try response(1), selection: season, savedAt: now)
        XCTAssertFalse(state.restore(snapshot, for: attempt, now: now))
        XCTAssertTrue(state.complete(try response(2), for: attempt)); state.finish(attempt)
        XCTAssertNil(state.savedAt); XCTAssertFalse(state.loading)
        XCTAssertEqual(state.response?.seasonal.media?.first?.id, 2)
    }
}
