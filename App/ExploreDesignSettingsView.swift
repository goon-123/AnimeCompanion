import SwiftUI
import AnimeCore

struct ExploreDesignSettingsView: View {
    @AppStorage(ExploreDesign.storageKey) private var saved = ExploreDesign.discover.rawValue
    private var selected: ExploreDesign { ExploreDesign(preference: saved) }
    var body: some View {
        Form {
            Section {
                ScreenPresentationPicker(scope: selected.presentationScope).id(selected.presentationScope)
                NavigationLink("Home & all Explore styles") { ScreenAppearanceSettingsView() }
            } header: { Text("Screen appearance") }
            Section {
                ForEach(ExploreDesign.allCases) { design in
                    Button { saved = design.rawValue } label: {
                        HStack(spacing: 14) {
                            Image(systemName: design.symbol).font(.title2).foregroundStyle(.mint).frame(width: 34)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(design.title).font(.headline).foregroundStyle(.primary)
                                Text(design.detail).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                            if design == selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(.mint) }
                        }.padding(.vertical, 10).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("explore-design-" + design.rawValue)
                        .accessibilityAddTraits(design == selected ? .isSelected : [])
                        .accessibilityValue(design == selected ? "Selected" : "")
                }
            } header: { Text("Explore design") } footer: {
                Text("Your choice is saved. Classic separates Anime from Manga & Novels. Choose Original above to restore the previous appearance of the selected layout.")
            }
        }.navigationTitle("Explore design").navigationBarTitleDisplayMode(.inline)
    }
}
