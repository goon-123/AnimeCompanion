import SwiftUI
import AnimeCore

struct PlaybackSettingsView: View {
    @EnvironmentObject private var playback: PlaybackStore
    @State private var installURL = ""
    @State private var saved = false
    @State private var installationTask: Task<Void, Never>?
    @FocusState private var enteringManifest: Bool
    var body: some View {
        Form {
            Section("External player") {
                Label("VidHub", systemImage: "play.rectangle.fill")
                Text("Videos open in VidHub. When you return, supported versions send the playback position back so you can resume here.")
                    .font(.caption).foregroundStyle(.secondary)
                Link("VidHub integration help", destination: URL(string: "https://vidhub.okaapps.com/3rd-party-app-integration/")!)
            }
            if !playback.installations.isEmpty {
                Section("Installed add-ons · \(playback.installations.count)") {
                    Toggle("Enable streaming add-ons", isOn: $playback.enabled).accessibilityIdentifier("addon-enabled")
                    ForEach(playback.installations) { installation in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(installation.addon.manifest.name).font(.headline).accessibilityIdentifier("installed-addon-name")
                            Text(installation.addon.endpoint.displayHost).font(.caption).foregroundStyle(.secondary)
                            Toggle("Enable \(installation.addon.manifest.name)", isOn: Binding(
                                get: { playback.installations.first { $0.id == installation.id }?.enabled ?? false },
                                set: { playback.setEnabled($0, id: installation.id) }))
                                .disabled(playback.installing).accessibilityIdentifier("addon-enabled-\(installation.id)")
                            Button("Remove \(installation.addon.manifest.name)", role: .destructive) { playback.remove(id: installation.id); saved = false }
                                .disabled(playback.installing).accessibilityIdentifier("addon-remove-\(installation.id)")
                        }.padding(.vertical, 4)
                    }
                }
            }
            Section("Add a streaming add-on") {
                SecureField("Paste add-on install URL", text: $installURL)
                    .textContentType(.none).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .focused($enteringManifest).submitLabel(.done).onSubmit { enteringManifest = false }
                    .keyboardType(.URL).accessibilityIdentifier("addon-install-url")
                Button {
                    enteringManifest = false
                    installationTask = Task { if await playback.install(installURL) { installURL = ""; saved = true } }
                } label: { Text(playback.installing ? "Checking add-on…" : "Add add-on") }
                    .disabled(installURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || playback.installing)
                    .accessibilityIdentifier("connect-streaming-addon")
                if playback.installing { ProgressView() }
                if saved { Label("Add-on saved. Open an anime and tap Watch in VidHub.", systemImage: "checkmark.circle").foregroundStyle(.mint) }
                if let error = playback.setupError { Text(error).font(.caption).foregroundStyle(.orange) }
                Text("Add as many compatible manifest.json links as you need. Each add-on stays installed until you remove it. Reconnecting the same link updates that installation. Private links stay in this device’s Keychain.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Playback support") {
                Text("Supports Stremio manifest links that accept AniList or MyAnimeList IDs and return direct video links. Sources from enabled add-ons appear together, with each add-on named. English-audio choices stay first.")
                Text("Torrent-only sources and sources requiring playback headers need a streaming service or proxy configured in the add-on. Nuvio JavaScript plugins are not supported.")
                Text("Resume positions are saved on this device. Update AniList using the watched-progress controls.")
            }.font(.caption).foregroundStyle(.secondary)
        }.navigationTitle("Add-ons & playback").navigationBarTitleDisplayMode(.inline)
            .onDisappear { installationTask?.cancel(); installURL = "" }
    }
}
