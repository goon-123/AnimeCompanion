import SwiftUI
import AnimeCore

/// One bounded, shared copy of original broadcasts for Schedule and Home.
/// Library/content filters are applied at presentation time, never to this cache.
@MainActor
final class WeeklyScheduleStore: ObservableObject {
    struct Snapshot {
        var events: [ReleaseEvent] = []
        var loadedAt: Date?
        var loading = false
        var error: String?
    }
    @Published private var snapshots: [DateInterval: Snapshot] = [:]
    private var requests: [DateInterval: Task<Void, Never>] = [:]
    #if DEBUG
    private var delayedPreviewOnce = false
    #endif

    func snapshot(in window: DateInterval) -> Snapshot { snapshots[window] ?? Snapshot() }

    func load(in window: DateInterval, using client: AniListClient, refresh: Bool = false) async {
        if let request = requests[window] { await request.value; return }
        let previous = snapshot(in: window)
        if !refresh, let loadedAt = previous.loadedAt, Date().timeIntervalSince(loadedAt) < 15 * 60 { return }
        var pending = previous; pending.loading = true; pending.error = nil
        snapshots[window] = pending
        let request = Task { @MainActor in
            do {
                let events: [ReleaseEvent]
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--ui-schedule-preview") {
                    if ProcessInfo.processInfo.arguments.contains("--ui-schedule-delay-preview"), !delayedPreviewOnce {
                        delayedPreviewOnce = true
                        try await Task.sleep(for: .seconds(20))
                    }
                    let days = (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: window.start) }
                    var preview = days.enumerated().map { index, date in
                        ReleaseEvent(anime: Anime(id: 990200 + index, title: "Schedule preview · \(date.formatted(.dateTime.weekday(.wide)))"),
                            episode: index + 1, kind: .sub, date: Calendar.current.date(byAdding: .hour, value: 12, to: date), certainty: .broadcast)
                    }
                    if ProcessInfo.processInfo.arguments.contains("--ui-today-long-preview"), ScheduleClock.now >= window.start, ScheduleClock.now < window.end {
                        let today = Calendar.current.startOfDay(for: ScheduleClock.now)
                        preview += (1...12).map { index in
                            ReleaseEvent(anime: Anime(id: 990300 + index, title: "Today's release \(index)"), episode: index, kind: .sub,
                                date: Calendar.current.date(byAdding: .minute, value: 720 + index, to: today), certainty: .broadcast)
                        }
                    }
                    events = preview
                } else { events = try await client.airings(in: window, refresh: refresh, includeAdult: true) }
                #else
                events = try await client.airings(in: window, refresh: refresh, includeAdult: true)
                #endif
                snapshots[window] = Snapshot(events: events, loadedAt: Date())
            } catch {
                var failed = previous; failed.error = error.localizedDescription
                snapshots[window] = failed
            }
        }
        requests[window] = request
        await request.value
        requests[window] = nil
        // Browsing many weeks must not retain an unbounded schedule history.
        let oldest = snapshots.keys.filter { $0 != window && requests[$0] == nil }
            .sorted { (snapshots[$0]?.loadedAt ?? .distantPast) < (snapshots[$1]?.loadedAt ?? .distantPast) }
        for key in oldest.prefix(max(0, snapshots.count - 5)) { snapshots[key] = nil }
    }
}

enum ScheduleClock {
    static var now: Date {
        #if DEBUG
        if let value = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--ui-schedule-day=") }) {
            let parts = value.dropFirst("--ui-schedule-day=".count).split(separator: "-").compactMap { Int($0) }
            if parts.count == 3, let date = Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)) { return date }
        }
        #endif
        return Date()
    }
}
