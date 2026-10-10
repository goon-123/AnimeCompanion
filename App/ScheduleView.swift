import SwiftUI
import UIKit
import AnimeCore

private enum ScheduleFilter: String, CaseIterable { case all = "All", sub = "Sub", dub = "Dub" }
private enum ScheduleMode: String, CaseIterable { case airing = "Airing Now", weekly = "Weekly Schedule" }

struct ScheduleView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var dubs: ExploreDubStore
    @EnvironmentObject private var navigation: AppNavigationStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var mode = ScheduleMode.airing
    @State private var showSettings = false
    @State private var anchor = ScheduleClock.now
    @State private var now = ScheduleClock.now
    @State private var automaticDay: Date?
    @AppStorage("schedule.releaseType") private var filterValue = ScheduleFilter.all.rawValue
    @AppStorage("schedule.libraryOnly") private var libraryOnly = false
    @State private var pickingDate = false
    @State private var subEvents: [ReleaseEvent] = []
    @State private var dubEvents: [ReleaseEvent] = []
    @State private var subError: String?
    @State private var dubError: String?
    @State private var loading = false
    @State private var requestID = UUID()
    @State private var dubRequestID = UUID()
    private var filter: ScheduleFilter { ScheduleFilter(rawValue: filterValue) ?? .all }
    private var week: ScheduleWeek { ScheduleWeek(containing: anchor) }
    private var window: DateInterval { week.window }
    private var today: Date? { week.today(at: now) }
    private var dubPresentationKey: String { "\(window.start.timeIntervalSince1970)-\(dubs.revision)" }
    private var dubNotice: String? {
        let notices = [dubs.notice, dubError].compactMap { $0 }
        return notices.isEmpty ? nil : notices.joined(separator: "\n")
    }
    private var visible: [ReleaseEvent] {
        let ids = Set(store.watching.map(\.mediaId))
        return (subEvents + dubEvents).filter {
            guard store.isVisible($0.anime), filter == .all || (filter == .sub && $0.kind == .sub) || (filter == .dub && $0.kind == .dub) else { return false }
            return !libraryOnly || !store.isSignedIn || ids.contains($0.anime.id)
        }.sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
    }
    var body: some View {
        VStack(spacing: 0) {
            Picker("Schedule view", selection: $mode) {
                ForEach(ScheduleMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).padding(.horizontal, 16).padding(.vertical, 12)
                .readableContent(width: 1000).accessibilityIdentifier("schedule-mode")
            if mode == .airing { AiringNowView(showSettings: $showSettings) }
            else { weeklySchedule }
        }.background(Theme.background).navigationTitle("Schedule").navigationBarTitleDisplayMode(.inline).animeNavigation()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "person.crop.circle") }
                        .accessibilityLabel("Account and settings")
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .onChange(of: navigation.selectedTab) { _, tab in if tab == .schedule { mode = .airing } }
            .onChange(of: mode) { _, mode in if mode == .weekly { refreshToday() } }
            .onChange(of: scenePhase) { _, phase in if phase == .active { refreshToday() } }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in refreshToday() }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in refreshToday() }
    }
    private var weeklySchedule: some View {
      ScrollViewReader { scroll in
        VStack(spacing: 0) {
            weeklyControls(scroll: scroll)
            List {
            if loading { ProgressView("Loading releases…") }
            if filter != .dub, let error = subError { NoticeView(message: "Original schedule: \(error)") { Task { await load(refresh: true) } } }
            if filter != .sub, let error = dubNotice { NoticeView(message: "Dub schedule: \(error)") { Task { await load(refresh: true) } } }
            ForEach(week.days, id: \.self) { releaseDay($0) }
            if visible.contains(where: { $0.date == nil }) {
                Section("Delayed · No confirmed date") { ForEach(visible.filter { $0.date == nil }) { ReleaseRow(event: $0) } }
            }
            if visible.isEmpty && !loading {
                Section { Text("No listed releases for this week.").foregroundStyle(.secondary) }
            }
            Section { Text("English dub dates are reported by the maintained AniSchedule feed and may change. Estimates are labeled. An empty schedule does not mean that a dub is unavailable.").font(.caption).foregroundStyle(.secondary) }
            }.scrollContentBackground(.hidden).readableContent()
                .accessibilityIdentifier("schedule-weekly-list")
                .simultaneousGesture(DragGesture(minimumDistance: 8).onChanged { _ in automaticDay = nil })
                .refreshable { await load(refresh: true) }
        }.background(Theme.background)
            // The day rows exist before network results arrive, even on empty days.
            // Re-anchor late-loading rows only until the user starts browsing manually.
            .task(id: "\(window.start)-\(today?.timeIntervalSince1970 ?? -1)") {
                automaticDay = today
                await Task.yield()
                guard !Task.isCancelled, let today, automaticDay == today else { return }
                scroll.scrollTo(today, anchor: .top)
            }
            .onChange(of: visible) { _, _ in
                Task { @MainActor in
                    await Task.yield()
                    guard let automaticDay, automaticDay == today else { return }
                    scroll.scrollTo(automaticDay, anchor: .top)
                }
            }
            .onAppear { refreshToday() }
            .task(id: "\(window.start)-\(store.includeAdult)") { await load() }
            .task(id: dubPresentationKey) { await presentDubs() }
            .sheet(isPresented: $pickingDate) {
                NavigationStack {
                    DatePicker("Schedule date", selection: $anchor, displayedComponents: .date).datePickerStyle(.graphical).padding()
                        .navigationTitle("Choose a date").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { pickingDate = false } } }
                }.presentationDetents([.medium, .large])
            }
            .onChange(of: store.isSignedIn) { _, signedIn in if !signedIn { libraryOnly = false } }
      }
    }
    private func weeklyControls(scroll: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button { shift(-7) } label: { Image(systemName: "chevron.left").frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("Previous week")
                Spacer()
                Button { pickingDate = true } label: {
                    Label(window.start.formatted(.dateTime.month(.abbreviated).day()) + " – " + window.end.addingTimeInterval(-1).formatted(.dateTime.month(.abbreviated).day()), systemImage: "calendar")
                        .font(.subheadline.bold())
                }.accessibilityLabel("Choose schedule date")
                    .accessibilityIdentifier("schedule-week")
                    .accessibilityValue(window.start.formatted(.dateTime.year().month().day()))
                Spacer()
                Button { shift(7) } label: { Image(systemName: "chevron.right").frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("Next week")
            }.buttonStyle(.borderless)
            Button("This week") {
                refreshToday(); anchor = now; automaticDay = today
                if let today { scroll.scrollTo(today, anchor: .top) }
            }.accessibilityIdentifier("schedule-this-week")
            Picker("Release type", selection: $filterValue) { ForEach(ScheduleFilter.allCases, id: \.self) { Text($0.rawValue).tag($0.rawValue) } }
                .pickerStyle(.segmented).accessibilityIdentifier("schedule-release-type")
            if store.isSignedIn { Toggle("My watching list only", isOn: $libraryOnly) }
            weekdayStrip(scroll: scroll)
            Text("Times in \(TimeZone.current.identifier). Sub times are original Japanese broadcasts.").font(.caption).foregroundStyle(.secondary)
        }.padding(.horizontal, 16).padding(.bottom, 12).readableContent(width: 1000)
    }
    private func releaseDay(_ date: Date) -> some View {
        let releases = visible.filter { event in event.date.map { Calendar.current.isDate($0, inSameDayAs: date) } ?? false }
        return Section {
            HStack {
                Text(date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())).font(.subheadline.bold())
                Spacer()
                if date == today { Text("Today").font(.caption.bold()).padding(.horizontal, 9).padding(.vertical, 5).background(Color.white.opacity(0.12), in: Capsule()) }
            }.id(date).accessibilityElement(children: .combine)
                .accessibilityIdentifier("schedule-day-\(dayID(date))")
                .accessibilityValue(date == today ? "Today" : "")
                .listRowBackground(date == today ? Theme.surface : Theme.surface.opacity(0.45))
            ForEach(releases) { ReleaseRow(event: $0) }
            if releases.isEmpty {
                Text(loading ? "Loading releases…" : "No listed releases for this day.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private func weekdayStrip(scroll: ScrollViewProxy) -> some View {
        ScrollViewReader { dayScroll in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(week.days, id: \.self) { date in
                        Button { automaticDay = nil; scroll.scrollTo(date, anchor: .top) } label: {
                            VStack(spacing: 3) {
                                Text(date.formatted(.dateTime.weekday(.abbreviated))).font(.caption2.weight(.semibold))
                                Text(date.formatted(.dateTime.day())).font(.subheadline.bold())
                            }.frame(minWidth: 47, minHeight: 46)
                                .foregroundStyle(date == today ? Color.black : Color.white)
                                .background(date == today ? Color.white : Theme.surface, in: RoundedRectangle(cornerRadius: 10))
                        }.buttonStyle(.plain).id(dayID(date))
                            .accessibilityIdentifier("schedule-jump-\(dayID(date))")
                            .accessibilityLabel(date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()) + (date == today ? ", Today" : ""))
                            .accessibilityHint("Scroll to this day's releases")
                            .accessibilityAddTraits(date == today ? .isSelected : [])
                    }
                }
            }.accessibilityIdentifier("schedule-weekdays")
                .task(id: today) {
                    await Task.yield()
                    guard !Task.isCancelled, let today else { return }
                    dayScroll.scrollTo(dayID(today), anchor: .center)
                }
        }
    }
    private func dayID(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
    private func refreshToday() {
        let updated = ScheduleClock.now
        // Follow a new week only if the user was already browsing the current week.
        if week.today(at: now) != nil, week.today(at: updated) == nil { anchor = updated }
        now = updated
    }
    private func shift(_ days: Int) {
        automaticDay = nil
        anchor = Calendar.current.date(byAdding: .day, value: days, to: anchor) ?? anchor
    }
    private func load(refresh: Bool = false) async {
        let attempt = UUID(); requestID = attempt; let selected = window
        loading = true; subError = nil; subEvents = []
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-schedule-preview") {
            if ProcessInfo.processInfo.arguments.contains("--ui-schedule-delay-preview") {
                do { try await Task.sleep(for: .seconds(20)); try Task.checkCancellation() } catch { return }
                guard requestID == attempt, selected == window else { return }
            }
            subEvents = week.days.enumerated().map { index, date in
                let anime = Anime(id: 990200 + index, title: "Schedule preview · \(date.formatted(.dateTime.weekday(.wide)))")
                return ReleaseEvent(anime: anime, episode: index + 1, kind: .sub,
                    date: Calendar.current.date(byAdding: .hour, value: 12, to: date), certainty: .broadcast)
            }
            loading = false; return
        }
        #endif
        async let original: Void = loadSub(selected, attempt: attempt, refresh: refresh)
        async let dubbed: Void = dubs.load(using: store.dubs, refresh: refresh)
        _ = await (original, dubbed)
        if requestID == attempt { loading = false }
    }
    private func loadSub(_ window: DateInterval, attempt: UUID, refresh: Bool) async {
        do {
            let events = try await store.aniList.airings(in: window, refresh: refresh, includeAdult: store.includeAdult)
            try Task.checkCancellation(); if requestID == attempt { subEvents = events }
        } catch is CancellationError {} catch { if requestID == attempt { subError = error.localizedDescription } }
    }
    private func presentDubs() async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-schedule-preview") { dubEvents = []; return }
        #endif
        let attempt = UUID(); dubRequestID = attempt
        let selected = window; let revision = dubs.revision
        dubError = nil
        guard let snapshot = dubs.snapshot else { dubEvents = []; return }
        do {
            let known = Dictionary(uniqueKeysWithValues: store.entries.compactMap { $0.media.map { ($0.id, $0) } })
            let initial = snapshot.events(knownMedia: known).filter { event in
                guard let date = event.date else { return true }
                return date >= selected.start && date < selected.end
            }
            try Task.checkCancellation()
            guard dubRequestID == attempt, revision == dubs.revision, selected == window else { return }
            dubEvents = initial
            let missing = initial.filter { $0.anime.title?.english == "Anime #\($0.anime.id)" }.map { $0.anime.id }
            if !missing.isEmpty {
                do {
                    let found = try await store.aniList.media(ids: missing)
                    try Task.checkCancellation()
                    let hydrated = known.merging(Dictionary(uniqueKeysWithValues: found.map { ($0.id, $0) })) { _, new in new }
                    if dubRequestID == attempt, revision == dubs.revision, selected == window {
                        dubEvents = snapshot.events(knownMedia: hydrated).filter { event in
                            guard store.isVisible(event.anime) else { return false }
                            guard let date = event.date else { return true }
                            return date >= selected.start && date < selected.end
                        }
                    }
                } catch is CancellationError {} catch {
                    if dubRequestID == attempt, revision == dubs.revision, selected == window {
                        dubError = "Some titles could not be resolved. " + error.localizedDescription
                    }
                }
            }
        } catch is CancellationError {} catch { if dubRequestID == attempt { dubError = error.localizedDescription } }
    }
}

private enum ScheduleClock {
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

