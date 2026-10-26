import SwiftUI
import AnimeCore

private enum LibrarySort: String, CaseIterable {
    case airing = "Airing schedule", title = "Title", rating = "AniList rating"
    case updated = "Last updated", progress = "Progress", score = "Your score", behind = "Behind first"
    case year = "Release year", completion = "Completion"
}

struct LibraryView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var dubs: ExploreDubStore
    @AppStorage("library.layout") private var layout = "list"
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.animeSplitPresentation) private var usesSplit
    @Environment(\.scenePhase) private var scenePhase
    private var posters = PosterPreferences(.library)
    @AppStorage("library.sort") private var sortValue = LibrarySort.airing.rawValue
    @AppStorage("library.anime.defaultStatus") private var defaultStatus = LibraryScope.anime.initialStatus
    @State private var selected: LibraryStatus? = LibraryStatus(rawValue: LibraryScope.anime.openingStatus())
    @State private var query = ""
    @AppStorage("library.reversed") private var reversed = false
    @State private var showSettings = false
    @State private var showDisplay = false
    @State private var showTorBoxFiles = false
    @State private var dubEvents: [ReleaseEvent] = []
    @State private var dubProgress: [Int: LibraryDubProgress] = [:]
    @State private var now = Date()
    @FocusState private var searchFocused: Bool
    private let statuses: [LibraryStatus] = [.watching, .planning, .completed, .dropped, .paused, .rewatching]
    private var sort: LibrarySort { LibrarySort(rawValue: sortValue) ?? .airing }
    private var syncKey: String { "\(store.isSignedIn)-\(store.viewer?.id ?? 0)-\(store.entries.map(\.mediaId).sorted())" }

    private var filtered: [LibraryEntry] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let entries = selectedEntries.filter { entry in
            guard (selected == nil || entry.status == selected), let anime = entry.media else { return false }
            return text.isEmpty || [anime.displayTitle, anime.title?.romaji ?? "", anime.title?.english ?? ""].contains { $0.localizedCaseInsensitiveContains(text) }
        }
        return entries.sorted { a, b in
            switch sort {
            case .behind:
                let first = airing(for: a)?.behindCount ?? 0, second = airing(for: b)?.behindCount ?? 0
                if first != second { return reversed ? first < second : first > second }
            case .airing:
                let first = a.media?.nextAiringEpisode?.date, second = b.media?.nextAiringEpisode?.date
                if (first == nil) != (second == nil) { return first != nil }
                if let first, let second, first != second { return reversed ? first > second : first < second }
            case .rating:
                let first = a.media?.averageScore, second = b.media?.averageScore
                if (first == nil) != (second == nil) { return first != nil }
                if let first, let second, first != second { return reversed ? first < second : first > second }
            case .title: break
            case .updated:
                if a.updatedAt != b.updatedAt { return reversed ? (a.updatedAt ?? 0) < (b.updatedAt ?? 0) : (a.updatedAt ?? 0) > (b.updatedAt ?? 0) }
            case .progress:
                if a.progressValue != b.progressValue { return reversed ? a.progressValue < b.progressValue : a.progressValue > b.progressValue }
            case .score:
                if a.score != b.score { return reversed ? (a.score ?? 0) < (b.score ?? 0) : (a.score ?? 0) > (b.score ?? 0) }
            case .year:
                let first = a.media?.seasonYear, second = b.media?.seasonYear
                if (first == nil) != (second == nil) { return first != nil }
                if let first, let second, first != second { return reversed ? first < second : first > second }
            case .completion:
                let first = completion(a), second = completion(b)
                if (first == nil) != (second == nil) { return first != nil }
                if let first, let second, first != second { return reversed ? first < second : first > second }
            }
            let order = (a.media?.displayTitle ?? "").localizedStandardCompare(b.media?.displayTitle ?? "")
            if order == .orderedSame { return a.mediaId < b.mediaId }
            return reversed && sort == .title ? order == .orderedDescending : order == .orderedAscending
        }
    }

    var body: some View {
        Group {
            if store.isSignedIn {
              GeometryReader { geometry in
                let contentWidth = max(0, min(geometry.size.width, layout == "grid" ? 1280 : 1000) - 24)
                ScrollView {
                    // Keep controls stable while the results below remain lazy.
                    VStack(alignment: .leading, spacing: 18) {
                        searchBar
                        if let anime = store.lastTrackedAnime, store.isVisible(anime), store.canUndo(anime.id) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(anime.displayTitle).font(.caption.bold())
                                TrackingFeedback(anime: anime)
                            }.padding(12).background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                        }
                        statusTabs
                        layoutControls.zIndex(1)
                        sortingBar.zIndex(1)
                        if layout == "list", posters.listPosterWidth(in: contentWidth) < posters.listWidth - 1 {
                            Text("Covers fit this pane at \(Int(posters.listPosterWidth(in: contentWidth))) pt. Your saved width is \(Int(posters.listWidth)) pt.")
                                .font(.caption2).foregroundStyle(.secondary).accessibilityIdentifier("library-list-size-constrained")
                        }
                        if layout == "grid", posters.fittingColumns(in: contentWidth, accessible: textSize.isAccessibilitySize, split: usesSplit) < posters.preferredColumns {
                            Text("This window fits \(posters.fittingColumns(in: contentWidth, accessible: textSize.isAccessibilitySize, split: usesSplit)) per row. Your saved choice is \(posters.preferredColumns).")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if let error = store.libraryError { NoticeView(message: error) { Task { await store.reloadLibrary() } } }
                        if store.loadingLibrary { ProgressView("Syncing AniList…").frame(maxWidth: .infinity) }
                        if layout == "grid" {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: posters.fittingColumns(in: contentWidth, accessible: textSize.isAccessibilitySize, split: usesSplit)), alignment: .leading, spacing: 20) {
                                ForEach(filtered) { entry in
                                    if let anime = entry.media {
                                        LibraryAnimeTile(entry: entry, anime: anime, dub: dubProgress[anime.id], posterWidth: posters.gridPosterWidth)
                                    }
                                }
                            }.accessibilityIdentifier("library-grid")
                        } else {
                            LazyVStack(spacing: 12) {
                                ForEach(filtered) { entry in
                                    if let anime = entry.media {
                                        LibraryAnimeRow(entry: entry, anime: anime, nextDub: nil, dub: dubProgress[anime.id], posterWidth: posters.listPosterWidth(in: contentWidth))
                                    }
                                }
                            }.accessibilityIdentifier("library-list")
                        }
                        if filtered.isEmpty && !store.loadingLibrary && store.libraryError == nil {
                            ContentUnavailableView(query.isEmpty ? "Your \(selected?.label.lowercased() ?? "all anime") list is empty" : "No matching anime",
                                                   systemImage: "books.vertical", description: Text(query.isEmpty ? "Add a title from Explore." : "Try another title or list status."))
                        }
                        if let notice = dubs.notice { Text(notice).font(.caption).foregroundStyle(.secondary) }
                        Text("Dub counts use reported releases and complete-dub listings. Missing counts stay unknown.").font(.caption2).foregroundStyle(.secondary)
                        if let date = store.savedAt { Text("Last synced \(date.formatted(.relative(presentation: .named)))").font(.caption).foregroundStyle(.secondary) }
                    }.padding(.horizontal, 12).padding(.vertical).readableContent(width: layout == "grid" ? 1280 : 1000)
                }.accessibilityIdentifier("library-scroll").scrollDismissesKeyboard(.interactively).refreshable { await store.reloadLibrary(); await loadDubs(refresh: true) }
              }
            } else { LibraryGuestView(showSettings: $showSettings) }
        }.background(Theme.background).navigationTitle("My Library").navigationBarTitleDisplayMode(.inline).animeNavigation()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showTorBoxFiles = true } label: { Image(systemName: "folder") }
                        .accessibilityLabel("TorBox files").accessibilityIdentifier("library-torbox-files")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showDisplay = true } label: { Image(systemName: "slider.horizontal.3") }
                        .accessibilityLabel("Library display options").accessibilityIdentifier("library-display-options")
                }
                ToolbarItem(placement: .topBarTrailing) { Button { showSettings = true } label: { Image(systemName: "gearshape") }.accessibilityLabel("Account and settings") }
            }
            .appSettingsSheet(isPresented: $showSettings)
            .sheet(isPresented: $showDisplay) { DisplayOptionsView(scope: .library) }
            .sheet(isPresented: $showTorBoxFiles) { TorBoxFilesView() }
            .onChange(of: defaultStatus) { _, _ in selected = LibraryStatus(rawValue: LibraryScope.anime.openingStatus()) }
            .task(id: syncKey) { await loadDubs() }
            .task(id: dubs.revision) { applyDubs() }
            .task(id: "\(store.isSignedIn)-\(scenePhase)") {
                guard scenePhase == .active else { return }
                while !Task.isCancelled {
                    now = Date()
                    await store.refreshLibraryIfNeeded(now: now)
                    do { try await Task.sleep(for: .seconds(60)) } catch { return }
                }
            }
    }
    private var selectedEntries: [LibraryEntry] { store.visibleEntries.filter { selected == nil || $0.status == selected } }
    private func completion(_ entry: LibraryEntry) -> Double? {
        guard let total = entry.media?.episodes, total > 0 else { return nil }
        return min(1, Double(entry.progressValue) / Double(total))
    }
    private func airing(for entry: LibraryEntry) -> LibraryAiringProgress? {
        guard let anime = entry.media else { return nil }
        return LibraryAiringProgress(anime: anime, watched: entry.progressValue, source: store.airingProgressSource,
                                    dub: dubProgress[anime.id], nextDub: nextDub(for: anime.id), now: now)
    }
    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search your anime", text: $query).textInputAutocapitalization(.never).autocorrectionDisabled()
                .focused($searchFocused).submitLabel(.search).onSubmit { searchFocused = false }.accessibilityIdentifier("library-search")
            if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }.accessibilityLabel("Clear library search") }
        }.padding(12).background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
    }
    private var statusTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 9) {
                Button { selected = nil } label: {
                    Text("All").font(.subheadline.bold()).padding(.horizontal, 14).padding(.vertical, 12)
                        .foregroundStyle(selected == nil ? Color.black : Color.white)
                        .background(selected == nil ? Color.white : Theme.surface, in: RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain).accessibilityIdentifier("library-status-all")
                    .accessibilityAddTraits(selected == nil ? .isSelected : [])
                ForEach(statuses) { status in
                    Button { selected = status } label: {
                        Text(status.label).font(.subheadline.bold()).padding(.horizontal, 14).padding(.vertical, 12)
                            .foregroundStyle(selected == status ? Color.black : Color.white)
                            .background(selected == status ? Color.white : Theme.surface, in: RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain).accessibilityIdentifier("library-status-\(status.rawValue)")
                        .accessibilityAddTraits(selected == status ? .isSelected : [])
                }
            }
        }
    }
    private var layoutControls: some View {
        HStack {
            Picker("Library layout", selection: $layout) {
                Text("List").tag("list")
                Text("Grid").tag("grid")
            }.pickerStyle(.segmented).accessibilityIdentifier("library-layout")
            if layout == "grid" {
                Menu {
                    ForEach(1...8, id: \.self) { count in
                        MenuChoice(title: "\(count) per row", selected: posters.preferredColumns == count) { posters.columns = count }
                            .accessibilityIdentifier("library-column-option-\(count)")
                    }
                } label: { Text("\(posters.preferredColumns) per row").font(.subheadline).padding(10).background(Theme.surface, in: RoundedRectangle(cornerRadius: 10)) }
                    .accessibilityIdentifier("library-columns")
            }
        }
    }
    private var sortingBar: some View {
        HStack {
            Text("\(filtered.count)").font(.subheadline.bold()).padding(.horizontal, 11).padding(.vertical, 5).background(Theme.surface, in: Capsule())
                .accessibilityLabel("\(filtered.count) anime in this list")
            Spacer()
            Menu {
                ForEach(LibrarySort.allCases, id: \.self) { order in
                    MenuChoice(title: order.rawValue, selected: sort == order) { sortValue = order.rawValue }
                }
                Section("Default view") { LibraryDefaultPicker(scope: .anime) }
            } label: { Label(sort.rawValue, systemImage: "arrow.up.arrow.down").font(.subheadline).padding(10).background(Theme.surface, in: RoundedRectangle(cornerRadius: 10)) }
                .accessibilityIdentifier("library-sort")
            Button { reversed.toggle() } label: { Image(systemName: reversed ? "arrow.down" : "arrow.up").frame(width: 40, height: 40).background(Theme.surface, in: Circle()) }
                .accessibilityLabel("Reverse library sort")
                .accessibilityValue(reversed ? "Reversed" : "Default direction")
        }
    }
    private func nextDub(for id: Int) -> ReleaseEvent? {
        dubEvents.first { $0.anime.id == id && ($0.date ?? .distantPast) > now }
    }
    private func loadDubs(refresh: Bool = false) async {
        let key = syncKey
        guard !store.entries.isEmpty else { applyDubs(); return }
        await dubs.load(using: store.dubs, refresh: refresh)
        guard !Task.isCancelled, key == syncKey else { return }
        applyDubs()
    }
    private func applyDubs() {
        let known = Dictionary(uniqueKeysWithValues: store.entries.compactMap { $0.media.map { ($0.id, $0) } })
        dubEvents = dubs.snapshot?.events(knownMedia: known).filter { known[$0.anime.id] != nil } ?? []
        dubProgress = dubs.loaded ? known.mapValues { LibraryDubProgress(anime: $0, snapshot: dubs.snapshot, index: dubs.index) } : [:]
    }
}

