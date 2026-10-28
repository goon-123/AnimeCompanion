import SwiftUI
import UIKit
import AnimeCore

@main
struct AnimeCompanionApp: App {
    @StateObject private var store = AppStore()
    @StateObject private var discoveryFilters = DiscoveryFilterStore()
    @StateObject private var playback = PlaybackStore()
    @StateObject private var seanime = SeanimeStore()
    @StateObject private var navigation = AppNavigationStore()
    @StateObject private var mangaExtensions = MangaExtensionStore()
    @StateObject private var mangaReading = MangaReadingStore()
    @StateObject private var mangaBaka = MangaBakaStore()
    @StateObject private var firstRun: FirstRunSetupState
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Read legacy install state before other stores initialize defaults.
        let shouldPresent = FirstRunSetupState.prepare()
        _firstRun = StateObject(wrappedValue: FirstRunSetupState(showOnLaunch: shouldPresent))
    }
    var body: some Scene {
        WindowGroup {
            root.environmentObject(store).environmentObject(store.exploreDubs).environmentObject(discoveryFilters).tint(Theme.accent)
                .environmentObject(playback).onOpenURL { playback.handle($0) }
                .environmentObject(seanime)
                .environmentObject(navigation)
                .environmentObject(mangaExtensions).environmentObject(mangaReading)
                .environmentObject(mangaBaka)
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
                    Task { await ArtworkPipeline.shared.clearMemory() }
                    Task { await MangaImagePipeline.shared.clearMemory() }
                }
                .preferredColorScheme(.dark).fontDesign(.rounded).task { if !artworkPreview { await store.restore() } }
                .task { if !artworkPreview { await mangaBaka.restore() } }
                .task(id: scenePhase) {
                    guard scenePhase == .active, !artworkPreview else { return }
                    await store.exploreDubs.keepUpdated(using: store.dubs)
                }
        }
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

enum Theme {
    static let accent = Color.white
    static let background = Color(red: 0.045, green: 0.05, blue: 0.065)
    static let surface = Color(red: 0.09, green: 0.105, blue: 0.135)
    static let highlight = Color.yellow
}

struct AnimeRoute: Identifiable, Hashable { let id: Int }
struct AnimeVisualsRoute: Hashable { let anime: Anime? }
struct MangaSearchRoute: Hashable {
    let id = UUID()
    let titles: [String]
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
    enum Kind { case manga([String]), schedule, genre(String) }
    let id = UUID()
    let kind: Kind
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

/// Genre links always open one fresh Explore result page, even from another tab's detail stack.
@MainActor
final class AppNavigationStore: ObservableObject {
    @Published var selectedTab: AppTab = .explore
    @Published private(set) var tabPreferences = AppTabPreferences(saved: UserDefaults.standard.string(forKey: AppTabPreferences.storageKey))
    @Published var supplementary: SupplementaryDestination?
    func applyTabPreferences() {
        let value = AppTabPreferences(saved: UserDefaults.standard.string(forKey: AppTabPreferences.storageKey))
        selectedTab = value.selection(for: selectedTab)
        tabPreferences = value
    }
    func openSchedule() {
        if tabPreferences.visible.contains(.schedule) { selectedTab = .schedule }
        else { supplementary = .init(kind: .schedule) }
    }
    @Published private(set) var tabletLayout = TabletLayout(preference: UserDefaults.standard.string(forKey: TabletLayout.preferenceKey))
    let explore = TabNavigationState()
    let schedule = TabNavigationState()
    let library = TabNavigationState()
    let news = TabNavigationState()
    let manga = TabNavigationState()

    /// Apply on settings dismissal so changing topology cannot tear down its
    /// presenting sheet while the user is still editing preferences.
    func applyLayoutPreference() {
        let value = TabletLayout(preference: UserDefaults.standard.string(forKey: TabletLayout.preferenceKey))
        guard value != tabletLayout else { return }
        for state in [explore, schedule, library, news] {
            state.path = NavigationPath(); state.detailPath = NavigationPath()
            state.animeID = nil; state.column = .sidebar; state.visibility = .all
        }
        tabletLayout = value
    }

    func state(for tab: AppTab) -> TabNavigationState {
        switch tab {
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

    func openMangaSearch(titles: [String]) {
        guard tabPreferences.visible.contains(.manga) else {
            supplementary = .init(kind: .manga(titles)); return
        }
        var path = NavigationPath()
        path.append(MangaSearchRoute(titles: titles))
        manga.path = path
        selectedTab = .manga
    }
}

struct AppTabs: View {
    @EnvironmentObject private var navigation: AppNavigationStore
    @State private var loadedLayout = false
    @AppStorage("app.mediaSection") private var mediaSection = "anime"
    @AppStorage(ExploreDesign.storageKey) private var exploreDesign = ExploreDesign.discover.rawValue
    @AppStorage("library.mediaSection") private var librarySection = "all"
    var body: some View {
        tabs.task {
            guard !loadedLayout else { return }
            loadedLayout = true
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-reset-content-preferences") {
                let hidden: Set<AppTab> = ProcessInfo.processInfo.arguments.contains("--ui-customization-preview") ? [.manga] : []
                UserDefaults.standard.set(AppTabPreferences(hidden: hidden).saved, forKey: AppTabPreferences.storageKey)
                UserDefaults.standard.set(ProcessInfo.processInfo.arguments.contains("--ui-customization-preview") ? "all" : "anime", forKey: "library.mediaSection")
                UserDefaults.standard.set("anime", forKey: "app.mediaSection")
            } else if !LibraryCustomizationPreview.active && (MangaReaderPreview.active || ProcessInfo.processInfo.arguments.contains("--ui-phase2-preview")) {
                UserDefaults.standard.set(AppTabPreferences(hidden: []).saved, forKey: AppTabPreferences.storageKey)
                UserDefaults.standard.set("anime", forKey: "library.mediaSection")
            }
            #endif
            navigation.applyLayoutPreference(); navigation.applyTabPreferences()
        }
    }
    private var tabs: some View {
        TabView(selection: $navigation.selectedTab) {
            ForEach(navigation.tabPreferences.visible) { tab in
                pane(tab).tabItem { Label(tab.title, systemImage: tab.symbol) }.tag(tab)
            }
        }.sheet(item: $navigation.supplementary) { destination in
            NavigationStack {
                supplementary(destination.kind).animeNavigation()
                    .environment(\.animeSplitPresentation, false)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { navigation.supplementary = nil } } }
            }
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
    @ViewBuilder private func pane(_ tab: AppTab) -> some View {
        switch tab {
        case .explore:
            AnimeTabPane(state: navigation.explore, layout: ExploreDesign(preference: exploreDesign) == .classic && mediaSection != "written" ? navigation.tabletLayout : .fullWidth) { MediaExploreView() }
        case .library:
            AnimeTabPane(state: navigation.library, layout: librarySection == "anime" ? navigation.tabletLayout : .fullWidth) { MediaLibraryView() }
        case .manga: MangaTabPane(state: navigation.manga)
        case .schedule: AnimeTabPane(state: navigation.schedule, layout: navigation.tabletLayout) { ScheduleView() }
        case .news: AnimeTabPane(state: navigation.news, layout: .fullWidth) { NewsView().animeNavigation() }
        }
    }
    @ViewBuilder private func supplementary(_ kind: SupplementaryDestination.Kind) -> some View {
        switch kind {
        case .manga(let titles): MangaTitleSearchView(titles: titles)
        case .schedule: ScheduleView()
        case .genre(let genre): DiscoveryBrowseView(category: .trending, selection: .current(), titleOverride: genre, initialGenre: genre)
        }
    }

}

private struct MangaTabPane: View {
    @ObservedObject var state: TabNavigationState
    var body: some View {
        NavigationStack(path: $state.path) {
            MangaHubView().navigationDestination(for: MangaSearchRoute.self) { route in
                MangaTitleSearchView(titles: route.titles).id(route.id)
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
            NavigationStack(path: $state.path) { content }
                .environment(\.animeSplitPresentation, false)
        }
    }
    private func split(browseWidth: Double) -> some View {
        NavigationSplitView(columnVisibility: $state.visibility, preferredCompactColumn: $state.column) {
            NavigationStack(path: $state.path) { content }
                .navigationSplitViewColumnWidth(min: 480, ideal: browseWidth, max: 820)
        } detail: {
            NavigationStack(path: $state.detailPath) {
                Group {
                    if let id = state.animeID {
                        AnimeDetailView(mediaID: id).id(id)
                            .navigationBarBackButtonHidden(sizeClass == .regular)
                            .toolbar {
                                if sizeClass == .regular {
                                    ToolbarItem(placement: .topBarLeading) {
                                        Button {
                                            state.detailPath = NavigationPath(); state.animeID = nil; state.column = .sidebar
                                            state.visibility = .all
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
extension EnvironmentValues {
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


