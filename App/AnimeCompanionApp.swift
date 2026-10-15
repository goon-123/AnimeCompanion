import SwiftUI
import UIKit
import AnimeCore

@main
struct AnimeCompanionApp: App {
    @StateObject private var store = AppStore()
    @StateObject private var discoveryFilters = DiscoveryFilterStore()
    @StateObject private var playback = PlaybackStore()
    @StateObject private var navigation = AppNavigationStore()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            root.environmentObject(store).environmentObject(store.exploreDubs).environmentObject(discoveryFilters).tint(Theme.accent)
                .environmentObject(playback).onOpenURL { playback.handle($0) }
                .environmentObject(navigation)
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
                    Task { await ArtworkPipeline.shared.clearMemory() }
                }
                .preferredColorScheme(.dark).fontDesign(.rounded).task { if !artworkPreview { await store.restore() } }
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
        else { AppTabs() }
        #else
        AppTabs()
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
struct DiscoveryRoute: Hashable {
    let category: DiscoveryCategory
    var selection = SeasonSelection.current()
    var titleOverride: String? = nil
    var genre: String? = nil
    var shortcutID: UUID? = nil
}

enum AppTab: Hashable { case explore, schedule, library, news }

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
    let explore = TabNavigationState()
    let schedule = TabNavigationState()
    let library = TabNavigationState()
    let news = TabNavigationState()

    func state(for tab: AppTab) -> TabNavigationState {
        switch tab {
        case .explore: return explore
        case .schedule: return schedule
        case .library: return library
        case .news: return news
        }
    }

    func openGenre(_ genre: String) {
        var path = NavigationPath()
        path.append(DiscoveryRoute(category: .trending, titleOverride: genre, genre: genre, shortcutID: UUID()))
        explore.path = path
        explore.animeID = nil
        explore.detailPath = NavigationPath()
        explore.column = .sidebar
        explore.visibility = .all
        selectedTab = .explore
    }
}

struct AppTabs: View {
    @EnvironmentObject private var navigation: AppNavigationStore
    var body: some View {
        if #available(iOS 18.0, *) {
            tabs.tabViewStyle(.sidebarAdaptable)
        } else { tabs }
    }
    private var tabs: some View {
        TabView(selection: $navigation.selectedTab) {
            AnimeTabPane(state: navigation.explore) { ExploreView() }
                .tabItem { Label("Explore", systemImage: "safari") }.tag(AppTab.explore)
            AnimeTabPane(state: navigation.schedule) { ScheduleView() }
                .tabItem { Label("Schedule", systemImage: "calendar") }.tag(AppTab.schedule)
            AnimeTabPane(state: navigation.library) { LibraryView() }
                .tabItem { Label("My Library", systemImage: "books.vertical") }.tag(AppTab.library)
            AnimeTabPane(state: navigation.news) { NewsView() }
                .tabItem { Label("News", systemImage: "newspaper") }.tag(AppTab.news)
        }.onChange(of: navigation.selectedTab) { _, tab in
            if tab == .schedule {
                navigation.schedule.path = NavigationPath()
                navigation.schedule.animeID = nil
                navigation.schedule.detailPath = NavigationPath()
                navigation.schedule.column = .sidebar
                navigation.schedule.visibility = .all
            }
        }
    }
}

/// One navigation topology at every size: compact devices collapse it into a
/// stack; iPad keeps browsing and the selected title side by side. Rotation never
/// recreates the browse view, so its query, loaded pages and scroll state survive.
private struct AnimeTabPane<Content: View>: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @ObservedObject var state: TabNavigationState
    let content: Content
    init(state: TabNavigationState, @ViewBuilder content: () -> Content) {
        self.state = state; self.content = content()
    }
    var body: some View {
        NavigationSplitView(columnVisibility: $state.visibility, preferredCompactColumn: $state.column) {
            NavigationStack(path: $state.path) { content }
                .navigationSplitViewColumnWidth(min: 320, ideal: 460, max: 600)
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
extension EnvironmentValues {
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
    let id: Int
    let content: Content
    init(id: Int, @ViewBuilder label: () -> Content) { self.id = id; content = label() }
    var body: some View {
        if inDetail { NavigationLink(value: AnimeRoute(id: id)) { content } }
        else { Button { navigation.state(for: navigation.selectedTab).open(id) } label: { content } }
    }
}

struct AnimeNavigation: ViewModifier {
    func body(content: Content) -> some View {
        content.navigationDestination(for: AnimeRoute.self) { AnimeDetailView(mediaID: $0.id).toolbar(.visible, for: .navigationBar) }
            .navigationDestination(for: DiscoveryRoute.self) { route in
                DiscoveryBrowseView(category: route.category, selection: route.selection, titleOverride: route.titleOverride, initialGenre: route.genre)
                    // Replacing a path with the same destination type otherwise reuses its
                    // @State filters. Each genre tap must initialize a fresh result page;
                    // normal detail/back navigation keeps the same route and loaded pages.
                    .id(route)
                    .toolbar(.visible, for: .navigationBar)
            }
    }
}
extension View { func animeNavigation() -> some View { modifier(AnimeNavigation()) } }

