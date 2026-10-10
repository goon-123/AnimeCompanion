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
}
