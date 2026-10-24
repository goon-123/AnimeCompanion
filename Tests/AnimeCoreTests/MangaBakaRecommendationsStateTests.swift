import XCTest
@testable import AnimeCore

final class MangaBakaRecommendationsStateTests: XCTestCase {
    private let account = UUID()
    private let revision = UUID()

    private func series(_ id: Int, rating: String = "safe") throws -> MangaBakaSeries {
        try JSONDecoder().decode(MangaBakaSeries.self,
            from: Data("{\"id\":\(id),\"title\":\"Owned story\",\"content_rating\":\"\(rating)\"}".utf8))
    }

    func testReappearingShelfDoesNotRestartCompletedOrInFlightRequest() throws {
        var state = MangaBakaRecommendationsState()
        let first = try XCTUnwrap(state.begin(account: account, revision: revision, includeAdult: false))
        XCTAssertNil(state.begin(account: account, revision: revision, includeAdult: false))
        XCTAssertNil(state.begin(account: account, revision: revision, includeAdult: false, refresh: true))
        XCTAssertTrue(state.loading)
        XCTAssertTrue(state.complete([try series(81)], for: first)); state.finish(first)
        for _ in 0..<20 {
            XCTAssertNil(state.begin(account: account, revision: revision, includeAdult: false))
            XCTAssertEqual(state.items.map(\.id), [81]); XCTAssertFalse(state.loading)
        }
    }

    func testRefreshAndFailureKeepPreviouslyDisplayedCards() throws {
        var state = MangaBakaRecommendationsState()
        let first = try XCTUnwrap(state.begin(account: account, revision: revision, includeAdult: false))
        state.complete([try series(81)], for: first); state.finish(first)
        let refresh = try XCTUnwrap(state.begin(account: account, revision: revision, includeAdult: false, refresh: true))
        XCTAssertEqual(state.items.map(\.id), [81]); XCTAssertTrue(state.loading)
        state.fail("Offline", for: refresh); state.finish(refresh)
        XCTAssertEqual(state.items.map(\.id), [81]); XCTAssertEqual(state.error, "Offline")
        XCTAssertFalse(state.loading)
        let retry = try XCTUnwrap(state.begin(account: account, revision: revision, includeAdult: false))
        XCTAssertNil(state.error); XCTAssertEqual(state.items.map(\.id), [81])
        state.complete([try series(82)], for: retry); state.finish(retry)
        XCTAssertEqual(state.items.map(\.id), [82])
    }

    func testLibraryRevisionRefreshKeepsCardsAndRejectsOldCompletionAndFinish() throws {
        var state = MangaBakaRecommendationsState()
        let first = try XCTUnwrap(state.begin(account: account, revision: revision, includeAdult: false))
        state.complete([try series(81)], for: first); state.finish(first)
        let old = try XCTUnwrap(state.begin(account: account, revision: revision, includeAdult: false, refresh: true))
        let newest = try XCTUnwrap(state.begin(account: account, revision: UUID(), includeAdult: false))
        XCTAssertEqual(state.items.map(\.id), [81])
        XCTAssertFalse(state.complete([try series(82)], for: old))
        state.fail("Old error", for: old); state.finish(old)
        XCTAssertTrue(state.loading); XCTAssertNil(state.error)
        state.complete([try series(83)], for: newest); state.finish(newest)
        XCTAssertEqual(state.items.map(\.id), [83]); XCTAssertFalse(state.loading)
    }

    func testDisablingMatureContentFiltersImmediatelyAndRejectsOlderPolicy() throws {
        var state = MangaBakaRecommendationsState()
        let first = try XCTUnwrap(state.begin(account: account, revision: revision, includeAdult: true))
        state.complete([try series(81), try series(82, rating: "erotica")], for: first); state.finish(first)
        let old = try XCTUnwrap(state.begin(account: account, revision: revision, includeAdult: true, refresh: true))
        let safe = try XCTUnwrap(state.begin(account: account, revision: revision, includeAdult: false))
        XCTAssertEqual(state.items.map(\.id), [81])
        XCTAssertFalse(state.complete([try series(82, rating: "erotica")], for: old))
        state.complete([try series(81), try series(81), try series(82, rating: "erotica")], for: safe)
        state.finish(safe)
        XCTAssertEqual(state.items.map(\.id), [81])
    }

    func testDisconnectAndAccountSwitchClearPrivateCardsAndInvalidateWork() throws {
        var state = MangaBakaRecommendationsState()
        let first = try XCTUnwrap(state.begin(account: account, revision: revision, includeAdult: false))
        state.complete([try series(81)], for: first); state.finish(first)
        let old = try XCTUnwrap(state.begin(account: account, revision: revision, includeAdult: false, refresh: true))
        state.reset()
        XCTAssertTrue(state.items.isEmpty); XCTAssertFalse(state.loading); XCTAssertNil(state.error)
        XCTAssertFalse(state.complete([try series(81)], for: old))
        let current = try XCTUnwrap(state.begin(account: UUID(), revision: revision, includeAdult: false))
        state.fail("Old account error", for: old); state.finish(old)
        XCTAssertTrue(state.loading); XCTAssertNil(state.error)
        state.complete([try series(82)], for: current); state.finish(current)
        _ = try XCTUnwrap(state.begin(account: UUID(), revision: revision, includeAdult: false))
        XCTAssertTrue(state.items.isEmpty)
    }

    func testCancelledInitialLoadCanRestartAndCancelledRefreshKeepsCards() throws {
        var state = MangaBakaRecommendationsState()
        let cancelled = try XCTUnwrap(state.begin(account: account, revision: revision, includeAdult: false))
        state.finish(cancelled)
        XCTAssertFalse(state.loading)
        let retry = try XCTUnwrap(state.begin(account: account, revision: revision, includeAdult: false))
        XCTAssertFalse(state.complete([try series(82)], for: cancelled))
        state.complete([try series(81)], for: retry); state.finish(retry)
        let refresh = try XCTUnwrap(state.begin(account: account, revision: revision, includeAdult: false, refresh: true))
        state.finish(refresh)
        XCTAssertEqual(state.items.map(\.id), [81]); XCTAssertFalse(state.loading)
        XCTAssertNotNil(state.begin(account: account, revision: revision, includeAdult: false))
    }

    func testSuccessfulEmptyRecommendationsDoNotRefetchOnEveryAppearance() throws {
        var state = MangaBakaRecommendationsState()
        let first = try XCTUnwrap(state.begin(account: account, revision: revision, includeAdult: false))
        state.complete([], for: first); state.finish(first)
        XCTAssertNil(state.begin(account: account, revision: revision, includeAdult: false))
        XCTAssertNotNil(state.begin(account: account, revision: revision, includeAdult: false, refresh: true))
    }
}
