import SwiftUI
import UIKit
import AnimeCore

@main
struct AnimeCompanionApp: App {
    var body: some Scene {
        WindowGroup { AppSessionHost() }
    }
}

struct AppSessionView: View {
    // Declare before all stores: classify fresh vs. upgraded installations before
    // AppStore writes its initialization defaults.
    @StateObject private var firstRun = FirstRunSetupState(showOnLaunch: FirstRunSetupState.prepare())
    @StateObject private var store = AppStore()
    @StateObject private var discoveryFilters = DiscoveryFilterStore()
    @StateObject private var playback = PlaybackStore()
    @StateObject private var seanime = SeanimeStore()
    @StateObject private var navigation = AppNavigationStore()
    @StateObject private var weeklySchedule = WeeklyScheduleStore()
    @StateObject private var mangaExtensions = MangaExtensionStore()
    @StateObject private var mangaReading = MangaReadingStore()
    @StateObject private var mangaSourceLinks = MangaSourceLinkStore()
    @StateObject private var mangaBaka = MangaBakaStore()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var reset: AppResetCoordinator
    @State private var launchFinished = false
    @State private var launchRevealing = false
    @State private var launchContentReady = false
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.system.rawValue
    var body: some View {
            launchRoot.environmentObject(store).environmentObject(store.exploreDubs).environmentObject(discoveryFilters).tint(Theme.accent)
                .onAppear {
                    reset.prepareForReset = { [weak store, weak mangaBaka] in
                        store?.prepareForAppReset(); mangaBaka?.prepareForAppReset()
                    }
                }
                .environmentObject(playback).onOpenURL { url in
                    if let completed = playback.handle(url) {
                        Task { await syncCompletedEpisode(completed) }
                    }
                }
                .environmentObject(seanime)
                .environmentObject(navigation)
                .environmentObject(weeklySchedule)
                .environmentObject(mangaExtensions).environmentObject(mangaReading)
                .environmentObject(mangaSourceLinks)
                .environmentObject(mangaBaka)
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
                    Task { await ArtworkPipeline.shared.clearMemory() }
                    Task { await MangaImagePipeline.shared.clearMemory() }
                }
                .preferredColorScheme(Theme.scheme(appearance)).task { if !artworkPreview { await store.restore() } }
                .task { if !artworkPreview { await mangaBaka.restore() } }
                .task { if !artworkPreview { await mangaSourceLinks.load() } }
                .task { if !artworkPreview { await mangaReading.load() } }
                .task {
                    if !skipsLaunch { await warmLaunchContent() }
                    launchContentReady = true
                }
                .task { await revealLaunchWhenReady() }
                .task(id: scenePhase) {
                    guard scenePhase == .active, !artworkPreview else { return }
                    async let library: Void = store.refreshLibraryIfNeeded()
                    async let dubbed: Void = store.exploreDubs.keepUpdated(using: store.dubs)
                    _ = await (library, dubbed)
                }
    }
    @MainActor private func syncCompletedEpisode(_ completed: PlaybackEpisode) async {
        guard store.isSignedIn, let entry = store.entry(for: completed.animeID),
              let anime = entry.media, entry.progressValue < completed.episode else { return }
        do { try await store.markWatched(anime: anime, through: completed.episode) }
        catch { playback.playerMessage = "Watched locally, but AniList could not sync: \(error.localizedDescription)" }
    }
    private var skipsLaunch: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--ui-") })
        #else
        false
        #endif
    }
    private var launchRoot: some View {
        ZStack {
            root.opacity(launchRevealing || launchFinished ? 1 : 0)
                .allowsHitTesting(launchFinished).accessibilityHidden(!launchFinished)
            if !launchFinished { LaunchLoadingView().opacity(launchRevealing ? 0 : 1).zIndex(1) }
        }.background(Color.black.ignoresSafeArea())
            .environment(\.browseInteractionReady, launchFinished)
    }
    @MainActor private func revealLaunchWhenReady() async {
        guard !launchFinished else { return }
        if skipsLaunch { launchRevealing = true; launchFinished = true; return }
        // Start after the splash mounts. Store initialization must not consume
        // the fade's time budget before there is even a visible logo frame.
        let started = ProcessInfo.processInfo.systemUptime
        while !Task.isCancelled {
            let restored = !store.restoring && !mangaBaka.restoring && !mangaReading.loading && !mangaSourceLinks.loading
            let showsReady = !store.loadingLibrary || store.savedAt != nil
            let booksReady = !mangaBaka.loadingLibrary || !mangaBaka.library.isEmpty
            let week = ScheduleWeek(containing: ScheduleClock.now, firstWeekday: 1)
            let weekReady = !weeklySchedule.snapshot(in: week.window).loading
            if StartupPresentation.shouldReveal(elapsed: ProcessInfo.processInfo.systemUptime - started,
                localReady: restored, contentReady: launchContentReady && showsReady && booksReady && weekReady) {
                let remaining = max(0, StartupPresentation.maximumDuration - (ProcessInfo.processInfo.systemUptime - started))
                withAnimation(.easeInOut(duration: min(StartupPresentation.revealDuration(reduceMotion: reduceMotion), remaining)),
                              completionCriteria: .removed) {
                    launchRevealing = true
                } completion: {
                    launchFinished = true
                }
                return
            }
            let remaining = max(0.001, StartupPresentation.maximumDuration - (ProcessInfo.processInfo.systemUptime - started))
            do { try await Task.sleep(for: .seconds(min(0.05, remaining))) } catch { return }
        }
    }
    @MainActor private func warmLaunchContent() async {
        guard !firstRun.showOnLaunch else { return }
        async let home: Void = warmHomeContent()
        async let explore: Void = warmExploreContent()
        _ = await (home, explore)
    }
    @MainActor private func warmHomeContent() async {
        let preferences = HomePreferences(saved: UserDefaults.standard.string(forKey: HomePreferences.storageKey) ?? "")
        async let news: Void = warmLaunchNews(enabled: preferences.visible.contains(.news))
        async let community: Void = warmLaunchCommunity(enabled: preferences.visible.contains(.community))
        _ = await (news, community)
    }
    @MainActor private func warmLaunchNews(enabled: Bool) async {
        guard enabled else { return }
        _ = try? await store.news.snapshot()
    }
    @MainActor private func warmLaunchCommunity(enabled: Bool) async {
        guard enabled, CommunityDestination(preference: UserDefaults.standard.string(forKey: CommunityDestination.storageKey) ?? "") == .aniList,
              let season = try? await store.homeCatalog.season(.current(), includeAdult: store.includeAdult), !Task.isCancelled else { return }
        _ = try? await store.homeCommunity.feed(mediaIDs: season.value.filter { store.isVisible($0) }.map(\.id), includeAdult: store.includeAdult)
    }
    @MainActor private func warmExploreContent() async {
        let preferences = ExplorePreferences(surface: .anime, saved: UserDefaults.standard.string(forKey: ExploreSurface.anime.storageKey) ?? "")
        guard preferences.visible.contains(.catalog(.spotlight)) else { return }
        let selection = SeasonSelection.current(), adult = store.includeAdult
        let response: ExploreResponse
        if let saved = await store.exploreCache.load(selection, includeAdult: adult) { response = saved.response }
        else {
            guard let fresh = try? await store.aniList.explore(selection, includeAdult: adult), !Task.isCancelled else { return }
            await store.exploreCache.save(ExploreSnapshot(response: fresh, selection: selection, includeAdult: adult))
            response = fresh
        }
        var seen = Set<Int>()
        let lineup = Array(((response.trending.media ?? []) + (response.seasonal.media ?? []) + (response.upcoming.media ?? [])).filter {
            store.isVisible($0) && seen.insert($0.id).inserted && discoveryFilters.includes($0, dubs: store.exploreDubs, library: store)
        }.prefix(2))
        let artworkPreferences = SeriesArtworkPreferences(
            banner: UserDefaults.standard.bool(forKey: SeriesArtworkPreferences.bannerKey),
            poster: UserDefaults.standard.bool(forKey: SeriesArtworkPreferences.posterKey))
        let api = store.seriesArtwork
        await withTaskGroup(of: Void.self) { group in
            for item in lineup {
                group.addTask {
                    let artwork = await api.spotlightArtwork(for: item)
                    async let logo: Void = Self.warmLaunchImage(artwork.logo, pixels: 1024)
                    async let poster: Void = Self.warmLaunchImage(artworkPreferences.spotlightURL(artwork: artwork, anime: item, landscape: false), pixels: 2560)
                    async let backdrop: Void = Self.warmLaunchImage(artworkPreferences.spotlightURL(artwork: artwork, anime: item, landscape: true), pixels: 2560)
                    _ = await (logo, poster, backdrop)
                }
            }
        }
    }
    private static func warmLaunchImage(_ url: URL?, pixels: Int) async {
        guard let url, !Task.isCancelled else { return }
        _ = try? await ArtworkPipeline.shared.image(at: url, pixels: pixels)
    }
    private var artworkPreview: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--ui-phase3-artwork-preview")
        #else
        false
        #endif
    }
    @ViewBuilder private var root: some View {
        #if DEBUG
        if artworkPreview { ArtworkPerformancePreview() }
        else if firstRun.showOnLaunch { FirstRunSetupView { firstRun.finish() } }
        else { AppTabs() }
        #else
        if firstRun.showOnLaunch { FirstRunSetupView { firstRun.finish() } }
        else { AppTabs() }
        #endif
    }
}

struct AnimeRoute: Identifiable, Hashable { let id: Int }
struct AnimeVisualsRoute: Hashable { let anime: Anime? }
struct MangaSearchRoute: Hashable {
    let id = UUID()
    let titles: [String]
    let linkingTo: MangaSourceLinkTarget?
    init(titles: [String], linkingTo: MangaSourceLinkTarget? = nil) { self.titles = titles; self.linkingTo = linkingTo }
}
struct LinkedMangaRoute: Hashable {
    let id = UUID()
    let link: MangaSourceLink
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
struct DiscoveryRoute: Hashable {
    let category: DiscoveryCategory
    var selection = SeasonSelection.current()
    var titleOverride: String? = nil
    var genre: String? = nil
    var shortcutID: UUID? = nil
    var initialQuery = ""
}

struct SupplementaryDestination: Identifiable {
    enum Kind { case manga([String], linkingTo: MangaSourceLinkTarget? = nil), linkedManga(MangaSourceLink), schedule, genre(String), library, tab(AppTab), search }
    let id = UUID()
    let kind: Kind
}

enum ScheduleLanding: String, Hashable { case airing, weekly }
struct ScheduleHomeRoute: Hashable {
    let day: Date
    let id = UUID()
    var page: ScheduleLanding = .weekly
}
enum HomeDestination: Hashable {
    case schedule(ScheduleHomeRoute)
    case news(NewsCollection)
}

@MainActor
final class TabNavigationState: ObservableObject {
    @Published var path = NavigationPath()
    @Published var detailPath = NavigationPath()
    @Published var animeID: Int?
    @Published var column: NavigationSplitViewColumn = .sidebar
    @Published var visibility: NavigationSplitViewVisibility = .all

    func open(_ id: Int) { detailPath = NavigationPath(); animeID = id; column = .detail }
}

/// Selection has its own narrow publisher. Routing consumers elsewhere in the
/// app should not rebuild entire catalogs whenever the user taps the dock.
@MainActor
final class AppTabSelection: ObservableObject {
    @Published private(set) var value: AppTab = .home
    func select(_ value: AppTab) {
        guard self.value != value else { return }
        self.value = value
    }
}
struct AppTabSelectionReader<Content: View>: View {
    @ObservedObject var selection: AppTabSelection
    @ViewBuilder let content: () -> Content
    var body: some View { let _ = selection.value; content() }
}

/// Genre links always open one fresh Explore result page, even from another tab's detail stack.
@MainActor
final class AppNavigationStore: ObservableObject {
    let tabSelection = AppTabSelection()
    var selectedTab: AppTab {
        get { tabSelection.value }
        set { tabSelection.select(newValue) }
    }
    @Published private(set) var tabPreferences = AppTabPreferences(saved: UserDefaults.standard.string(forKey: AppTabPreferences.storageKey))
    @Published var supplementary: SupplementaryDestination?
    func open(_ tab: AppTab) {
        if tab == .schedule { openSchedule(); return }
        if tab == .news { openNews(); return }
        if tabPreferences.visible.contains(tab) { selectedTab = tab }
        else { supplementary = .init(kind: .tab(tab)) }
    }
    func openSearch() { supplementary = .init(kind: .search) }
    func applyTabPreferences() {
        let value = AppTabPreferences(saved: UserDefaults.standard.string(forKey: AppTabPreferences.storageKey))
        selectedTab = value.selection(for: selectedTab)
        if tabPreferences != value { tabPreferences = value }
    }
    func openSchedule(on day: Date? = nil, page: ScheduleLanding = .weekly) {
        openHomeDestination(.schedule(ScheduleHomeRoute(day: day ?? ScheduleClock.now, page: page)))
    }
    func openNews(_ collection: NewsCollection = .latest) { openHomeDestination(.news(collection)) }
    private func openHomeDestination(_ destination: HomeDestination) {
        // Explicit feature links get a normal Back path within Home. Calls
        // from another tab start fresh instead of reviving an unrelated detail.
        if selectedTab != .home || supplementary != nil { home.path = NavigationPath() }
        supplementary = nil
        home.animeID = nil; home.detailPath = NavigationPath()
        home.path.append(destination)
        selectedTab = .home
    }
    @Published private(set) var tabletLayout = TabletLayout(preference: UserDefaults.standard.string(forKey: TabletLayout.preferenceKey))
    let explore = TabNavigationState()
    let home = TabNavigationState()
    let schedule = TabNavigationState()
    let library = TabNavigationState()
    let news = TabNavigationState()
    let manga = TabNavigationState()

    func openAccountLibrary(_ account: TrackingAccount) {
        UserDefaults.standard.set(account.rawValue, forKey: TrackingAccount.storageKey)
        UserDefaults.standard.set(account.librarySection, forKey: "library.mediaSection")
        library.path = NavigationPath(); library.detailPath = NavigationPath()
        library.animeID = nil; library.column = .sidebar; library.visibility = .all
        if tabPreferences.visible.contains(.library) { selectedTab = .library }
        else if case .library? = supplementary?.kind { return }
        else { supplementary = .init(kind: .library) }
    }

    /// Apply on settings dismissal so changing topology cannot tear down its
    /// presenting sheet while the user is still editing preferences.
    func applyLayoutPreference() {
        let value = TabletLayout(preference: UserDefaults.standard.string(forKey: TabletLayout.preferenceKey))
        guard value != tabletLayout else { return }
        for state in [home, explore, schedule, library, news, manga] {
            state.path = NavigationPath(); state.detailPath = NavigationPath()
            state.animeID = nil; state.column = .sidebar; state.visibility = .all
        }
        tabletLayout = value
    }

    func state(for tab: AppTab) -> TabNavigationState {
        switch tab {
        case .home: return home
        case .explore: return explore
        case .schedule: return schedule
        case .library: return library
        case .news: return news
        case .manga: return manga
        }
    }

    func openGenre(_ genre: String) {
        guard tabPreferences.visible.contains(.explore) else {
            supplementary = .init(kind: .genre(genre)); return
        }
        UserDefaults.standard.set("anime", forKey: "app.mediaSection")
        var path = NavigationPath()
        path.append(DiscoveryRoute(category: .trending, titleOverride: genre, genre: genre, shortcutID: UUID()))
        explore.path = path
        explore.animeID = nil
        explore.detailPath = NavigationPath()
        explore.column = .sidebar
        explore.visibility = .all
        selectedTab = .explore
    }

    func openMangaSearch(for anime: Anime) {
        openMangaSearch(titles: MangaSearchTitles.suggestions(for: anime))
    }

    func openMangaSearch(titles: [String], linkingTo: MangaSourceLinkTarget? = nil) {
        guard tabPreferences.visible.contains(.manga) else {
            supplementary = .init(kind: .manga(titles, linkingTo: linkingTo)); return
        }
        var path = NavigationPath()
        path.append(MangaSearchRoute(titles: titles, linkingTo: linkingTo))
        manga.path = path
        selectedTab = .manga
    }
    func openLinkedManga(_ link: MangaSourceLink) {
        guard tabPreferences.visible.contains(.manga) else {
            supplementary = .init(kind: .linkedManga(link)); return
        }
        var path = NavigationPath()
        path.append(LinkedMangaRoute(link: link))
        manga.path = path; selectedTab = .manga
    }
}

struct AppTabs: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var navigation: AppNavigationStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var dock = CompanionDockPresentation()
    @State private var loadedLayout = false
    @AppStorage("app.mediaSection") private var mediaSection = "anime"
    @AppStorage(ExploreDesign.storageKey) private var exploreDesign = ExploreDesign.classic.rawValue
    @AppStorage("library.mediaSection") private var librarySection = "all"
    @State private var sidebarSettings = false
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .all
    @State private var sidebarColumn: NavigationSplitViewColumn = .detail
    var body: some View {
        AppTabSelectionReader(selection: navigation.tabSelection) { tabs }.task {
            guard !loadedLayout else { return }
            loadedLayout = true
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--ui-") }) {
                navigation.selectedTab = ProcessInfo.processInfo.arguments.contains("--ui-redesign-preview") ? .home : .explore
            }
            if ProcessInfo.processInfo.arguments.contains("--ui-reset-content-preferences") {
                var hidden: Set<AppTab> = ProcessInfo.processInfo.arguments.contains("--ui-customization-preview") ? [.manga] : []
                if ProcessInfo.processInfo.arguments.contains("--ui-account-hidden-library") { hidden.insert(.library) }
                if !ProcessInfo.processInfo.arguments.contains("--ui-redesign-preview") { hidden.insert(.home) }
                UserDefaults.standard.removeObject(forKey: TrackingAccount.storageKey)
                for page in SeriesDetailPage.allCases { UserDefaults.standard.removeObject(forKey: page.storageKey) }
                for surface in ExploreSurface.allCases { UserDefaults.standard.removeObject(forKey: surface.storageKey) }
                UserDefaults.standard.removeObject(forKey: AnimeEpisodeFilter.storageKey)
                var preferences = ProcessInfo.processInfo.arguments.contains("--ui-redesign-preview") ? AppTabPreferences() : AppTabPreferences(hidden: hidden)
                if ProcessInfo.processInfo.arguments.contains("--ui-account-hidden-library") { preferences.setVisible(.library, false) }
                UserDefaults.standard.set(preferences.saved, forKey: AppTabPreferences.storageKey)
                UserDefaults.standard.set(ProcessInfo.processInfo.arguments.contains("--ui-customization-preview") ? "all" : "anime", forKey: "library.mediaSection")
                UserDefaults.standard.set("anime", forKey: "app.mediaSection")
            } else if !LibraryCustomizationPreview.active && (MangaReaderPreview.active || ProcessInfo.processInfo.arguments.contains("--ui-phase2-preview")) {
                UserDefaults.standard.set(AppTabPreferences(hidden: [.home]).saved, forKey: AppTabPreferences.storageKey)
                UserDefaults.standard.set("anime", forKey: "library.mediaSection")
            }
            #endif
            navigation.applyLayoutPreference(); navigation.applyTabPreferences()
        }
    }
    private var tabs: some View {
        navigationSurface.sheet(item: $navigation.supplementary) { destination in
            AppNavigationStack {
                supplementary(destination.kind).animeNavigation().mangaBakaNavigation()
                    .environment(\.animeSplitPresentation, false)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { navigation.supplementary = nil } } }
            }.environment(\.companionDockPresentation, nil)
        }.onChange(of: navigation.selectedTab) { _, tab in
            guard navigation.tabPreferences.visible.contains(tab) else {
                navigation.selectedTab = navigation.tabPreferences.selection(for: tab); return
            }
            if tab == .schedule {
                navigation.schedule.path = NavigationPath()
                navigation.schedule.animeID = nil
                navigation.schedule.detailPath = NavigationPath()
                navigation.schedule.column = .sidebar
                navigation.schedule.visibility = .all
            }
        }
    }
    @ViewBuilder private var navigationSurface: some View {
        // Series change navigation-bar and bottom-dock visibility. Measure above
        // those containers so their transitions cannot change Spotlight's height.
        GeometryReader { viewport in
            Group {
                if UIDevice.current.userInterfaceIdiom == .pad && navigation.tabletLayout == .sidebar { sidebar }
                else { destinationTabs(showDock: true) }
            }.environment(\.animeBrowseViewportHeight, viewport.size.height + viewport.safeAreaInsets.top)
        }
    }
    @ViewBuilder private func destinationTabs(showDock: Bool) -> some View {
        if #available(iOS 26.0, *), showDock {
            CompanionNativeTabs(presentation: dock, tabs: navigation.tabPreferences.visible,
                                selection: $navigation.selectedTab, reduceMotion: reduceMotion,
                                contentKey: { UIDevice.current.userInterfaceIdiom == .pad ? paneLayout($0).rawValue : "phone" }) { tab in
                pane(tab)
            }.ignoresSafeArea()
        } else {
            nativeTabs.toolbarBackground(.ultraThinMaterial, for: .tabBar)
        }
    }
    private var nativeTabs: some View {
        TabView(selection: $navigation.selectedTab) {
            ForEach(navigation.tabPreferences.visible) { tab in
                pane(tab)
                    .environment(\.companionDockTab, tab)
                    .tabItem { Label(tab.title, systemImage: tab.symbol) }.tag(tab)
            }
        }
    }
    private var sidebar: some View {
        NavigationSplitView(columnVisibility: $sidebarVisibility, preferredCompactColumn: $sidebarColumn) {
            List(selection: Binding<AppTab?>(get: { navigation.selectedTab }, set: {
                if let value = $0 { navigation.open(value); sidebarColumn = .detail }
            })) {
                Section("Your world") {
                    ForEach(navigation.tabPreferences.visible) { tab in
                        Label(tab.title, systemImage: tab.symbol).tag(tab)
                            .accessibilityIdentifier("sidebar-tab-" + tab.rawValue)
                    }
                }
                if !navigation.tabPreferences.hidden.isEmpty {
                    DisclosureGroup("More") {
                        ForEach(navigation.tabPreferences.order.filter { navigation.tabPreferences.hidden.contains($0) }) { tab in
                            Button { navigation.open(tab) } label: { Label(tab.title, systemImage: tab.symbol) }
                        }
                    }
                }
                Section {
                    Button { navigation.openSearch() } label: { Label("Search all stories", systemImage: "magnifyingglass") }
                    Button { sidebarSettings = true } label: { Label("Settings", systemImage: "gearshape") }
                }
            }.listStyle(.sidebar).navigationTitle("AnimeCompanion").navigationBarTitleDisplayMode(.inline)
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 320)
                .appSettingsSheet(isPresented: $sidebarSettings)
                .accessibilityIdentifier("companion-sidebar")
        } detail: {
            // Keep each destination's navigation/search state alive, with the
            // sidebar owning navigation and the phone tab bar hidden.
            destinationTabs(showDock: false).toolbar(.hidden, for: .tabBar)
        }.navigationSplitViewStyle(.balanced)
    }
    private func paneLayout(_ tab: AppTab) -> TabletLayout {
        switch tab {
        case .explore: return ExploreDesign(preference: exploreDesign) == .classic && mediaSection != "written" ? navigation.tabletLayout : .fullWidth
        case .library: return librarySection == "anime" ? navigation.tabletLayout : .fullWidth
        case .schedule: return navigation.tabletLayout
        default: return .fullWidth
        }
    }
    @ViewBuilder private func pane(_ tab: AppTab) -> some View {
        switch tab {
        case .home: AnimeTabPane(state: navigation.home, layout: .fullWidth) { HomeView() }
        case .explore:
            AnimeTabPane(state: navigation.explore, layout: paneLayout(tab)) { MediaExploreView() }
        case .library:
            AnimeTabPane(state: navigation.library, layout: paneLayout(tab)) { MediaLibraryView() }
        case .manga: MangaTabPane(state: navigation.manga)
        case .schedule: AnimeTabPane(state: navigation.schedule, layout: navigation.tabletLayout) { ScheduleView() }
        case .news: AnimeTabPane(state: navigation.news, layout: .fullWidth) { NewsView().animeNavigation() }
        }
    }
    @ViewBuilder private func supplementary(_ kind: SupplementaryDestination.Kind) -> some View {
        switch kind {
        case .manga(let titles, let target): MangaTitleSearchView(titles: titles, linkingTo: target)
        case .linkedManga(let link): MangaTitleDetailView(title: link.title, linkingTo: link.library, resumeOnOpen: true)
        case .schedule: ScheduleView()
        case .library: MediaLibraryView()
        case .genre(let genre): DiscoveryBrowseView(category: .trending, selection: .current(), titleOverride: genre, initialGenre: genre)
        case .search: UnifiedExploreSearchView().animeNavigation().mangaBakaNavigation()
        case .tab(let tab):
            switch tab {
            case .home: HomeView()
            case .explore: MediaExploreView()
            case .library: MediaLibraryView()
            case .manga: MangaHubView()
            case .schedule: ScheduleView()
            case .news: NewsView()
            }
        }
    }

}

private struct MangaTabPane: View {
    @ObservedObject var state: TabNavigationState
    var body: some View {
        AppNavigationStack(path: $state.path) {
            MangaHubView().navigationDestination(for: MangaSearchRoute.self) { route in
                MangaTitleSearchView(titles: route.titles, linkingTo: route.linkingTo).id(route.id)
            }
            .navigationDestination(for: LinkedMangaRoute.self) { route in
                MangaTitleDetailView(title: route.link.title, linkingTo: route.link.library, resumeOnOpen: true).id(route.id)
            }
        }
    }
}

/// The chosen topology stays stable through rotation. Full-width navigation is
/// the default; iPad users can opt into a native, resizable split presentation.
private struct AnimeTabPane<Content: View>: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @ObservedObject var state: TabNavigationState
    let layout: TabletLayout
    let content: Content
    init(state: TabNavigationState, layout: TabletLayout, @ViewBuilder content: () -> Content) {
        self.state = state; self.layout = layout; self.content = content()
    }
    private var usesSplit: Bool { UIDevice.current.userInterfaceIdiom == .pad && layout == .sideBySide }
    @ViewBuilder
    var body: some View {
        if usesSplit {
            GeometryReader { geometry in
                split(browseWidth: TabletLayout.browseWidth(windowWidth: geometry.size.width))
            }.environment(\.animeSplitPresentation, true)
        } else {
            AppNavigationStack(path: $state.path) { content }
                .environment(\.animeSplitPresentation, false)
        }
    }
    private func backToBrowsing() {
        state.detailPath = NavigationPath(); state.animeID = nil; state.column = .sidebar; state.visibility = .all
    }
    private func split(browseWidth: Double) -> some View {
        NavigationSplitView(columnVisibility: $state.visibility, preferredCompactColumn: $state.column) {
            AppNavigationStack(path: $state.path) { content }
                .navigationSplitViewColumnWidth(min: 480, ideal: browseWidth, max: 820)
        } detail: {
            AppNavigationStack(path: $state.detailPath, rootBack: state.animeID == nil ? nil : backToBrowsing) {
                Group {
                    if let id = state.animeID {
                        AnimeDetailView(mediaID: id).id(id)
                            .navigationBarBackButtonHidden(sizeClass == .regular)
                            .toolbar {
                                if sizeClass == .regular {
                                    ToolbarItem(placement: .topBarLeading) {
                                        Button {
                                            backToBrowsing()
                                        } label: { Label("Browse", systemImage: "chevron.left") }
                                            .accessibilityLabel("Back to browsing").accessibilityIdentifier("back-to-browsing")
                                    }
                                }
                            }
                    }
                    else {
                        ContentUnavailableView("Choose an anime", systemImage: "play.rectangle",
                            description: Text("Browse a title to see its episodes, English dub information and tracking here."))
                            .accessibilityIdentifier("anime-detail-placeholder")
                    }
                }.animeNavigation()
            }.environment(\.animeDetailContext, true)
        }.navigationSplitViewStyle(.balanced)
    }
}

private struct AnimeDetailContextKey: EnvironmentKey { static let defaultValue = false }
private struct AnimeSplitPresentationKey: EnvironmentKey { static let defaultValue = false }
private struct AnimeBrowseViewportHeightKey: EnvironmentKey { static let defaultValue: CGFloat? = nil }
extension EnvironmentValues {
    var animeBrowseViewportHeight: CGFloat? {
        get { self[AnimeBrowseViewportHeightKey.self] }
        set { self[AnimeBrowseViewportHeightKey.self] = newValue }
    }
    var animeSplitPresentation: Bool {
        get { self[AnimeSplitPresentationKey.self] }
        set { self[AnimeSplitPresentationKey.self] = newValue }
    }
    var animeDetailContext: Bool {
        get { self[AnimeDetailContextKey.self] }
        set { self[AnimeDetailContextKey.self] = newValue }
    }
}

/// Browse links select the split detail; related titles retain native detail
/// stack history. Both paths use the same destination on phone and tablet.
struct AnimeLink<Content: View>: View {
    @EnvironmentObject private var navigation: AppNavigationStore
    @Environment(\.animeDetailContext) private var inDetail
    @Environment(\.animeSplitPresentation) private var usesSplit
    let id: Int
    let content: Content
    init(id: Int, @ViewBuilder label: () -> Content) { self.id = id; content = label() }
    var body: some View {
        if inDetail || !usesSplit { NavigationLink(value: AnimeRoute(id: id)) { content } }
        else { Button { navigation.state(for: navigation.selectedTab).open(id) } label: { content } }
    }
}

struct AnimeNavigation: ViewModifier {
    func body(content: Content) -> some View {
        content.navigationDestination(for: AnimeRoute.self) {
            AnimeDetailView(mediaID: $0.id).id($0.id).environment(\.animeDetailContext, true).toolbar(.visible, for: .navigationBar)
        }
            .navigationDestination(for: RelatedMangaBakaRoute.self) { route in
                RelatedMangaBakaView(media: route.media).id(route.media.id)
                    .environment(\.animeDetailContext, true).toolbar(.visible, for: .navigationBar)
            }
            .navigationDestination(for: AnimeVisualsRoute.self) { route in
                AnimeVisualsView(anime: route.anime).id(route.anime?.id ?? 0)
            }
            .navigationDestination(for: DiscoveryRoute.self) { route in
                DiscoveryBrowseView(category: route.category, selection: route.selection, titleOverride: route.titleOverride, initialGenre: route.genre, initialQuery: route.initialQuery)
                    // Replacing a path with the same destination type otherwise reuses its
                    // @State filters. Each genre tap must initialize a fresh result page;
                    // normal detail/back navigation keeps the same route and loaded pages.
                    .id(route)
                    .toolbar(.visible, for: .navigationBar)
            }
    }
}
extension View { func animeNavigation() -> some View { modifier(AnimeNavigation()) } }
