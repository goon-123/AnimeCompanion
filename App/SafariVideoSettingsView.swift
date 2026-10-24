import SwiftUI

struct SafariVideoSettingsView: View {
    var body: some View {
        Form {
            Section {
                Label("Keep browsing in Safari", systemImage: "safari.fill")
                    .font(.headline).foregroundStyle(.cyan)
                Text("When a playable video is detected, tap Open in VidHub to continue there. Your place in the video is included when available.")
            }
            Section("Enable the extension") {
                instruction("1", title: "Open Settings", detail: "Go to Apps → Safari → Extensions.")
                instruction("2", title: "Turn on Anime Companion – VidHub", detail: "The extension is included with this app. It requires iOS or iPadOS 18 or later.")
                instruction("3", title: "Allow website access", detail: "Choose All Websites → Allow to detect videos wherever you browse. If asked, also allow access to an embedded player’s website.")
                instruction("4", title: "Start a video in Safari", detail: "Tap Open in VidHub when the prompt appears. You can also open Safari’s page menu, choose Extensions, then Anime Companion – VidHub.")
            }
            Section("Make it yours") {
                Label("Automatic prompts", systemImage: "play.bubble")
                Text("Turn prompts off in the Safari extension’s menu to use its stream list manually. Detection stays available.")
                Label("Website preferences", systemImage: "globe")
                Text("Use Not on this site to disable detection for that website. Re-enable it from the extension’s menu, or reset website preferences there.")
            }.font(.subheadline)
            Section("If a video does not open") {
                Text("Open the extension in Safari and tap Scan again to restore detection on the current page, including embedded players.")
                Text("If Open in VidHub does nothing in the extension menu, choose Open from webpage. Close the menu and tap the Open in VidHub button on the page.")
            }.font(.subheadline)
            Section("Playback compatibility") {
                Text("Works with accessible video files and streaming playlists. Some websites use protected playback, browser-only video, or links that require their login session; those may need Safari’s player.")
                Text("Safari videos do not change your anime watch progress. Detected links stay on this device during the browsing session and are only handed to VidHub when you tap Open.")
            }.font(.subheadline).foregroundStyle(.secondary)
            Section {
                Link("VidHub playback help", destination: URL(string: "https://vidhub.okaapps.com/3rd-party-app-integration/")!)
            }
        }
        .navigationTitle("Safari → VidHub")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("safari-vidhub-setup")
    }

    private func instruction(_ number: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number).font(.subheadline.bold()).foregroundStyle(.cyan)
                .frame(width: 26, height: 26).background(.cyan.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 4)
    }
}
