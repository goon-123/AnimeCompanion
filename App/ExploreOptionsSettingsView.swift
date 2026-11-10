import SwiftUI
import AnimeCore

struct ExploreOptionsSettingsView: View {
    var body: some View {
        Form {
            Section("Layout") {
                NavigationLink("Explore design") { ExploreDesignSettingsView() }
                NavigationLink("Anime rows & widgets") { ExploreCustomizationView(surface: .anime) }
                NavigationLink("Manga & Novel rows") { ExploreCustomizationView(surface: .reading) }
                NavigationLink("Discovery shelves") { ExploreCustomizationView(surface: .discovery) }
                NavigationLink("Mixed poster grid") { ExploreCustomizationView(surface: .grid) }
            }
            Section("Anime") {
                NavigationLink("Browse seasons") { ExploreSeasonPickerView() }
                NavigationLink("Dub & library filters") { DubFiltersView() }
                NavigationLink("Poster display") { DisplayOptionsView(scope: .explore) }
            }
        }.navigationTitle("Explore settings").navigationBarTitleDisplayMode(.inline)
    }
}

private struct ExploreSeasonPickerView: View {
    @State private var selection = SeasonSelection.current()
    var body: some View {
        Form {
            Picker("Season", selection: $selection.season) {
                ForEach(AnimeSeason.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            Stepper("Year \(String(selection.year))", value: $selection.year, in: 1960...2100)
            NavigationLink("Browse \(selection.label)") {
                DiscoveryBrowseView(category: .seasonal, selection: selection).id(selection.label)
            }
        }.navigationTitle("Browse seasons").navigationBarTitleDisplayMode(.inline)
    }
}
