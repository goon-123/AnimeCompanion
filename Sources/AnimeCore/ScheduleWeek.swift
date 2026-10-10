import Foundation

/// Local calendar dates, not fixed 24-hour offsets: weeks can cross daylight-saving changes.
public struct ScheduleWeek {
    public let window: DateInterval
    public let days: [Date]
    private let calendar: Calendar

    public init(containing date: Date, calendar: Calendar = .autoupdatingCurrent) {
        self.calendar = calendar
        let start = calendar.startOfDay(for: date)
        let window = calendar.dateInterval(of: .weekOfYear, for: date)
            ?? DateInterval(start: start, end: calendar.date(byAdding: .day, value: 7, to: start) ?? start)
        self.window = window
        days = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: window.start) }
    }

    /// The end boundary belongs to the following week. Other weeks have no Today target.
    public func today(at now: Date) -> Date? {
        guard now >= window.start, now < window.end else { return nil }
        return calendar.startOfDay(for: now)
    }
}
