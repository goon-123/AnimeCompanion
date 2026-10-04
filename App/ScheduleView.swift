import SwiftUI
import AnimeCore

private enum ScheduleFilter: String, CaseIterable { case all = "All", sub = "Sub", dub = "Dub" }

struct ScheduleView: View {
    @EnvironmentObject private var store: AppStore
    @State private var anchor = Date()
    @AppStorage("schedule.releaseType") private var filterValue = ScheduleFilter.all.rawValue
    @AppStorage("schedule.libraryOnly") private var libraryOnly = false
    @State private var pickingDate = false
    @State private var subEvents: [ReleaseEvent] = []
    @State private var dubEvents: [ReleaseEvent] = []
    @State private var subError: String?
    @State private var dubError: String?
    @State private var loading = false
    @State private var requestID = UUID()
    private var filter: ScheduleFilter { ScheduleFilter(rawValue: filterValue) ?? .all }
    private var window: DateInterval {
        Calendar.current.dateInterval(of: .weekOfYear, for: anchor) ?? DateInterval(start: anchor, duration: 7 * 86400)
    }
    private var visible: [ReleaseEvent] {
        let ids = Set(store.watching.map(\.mediaId))
        return (subEvents + dubEvents).filter {
            guard filter == .all || (filter == .sub && $0.kind == .sub) || (filter == .dub && $0.kind == .dub) else { return false }
            return !libraryOnly || !store.isSignedIn || ids.contains($0.anime.id)
        }.sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
    }
    private var days: [Date] {
        Array(Set(visible.compactMap { $0.date }.map { Calendar.current.startOfDay(for: $0) })).sorted()
    }
    var body: some View {
        List {
            Section {
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
                Button("This week") { anchor = Date() }
                Picker("Release type", selection: $filterValue) { ForEach(ScheduleFilter.allCases, id: \.self) { Text($0.rawValue).tag($0.rawValue) } }
                    .pickerStyle(.segmented).accessibilityIdentifier("schedule-release-type")
                if store.isSignedIn { Toggle("My watching list only", isOn: $libraryOnly) }
                Text("Times in \(TimeZone.current.identifier). Sub times are original Japanese broadcasts.").font(.caption).foregroundStyle(.secondary)
            }
            if loading { ProgressView("Loading releases…") }
            if filter != .dub, let error = subError { NoticeView(message: "Original schedule: \(error)") { Task { await load(refresh: true) } } }
            if filter != .sub, let error = dubError { NoticeView(message: "Dub schedule: \(error)") { Task { await load(refresh: true) } } }
            ForEach(days, id: \.self) { date in
                Section(date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())) {
                    ForEach(visible.filter { event in event.date.map { Calendar.current.isDate($0, inSameDayAs: date) } ?? false }) { ReleaseRow(event: $0) }
                }
            }
            if visible.contains(where: { $0.date == nil }) {
                Section("Delayed · No confirmed date") { ForEach(visible.filter { $0.date == nil }) { ReleaseRow(event: $0) } }
            }
            if visible.isEmpty && !loading {
                Section { Text("No listed releases for this week.").foregroundStyle(.secondary) }
            }
            Section { Text("English dub dates are reported by AniSchedule and may change. Unverified dates are labeled. An empty schedule does not mean that a dub is unavailable.").font(.caption).foregroundStyle(.secondary) }
        }.navigationTitle("Schedule").animeNavigation().task(id: window.start) { await load() }
            .refreshable { await load(refresh: true) }
            .sheet(isPresented: $pickingDate) {
                NavigationStack {
                    DatePicker("Schedule date", selection: $anchor, displayedComponents: .date).datePickerStyle(.graphical).padding()
                        .navigationTitle("Choose a date").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { pickingDate = false } } }
                }.presentationDetents([.medium, .large])
            }
            .onChange(of: store.isSignedIn) { _, signedIn in if !signedIn { libraryOnly = false } }
    }
    private func shift(_ days: Int) { anchor = Calendar.current.date(byAdding: .day, value: days, to: anchor) ?? anchor }
    private func load(refresh: Bool = false) async {
        let attempt = UUID(); requestID = attempt; let selected = window
        loading = true; subError = nil; dubError = nil; subEvents = []; dubEvents = []
        async let original: Void = loadSub(selected, attempt: attempt, refresh: refresh)
        async let dubbed: Void = loadDub(selected, attempt: attempt, refresh: refresh)
        _ = await (original, dubbed)
        if requestID == attempt { loading = false }
    }
    private func loadSub(_ window: DateInterval, attempt: UUID, refresh: Bool) async {
        do {
            let events = try await store.aniList.airings(in: window, refresh: refresh)
            try Task.checkCancellation(); if requestID == attempt { subEvents = events }
        } catch is CancellationError {} catch { if requestID == attempt { subError = error.localizedDescription } }
    }
    private func loadDub(_ window: DateInterval, attempt: UUID, refresh: Bool) async {
        do {
            let snapshot = try await store.dubs.snapshot(refresh: refresh)
            let known = Dictionary(uniqueKeysWithValues: store.entries.compactMap { $0.media.map { ($0.id, $0) } })
            let initial = snapshot.events(knownMedia: known).filter { event in
                guard let date = event.date else { return true }
                return date >= window.start && date < window.end
            }
            try Task.checkCancellation()
            guard requestID == attempt else { return }
            dubEvents = initial
            let missing = initial.filter { $0.anime.title?.english == "Anime #\($0.anime.id)" }.map { $0.anime.id }
            if !missing.isEmpty {
                do {
                    let found = try await store.aniList.media(ids: missing)
                    try Task.checkCancellation()
                    let hydrated = known.merging(Dictionary(uniqueKeysWithValues: found.map { ($0.id, $0) })) { _, new in new }
                    if requestID == attempt {
                        dubEvents = snapshot.events(knownMedia: hydrated).filter { event in
                            guard event.anime.isAdult != true else { return false }
                            guard let date = event.date else { return true }
                            return date >= window.start && date < window.end
                        }
                    }
                } catch { if requestID == attempt { dubError = "Some titles could not be resolved. " + error.localizedDescription } }
            }
        } catch is CancellationError {} catch { if requestID == attempt { dubError = error.localizedDescription } }
    }
}
