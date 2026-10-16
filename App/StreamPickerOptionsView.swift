import SwiftUI

struct StreamPickerOptionsView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var playableOnly: Bool
    var body: some View {
        Form {
            Section("Sources") {
                NavigationLink { PlaybackSettingsView() } label: { Label("Stremio add-ons", systemImage: "puzzlepiece.extension") }
                NavigationLink { SeanimeSettingsView() } label: { Label("Seanime extensions", systemImage: "shippingbox") }
                NavigationLink { TorBoxSettingsView() } label: { Label("TorBox connection", systemImage: "cloud") }
                NavigationLink { AddonCatalogHome() } label: { Label("Catalogs & other video IDs", systemImage: "rectangle.stack") }
            }
            Section {
                Toggle("Playable streaming sources only", isOn: $playableOnly).accessibilityIdentifier("playback-playable-only")
            } footer: { Text("Turn off to also inspect unavailable streaming sources. Torrent readiness is checked separately in TorBox.") }
            Section {
                NavigationLink("Playback help") { StreamPickerHelpView() }
                NavigationLink("VidHub & resume") { PlayerSettingsView() }
            }
        }.navigationTitle("Source options").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
}
