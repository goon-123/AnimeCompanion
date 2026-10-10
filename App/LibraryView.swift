import SwiftUI
import AnimeCore

private enum LibrarySort: String, CaseIterable {
    case airing = "Airing schedule", title = "Title", rating = "AniList rating"
    case updated = "Last updated", progress = "Progress", score = "Your score", behind = "Behind first"
}

struct LibraryView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var dubs: ExploreDubStore
    @AppStorage("library.layout") private var layout = "list"
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.scenePhase) private var scenePhase
    private var posters = PosterPreferences(.library)
    @AppStorage("library.sort") private var sortValue = LibrarySort.airing.rawValue
    @State private var selected: LibraryStatus = .watching
    @State private var query = ""
    @State private var reversed = false
    @State private var showSettings = false
    @State private var showDisplay = false
    @State private var comingExpanded = false
    @State private var dubEvents: [ReleaseEvent] = []
    @State private var dubProgress: [Int: LibraryDubProgress] = [:]
    @State private var now = Date()
    @FocusState private var searchFocused: Bool
    private let statuses: [LibraryStatus] = [.watching, .planning, .completed, .dropped, .paused, .rewatching]
    private var sort: LibrarySort { LibrarySort(rawValue: sortValue) ?? .airing }
    private var syncKey: String { "\(store.isSignedIn)-\(store.viewer?.id ?? 0)-\(store.entries.map(\.mediaId).sorted())" }

    private var comingUp: [ReleaseEvent] {
        let originals = store.watching.compactMap { entry -> ReleaseEvent? in
            guard let anime = entry.media, let next = anime.nextAiringEpisode else { return nil }
            return ReleaseEvent(anime: anime, episode: next.episode, kind: .sub, date: next.date, certainty: .broadcast)
        }
        let ids = Set(store.watching.map(\.mediaId))
        let end = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date().addingTimeInterval(604800)
        return (originals + dubEvents.filter { ids.contains($0.anime.id) }).filter {
            guard let date = $0.date else { return false }; return date >= Date() && date < end
        }.sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
    }
    private var filtered: [LibraryEntry] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let entries = selectedEntries.filter { entry in
            guard entry.status == selected, let anime = entry.media else { return false }
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
                        comingUpSection(width: contentWidth)
                        statusTabs
                        layoutControls.zIndex(1)
                        sortingBar.zIndex(1)
                        if layout == "grid", posters.fittingColumns(in: contentWidth, accessible: textSize.isAccessibilitySize) < posters.preferredColumns {
                            Text("This window fits \(posters.fittingColumns(in: contentWidth, accessible: textSize.isAccessibilitySize)) per row. Your saved choice is \(posters.preferredColumns).")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if let error = store.libraryError { NoticeView(message: error) { Task { await store.reloadLibrary() } } }
                        if store.loadingLibrary { ProgressView("Syncing AniList…").frame(maxWidth: .infinity) }
                        if layout == "grid" {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: posters.fittingColumns(in: contentWidth, accessible: textSize.isAccessibilitySize)), alignment: .leading, spacing: 20) {
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
                            ContentUnavailableView(query.isEmpty ? "Your \(selected.label.lowercased()) list is empty" : "No matching anime",
                                                   systemImage: "books.vertical", description: Text(query.isEmpty ? "Add a title from Explore." : "Try another title or list status."))
                        }
                        if let notice = dubs.notice { Text(notice).font(.caption).foregroundStyle(.secondary) }
                        Text("Dub counts use reported releases and complete-dub listings. Missing counts stay unknown.").font(.caption2).foregroundStyle(.secondary)
                        if let date = store.savedAt { Text("Last synced \(date.formatted(.relative(presentation: .named)))").font(.caption).foregroundStyle(.secondary) }
                    }.padding(.horizontal, 12).padding(.vertical).readableContent(width: layout == "grid" ? 1280 : 1000)
                }.scrollDismissesKeyboard(.interactively).refreshable { await store.reloadLibrary(); await loadDubs(refresh: true) }
              }
            } else { LibraryGuestView(showSettings: $showSettings) }
        }.background(Theme.background).navigationTitle("My Library").navigationBarTitleDisplayMode(.inline).animeNavigation()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showDisplay = true } label: { Image(systemName: "slider.horizontal.3") }
                        .accessibilityLabel("Library display options").accessibilityIdentifier("library-display-options")
                }
                ToolbarItem(placement: .topBarTrailing) { Button { showSettings = true } label: { Image(systemName: "gearshape") }.accessibilityLabel("Account and settings") }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showDisplay) { DisplayOptionsView(scope: .library) }
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
    private var selectedEntries: [LibraryEntry] { store.visibleEntries.filter { $0.status == selected } }
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
            } label: { Label(sort.rawValue, systemImage: "arrow.up.arrow.down").font(.subheadline).padding(10).background(Theme.surface, in: RoundedRectangle(cornerRadius: 10)) }
                .accessibilityIdentifier("library-sort")
            Button { reversed.toggle() } label: { Image(systemName: reversed ? "arrow.down" : "arrow.up").frame(width: 40, height: 40).background(Theme.surface, in: Circle()) }
                .accessibilityLabel("Reverse library sort")
        }
    }
    private func comingUpSection(width: CGFloat) -> some View {
        Group {
            if !store.watching.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Button { withAnimation { comingExpanded.toggle() } } label: {
                        HStack {
                            Text("Coming up for you").font(.subheadline.weight(.semibold))
                            Spacer()
                            Image(systemName: comingExpanded ? "chevron.down" : "chevron.right").font(.subheadline.bold())
                        }.frame(minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("library-coming-up")
                        .accessibilityValue(comingExpanded ? "Expanded" : "Collapsed")
                    if comingExpanded {
                        ForEach(Array(comingUp.prefix(8))) {
                            ReleaseRow(event: $0, posterWidth: CGFloat(PosterLayout.listWidth(preferred: min(200, max(60, posters.comingWidth)), availableWidth: Double(width))))
                        }
                        if comingUp.isEmpty { Text("No listed releases for your watching list in the next seven days.").font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
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

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var clientID = AppConfiguration.clientID ?? ""
    @State private var confirmation = false
    var body: some View {
        NavigationStack {
            Form {
                Section("AniList connection") {
                    if store.isSignedIn {
                        Text(store.viewer.map { "Signed in as \($0.name)" } ?? "Connected to AniList")
                        Button("Refresh library") { Task { await store.reloadLibrary() } }.disabled(store.loadingLibrary || !store.savingMedia.isEmpty)
                        Button("Disconnect", role: .destructive) { confirmation = true }.disabled(!store.savingMedia.isEmpty)
                    } else {
                        TextField("AniList app ID", text: $clientID).keyboardType(.numberPad)
                        Button("Connect AniList") {
                            UserDefaults.standard.set(clientID.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "anilist.clientID")
                            Task { await store.connect() }
                        }.disabled(Int(clientID) == nil || store.connecting)
                        if store.connecting { ProgressView("Opening AniList…") }
                        Link("Register this app on AniList", destination: URL(string: "https://anilist.co/settings/developer")!)
                        Text("Use this redirect URL when creating the app:").font(.caption)
                        Text(AppConfiguration.callback.absoluteString).font(.caption.monospaced()).textSelection(.enabled)
                        Text("Enter the client ID only. Your AniList password stays on AniList.").font(.caption).foregroundStyle(.secondary)
                    }
                    if let error = store.accountError { Text(error).foregroundStyle(.red) }
                }
                Section("Watching") {
                    NavigationLink { PlaybackSettingsView() } label: { Label("Add-ons & playback", systemImage: "play.rectangle") }
                        .accessibilityIdentifier("playback-settings")
                }
                Section("Browsing and content") {
                    Picker("Default metadata source", selection: $store.metadataSource) {
                        ForEach(MetadataSource.allCases) { Text($0.label).tag($0) }
                    }.accessibilityIdentifier("settings-metadata-source")
                    Text("Switch between AniList details and LiveChart’s in-app web listings. Your progress always saves to AniList.")
                        .font(.caption).foregroundStyle(.secondary)
                    Toggle("Show adult anime (18+)", isOn: $store.includeAdult).accessibilityIdentifier("settings-adult-content")
                    Text("Applies to this app’s catalog, search, details, library, and schedules. Hidden entries stay in AniList. LiveChart web pages use LiveChart’s own website preferences.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Tracking") {
                    Picker("Airing catch-up comparison", selection: $store.airingProgressSource) {
                        ForEach(AiringProgressSource.allCases) { Text($0.label).tag($0) }
                    }.accessibilityIdentifier("settings-airing-progress-source")
                    Text("Green means caught up; yellow means behind the released episodes. Only ongoing airings show this status. English dub uses reported dub releases, not the original broadcast count.")
                        .font(.caption).foregroundStyle(.secondary)
                    Toggle("Complete at the final episode", isOn: $store.automaticallyComplete).accessibilityIdentifier("settings-auto-complete")
                    Text("Marking the final known episode watched moves the title to Completed. Finishing a rewatch also increases the rewatch count. You can undo the last saved change.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Data sources") {
                    Link("Anime metadata and lists · AniList", destination: URL(string: "https://anilist.co")!)
                    Link("Alternate metadata · LiveChart.me", destination: URL(string: "https://www.livechart.me")!)
                    Link("ID matching · AnimeAPI / Anime Offline Database", destination: URL(string: "https://github.com/nattadasu/animeApi")!)
                    Link("Mapping database license · ODbL 1.0", destination: URL(string: "https://opendatacommons.org/licenses/odbl/1-0/")!)
                    Link("Dub dates · AniSchedule by RockinChaos", destination: DubProvider.current.repositoryURL)
                    Link("Dub source fallback · AniSchedule by Bas1874", destination: DubProvider.legacy.repositoryURL)
                    Link("Dub data © MyDubList · CC BY 4.0", destination: URL(string: "https://mydublist.com")!)
                    Link("MyDubList dataset license", destination: URL(string: "https://creativecommons.org/licenses/by/4.0/")!)
                    Text("Data is matched by IDs and formatted for display; no source records are edited.").font(.caption).foregroundStyle(.secondary)
                    Link("Report inaccurate dub data", destination: URL(string: "https://github.com/Joelis57/MyDubList/issues/new/choose")!)
                    Link("News · Anime News Network", destination: URL(string: "https://www.animenewsnetwork.com")!)
                    Link("News · Crunchyroll", destination: URL(string: "https://www.crunchyroll.com/news")!)
                    Link("News · Anime Corner", destination: URL(string: "https://animecorner.me")!)
                }
                Section("About") {
                    Text("Anime Companion · LiveChart & AniList tracking")
                    Text("Broadcast times and dub dates may change. Times use your device timezone. Original Japanese broadcasts do not guarantee local subtitle availability.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.navigationTitle("Settings").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .confirmationDialog("Disconnect from AniList?", isPresented: $confirmation) {
                    Button("Disconnect", role: .destructive) { store.disconnect() }
                } message: { Text("Your AniList lists stay on AniList. This removes the saved connection from this device.") }
        }
    }
}

