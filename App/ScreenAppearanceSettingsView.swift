import SwiftUI
import AnimeCore

struct ScreenAppearanceSettingsView: View {
    var body: some View {
        Form {
            Section {
                ScreenPresentationPicker(scope: .home)
            } header: { Text("Home") }
            Section {
                ForEach([ScreenPresentationScope.classicExplore, .mixedExplore, .discoveryExplore]) { scope in
                    ScreenPresentationPicker(scope: scope)
                }
            } header: { Text("Explore") } footer: {
                Text("Choose each screen independently. Original restores its previous design. Your widgets, sizes, filters and library progress are kept when you switch.")
            }
            Section {
                NavigationLink { ExploreDesignSettingsView() } label: { Label("Choose Explore layout", systemImage: "rectangle.stack") }
                NavigationLink { SeriesAppearanceSettingsView() } label: { Label("Anime series appearance", systemImage: "rectangle.on.rectangle") }
            } footer: { Text("Series layout and artwork choices are managed separately.") }
        }.navigationTitle("Home & Explore appearance").navigationBarTitleDisplayMode(.inline)
    }
}

struct ScreenPresentationPicker: View {
    let scope: ScreenPresentationScope
    @AppStorage private var saved: String
    init(scope: ScreenPresentationScope) {
        self.scope = scope
        _saved = AppStorage(wrappedValue: ScreenPresentation.cinematic.rawValue, scope.storageKey)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(scope.title).font(.subheadline.weight(.semibold))
            Picker(scope.title, selection: Binding(get: { ScreenPresentation(preference: saved).rawValue }, set: { saved = $0 })) {
                ForEach(ScreenPresentation.allCases) { value in Text(value.title).tag(value.rawValue) }
            }.pickerStyle(.segmented).accessibilityIdentifier("screen-presentation-" + scope.rawValue)
        }.padding(.vertical, 4)
    }
}

private struct CinematicCardsKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var cinematicCards: Bool {
        get { self[CinematicCardsKey.self] }
        set { self[CinematicCardsKey.self] = newValue }
    }
}
