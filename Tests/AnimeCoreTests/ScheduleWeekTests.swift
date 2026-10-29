import XCTest
@testable import AnimeCore
import Foundation

final class ScheduleWeekTests: XCTestCase {
    private func calendar(firstWeekday: Int = 1, zone: String = "America/Los_Angeles") -> Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: zone)!
        value.firstWeekday = firstWeekday
        return value
    }
    private func date(_ year: Int = 2026, _ month: Int = 10, _ day: Int, hour: Int = 12, in calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }
    func testFullWeekIncludesEveryDayEvenWithoutReleasesAndTargetsToday() {
        let cal = calendar(); let now = date(2026, 10, 10, in: cal)
        let week = ScheduleWeek(containing: now, calendar: cal)
        XCTAssertEqual(week.days.count, 7)
        XCTAssertEqual(week.days.map { cal.component(.day, from: $0) }, Array(4...10))
        XCTAssertEqual(week.today(at: now), week.days.last)
    }
    func testPreviousAndUpcomingWeeksHaveNoTodayTarget() {
        let cal = calendar(); let now = date(2026, 10, 10, in: cal)
        for offset in [-7, 7] {
            let anchor = cal.date(byAdding: .day, value: offset, to: now)!
            XCTAssertNil(ScheduleWeek(containing: anchor, calendar: cal).today(at: now))
        }
    }
    func testNextDayTargetsNewLocalDayWithinTheSameWeek() {
        let cal = calendar(); let now = date(2026, 10, 7, hour: 23, in: cal)
        let week = ScheduleWeek(containing: now, calendar: cal)
        XCTAssertEqual(week.today(at: now), week.days[3])
        XCTAssertEqual(week.today(at: date(2026, 10, 8, hour: 0, in: cal)), week.days[4])
    }
    func testWeekEndIsExclusiveAndNextWeekStartsOnNewDay() {
        let cal = calendar(); let week = ScheduleWeek(containing: date(2026, 10, 10, in: cal), calendar: cal)
        XCTAssertEqual(week.today(at: week.window.start), week.days.first)
        XCTAssertNil(week.today(at: week.window.end))
        XCTAssertEqual(ScheduleWeek(containing: week.window.end, calendar: cal).today(at: week.window.end), week.window.end)
    }
    func testRespectsMondayFirstCalendars() {
        let cal = calendar(firstWeekday: 2)
        let week = ScheduleWeek(containing: date(2026, 10, 7, in: cal), calendar: cal)
        XCTAssertEqual(week.days.map { cal.component(.day, from: $0) }, Array(5...11))
        XCTAssertEqual(cal.component(.weekday, from: week.days[0]), 2)
    }
    func testDaysRemainAtLocalMidnightAcrossBothDaylightSavingChanges() {
        let cal = calendar()
        for (month, day, duration) in [(3, 8, 7 * 86400 - 3600), (11, 1, 7 * 86400 + 3600)] {
            let week = ScheduleWeek(containing: date(2026, month, day, in: cal), calendar: cal)
            XCTAssertEqual(week.days.count, 7)
            XCTAssertTrue(week.days.allSatisfy { cal.component(.hour, from: $0) == 0 })
            XCTAssertEqual(week.window.duration, TimeInterval(duration))
            XCTAssertEqual(week.today(at: date(2026, month, day, hour: 23, in: cal)), week.days[0])
        }
    }
    func testDeviceTimezoneDefinesTodayInsteadOfUTCDay() {
        let cal = calendar()
        let utc = calendar(zone: "UTC")
        let now = date(2026, 10, 10, hour: 2, in: utc)
        let week = ScheduleWeek(containing: now, calendar: cal)
        XCTAssertEqual(cal.component(.day, from: week.today(at: now)!), 9)
        XCTAssertEqual(utc.component(.day, from: now), 10)
    }
    func testWidgetUsesSundayThroughSaturdayEvenOnMondayFirstDevicesAcrossDST() {
        let cal = calendar(firstWeekday: 2)
        let week = ScheduleWeek(containing: date(2026, 11, 3, in: cal), calendar: cal, firstWeekday: 1)
        XCTAssertEqual(week.days.map { cal.component(.weekday, from: $0) }, [1, 2, 3, 4, 5, 6, 7])
        XCTAssertEqual(week.window.duration, 7 * 86400 + 3600)
        XCTAssertTrue(week.days.allSatisfy { cal.component(.hour, from: $0) == 0 })
    }
    func testSelectedDayPartitionsReleasesAtNowAndExcludesOtherDaysAndUnconfirmedDates() {
        let cal = calendar(); let now = date(2026, 10, 29, in: cal)
        func event(_ id: Int, at time: Date?, certainty: ScheduleCertainty = .broadcast) -> ReleaseEvent {
            ReleaseEvent(anime: Anime(id: id, title: "Title \(id)"), episode: 1, kind: .sub, date: time, certainty: certainty)
        }
        let earlier = event(1, at: now.addingTimeInterval(-60))
        let boundary = event(2, at: now)
        let later = event(3, at: now.addingTimeInterval(60))
        let delayed = event(4, at: now.addingTimeInterval(-60), certainty: .delayed)
        let releases = ScheduleDayReleases(on: now, events: [later, boundary, earlier, delayed, earlier,
            event(5, at: date(2026, 10, 30, in: cal)), event(6, at: nil)], now: now, calendar: cal)
        XCTAssertEqual(releases.events.count, 4)
        XCTAssertEqual(releases.aired.map(\.anime.id), [1, 2])
        XCTAssertEqual(releases.upcoming.map(\.anime.id), [4, 3])
        XCTAssertTrue(ScheduleDayReleases(on: date(2026, 10, 28, in: cal), events: releases.events, now: now, calendar: cal).events.isEmpty)
    }
    func testWidgetShowsOnlyTrackedSeriesAndCountsBatchesAndAudioVersionsOnce() {
        let cal = calendar(); let now = date(2026, 10, 29, in: cal)
        let tracked = Anime(id: 1, title: "Tracked")
        let planned = Anime(id: 2, title: "Also in library")
        let unrelated = Anime(id: 3, title: "Unrelated")
        let events = [
            ReleaseEvent(anime: tracked, episode: 2, kind: .dub, date: now, certainty: .verified),
            ReleaseEvent(anime: tracked, episode: 1, kind: .sub, date: now, certainty: .broadcast),
            ReleaseEvent(anime: planned, episode: 1, kind: .sub, date: now.addingTimeInterval(60), certainty: .broadcast),
            ReleaseEvent(anime: unrelated, episode: 1, kind: .sub, date: now, certainty: .broadcast)
        ]
        let releases = ScheduleDayReleases(on: now, events: events, now: now, calendar: cal)
        XCTAssertEqual(releases.trackedAnime(ids: [1, 2]).map(\.id), [1, 2])
        XCTAssertTrue(releases.trackedAnime(ids: []).isEmpty)
    }
    func testReleaseDayUsesDeviceTimezoneAtMidnightAndExclusiveNextDayBoundary() {
        let cal = calendar(); let utc = calendar(zone: "UTC")
        let day = date(2026, 10, 29, hour: 0, in: cal)
        let nextDay = date(2026, 10, 30, hour: 0, in: cal)
        let events = [day, date(2026, 10, 30, hour: 2, in: utc), nextDay].enumerated().map { index, time in
            ReleaseEvent(anime: Anime(id: index + 1, title: "Boundary"), episode: 1, kind: .sub, date: time, certainty: .broadcast)
        }
        XCTAssertEqual(ScheduleDayReleases(on: day, events: events, now: day, calendar: cal).events.map(\.anime.id), [1, 2])
        XCTAssertEqual(ScheduleDayReleases(on: nextDay, events: events, now: day, calendar: cal).events.map(\.anime.id), [3])
    }
    func testCountdownKeepsEstimatesDelaysAndUnknownDatesHonest() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func event(_ seconds: TimeInterval?, _ certainty: ScheduleCertainty = .broadcast) -> ReleaseEvent {
            ReleaseEvent(anime: Anime(id: 1, title: "Timing"), episode: 1, kind: .sub,
                date: seconds.map { now.addingTimeInterval($0) }, certainty: certainty)
        }
        XCTAssertEqual(ScheduleCountdown.label(for: event(5400), at: now), "In 1h 30m")
        XCTAssertEqual(ScheduleCountdown.label(for: event(5400), at: now, compact: true), "1h 30m")
        XCTAssertEqual(ScheduleCountdown.label(for: event(1), at: now, compact: true), "1m")
        XCTAssertEqual(ScheduleCountdown.label(for: event(-1), at: now), "Aired just now")
        XCTAssertEqual(ScheduleCountdown.label(for: event(-5400), at: now), "Aired 1h 30m ago")
        XCTAssertEqual(ScheduleCountdown.label(for: event(-5400), at: now, compact: true), "Aired")
        XCTAssertEqual(ScheduleCountdown.label(for: event(5400, .unverified), at: now), "Est. 1h 30m")
        XCTAssertEqual(ScheduleCountdown.label(for: event(nil), at: now), "Unconfirmed")
        XCTAssertEqual(ScheduleCountdown.label(for: event(-60, .delayed), at: now), "Delayed")
    }
}
