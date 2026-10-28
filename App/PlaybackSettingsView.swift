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
            Section {
                NavigationLink { AddonDirectoryBrowser(startURL: URL(string: "https://aiostreams.elfhosted.com/stremio/configure")!) } label: {
                    Label("Configure AIOStreams", systemImage: "square.stack.3d.up")
                }.accessibilityIdentifier("configure-aiostreams")
                NavigationLink { AddonDirectoryBrowser() } label: { Label("Browse stremio-addons.net", systemImage: "globe") }
                    .accessibilityIdentifier("browse-addon-directory")
                NavigationLink { AddonCatalogHome() } label: { Label("Browse installed catalogs", systemImage: "rectangle.stack") }
                    .accessibilityIdentifier("browse-installed-catalogs")
            } header: { Text("Discover add-ons") } footer: { Text("Browse, configure a provider and use its Install button. You review each manifest before it is saved.") }
            if !playback.installations.isEmpty {
                Section("Installed add-ons · \(playback.installations.count)") {
                    Toggle("Enable add-ons", isOn: $playback.enabled).accessibilityIdentifier("addon-enabled")
                    ForEach(playback.installations) { installation in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(installation.addon.manifest.name).font(.headline).accessibilityIdentifier("installed-addon-name")
                            Text(installation.addon.manifest.capabilitySummary).font(.caption).foregroundStyle(.secondary)
                            Toggle("Enable \(installation.addon.manifest.name)", isOn: Binding(
                                get: { playback.installations.first { $0.id == installation.id }?.enabled ?? false },
                                set: { playback.setEnabled($0, id: installation.id) }))
                                .disabled(playback.installing).accessibilityIdentifier("addon-enabled-\(installation.id)")
                            DisclosureGroup("Details & management") {
                                Text(installation.addon.endpoint.displayHost).font(.caption).foregroundStyle(.secondary)
                                AddonCompatibilityText(addon: installation.addon)
                                Text(installation.addon.endpoint.manifestURL.absoluteString).font(.caption).textSelection(.enabled)
                                if installation.addon.manifest.behaviorHints?.configurable == true || installation.addon.manifest.behaviorHints?.configurationRequired == true {
                                    NavigationLink("Configure \(installation.addon.manifest.name)") {
                                        AddonDirectoryBrowser(startURL: installation.addon.endpoint.configurationURL)
                                    }
                                }
                                Button("Remove \(installation.addon.manifest.name)", role: .destructive) { playback.remove(id: installation.id); saved = false }
                                    .disabled(playback.installing).accessibilityIdentifier("addon-remove-\(installation.id)")
                            }.accessibilityIdentifier("addon-manage-\(installation.addon.manifest.name)")
                        }.padding(.vertical, 4)
                    }
                }
            }
            Section("Add a manifest") {
                TextField("Paste add-on install URL", text: $installURL)
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
                if saved { Label("Add-on saved. Open native Watch or browse installed catalogs.", systemImage: "checkmark.circle").foregroundStyle(.mint) }
                if let error = playback.setupError { Text(error).font(.caption).foregroundStyle(.orange) }
                if let endpoint = try? AddonEndpoint(installURL), !installURL.isEmpty {
                    NavigationLink("Open this add-on’s configuration page") { AddonDirectoryBrowser(startURL: endpoint.configurationURL) }
                }
                Text("Add as many compatible manifest.json links as you need. Each add-on stays installed until you remove it. Reconnecting the same link updates that installation. Private links stay in this device’s Keychain.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("The URL is visible as requested. It may contain private tokens—avoid including it in screenshots or sharing it.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Playback support") {
                NavigationLink("VidHub & resume") { PlayerSettingsView() }
                DisclosureGroup("Compatibility details") {
                Text("Supports standard HTTPS Stremio manifests with catalogs, metadata, streams and subtitles. Native anime Watch uses AniList/MAL IDs; installed catalogs and exact-ID lookup also support IMDb, Kitsu and provider IDs. Enabled compatible stream sources appear together, with English-audio choices first.")
                Text("Not every Stremio add-on is playable: torrent-only sources, DRM, YouTube IDs and special playback headers require a compatible service or proxy. Nested add-on directories and legacy/IPFS transports are not supported natively. Supported Seanime torrent-provider scripts run separately in Seanime extensions & TorBox; other plugin types remain unsupported.")
                Text("Native anime Watch saves resume on this device. Catalog/exact-ID playback does not save resume here. Update AniList using the watched-progress controls.")
                }
            }.font(.caption).foregroundStyle(.secondary)
        }.navigationTitle("Stremio add-ons").navigationBarTitleDisplayMode(.inline)
            .onDisappear { installationTask?.cancel(); installURL = "" }
    }
}
