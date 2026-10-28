import XCTest
@testable import AnimeCore

final class LibraryBroadcastSummaryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000)
    private func anime(_ overrides: [String: Any] = [:]) throws -> Anime {
        let object: [String: Any] = ["id": 10, "idMal": 20, "episodes": 26, "status": "RELEASING",
            "nextAiringEpisode": ["episode": 18, "airingAt": 66_800]]
        return try JSONDecoder().decode(Anime.self, from: JSONSerialization.data(withJSONObject: object.merging(overrides) { _, new in new }))
    }
    func testSeventeenAiredFifteenDubbedRequiresAllSeventeenWatched() throws {
        let title = try anime()
        let history = try JSONDecoder().decode([RawDubFeedItem].self, from: Data(#"[{"id":10,"episode":{"aired":15,"airedAt":1000}}]"#.utf8))
        let dub = LibraryDubProgress(anime: title, snapshot: DubSnapshot(upcoming: [], history: history), index: nil, now: now)
        XCTAssertEqual(dub.released, 15)
        XCTAssertTrue(dub.hasAvailableDub)
        for watched in [0, 15, 16] {
            let summary = LibraryBroadcastSummary(anime: title, watched: watched, now: now)
            XCTAssertEqual(summary.aired, 17)
            XCTAssertEqual(summary.state, .behind)
            XCTAssertEqual(summary.countdown(at: now), "Airs in 18hrs")
        }
        let caughtUp = LibraryBroadcastSummary(anime: title, watched: 17, now: now)
        XCTAssertEqual(caughtUp.state, .caughtUp)
        XCTAssertEqual(caughtUp.countdown(at: now), "Airs in 18hrs")
        // A dub-oriented schedule may say caught up at 15. The Library card's
        // summary has no audio/source input, so that preference cannot turn it green.
        XCTAssertEqual(LibraryBroadcastSummary(anime: title, watched: 15, now: now).state, .behind)
    }
    func testMissingExpiredAndImpossibleSchedulesStayNeutral() throws {
        let schedules: [Any] = [NSNull(), ["episode": 18, "airingAt": 1_000], ["episode": 99, "airingAt": 66_800]]
        for schedule in schedules {
            let summary = LibraryBroadcastSummary(anime: try anime(["nextAiringEpisode": schedule]), watched: 17, now: now)
            XCTAssertNil(summary.aired)
            XCTAssertEqual(summary.state, .unknown)
            XCTAssertNil(summary.countdown(at: now))
        }
    }
    func testUnknownTotalsStillUseTheBroadcastAndCompletedTitlesUseTheirTotal() throws {
        let ongoing = LibraryBroadcastSummary(anime: try anime(["episodes": NSNull()]), watched: 17, now: now)
        XCTAssertEqual(ongoing.aired, 17)
        XCTAssertEqual(ongoing.state, .caughtUp)
        for watched in [16, 26] {
            let finished = LibraryBroadcastSummary(anime: try anime(["status": "FINISHED"]), watched: watched, now: now)
            XCTAssertEqual(finished.aired, 26)
            XCTAssertEqual(finished.state, watched == 26 ? .caughtUp : .behind)
            XCTAssertNil(finished.next)
        }
        let future = LibraryBroadcastSummary(anime: try anime(["status": "NOT_YET_RELEASED"]), watched: 0, now: now)
        XCTAssertEqual(future.aired, 0)
        XCTAssertEqual(future.state, .waiting)
    }
    func testCountdownHandlesMinutesDaysAndReachedDates() throws {
        let summary = LibraryBroadcastSummary(anime: try anime(), watched: 16, now: now)
        XCTAssertEqual(summary.countdown(at: Date(timeIntervalSince1970: 66_799)), "Airs in 1min")
        XCTAssertEqual(summary.countdown(at: Date(timeIntervalSince1970: 66_800)), "Airing time updating")
        let later = LibraryBroadcastSummary(anime: try anime(["nextAiringEpisode": ["episode": 18, "airingAt": 2_000 + 2 * 86_400 + 3 * 3600]]), watched: 17, now: now)
        XCTAssertEqual(later.countdown(at: now), "Airs in 2d 3hrs")
    }
    func testOnlyAvailableDubEvidenceGetsAPosterBadge() throws {
        let title = try anime()
        for index in [DubIndex(dubbed: [20], partial: []), DubIndex(dubbed: [], partial: [20])] {
            XCTAssertTrue(LibraryDubProgress(anime: title, snapshot: nil, index: index, now: now).hasAvailableDub)
        }
        let planned = try JSONDecoder().decode([RawDubItem].self, from: Data(#"[{"episodeNumber":1,"episodeDate":66800,"media":{"media":{"id":10}}}]"#.utf8))
        XCTAssertFalse(LibraryDubProgress(anime: title, snapshot: DubSnapshot(upcoming: planned, history: []), index: nil, now: now).hasAvailableDub)
        XCTAssertFalse(LibraryDubProgress(anime: title, snapshot: nil, index: nil, now: now).hasAvailableDub)
    }
}
