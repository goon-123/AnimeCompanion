import SwiftUI
import UIKit
import AnimeCore

private enum ScheduleFilter: String, CaseIterable { case all = "All", sub = "Sub", dub = "Dub" }
private enum ScheduleMode: String, CaseIterable { case airing = "Airing Now", weekly = "Weekly Schedule" }
private enum WeeklyScheduleMode: String, CaseIterable { case continuous, day }
private struct ScheduleScrollRequest: Equatable { let day: Date; var token = UUID() }

struct ScheduleView: View {
    var landing: ScheduleHomeRoute? = nil
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var dubs: ExploreDubStore
    @EnvironmentObject private var navigation: AppNavigationStore
    @EnvironmentObject private var schedule: WeeklyScheduleStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var textSize
    @AppStorage("schedule.page") private var mode = ScheduleMode.airing
    @State private var showSettings = false
    @State private var anchor = ScheduleClock.now
    @State private var now = ScheduleClock.now
    @State private var scrollRequest: ScheduleScrollRequest?
    @State private var selectedDay: Date?
    @State private var appliedLanding: UUID?
    @ScaledMetric(relativeTo: .subheadline) private var weekdayHeight: CGFloat = 74
    @AppStorage("schedule.releaseType") private var filterValue = ScheduleFilter.all.rawValue
    @AppStorage("schedule.libraryOnly") private var libraryOnly = false
    @AppStorage("schedule.weekly.mode") private var weeklyModeValue = WeeklyScheduleMode.continuous.rawValue
    @AppStorage("schedule.weekly.layout") private var dayLayout = "list"
    @State private var pickingDate = false
    @State private var dubEvents: [ReleaseEvent] = []
    @State private var dubError: String?
    @State private var dubRequestID = UUID()
    private var subEvents: [ReleaseEvent] { schedule.snapshot(in: window).events }
    private var subError: String? { schedule.snapshot(in: window).error }
    private var loading: Bool { schedule.snapshot(in: window).loading || dubs.loading }
    private var weeklyMode: WeeklyScheduleMode { WeeklyScheduleMode(rawValue: weeklyModeValue) ?? .continuous }
    private var filter: ScheduleFilter { ScheduleFilter(rawValue: filterValue) ?? .all }
    private var week: ScheduleWeek { ScheduleWeek(containing: anchor) }
    private var window: DateInterval { week.window }
    private var today: Date? { week.today(at: now) }
    private var selectedDate: Date { selectedDay ?? today ?? window.start }
    private var selectedReleases: ScheduleDayReleases { ScheduleDayReleases(on: selectedDate, events: visible, now: now) }
    private var dayColumns: [GridItem] {
        if textSize.isAccessibilitySize { return [GridItem(.adaptive(minimum: 220), spacing: 12, alignment: .top)] }
        if UIDevice.current.userInterfaceIdiom == .pad { return [GridItem(.adaptive(minimum: 140), spacing: 12, alignment: .top)] }
        return Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: 3)
    }
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
            .appSettingsSheet(isPresented: $showSettings)
            .onChange(of: landing, initial: true) { _, request in
                guard let request, appliedLanding != request.id else { return }
                appliedLanding = request.id
                mode = request.page == .weekly ? .weekly : .airing
                selectDate(request.day)
            }
            .onChange(of: mode) { _, mode in if mode == .weekly { refreshToday() } }
            .onChange(of: scenePhase) { _, phase in if phase == .active { refreshToday() } }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in refreshToday() }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in refreshToday() }
            .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in
                if scenePhase == .active, mode == .weekly { refreshToday() }
            }
    }
    private var weeklySchedule: some View {
        VStack(spacing: 0) {
            weeklyControls
            if weeklyMode == .continuous { continuousSchedule }
            else { singleDaySchedule }
        }.background(Theme.background)
            .onAppear { refreshToday(); ensureSelectedDay() }
            .onChange(of: weeklyModeValue) { _, _ in requestSelectedDay() }
            .onChange(of: visible) { _, _ in
                // Network results may change row heights, but never replace the
                // user's chosen date. A free scroll cancels this positioning.
                guard let day = scrollRequest?.day else { return }
                scrollRequest = ScheduleScrollRequest(day: day)
            }
            .task(id: "\(window.start)") { await load() }
            .task(id: dubPresentationKey) { await presentDubs() }
            .sheet(isPresented: $pickingDate) {
                AppNavigationStack {
                    DatePicker("Schedule date", selection: Binding(get: { selectedDate }, set: { selectDate($0) }), displayedComponents: .date)
                        .datePickerStyle(.graphical).padding()
                        .navigationTitle("Choose a date").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { pickingDate = false } } }
                }.presentationDetents([.medium, .large])
            }
            .onChange(of: store.isSignedIn) { _, signedIn in if !signedIn { libraryOnly = false } }
    }
    private var continuousSchedule: some View {
        // Keep the vertical reader independent of the weekday strip's reader.
        ScrollViewReader { scroll in
            List {
                scheduleNotices
                ForEach(week.days, id: \.self) { releaseDay($0) }
                if visible.contains(where: { $0.date == nil }) {
                    Section("Awaiting a date") {
                        ForEach(visible.filter { $0.date == nil }) {
                            ScheduleReleaseRow(event: $0, now: now).modifier(ScheduleRowInsets())
                        }
                    }
                }
                if visible.isEmpty && !loading {
                    Section { Text("No listed releases for this week.").foregroundStyle(.secondary) }
                }
                Section { scheduleFootnote.padding(.vertical, 12) }
            }.listStyle(.plain).listSectionSpacing(0)
                .listRowSeparator(.hidden).scrollContentBackground(.hidden).readableContent(width: 1000)
                .contentMargins(.bottom, 28, for: .scrollContent)
                .accessibilityIdentifier("schedule-weekly-list")
                .simultaneousGesture(DragGesture(minimumDistance: 8).onChanged { _ in cancelAutomaticPositioning() })
                .refreshable { await load(refresh: true) }
                .task(id: scrollRequest) {
                    guard let request = scrollRequest else { return }
                    // Wait for the List's rows to register their first layout.
                    do { try await Task.sleep(for: .milliseconds(150)); try Task.checkCancellation() } catch { return }
                    guard scrollRequest == request else { return }
                    scroll.scrollTo("release-day-\(dayID(request.day))", anchor: .top)
                }
        }
    }
    private var singleDaySchedule: some View {
        let releases = selectedReleases
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                scheduleNotices
                dayHeading(selectedDate, count: releases.events.count)
                if releases.events.isEmpty && !loading {
                    Text("No listed releases for this day.")
                        .font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 20)
                }
                releaseGroup("Upcoming", events: releases.upcoming)
                releaseGroup(selectedDate == today ? "Aired today" : "Already aired", events: releases.aired)
                scheduleFootnote.padding(.vertical, 8)
            }.padding(16).padding(.bottom, 28).readableContent(width: 1000)
        }.id(dayID(selectedDate)).accessibilityIdentifier("schedule-single-day")
            .refreshable { await load(refresh: true) }
    }
    @ViewBuilder private var scheduleNotices: some View {
        if loading { ProgressView("Loading releases…") }
        if filter != .dub, let error = subError { NoticeView(message: "Original schedule: \(error)") { Task { await load(refresh: true) } } }
        if filter != .sub, let error = dubNotice { NoticeView(message: "Dub schedule: \(error)") { Task { await load(refresh: true) } } }
    }
    private var scheduleFootnote: some View {
        Text("Times in \(TimeZone.current.identifier). Sub times are original Japanese broadcasts. English dub dates use AniSchedule; estimates and delays are labeled. Missing dates remain unconfirmed.")
            .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
    @ViewBuilder private func releaseGroup(_ title: String, events: [ReleaseEvent]) -> some View {
        if !events.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(title).font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(events.count)").font(.caption).foregroundStyle(.secondary)
                }.accessibilityAddTraits(.isHeader)
                if dayLayout == "grid" {
                    LazyVGrid(columns: dayColumns, alignment: .leading, spacing: 16) {
                        ForEach(events) { ScheduleReleaseGridCard(event: $0, now: now) }
                    }
                } else {
                    ForEach(events) { ScheduleReleaseRow(event: $0, now: now) }
                }
            }
        }
    }
    private var weeklyControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 4) {
                Button { shift(-7) } label: { Image(systemName: "chevron.left").frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("Previous week")
                Button { pickingDate = true } label: {
                    HStack(spacing: 5) {
                        Text(window.start.formatted(.dateTime.month(.abbreviated).day()) + " – " + window.end.addingTimeInterval(-1).formatted(.dateTime.month(.abbreviated).day()))
                            .font(.headline)
                        Image(systemName: "chevron.down").font(.caption2.weight(.bold))
                    }.frame(minHeight: 44)
                }.accessibilityLabel("Choose schedule date")
                    .accessibilityIdentifier("schedule-week")
                    .accessibilityValue(window.start.formatted(.dateTime.year().month().day()))
                Button { shift(7) } label: { Image(systemName: "chevron.right").frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("Next week")
                Spacer(minLength: 0)
                Button("Today") { refreshToday(); selectDate(now) }
                    .font(.caption.weight(.semibold)).padding(.horizontal, 12).frame(minHeight: 44)
                    .background(Theme.accent.opacity(0.10), in: Capsule())
                    .accessibilityLabel("This week").accessibilityIdentifier("schedule-this-week")
            }.buttonStyle(.plain).foregroundStyle(Theme.accent)
            HStack(spacing: 12) {
                Picker("Release type", selection: $filterValue) { ForEach(ScheduleFilter.allCases, id: \.self) { Text($0.rawValue).tag($0.rawValue) } }
                    .pickerStyle(.segmented).frame(maxWidth: 240).accessibilityIdentifier("schedule-release-type")
                Spacer(minLength: 0)
                if store.isSignedIn {
                    Menu {
                        Toggle("My watching list only", isOn: $libraryOnly)
                    } label: {
                        Label(libraryOnly ? "My list" : "Everyone", systemImage: libraryOnly ? "person.fill" : "line.3.horizontal.decrease")
                            .font(.caption.weight(.medium)).frame(minHeight: 44)
                    }.accessibilityLabel("Schedule library filter").accessibilityValue(libraryOnly ? "My watching list only" : "Everyone")
                        .accessibilityIdentifier("schedule-library-filter")
                }
            }
            weekdayStrip
            HStack(spacing: 12) {
                Picker("Weekly viewing mode", selection: $weeklyModeValue) {
                    Text("Continuous").tag(WeeklyScheduleMode.continuous.rawValue)
                    Text("Single day").tag(WeeklyScheduleMode.day.rawValue)
                }.pickerStyle(.segmented).frame(maxWidth: 340).accessibilityIdentifier("schedule-weekly-mode")
                Spacer(minLength: 0)
                if weeklyMode == .day {
                    Picker("Single-day layout", selection: $dayLayout) {
                        Image(systemName: "square.grid.3x3").accessibilityLabel("Grid").tag("grid")
                        Image(systemName: "list.bullet").accessibilityLabel("List").tag("list")
                    }.pickerStyle(.segmented).frame(width: 92).accessibilityIdentifier("schedule-day-layout")
                }
            }
        }.padding(.horizontal, 16).padding(.bottom, 12).readableContent(width: 1000)
    }
    private func releaseDay(_ date: Date) -> some View {
        let releases = ScheduleDayReleases(on: date, events: visible, now: now).events
        let isToday = date == today
        return Section {
            dayHeading(date, count: releases.count)
                .id("release-day-\(dayID(date))").accessibilityElement(children: .combine)
                .accessibilityIdentifier("schedule-day-\(dayID(date))")
                .accessibilityValue(isToday ? "Today" : "")
                .listRowBackground(ScheduleDayBackground(isToday: isToday)).listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 8, trailing: 16))
            ForEach(releases) { event in
                ScheduleReleaseRow(event: event, now: now, isToday: isToday)
                    .listRowBackground(ScheduleDayBackground(isToday: isToday)).listRowSeparator(.hidden)
                    .modifier(ScheduleRowInsets())
            }
            if releases.isEmpty {
                Text(loading ? "Loading releases…" : "No listed releases for this day.").font(.caption).foregroundStyle(.secondary)
                    .padding(.vertical, 10)
                    .accessibilityIdentifier("schedule-empty-day-\(dayID(date))").accessibilityValue(isToday ? "Today" : "")
                    .listRowBackground(ScheduleDayBackground(isToday: isToday)).listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 12, trailing: 16))
            }
        }
    }
    private func dayHeading(_ date: Date, count: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(date == today ? "Today" : date.formatted(.dateTime.weekday(.wide))).font(.headline)
                    .foregroundStyle(date == today ? Theme.accent : Color.primary)
                Text(date.formatted(.dateTime.month(.abbreviated).day())).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text("\(count) \(count == 1 ? "release" : "releases")").font(.caption).foregroundStyle(.secondary)
        }.accessibilityAddTraits(.isHeader)
    }
    private var weekdayStrip: some View {
      GeometryReader { geometry in
        let dayWidth = max(44, (geometry.size.width - 24) / 7)
        ScrollViewReader { dayScroll in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(week.days, id: \.self) { date in
                        let selected = date == selectedDay
                        let count = visible.filter { $0.date.map { Calendar.current.isDate($0, inSameDayAs: date) } ?? false }.count
                        Button {
                            selectDate(date)
                        } label: {
                            VStack(spacing: 5) {
                                Text(date == today ? "Today" : date.formatted(.dateTime.weekday(.abbreviated))).font(.caption2.weight(.medium))
                                Text(date.formatted(.dateTime.day())).font(.title3.bold())
                                Circle().fill(count > 0 ? (selected ? Theme.background : Theme.accent) : Color.clear).frame(width: 4, height: 4)
                            }.frame(width: dayWidth, height: weekdayHeight)
                                .foregroundStyle(selected ? Theme.background : date == today ? Theme.accent : Color.primary)
                                .background(selected ? Theme.accent : Theme.surface, in: RoundedRectangle(cornerRadius: 14))
                                .overlay { RoundedRectangle(cornerRadius: 14).stroke(date == today && !selected ? Theme.accent : Color.clear, lineWidth: 1) }
                        }.buttonStyle(.plain).id(dayID(date))
                            .accessibilityIdentifier("schedule-jump-\(dayID(date))")
                            .accessibilityLabel(date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()) + (date == today ? ", Today" : ""))
                            .accessibilityHint(weeklyMode == .day ? "Show only this day's releases" : "Scroll to this day's releases")
                            .accessibilityValue("\(count) \(count == 1 ? "release" : "releases")")
                            .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
            }.accessibilityIdentifier("schedule-weekdays")
                .task(id: selectedDay) {
                    await Task.yield()
                    guard !Task.isCancelled, let selectedDay else { return }
                    dayScroll.scrollTo(dayID(selectedDay), anchor: .center)
                }
        }
      }.frame(height: weekdayHeight)
    }
    private func dayID(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
    private func refreshToday() {
        let updated = ScheduleClock.now
        let followedToday = selectedDay == Calendar.current.startOfDay(for: now)
        // Follow midnight only when the user was following Today. An explicit
        // date from Home or manual browsing must not be overwritten on activation.
        if followedToday, !Calendar.current.isDate(updated, inSameDayAs: now) { selectDate(updated) }
        now = updated
    }
    private func shift(_ days: Int) {
        selectDate(Calendar.current.date(byAdding: .day, value: days, to: selectedDate) ?? selectedDate)
    }
    private func selectDate(_ date: Date) {
        let day = Calendar.current.startOfDay(for: date)
        anchor = day; selectedDay = day
        requestSelectedDay()
    }
    private func ensureSelectedDay() {
        if let selectedDay, week.days.contains(selectedDay) { requestSelectedDay() }
        else { selectDate(today ?? week.days[0]) }
    }
    private func requestSelectedDay() {
        scrollRequest = weeklyMode == .continuous ? ScheduleScrollRequest(day: selectedDate) : nil
    }
    private func cancelAutomaticPositioning() {
        scrollRequest = nil
    }
    private func load(refresh: Bool = false) async {
        async let original: Void = schedule.load(in: window, using: store.aniList, refresh: refresh)
        async let dubbed: Void = dubs.load(using: store.dubs, refresh: refresh)
        _ = await (original, dubbed)
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

/// Identical backgrounds touch across the header, every release and empty states.
/// The continuous leading rail remains recognizable after Today scrolls offscreen.
private struct ScheduleDayBackground: View {
    let isToday: Bool
    var body: some View {
        Group {
            if isToday {
                Theme.accent.opacity(0.12)
                    .overlay(alignment: .leading) { Rectangle().fill(Theme.accent).frame(width: 3) }
            } else { Color.clear }
        }.accessibilityHidden(true)
    }
}

