import SwiftUI
import AnimeCore

struct ExploreDesignSettingsView: View {
    @AppStorage(ExploreDesign.storageKey) private var saved = ExploreDesign.discover.rawValue
    private var selected: ExploreDesign { ExploreDesign(preference: saved) }
    var body: some View {
        Form {
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
                Text("Your choice is saved. You can change it here or from Explore's layout button. Classic restores the original discovery pages and their display preferences.")
            }
        }.navigationTitle("Explore design").navigationBarTitleDisplayMode(.inline)
    }
}
