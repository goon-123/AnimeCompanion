import SwiftUI
import UIKit
import AnimeCore

/// Home is independent of the Schedule screen's Sub/Dub and library filters.
/// It shares original broadcasts and the existing dub snapshot, then intersects
/// them with every visible status in the user's actual AniList library.
struct AiringThisWeekView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var schedule: WeeklyScheduleStore
    @EnvironmentObject private var dubs: ExploreDubStore
    @EnvironmentObject private var navigation: AppNavigationStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var now = ScheduleClock.now
    private var week: ScheduleWeek { ScheduleWeek(containing: now, firstWeekday: 1) }
    private var trackedIDs: Set<Int> { store.isSignedIn ? Set(store.visibleEntries.map(\.mediaId)) : [] }
    private var events: [ReleaseEvent] {
        let snapshot = schedule.snapshot(in: week.window)
        var events = snapshot.events
        let known = store.visibleEntries.compactMap(\.media).reduce(into: [Int: Anime]()) { $0[$1.id] = $1 }
        events += dubs.snapshot?.events(knownMedia: known, now: now) ?? []
        // Existing next-airing metadata supplies real upcoming dates while the
        // full week loads or is unavailable. Never infer a weekly recurrence.
        if snapshot.loadedAt == nil {
            events += known.values.compactMap { anime in
                guard let next = anime.nextAiringEpisode else { return nil }
                return ReleaseEvent(anime: anime, episode: next.episode, kind: .sub, date: next.date, certainty: .broadcast)
            }
        }
        return events.filter { store.isVisible($0.anime) }
    }
    private var refreshKey: String { "\(scenePhase)-\(navigation.selectedTab)-\(week.window.start)-\(!trackedIDs.isEmpty)" }

    var body: some View {
        let weeklyEvents = events
        let ids = trackedIDs
        VStack(alignment: .leading, spacing: 12) {
            CompanionSectionHeading(title: "Airing this week")
            HStack(alignment: .top, spacing: 6) {
                ForEach(week.days, id: \.self) { day in
                    let titles = ScheduleDayReleases(on: day, events: weeklyEvents, now: now).trackedAnime(ids: ids)
                    Button { navigation.openSchedule(on: day) } label: {
                        dayCell(day, titles: titles).frame(maxWidth: .infinity)
                    }.buttonStyle(.plain)
                        .accessibilityIdentifier("home-week-\(Calendar.current.component(.weekday, from: day))")
                        .accessibilityLabel(day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()) + (Calendar.current.isDate(day, inSameDayAs: now) ? ", Today" : ""))
                        .accessibilityValue(titles.isEmpty ? "No tracked releases" : titles.map(\.displayTitle).joined(separator: ", "))
                        .accessibilityHint("Open this date in Weekly Schedule")
                }
            }
            if let error = schedule.snapshot(in: week.window).error, !trackedIDs.isEmpty {
                Button { Task { await refresh(force: true) } } label: {
                    Text("Weekly schedule unavailable · Retry").font(.caption2).foregroundStyle(.secondary)
                }.accessibilityHint(error)
            }
        }.accessibilityIdentifier("home-airing-week")
            .task(id: refreshKey) {
                guard scenePhase == .active, navigation.selectedTab == .home else { return }
                while !Task.isCancelled {
                    now = ScheduleClock.now
                    await refresh()
                    do { try await Task.sleep(for: .seconds(60)) } catch { return }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in now = ScheduleClock.now }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in now = ScheduleClock.now }
    }

    private func dayCell(_ day: Date, titles: [Anime]) -> some View {
        let isToday = Calendar.current.isDate(day, inSameDayAs: now)
        return VStack(spacing: 8) {
            Text(day.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                .font(.caption2.weight(isToday ? .bold : .medium)).lineLimit(1).minimumScaleFactor(0.7)
                .foregroundStyle(isToday ? Theme.accent : Color.secondary)
            Color.clear.aspectRatio(1 / 1.45, contentMode: .fit)
                .overlay {
                    if let anime = titles.first {
                        GeometryReader { geometry in
                            ArtworkImage(url: anime.coverURL, pointSize: geometry.size.height) { image in
                                image.resizable().scaledToFill()
                            } placeholder: { Theme.surface }
                                .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                        }.clipShape(RoundedRectangle(cornerRadius: 9))
                    } else {
                        RoundedRectangle(cornerRadius: 9).fill(Theme.surface.opacity(0.45))
                        RoundedRectangle(cornerRadius: 9)
                            .strokeBorder(isToday ? Theme.accent : Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: isToday ? 1.5 : 1, dash: [4, 4]))
                        if isToday { Image(systemName: "plus").font(.headline).foregroundStyle(Theme.accent) }
                    }
                }
                .overlay {
                    if isToday, !titles.isEmpty {
                        RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.accent, lineWidth: 2)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if titles.count > 1 {
                        Text("+\(titles.count - 1)").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                            .padding(.horizontal, 4).padding(.vertical, 3)
                            .background(Color.black.opacity(0.8), in: Capsule()).padding(3)
                    }
                }
        }.frame(maxWidth: 72).contentShape(Rectangle())
    }
    private func refresh(force: Bool = false) async {
        guard !trackedIDs.isEmpty else { return }
        async let original: Void = schedule.load(in: week.window, using: store.aniList, refresh: force)
        async let dubbed: Void = dubs.load(using: store.dubs, refresh: force)
        _ = await (original, dubbed)
    }
}
