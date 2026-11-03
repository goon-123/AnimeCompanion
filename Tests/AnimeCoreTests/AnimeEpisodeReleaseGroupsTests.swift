import XCTest
@testable import AnimeCore

final class AnimeEpisodeReleaseGroupsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func anime(status: String, total: Int? = 12, next: Int? = nil) throws -> Anime {
        var value: [String: Any] = ["id": 1, "status": status]
        if let total { value["episodes"] = total }
        if let next { value["nextAiringEpisode"] = ["episode": next, "airingAt": Int(now.timeIntervalSince1970 + 3600)] }
        return try JSONDecoder().decode(Anime.self, from: JSONSerialization.data(withJSONObject: value))
    }
    func testAiringShowSeparatesPlannedEpisodesUsingOriginalBroadcastCount() throws {
        let show = try anime(status: "RELEASING", next: 5)
        let groups = AnimeEpisodeReleaseGroups(anime: show, episodes: (1...12).map { AnimeEpisodeMetadata(number: $0) }, now: now)
        XCTAssertEqual(groups.aired.map(\.number), [1, 2, 3, 4])
        XCTAssertEqual(groups.upcoming.map(\.number), Array(5...12))
        XCTAssertEqual(groups.next?.episode, 5)
        XCTAssertEqual(groups.unairedCount, 8)
        XCTAssertFalse(AnimeEpisodeReleaseGroups.isReleased(AnimeEpisodeMetadata(number: 5), anime: show, now: now))
    }
    func testNotYetReleasedShowNeverTreatsUndatedOrOldMetadataAsPlayable() throws {
        let show = try anime(status: "NOT_YET_RELEASED", next: 1)
        let rows = [AnimeEpisodeMetadata(number: 1, airDate: "2020-01-01"), AnimeEpisodeMetadata(number: 2)]
        let groups = AnimeEpisodeReleaseGroups(anime: show, episodes: rows, now: now)
        XCTAssertTrue(groups.aired.isEmpty); XCTAssertEqual(groups.upcoming.count, 2)
        XCTAssertEqual(groups.unairedCount, 12); XCTAssertTrue(groups.hasUpcoming)
    }
    func testFinishedOriginalBroadcastIgnoresFutureRebroadcastDates() throws {
        let show = try anime(status: "FINISHED", total: 2, next: 1)
        let groups = AnimeEpisodeReleaseGroups(anime: show,
            episodes: [AnimeEpisodeMetadata(number: 1, airDate: "2099-01-01"), AnimeEpisodeMetadata(number: 2)], now: now)
        XCTAssertEqual(groups.aired.count, 2); XCTAssertTrue(groups.upcoming.isEmpty)
        XCTAssertNil(groups.next); XCTAssertFalse(groups.hasUpcoming)
    }
    func testUnknownBroadcastCountsUseExplicitDatesWithoutHidingUndatedRows() throws {
        let show = try anime(status: "RELEASING", total: nil)
        let rows = [AnimeEpisodeMetadata(number: 1, airDate: "2020-01-01"),
                    AnimeEpisodeMetadata(number: 2, airDate: "2099-01-01"), AnimeEpisodeMetadata(number: 3)]
        let groups = AnimeEpisodeReleaseGroups(anime: show, episodes: rows, now: now)
        XCTAssertEqual(groups.aired.map(\.number), [1, 3])
        XCTAssertEqual(groups.upcoming.map(\.number), [2]); XCTAssertNil(groups.unairedCount)
    }
    func testPassingTheNextAiringTimeMovesOnlyThatEpisodeToReleased() throws {
        let show = try anime(status: "RELEASING", total: 7, next: 5)
        let groups = AnimeEpisodeReleaseGroups(anime: show, episodes: (1...7).map { AnimeEpisodeMetadata(number: $0) },
                                             now: now.addingTimeInterval(3601))
        XCTAssertEqual(groups.aired.map(\.number), Array(1...5))
        XCTAssertEqual(groups.upcoming.map(\.number), [6, 7])
        XCTAssertNil(groups.next, "Never guess a weekly date for the following episode")
    }
    func testUnknownTotalStillOffersTheConfirmedNextReleaseWithoutMakingUpRows() throws {
        let show = try anime(status: "RELEASING", total: nil, next: 42)
        let groups = AnimeEpisodeReleaseGroups(anime: show, episodes: [], now: now)
        XCTAssertEqual(groups.next?.episode, 42); XCTAssertTrue(groups.hasUpcoming)
        XCTAssertNil(groups.unairedCount); XCTAssertTrue(groups.upcoming.isEmpty)
    }
}
