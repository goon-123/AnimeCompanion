import XCTest
@testable import AnimeCore

final class HomeSeasonContentTests: XCTestCase {
    private var clock: Calendar { var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(secondsFromGMT: 0)!; return value }
    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date { clock.date(from: DateComponents(year: year, month: month, day: day))! }

    func testFallCountsDownToWinterAndRollsOverWithoutNegativeTime() {
        let fall = HomeSeasonCountdown(now: date(2026, 11, 1), calendar: clock)
        XCTAssertEqual(fall.current, .init(season: .fall, year: 2026))
        XCTAssertEqual(fall.next, .init(season: .winter, year: 2027))
        XCTAssertEqual(fall.startsAt, date(2027, 1, 1))
        XCTAssertEqual(fall.days, 61); XCTAssertEqual(fall.hours, 0)
        XCTAssertGreaterThan(fall.progress, 0); XCTAssertLessThan(fall.progress, 1)
        let midnight = HomeSeasonCountdown(now: date(2027, 1, 1), calendar: clock)
        XCTAssertEqual(midnight.current, fall.next)
        XCTAssertEqual(midnight.next, .init(season: .spring, year: 2027))
        XCTAssertEqual(midnight.progress, 0)
        let before = HomeSeasonCountdown(now: date(2027, 1, 1).addingTimeInterval(-60), calendar: clock)
        XCTAssertEqual(before.days, 0); XCTAssertEqual(before.hours, 0); XCTAssertEqual(before.minutes, 1)
    }
    func testAllQuarterBoundariesLeapYearsAndLocalDaylightSaving() {
        for (month, nextMonth) in [(1, 4), (4, 7), (7, 10)] {
            let value = HomeSeasonCountdown(now: date(2028, month, 1), calendar: clock)
            XCTAssertEqual(value.startsAt, date(2028, nextMonth, 1)); XCTAssertEqual(value.progress, 0)
        }
        XCTAssertEqual(HomeSeasonCountdown(now: date(2028, 2, 29), calendar: clock).days, 32)
        var local = clock; local.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let start = local.date(from: DateComponents(year: 2026, month: 10, day: 1))!
        let fall = HomeSeasonCountdown(now: start, calendar: local)
        XCTAssertEqual(fall.days, 92); XCTAssertEqual(fall.hours, 0)
        XCTAssertEqual(local.component(.hour, from: fall.startsAt), 0)
        var buddhist = Calendar(identifier: .buddhist); buddhist.timeZone = clock.timeZone
        XCTAssertEqual(HomeSeasonCountdown(now: date(2026, 11, 1), calendar: buddhist).next.year, 2027)
    }
    func testReturningSeriesRequiresExplicitPrequelOrSavedID() throws {
        let lineup = try JSONDecoder().decode([Anime].self, from: Data("""
        [
          {"id":2,"title":{"english":"Sequel"},"relations":{"edges":[{"relationType":"PREQUEL","node":{"id":1,"type":"ANIME"}}]}},
          {"id":3,"title":{"english":"Similar name"},"relations":{"edges":[{"relationType":"ADAPTATION","node":{"id":1,"type":"MANGA"}}]}},
          {"id":4,"title":{"english":"Saved premiere"}}
        ]
        """.utf8))
        let library = try entries("""
        [{"id":1,"mediaId":1,"status":"COMPLETED"},{"id":4,"mediaId":4,"status":"PLANNING"}]
        """)
        XCTAssertEqual(HomeSeasonContent.returning(lineup, library: library).map(\.id), [2, 4])
        XCTAssertTrue(HomeSeasonContent.returning(lineup, library: []).isEmpty)
    }
    func testTonightNeverSuggestsUnreleasedOrAlreadyWatchedEpisodesAndFavoritesUsePersonalScores() throws {
        let library = try entries("""
        [
          {"id":1,"mediaId":1,"status":"CURRENT","progress":2,"media":{"id":1,"status":"RELEASING","episodes":12,"nextAiringEpisode":{"episode":4,"airingAt":2200000000}}},
          {"id":2,"mediaId":2,"status":"PLANNING","media":{"id":2,"status":"NOT_YET_RELEASED","episodes":12}},
          {"id":3,"mediaId":3,"status":"CURRENT","progress":3,"media":{"id":3,"status":"RELEASING","nextAiringEpisode":{"episode":4,"airingAt":2200000000}}},
          {"id":4,"mediaId":4,"status":"PLANNING","media":{"id":4,"status":"FINISHED","episodes":12}},
          {"id":5,"mediaId":5,"status":"PLANNING","media":{"id":5,"episodes":12}},
          {"id":6,"mediaId":6,"status":"COMPLETED","score":80,"media":{"id":6,"averageScore":100}},
          {"id":7,"mediaId":7,"status":"COMPLETED","score":95,"media":{"id":7,"averageScore":20}}
        ]
        """)
        XCTAssertEqual(HomeSeasonContent.tonightCandidates(library, now: date(2026, 11, 1)).map(\.id), [1, 4])
        XCTAssertEqual(HomeSeasonContent.favorites(library).map(\.mediaId), [7, 6])
    }
    func testNewWidgetsMigrateHiddenWithoutChangingExistingHomeChoices() {
        let old = HomePreferences(saved: #"{"version":3,"order":["reading","seasonSpotlight","search"],"hidden":["search"],"sizes":{"reading":"compact"},"shortcuts":["community","library",""]}"#)
        let added: Set<HomeSection> = [.seasonCountdown, .nextSeason, .returningSeries, .tonightPick, .hallOfFame]
        XCTAssertTrue(added.isSubset(of: old.hidden)); XCTAssertTrue(old.hidden.contains(.search))
        XCTAssertEqual(Array(old.order.prefix(3)), [.reading, .seasonSpotlight, .search])
        XCTAssertEqual(old.shortcuts, [.community, .library, nil]); XCTAssertEqual(old.size(for: .reading), .compact)
        var edited = old; edited.setVisible(.seasonCountdown, true); edited.move(.seasonCountdown, before: .reading)
        let reopened = HomePreferences(saved: edited.saved)
        XCTAssertEqual(reopened.visible.first, .seasonCountdown); XCTAssertEqual(reopened, edited)
    }
    private func entries(_ raw: String) throws -> [LibraryEntry] { try JSONDecoder().decode([LibraryEntry].self, from: Data(raw.utf8)) }
}
