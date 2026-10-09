import SwiftUI
import AnimeCore

struct PlaybackSettingsView: View {
    @EnvironmentObject private var playback: PlaybackStore
    @State private var installURL = ""
    @State private var saved = false
    @State private var installationTask: Task<Void, Never>?
    var body: some View {
        Form {
            Section("External player") {
                Label("VidHub", systemImage: "play.rectangle.fill")
                Text("Videos open in VidHub. When you return, supported versions send the playback position back so you can resume here.")
                    .font(.caption).foregroundStyle(.secondary)
                Link("VidHub integration help", destination: URL(string: "https://vidhub.okaapps.com/3rd-party-app-integration/")!)
            }
            if let addon = playback.addon {
                Section("Connected add-on") {
                    Text(addon.manifest.name).font(.headline).accessibilityIdentifier("installed-addon-name")
                    Text(addon.endpoint.displayHost).font(.caption).foregroundStyle(.secondary)
                    Toggle("Enable streaming add-on", isOn: $playback.enabled).accessibilityIdentifier("addon-enabled")
                    Button("Remove add-on", role: .destructive) { playback.remove(); saved = false }
                        .disabled(playback.installing)
                }
            }
            Section(playback.addon == nil ? "Connect AIOStreams" : "Replace add-on") {
                SecureField("Paste add-on install URL", text: $installURL)
                    .textContentType(.none).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .keyboardType(.URL).accessibilityIdentifier("addon-install-url")
                Button {
                    installationTask = Task { if await playback.install(installURL) { installURL = ""; saved = true } }
                } label: { Text(playback.installing ? "Checking add-on…" : "Connect add-on") }
                    .disabled(installURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || playback.installing)
                    .accessibilityIdentifier("connect-streaming-addon")
                if playback.installing { ProgressView() }
                if saved { Label("Add-on saved. Open an anime and tap Watch in VidHub.", systemImage: "checkmark.circle").foregroundStyle(.mint) }
                if let error = playback.setupError { Text(error).font(.caption).foregroundStyle(.orange) }
                Text("Paste your AIOStreams install link, with or without /manifest.json. The private link is stored in this device’s Keychain.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Playback support") {
                Text("Supports Stremio add-ons that accept AniList or MyAnimeList IDs and return direct video links. AIOStreams controls source ordering and language labels.")
                Text("Torrent-only sources and sources requiring playback headers need a streaming service or proxy configured in the add-on. Nuvio JavaScript plugins are not supported.")
                Text("Resume positions are saved on this device. Update AniList using the watched-progress controls.")
            }.font(.caption).foregroundStyle(.secondary)
        }.navigationTitle("Add-ons & playback").navigationBarTitleDisplayMode(.inline)
            .onDisappear { installationTask?.cancel(); installURL = "" }
    }
}
