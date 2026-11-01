import Foundation

/// Local calendar dates, not fixed 24-hour offsets: weeks can cross daylight-saving changes.
public struct ScheduleWeek {
    public let window: DateInterval
    public let days: [Date]
    private let calendar: Calendar

    public init(containing date: Date, calendar: Calendar = .autoupdatingCurrent, firstWeekday: Int? = nil) {
        var calendar = calendar
        if let firstWeekday, (1...7).contains(firstWeekday) { calendar.firstWeekday = firstWeekday }
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

/// Both agenda layouts and the Home week use the same local-day boundaries.
public struct ScheduleDayReleases {
    public let events: [ReleaseEvent]
    public let upcoming: [ReleaseEvent]
    public let aired: [ReleaseEvent]

    public init(on day: Date, events: [ReleaseEvent], now: Date = Date(), calendar: Calendar = .autoupdatingCurrent) {
        var seen = Set<String>()
        self.events = events.filter {
            guard let date = $0.date else { return false }
            return calendar.isDate(date, inSameDayAs: day) && seen.insert($0.id).inserted
        }.sorted {
            if $0.date != $1.date { return ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
            return $0.id < $1.id
        }
        upcoming = self.events.filter { $0.certainty == .delayed || ($0.date ?? .distantFuture) > now }
        aired = self.events.filter { $0.certainty != .delayed && ($0.date ?? .distantFuture) <= now }
    }

    /// A batch or a Sub/Dub pair still occupies one poster for the tracked series.
    public func trackedAnime(ids: Set<Int>) -> [Anime] {
        var seen = Set<Int>()
        return events.compactMap { event in
            guard ids.contains(event.anime.id), seen.insert(event.anime.id).inserted else { return nil }
            return event.anime
        }
    }
}

public enum ScheduleCountdown {
    public static func label(for event: ReleaseEvent, at now: Date = Date(), compact: Bool = false) -> String {
        if event.certainty == .delayed { return "Delayed" }
        guard let date = event.date else { return "Unconfirmed" }
        let remaining = date.timeIntervalSince(now)
        if remaining <= 0, event.certainty != .unverified {
            if compact { return "Aired" }
            if remaining > -60 { return "Aired just now" }
        }
        let minutes = max(1, Int(remaining > 0 ? ceil(remaining / 60) : floor(-remaining / 60)))
        let duration: String
        if minutes >= 1440 {
            duration = "\(minutes / 1440)d" + (minutes % 1440 >= 60 ? " \(minutes % 1440 / 60)h" : "")
        } else if minutes >= 60 {
            duration = "\(minutes / 60)h" + (minutes % 60 > 0 ? " \(minutes % 60)m" : "")
        } else { duration = "\(minutes)m" }
        if event.certainty == .unverified { return "Est. \(duration)" + (remaining <= 0 ? " ago" : "") }
        return remaining > 0 ? (compact ? duration : "In \(duration)") : "Aired \(duration) ago"
    }
}
