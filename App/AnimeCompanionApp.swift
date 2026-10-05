import SwiftUI
import AnimeCore

@main
struct AnimeCompanionApp: App {
    @StateObject private var store = AppStore()
    @StateObject private var discoveryFilters = DiscoveryFilterStore()
    @StateObject private var playback = PlaybackStore()
    var body: some Scene {
        WindowGroup {
            AppTabs().environmentObject(store).environmentObject(store.exploreDubs).environmentObject(discoveryFilters).tint(Theme.accent)
                .environmentObject(playback).onOpenURL { playback.handle($0) }
                .preferredColorScheme(.dark).fontDesign(.rounded).task { await store.restore() }
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
}

struct AppTabs: View {
    @Environment(\.horizontalSizeClass) private var contentSizeClass
    var body: some View {
        TabView {
            NavigationStack { ExploreView() }.environment(\.horizontalSizeClass, contentSizeClass).tabItem { Label("Explore", systemImage: "safari") }
            NavigationStack { ScheduleView() }.environment(\.horizontalSizeClass, contentSizeClass).tabItem { Label("Schedule", systemImage: "calendar") }
            NavigationStack { LibraryView() }.environment(\.horizontalSizeClass, contentSizeClass).tabItem { Label("My Library", systemImage: "books.vertical") }
            NavigationStack { NewsView() }.environment(\.horizontalSizeClass, contentSizeClass).tabItem { Label("News", systemImage: "newspaper") }
        }
        // Keep the native floating bottom bar on iPad while preserving tablet content layouts.
        .environment(\.horizontalSizeClass, .compact)
    }
}

struct AnimeNavigation: ViewModifier {
    func body(content: Content) -> some View {
        content.navigationDestination(for: AnimeRoute.self) { AnimeDetailView(mediaID: $0.id) }
            .navigationDestination(for: DiscoveryRoute.self) {
                DiscoveryBrowseView(category: $0.category, selection: $0.selection, titleOverride: $0.titleOverride)
            }
    }
}
extension View { func animeNavigation() -> some View { modifier(AnimeNavigation()) } }
