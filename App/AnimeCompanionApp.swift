import SwiftUI
import AnimeCore

@main
struct AnimeCompanionApp: App {
    @StateObject private var store = AppStore()
    var body: some Scene {
        WindowGroup {
            AppTabs().environmentObject(store).environmentObject(store.exploreDubs).tint(Theme.accent)
                .preferredColorScheme(.dark).fontDesign(.rounded).task { await store.restore() }
        }
    }
}

enum Theme {
    static let accent = Color.white
    static let background = Color(red: 0.115, green: 0.115, blue: 0.153)
    static let surface = Color(red: 0.15, green: 0.15, blue: 0.19)
    static let highlight = Color.yellow
}

struct AnimeRoute: Identifiable, Hashable { let id: Int }
struct DiscoveryRoute: Hashable {
    let category: DiscoveryCategory
    var selection = SeasonSelection.current()
    var titleOverride: String? = nil
}

struct AppTabs: View {
    var body: some View {
        TabView {
            NavigationStack { ExploreView() }.tabItem { Label("Explore", systemImage: "safari") }
            NavigationStack { ScheduleView() }.tabItem { Label("Schedule", systemImage: "calendar") }
            NavigationStack { LibraryView() }.tabItem { Label("My Library", systemImage: "books.vertical") }
            NavigationStack { NewsView() }.tabItem { Label("News", systemImage: "newspaper") }
        }
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
