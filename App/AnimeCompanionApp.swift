import SwiftUI
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
            AppTabs().environmentObject(store).environmentObject(store.exploreDubs).environmentObject(discoveryFilters).tint(Theme.accent)
                .environmentObject(playback).onOpenURL { playback.handle($0) }
                .environmentObject(navigation)
                .preferredColorScheme(.dark).fontDesign(.rounded).task { await store.restore() }
                .task(id: scenePhase) {
                    guard scenePhase == .active else { return }
                    await store.exploreDubs.keepUpdated(using: store.dubs)
                }
        }
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

/// Genre links always open one fresh Explore result page, even from another tab's detail stack.
@MainActor
final class AppNavigationStore: ObservableObject {
    @Published var selectedTab: AppTab = .explore
    @Published var explorePath = NavigationPath()

    func openGenre(_ genre: String) {
        var path = NavigationPath()
        path.append(DiscoveryRoute(category: .trending, titleOverride: genre, genre: genre, shortcutID: UUID()))
        explorePath = path
        selectedTab = .explore
    }
}

struct AppTabs: View {
    @Environment(\.horizontalSizeClass) private var contentSizeClass
    @EnvironmentObject private var navigation: AppNavigationStore
    var body: some View {
        TabView(selection: $navigation.selectedTab) {
            NavigationStack(path: $navigation.explorePath) { ExploreView() }.environment(\.horizontalSizeClass, contentSizeClass).tabItem { Label("Explore", systemImage: "safari") }.tag(AppTab.explore)
            NavigationStack { ScheduleView() }.environment(\.horizontalSizeClass, contentSizeClass).tabItem { Label("Schedule", systemImage: "calendar") }.tag(AppTab.schedule)
            NavigationStack { LibraryView() }.environment(\.horizontalSizeClass, contentSizeClass).tabItem { Label("My Library", systemImage: "books.vertical") }.tag(AppTab.library)
            NavigationStack { NewsView() }.environment(\.horizontalSizeClass, contentSizeClass).tabItem { Label("News", systemImage: "newspaper") }.tag(AppTab.news)
        }
        // Keep the native floating bottom bar on iPad while preserving tablet content layouts.
        .environment(\.horizontalSizeClass, .compact)
    }
}

struct AnimeNavigation: ViewModifier {
    func body(content: Content) -> some View {
        content.navigationDestination(for: AnimeRoute.self) { AnimeDetailView(mediaID: $0.id) }
            .navigationDestination(for: DiscoveryRoute.self) {
                DiscoveryBrowseView(category: $0.category, selection: $0.selection, titleOverride: $0.titleOverride, initialGenre: $0.genre)
            }
    }
}
extension View { func animeNavigation() -> some View { modifier(AnimeNavigation()) } }

