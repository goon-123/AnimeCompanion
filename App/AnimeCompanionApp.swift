import SwiftUI
import AnimeCore

@main
struct AnimeCompanionApp: App {
    @StateObject private var store = AppStore()
    var body: some Scene {
        WindowGroup {
            AppTabs().environmentObject(store).tint(Theme.accent).task { await store.restore() }
        }
    }
}

enum Theme {
    static let accent = Color("AccentColor")
    static let background = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
}

struct AnimeRoute: Identifiable, Hashable { let id: Int }

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
    }
}
extension View { func animeNavigation() -> some View { modifier(AnimeNavigation()) } }
