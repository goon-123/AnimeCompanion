import SwiftUI
import UIKit
import AnimeCore

struct HomeTodayWidget: View {
    @EnvironmentObject private var anime: AppStore
    @EnvironmentObject private var schedule: WeeklyScheduleStore
    @EnvironmentObject private var dubs: ExploreDubStore
    @EnvironmentObject private var navigation: AppNavigationStore
    @Environment(\.scenePhase) private var scenePhase
    let limit: Int
    let refreshID: Int
    @State private var now = ScheduleClock.now
    @State private var appliedRefreshID = 0
    private var week: ScheduleWeek { ScheduleWeek(containing: now, firstWeekday: 1) }
    private var tracked: [LibraryEntry] { anime.isSignedIn ? HomeLibraryContent.unique(anime.visibleEntries) : [] }
    private var events: [ReleaseEvent] {
        let ids = Set(tracked.map(\.mediaId))
        let known = tracked.compactMap(\.media).reduce(into: [Int: Anime]()) { $0[$1.id] = $1 }
        let snapshot = schedule.snapshot(in: week.window)
        var events = snapshot.events + (dubs.snapshot?.events(knownMedia: known, now: now) ?? [])
        if snapshot.loadedAt == nil {
            events += known.values.compactMap { value in
                guard let next = value.nextAiringEpisode else { return nil }
                return ReleaseEvent(anime: value, episode: next.episode, kind: .sub, date: next.date, certainty: .broadcast)
            }
        }
        return ScheduleDayReleases(on: now, events: events.filter { ids.contains($0.anime.id) && anime.isVisible($0.anime) }, now: now).events
    }
    private var refreshKey: String { "\(scenePhase)-\(navigation.selectedTab)-\(week.window.start)-\(!tracked.isEmpty)-\(refreshID)" }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                CompanionSectionHeading(title: "Airing today")
                Button("Calendar") { navigation.openSchedule(on: now) }.font(.caption.weight(.semibold)).frame(minHeight: 44)
            }
            if events.isEmpty {
                if schedule.snapshot(in: week.window).loading && !tracked.isEmpty { ProgressView("Checking today's releases…") }
                else {
                    HomeWidgetEmpty(symbol: "calendar", title: "No tracked releases today.", detail: "Original and English dub releases from your library appear here.")
                }
            } else {
                VStack(spacing: 10) {
                    ForEach(Array(events.prefix(limit))) { event in
                        AnimeLink(id: event.anime.id) {
                            VStack(alignment: .leading, spacing: 5) {
                                HomeLibraryRow(anime: event.anime, detail: "Ep \(event.episode) · \(event.kind == .dub ? "English dub" : "Original broadcast")")
                                HStack(spacing: 8) {
                                    if let date = event.date { Text(date, style: .time) }
                                    Text(ScheduleCountdown.label(for: event, at: now))
                                }.font(.caption.weight(.medium)).foregroundStyle(Theme.accent).padding(.horizontal, 10)
                            }
                        }.buttonStyle(.plain)
                    }
                }
            }
            if schedule.snapshot(in: week.window).error != nil && !tracked.isEmpty {
                Button("Today's schedule unavailable · Retry") { Task { await refresh(force: true) } }.font(.caption)
            }
        }.task(id: refreshKey) {
            guard scenePhase == .active, navigation.selectedTab == .home else { return }
            while !Task.isCancelled {
                now = ScheduleClock.now
                await refresh(force: refreshID != appliedRefreshID)
                if !Task.isCancelled { appliedRefreshID = refreshID }
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in now = ScheduleClock.now }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in now = ScheduleClock.now }
    }
    private func refresh(force: Bool = false) async {
        guard !tracked.isEmpty else { return }
        async let originals: Void = schedule.load(in: week.window, using: anime.aniList, refresh: force)
        async let dubbed: Void = dubs.load(using: anime.dubs, refresh: force)
        _ = await (originals, dubbed)
    }
}
