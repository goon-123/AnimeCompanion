import XCTest
@testable import AnimeCore

final class MangaBakaRecommendationsStateTests: XCTestCase {
    private let account = UUID()
    private let now = Date(timeIntervalSince1970: 100_000)
    private let week = MangaBakaRecommendationSnapshot.lifetime
    private func series(_ id: Int, rating: String = "safe") throws -> MangaBakaSeries {
        try JSONDecoder().decode(MangaBakaSeries.self,
            from: Data("{\"id\":\(id),\"title\":\"Owned story\",\"content_rating\":\"\(rating)\"}".utf8))
    }
    private func payload(_ records: String = #"{"id":81,"title":"Owned story","content_rating":"safe"}"#) -> MangaBakaRecommendationPayload {
        .init(response: Data("{\"results\":[\(records)]}".utf8))
    }
    private func loaded(_ items: [MangaBakaSeries]? = nil, adult: Bool = false) throws -> MangaBakaRecommendationsState {
        var state = MangaBakaRecommendationsState()
        let first = try XCTUnwrap(state.begin(account: account, includeAdult: adult, now: now))
        state.complete(try items ?? [series(81)], for: first, now: now); state.finish(first)
        return state
    }
    func testReappearingAndConcurrentCallersReuseResultUntilExactlySevenDays() throws {
        var state = MangaBakaRecommendationsState()
        let first = try XCTUnwrap(state.begin(account: account, includeAdult: false, now: now))
        XCTAssertNil(state.begin(account: account, includeAdult: false, refresh: true, now: now))
        state.complete([try series(81)], for: first, now: now); state.finish(first)
        for seconds in [0.0, 31, 301, 3600, 86400, week - 1] {
            XCTAssertNil(state.begin(account: account, includeAdult: false, now: now.addingTimeInterval(seconds)))
            XCTAssertEqual(state.items.map(\.id), [81]); XCTAssertFalse(state.loading)
        }
        XCTAssertNotNil(state.begin(account: account, includeAdult: false, now: now.addingTimeInterval(week)))
        XCTAssertEqual(state.items.map(\.id), [81])
    }
    func testExplicitRefreshBypassesWeekAndStartsNewSevenDayWindow() throws {
        var state = try loaded()
        let date = now.addingTimeInterval(60)
        let refresh = try XCTUnwrap(state.begin(account: account, includeAdult: false, refresh: true, now: date))
        XCTAssertEqual(state.items.map(\.id), [81]); XCTAssertTrue(state.loading)
        state.complete([try series(82)], for: refresh, now: date); state.finish(refresh)
        XCTAssertEqual(state.fetchedAt, date); XCTAssertEqual(state.refreshAt, date.addingTimeInterval(week))
        XCTAssertNil(state.begin(account: account, includeAdult: false, now: now.addingTimeInterval(week)))
    }
    func testSuccessfulEmptyResultsAlsoWaitAWeekUnlessExplicitlyRefreshed() throws {
        var state = try loaded([])
        XCTAssertTrue(state.hasResult); XCTAssertTrue(state.items.isEmpty)
        for seconds in [31.0, 300, week - 1] {
            XCTAssertNil(state.begin(account: account, includeAdult: false, now: now.addingTimeInterval(seconds)))
        }
        XCTAssertNotNil(state.begin(account: account, includeAdult: false, refresh: true, now: now.addingTimeInterval(31)))
    }
    func testContentPolicyFiltersImmediatelyWithoutFetchingAndCanBeReversed() throws {
        var state = try loaded([series(81), series(82, rating: "erotica")], adult: true)
        XCTAssertNil(state.begin(account: account, includeAdult: false, now: now.addingTimeInterval(1)))
        XCTAssertEqual(state.items.map(\.id), [81])
        XCTAssertNil(state.begin(account: account, includeAdult: true, now: now.addingTimeInterval(2)))
        XCTAssertEqual(state.items.map(\.id), [81, 82]); XCTAssertEqual(state.fetchedAt, now)
    }
    func testPolicyChangeDuringSharedRefreshAppliesToItsLateResponse() throws {
        var state = try loaded(adult: true)
        let refresh = try XCTUnwrap(state.begin(account: account, includeAdult: true, refresh: true, now: now))
        XCTAssertNil(state.begin(account: account, includeAdult: false, now: now))
        state.complete([try series(81), try series(82, rating: "erotica")], for: refresh, now: now); state.finish(refresh)
        XCTAssertEqual(state.items.map(\.id), [81]); XCTAssertFalse(state.loading)
    }
    func testFailedManualRefreshPreservesFreshTimestampAndDoesNotTriggerAutomaticRefresh() throws {
        var state = try loaded()
        let refresh = try XCTUnwrap(state.begin(account: account, includeAdult: false, refresh: true, now: now))
        state.fail("Offline", for: refresh, now: now); state.finish(refresh)
        XCTAssertEqual(state.items.map(\.id), [81]); XCTAssertEqual(state.fetchedAt, now)
        XCTAssertEqual(state.error, "Offline")
        XCTAssertNil(state.begin(account: account, includeAdult: false, now: now.addingTimeInterval(301)))
        XCTAssertNotNil(state.begin(account: account, includeAdult: false, refresh: true, now: now))
    }
    func testFailedWeeklyRefreshKeepsStaleCardsAndThrottlesAutomaticRetries() throws {
        var state = try loaded()
        let due = now.addingTimeInterval(week)
        let refresh = try XCTUnwrap(state.begin(account: account, includeAdult: false, now: due))
        state.fail("Offline", for: refresh, now: due); state.finish(refresh)
        XCTAssertEqual(state.items.map(\.id), [81]); XCTAssertEqual(state.fetchedAt, now)
        XCTAssertNil(state.begin(account: account, includeAdult: false, now: due.addingTimeInterval(299)))
        XCTAssertNotNil(state.begin(account: account, includeAdult: false, now: due.addingTimeInterval(300)))
    }
    func testDisconnectAndAccountSwitchClearPrivateCardsAndRejectOldCompletions() throws {
        var state = try loaded()
        let old = try XCTUnwrap(state.begin(account: account, includeAdult: false, refresh: true, now: now))
        state.reset()
        XCTAssertTrue(state.items.isEmpty); XCTAssertNil(state.fetchedAt)
        XCTAssertFalse(state.complete([try series(81)], for: old, now: now))
        let current = try XCTUnwrap(state.begin(account: UUID(), includeAdult: false, now: now))
        state.fail("Old account error", for: old, now: now); state.finish(old)
        XCTAssertTrue(state.loading); XCTAssertNil(state.error)
        state.complete([try series(82)], for: current, now: now); state.finish(current)
        _ = try XCTUnwrap(state.begin(account: UUID(), includeAdult: false, now: now))
        XCTAssertTrue(state.items.isEmpty); XCTAssertFalse(state.hasResult)
    }
    func testCancellationAllowsInitialRetryAndKeepsCompletedRefreshCache() throws {
        var state = MangaBakaRecommendationsState()
        let cancelled = try XCTUnwrap(state.begin(account: account, includeAdult: false, now: now))
        state.finish(cancelled)
        let retry = try XCTUnwrap(state.begin(account: account, includeAdult: false, now: now))
        XCTAssertFalse(state.complete([try series(82)], for: cancelled, now: now))
        state.complete([try series(81)], for: retry, now: now); state.finish(retry)
        let refresh = try XCTUnwrap(state.begin(account: account, includeAdult: false, refresh: true, now: now))
        state.finish(refresh)
        XCTAssertEqual(state.items.map(\.id), [81]); XCTAssertFalse(state.loading)
        XCTAssertNil(state.begin(account: account, includeAdult: false, now: now))
    }
    func testSnapshotRoundTripRestoresOriginalTimestampAndReadinessWithoutRequest() throws {
        let status = try JSONDecoder().decode(MangaBakaRecommendationStatus.self,
            from: Data(#"{"cold_start":false,"profile_stale":true,"library_count":2}"#.utf8))
        let original = MangaBakaRecommendationSnapshot(payload: payload(), fetchedAt: now, status: status)
        let snapshot = try JSONDecoder().decode(MangaBakaRecommendationSnapshot.self, from: JSONEncoder().encode(original))
        var state = MangaBakaRecommendationsState()
        XCTAssertTrue(try state.restore(snapshot, account: account, includeAdult: false, now: now.addingTimeInterval(86400)))
        XCTAssertEqual(state.items.map(\.id), [81]); XCTAssertEqual(state.fetchedAt, now); XCTAssertEqual(state.status, status)
        XCTAssertNil(state.begin(account: account, includeAdult: false, now: now.addingTimeInterval(week - 1)))
        XCTAssertNotNil(state.begin(account: account, includeAdult: false, now: now.addingTimeInterval(week)))
    }
    func testExpiredSnapshotStillRestoresCardsForOfflineUseWithoutExtendingFreshness() throws {
        var state = MangaBakaRecommendationsState()
        let snapshot = MangaBakaRecommendationSnapshot(payload: payload(), fetchedAt: now)
        let later = now.addingTimeInterval(week * 2)
        XCTAssertTrue(try state.restore(snapshot, account: account, includeAdult: false, now: later))
        XCTAssertEqual(state.fetchedAt, now); XCTAssertEqual(state.items.map(\.id), [81])
        XCTAssertNotNil(state.begin(account: account, includeAdult: false, now: later))
    }
    func testFutureOrLateSnapshotCannotOverwriteActiveOrNewerResult() throws {
        var state = MangaBakaRecommendationsState()
        XCTAssertFalse(try state.restore(.init(payload: payload(), fetchedAt: now.addingTimeInterval(3600)),
            account: account, includeAdult: false, now: now))
        let request = try XCTUnwrap(state.begin(account: account, includeAdult: false, now: now))
        XCTAssertFalse(try state.restore(.init(payload: payload(), fetchedAt: now), account: account, includeAdult: false, now: now))
        state.complete([try series(82)], for: request, now: now); state.finish(request)
        XCTAssertFalse(try state.restore(.init(payload: payload(), fetchedAt: now), account: account, includeAdult: false, now: now))
        XCTAssertEqual(state.items.map(\.id), [82])
    }
    func testPayloadRetainsHydratedDetailsPublishersAndOrderAndRejectsWrongIdentity() throws {
        let response = Data(#"{"data":[],"results":[{"series":{"id":81,"title":"Owned"}},{"id":81},{"id":82,"content_rating":"safe"},{"id":"bad"}]}"#.utf8)
        let details = Data(#"{"data":[{"id":81,"content_rating":"suggestive","description":"Owned synopsis","publishers":[{"id":19,"name":"Owned Press"}]}]}"#.utf8)
        let records = try MangaBakaRecommendationPayload(response: response, details: details).records()
        XCTAssertEqual(records.map(\.id), [81, 82]); XCTAssertEqual(records.first?.synopsis, "Owned synopsis")
        XCTAssertEqual(records.first?.publishers.first?.id, 19)
        let wrong = Data(#"{"data":[{"id":99}]}"#.utf8)
        XCTAssertThrowsError(try MangaBakaRecommendationPayload(response: response, details: wrong).records())
        XCTAssertThrowsError(try payload(#"{"id":"bad"}"#).records())
    }
    func testEmptyMessagesDistinguishServiceReadinessAndContentFiltering() throws {
        var state = MangaBakaRecommendationsState()
        XCTAssertTrue(state.emptyMessage.contains("haven’t loaded"))
        let first = try XCTUnwrap(state.begin(account: account, includeAdult: false, now: now))
        let cold = try JSONDecoder().decode(MangaBakaRecommendationStatus.self,
            from: Data(#"{"cold_start":true,"profile_stale":false,"library_count":2}"#.utf8))
        state.complete([], for: first, status: cold, now: now); state.finish(first)
        XCTAssertTrue(state.emptyMessage.contains("building")); XCTAssertTrue(state.emptyMessage.contains("2 titles"))
        let next = try XCTUnwrap(state.begin(account: account, includeAdult: false, refresh: true, now: now))
        state.complete([try series(82, rating: "erotica")], for: next, now: now); state.finish(next)
        XCTAssertTrue(state.emptyMessage.contains("content settings"))
    }
}
