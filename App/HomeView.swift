import SwiftUI
import AnimeCore

struct HomeView: View {
    @EnvironmentObject private var anime: AppStore
    @EnvironmentObject private var books: MangaBakaStore
    @EnvironmentObject private var reading: MangaReadingStore
    @EnvironmentObject private var navigation: AppNavigationStore
    @EnvironmentObject private var sourceLinks: MangaSourceLinkStore
    @EnvironmentObject private var extensions: MangaExtensionStore
    @EnvironmentObject private var weeklySchedule: WeeklyScheduleStore
    @EnvironmentObject private var dubs: ExploreDubStore
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var textSize
    @AppStorage(HomePreferences.storageKey) private var sections = ""
    @AppStorage("manga.showMatureSources") private var matureSources = false
    @State private var customize = false
    @State private var pickingWidgets = false
    @State private var editing = false
    @State private var dragging: HomeSection?
    @State private var settings = false
    @State private var watching: Anime?
    @State private var newsRefreshID = 0
    @Environment(\.scenePhase) private var scenePhase
    @State private var appeared = false
    @State private var homeVisitID = 0
    private var preferences: HomePreferences { HomePreferences(saved: sections) }
    private var cardColumns: [GridItem] {
        [GridItem(sizeClass == .regular && !textSize.isAccessibilitySize ? .adaptive(minimum: 270) : .flexible(), spacing: 12, alignment: .top)]
    }
    private var shows: [LibraryEntry] {
        Array(anime.watching.filter { $0.media != nil }.sorted { ($0.updatedAt ?? 0) > ($1.updatedAt ?? 0) }.prefix(preferences.size(for: .watching).itemLimit))
    }
    private var recent: [MangaReadingRecord] {
        guard !extensions.loading else { return [] }
        return Array(reading.state.records.filter { record in
            let mature = record.title.source.adult || extensions.installed(record.title.source.extensionID)?.descriptor.adult == true
            return record.lastReadAt != nil && (matureSources || !mature)
        }
            .sorted { ($0.lastReadAt ?? .distantPast) > ($1.lastReadAt ?? .distantPast) }.prefix(preferences.size(for: .reading).itemLimit))
    }
    private var trackedBooks: [MangaBakaLibraryEntry] {
        let resumed = Set(recent.map { $0.title.id })
        return Array(books.library.map { books.entries[$0.id] ?? $0 }.filter { entry in
            guard ["reading", "rereading"].contains(entry.state), let series = entry.series,
                  series.isVisible(contentFilter: anime.mangaBakaContent) else { return false }
            if let target = books.sourceLinkTarget(for: series), let link = sourceLinks.link(for: target), resumed.contains(link.title.id) { return false }
            return true
        }.prefix(max(0, preferences.size(for: .reading).itemLimit - recent.count)))
    }
    private var upcoming: [Anime] {
        Array(anime.watching.compactMap(\.media).filter { ($0.nextAiringEpisode?.date ?? .distantPast) > .now }
            .sorted { ($0.nextAiringEpisode?.date ?? .distantFuture) < ($1.nextAiringEpisode?.date ?? .distantFuture) }.prefix(preferences.size(for: .airing).itemLimit))
    }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                if editing { editorBar }
                ForEach(preferences.visible) { section in
                    if shouldDisplay(section) {
                        HomeWidgetFrame(section: section, saved: $sections, editing: $editing, dragging: $dragging) {
                            widget(section)
                        }.id(section)
                    }
                }
                if preferences.visible.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "rectangle.stack.badge.plus").font(.largeTitle).foregroundStyle(Theme.accent)
                        Text("A fresh start.").font(.headline)
                        Text("Add only what you want on Home.").font(.subheadline).foregroundStyle(.secondary)
                        Button("Add widgets", systemImage: "plus") { editing = true; pickingWidgets = true }
                            .buttonStyle(.borderedProminent).accessibilityIdentifier("home-empty-add")
                    }.frame(maxWidth: .infinity).padding(.vertical, 44).accessibilityIdentifier("home-empty-layout")
                }
            }.padding(20).padding(.bottom, 20).frame(maxWidth: 1180, alignment: .leading).frame(maxWidth: .infinity)
        }.background(Theme.background).navigationTitle("Home").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { AccountSwitcherButton() }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if editing {
                        Button { pickingWidgets = true } label: { Image(systemName: "plus") }
                            .accessibilityLabel("Add widgets").accessibilityIdentifier("home-add-widgets")
                    }
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) { editing.toggle(); dragging = nil }
                    } label: {
                        if editing { Text("Done").fontWeight(.semibold) }
                        else { Image(systemName: "slider.horizontal.3") }
                    }.accessibilityLabel(editing ? "Finish editing Home" : "Customize Home").accessibilityIdentifier("home-customize")
                    Menu {
                        Button("Add widgets", systemImage: "plus") { editing = true; pickingWidgets = true }
                        Button("Manage widgets", systemImage: "slider.horizontal.3") { customize = true }
                        Divider()
                        Button("Search", systemImage: "magnifyingglass") { navigation.openSearch() }
                        Button("Calendar", systemImage: "calendar") { navigation.openSchedule() }
                        Button("Airing Now", systemImage: "play.rectangle") { navigation.openSchedule(page: .airing) }
                        Button("News", systemImage: "newspaper") { navigation.openNews() }
                        NavigationLink { CommunityFeedView() } label: { Label("Community", systemImage: "bubble.left.and.bubble.right") }
                        Button("My Library", systemImage: "books.vertical") { navigation.open(.library) }
                        NavigationLink { SourcesSettingsView() } label: { Label("Sources & playback", systemImage: "puzzlepiece.extension") }
                        Button("Settings", systemImage: "gearshape") { settings = true }
                    } label: { Image(systemName: "ellipsis.circle") }
                        .accessibilityLabel("Home actions").accessibilityIdentifier("home-actions")
                }
            }
            .onDrop(of: [HomeWidgetDrag.type], delegate: HomeWidgetDropDelegate(target: nil, saved: $sections, dragging: $dragging, enabled: editing))
            .animeNavigation().mangaBakaNavigation()
            .navigationDestination(for: ExploreSearchRoute.self) { _ in UnifiedExploreSearchView().animeNavigation().mangaBakaNavigation() }
            .navigationDestination(for: HomeDestination.self) { destination in
                switch destination {
                case .schedule(let route): ScheduleView(landing: route).environment(\.animeSplitPresentation, false)
                case .news(let collection): NewsView(initialCollection: collection).environment(\.animeSplitPresentation, false)
                }
            }
            .onAppear {
                if appeared { homeVisitID += 1 }
                appeared = true
                Task { await anime.refreshLibraryIfNeeded() }
            }
            .onChange(of: scenePhase) { previous, current in
                if current == .active && previous != .active { homeVisitID += 1 }
            }
            .task {
                await reading.load(); await sourceLinks.load()
                if !reading.state.records.isEmpty { await extensions.load() }
            }
            .task(id: "\(books.connected)-\(books.connectionID)-\(books.revision)") { if books.connected { await books.loadLibrary(state: nil) } }
            .refreshable {
                newsRefreshID += 1
                async let shows: Void = refreshAnime()
                async let titles: Void = refreshBooks()
                async let week: Void = refreshWeek()
                _ = await (shows, titles, week)
            }
            .appSettingsSheet(isPresented: $settings)
            .sheet(isPresented: $customize) {
                AppNavigationStack {
                    HomeCustomizationView().toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { customize = false } } }
                }
            }
            .sheet(isPresented: $pickingWidgets) { AppNavigationStack { HomeWidgetPicker() } }
            .sheet(item: $watching) { WatchAnimeView(anime: $0) }
            .accessibilityIdentifier("home-dashboard")
    }
    private func refreshAnime() async { if anime.isSignedIn { await anime.reloadLibrary() } }
    private func refreshWeek() async {
        guard anime.isSignedIn, (preferences.visible.contains(.weekly) || preferences.visible.contains(.today)) else { return }
        async let original: Void = weeklySchedule.load(in: ScheduleWeek(containing: ScheduleClock.now, firstWeekday: 1).window, using: anime.aniList, refresh: true)
        async let dubbed: Void = dubs.load(using: anime.dubs, refresh: true)
        _ = await (original, dubbed)
    }
    private func refreshBooks() async { if books.connected { await books.loadLibrary(state: nil, refresh: true) } }
    private func shouldDisplay(_ section: HomeSection) -> Bool {
        if editing { return true }
        if section == .welcome { return !anime.isSignedIn && !books.connected && recent.isEmpty }
        if section == .syncStatus { return anime.loadingLibrary || books.loadingLibrary || anime.libraryError != nil || books.libraryError != nil || reading.error != nil }
        return true
    }
    @ViewBuilder private func widget(_ section: HomeSection) -> some View {
        switch section {
        case .greeting: header
        case .search: CompanionSearchLink().accessibilityIdentifier("home-search")
        case .featureLinks: HomeFeatureShortcuts()
        case .welcome:
            if !anime.isSignedIn && !books.connected && recent.isEmpty { welcome }
            else { empty("Welcome & setup", detail: "This widget appears when no library is connected.", symbol: "sparkles") }
        case .syncStatus: syncStatus
        case .weekly: AiringThisWeekView()
        case .news: HomeNewsSection(refreshID: newsRefreshID)
        case .community: HomeCommunityWidget(refreshID: newsRefreshID, activationID: homeVisitID)
        case .watching: watchSection
        case .reading: readingSection
        case .airing: airingSection
        case .shortcuts: shortcuts
        case .today: HomeTodayWidget(limit: preferences.size(for: .today).itemLimit, refreshID: newsRefreshID)
        case .catchUp, .libraryStats, .planned, .randomPick:
            HomeLibraryWidget(section: section, limit: preferences.size(for: section).itemLimit)
        case .savedNews: HomeSavedStoriesWidget(limit: preferences.size(for: .savedNews).itemLimit)
        case .seasonCountdown, .nextSeason, .returningSeries, .tonightPick, .hallOfFame:
            HomeSeasonWidget(section: section, limit: preferences.size(for: section).itemLimit, refreshID: newsRefreshID, activationID: homeVisitID)
        case .seasonSpotlight, .nextEpisode, .watchlistBanners:
            HomeBannerWidget(section: section, limit: preferences.size(for: section).itemLimit, refreshID: newsRefreshID, activationID: homeVisitID)
        }
    }
    private var editorBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Make Home yours").font(.headline)
            Text("Drag a handle to rearrange. Use − to hide a widget, or its menu to move it and change preview items.")
                .font(.caption).foregroundStyle(.secondary)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { editorActions }
                VStack(alignment: .leading, spacing: 4) { editorActions }
            }
        }.frame(maxWidth: .infinity, alignment: .leading).companionPanel(padding: 14).accessibilityIdentifier("home-editor")
    }
    @ViewBuilder private var editorActions: some View {
        Button("Add widgets", systemImage: "plus") { pickingWidgets = true }
        Button("Manage widgets", systemImage: "slider.horizontal.3") { customize = true }.accessibilityIdentifier("home-manage-widgets")
    }
    private var syncStatus: some View {
        VStack(alignment: .leading, spacing: 10) {
            if anime.loadingLibrary { ProgressView("Syncing AniList…").font(.caption) }
            if let error = anime.libraryError, anime.isSignedIn {
                NoticeView(message: error) { Task { await anime.reloadLibrary() } }
            }
            if let error = reading.error { NoticeView(message: error) }
            if books.loadingLibrary {
                ProgressView("Syncing reading library…").font(.caption).accessibilityIdentifier("home-reading-sync")
            }
            if let error = books.libraryError, books.connected {
                NoticeView(message: error) { Task { await refreshBooks() } }
            }
            if editing && !anime.loadingLibrary && !books.loadingLibrary && anime.libraryError == nil && books.libraryError == nil && reading.error == nil {
                empty("Library sync status", detail: "Loading and retry messages appear here when needed.", symbol: "arrow.triangle.2.circlepath")
            }
        }
    }
    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(Date.now, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                .font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
            Text("Your daily companion.").font(.title2.weight(.bold)).tracking(-0.4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    private var welcome: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Make yourself at home", systemImage: "sparkles").font(.headline)
            Text("Connect a library to bring your watchlist and reading progress here. You can explore without an account.")
                .font(.subheadline).foregroundStyle(.secondary)
            HStack {
                Button("Connect a library") { settings = true }.buttonStyle(.borderedProminent).foregroundStyle(Theme.background)
                Button("Explore") { navigation.open(.explore) }.buttonStyle(.bordered)
            }
        }.companionPanel().accessibilityIdentifier("home-welcome")
    }
    private var watchSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeading(.watching, destination: .library)
            if anime.loadingLibrary && shows.isEmpty { ProgressView("Loading your library…").frame(minHeight: 70) }
            else if shows.isEmpty {
                empty("Your watching list starts here.", detail: "Add an anime from Explore, or connect AniList.", symbol: "play.rectangle")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(shows) { entry in
                            if let value = entry.media {
                                HomeContinueWatchingCard(anime: value, entry: entry) { watching = value }
                                    .containerRelativeFrame(.horizontal, alignment: .leading) { width, _ in min(400, width * 0.90) }
                            }
                        }
                    }.padding(.vertical, 1)
                }
            }
        }
    }
    private var readingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeading(.reading, destination: .library)
            if recent.isEmpty && trackedBooks.isEmpty {
                empty("Your next chapter is waiting.", detail: "Read from a source to see your saved place here.", symbol: "book")
            } else {
                LazyVGrid(columns: cardColumns, alignment: .leading, spacing: 12) {
                    ForEach(recent) { record in
                        NavigationLink { MangaTitleDetailView(title: record.title, resumeOnOpen: true) } label: {
                            HomeContinueReadingCard(record: record)
                        }.buttonStyle(.plain).accessibilityIdentifier("home-read-" + record.id)
                    }
                    ForEach(trackedBooks) { entry in
                        if let series = entry.series {
                            NavigationLink(value: MangaBakaSeriesRoute(series: series)) {
                                HomeTrackedReadingCard(entry: entry, series: series)
                            }.buttonStyle(.plain).accessibilityIdentifier("home-reading-library-\(entry.id)")
                        }
                    }
                }
            }
        }
    }
    private var airingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeading(.airing, destination: .schedule)
            if upcoming.isEmpty {
                empty("See what’s airing.", detail: "Upcoming original broadcasts from your watching list will appear here.", symbol: "calendar")
            } else {
                LazyVGrid(columns: cardColumns, alignment: .leading, spacing: 12) {
                    ForEach(upcoming) { value in
                        if let next = value.nextAiringEpisode {
                            AnimeLink(id: value.id) {
                                HomeUpNextCard(anime: value, episode: next)
                            }.buttonStyle(.plain).accessibilityIdentifier("home-up-next-\(value.id)")
                        }
                    }
                }
            }
        }
    }
    private var shortcuts: some View {
        VStack(alignment: .leading, spacing: 12) {
            CompanionSectionHeading(title: HomeSection.shortcuts.title)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 12)], spacing: 12) {
                quickLink("Reading sources", detail: "Extensions & history", symbol: "book.closed", tab: .manga)
                NavigationLink { CommunityFeedView() } label: { shortcutLabel("Community", detail: "Conversations & episodes", symbol: "bubble.left.and.bubble.right") }
                NavigationLink { SourcesSettingsView() } label: { shortcutLabel("Sources & playback", detail: "Manage your connections", symbol: "puzzlepiece.extension") }.accessibilityIdentifier("home-sources")
                NavigationLink { MangaBakaRecommendationsView().mangaBakaNavigation() } label: { shortcutLabel("For your next read", detail: "MangaBaka recommendations", symbol: "sparkles") }
                Button { settings = true } label: { shortcutLabel("Settings", detail: "Accounts & preferences", symbol: "gearshape") }
            }.buttonStyle(.plain)
        }
    }
    private func sectionHeading(_ section: HomeSection, destination: AppTab) -> some View {
        HStack {
            CompanionSectionHeading(title: section.title)
            Button("See all") { navigation.open(destination) }.font(.caption.weight(.semibold)).frame(minHeight: 44)
                .accessibilityLabel("\(section.title), see all")
        }
    }
    private func empty(_ title: String, detail: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.title3).foregroundStyle(Theme.accent).frame(width: 26)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).companionPanel()
    }
    private func quickLink(_ title: String, detail: String, symbol: String, tab: AppTab) -> some View {
        Button { navigation.open(tab) } label: { shortcutLabel(title, detail: detail, symbol: symbol) }
            .accessibilityIdentifier("home-open-" + tab.rawValue)
    }
    private func shortcutLabel(_ title: String, detail: String, symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.title3).foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.primary)
                Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            }
        }.frame(maxWidth: .infinity, minHeight: 48, alignment: .leading).companionPanel(padding: 12).contentShape(Rectangle())
    }
}
