import SwiftUI
import AnimeCore

struct SourcesSettingsView: View {
    @EnvironmentObject private var manga: MangaExtensionStore
    @State private var query = ""
    var body: some View {
        Form { SourcesSettingsRows(query: query) }
            .navigationTitle("Sources & playback").navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Find a source or service")
            .accessibilityIdentifier("sources-settings").task { await manga.load() }
    }
}

struct SourcesSettingsRows: View {
    @EnvironmentObject private var playback: PlaybackStore
    @EnvironmentObject private var seanime: SeanimeStore
    @EnvironmentObject private var manga: MangaExtensionStore
    var query = ""
    private func matches(_ text: String) -> Bool { query.isEmpty || text.localizedCaseInsensitiveContains(query) }
    var body: some View {
        Section("Watch") {
            if matches("Stremio AIOStreams add-ons manifests streaming") {
                NavigationLink { PlaybackSettingsView() } label: {
                    SettingsCategoryLabel(title: "Stremio & AIOStreams", detail: "\(playback.installations.count) add-ons · Install & configure", symbol: "puzzlepiece.extension", tint: Theme.accent)
                }.accessibilityIdentifier("playback-settings")
            }
            if matches("Seanime torrent extensions providers") {
                NavigationLink { SeanimeSettingsView() } label: {
                    SettingsCategoryLabel(title: "Torrent extensions", detail: "\(seanime.installations.count) installed · Seanime providers", symbol: "shippingbox", tint: .orange)
                }.accessibilityIdentifier("seanime-settings")
            }
            if matches("TorBox cloud files account") {
                NavigationLink { TorBoxSettingsView() } label: {
                    SettingsCategoryLabel(title: "TorBox", detail: seanime.hasTorBoxKey ? "Connected · Cloud files & account" : "Connect your cloud account", symbol: "cloud", tint: .teal)
                }.accessibilityIdentifier("settings-torbox")
            }
            if matches("VidHub video player playback resume") {
                NavigationLink { PlayerSettingsView() } label: {
                    SettingsCategoryLabel(title: "Video player", detail: "VidHub · Playback & resume", symbol: "play.rectangle", tint: .pink)
                }.accessibilityIdentifier("settings-player")
            }
            if matches("Safari VidHub extension website videos") {
                NavigationLink { SafariVideoSettingsView() } label: {
                    SettingsCategoryLabel(title: "Safari → VidHub", detail: "Play videos from websites", symbol: "safari", tint: .blue)
                }.accessibilityIdentifier("settings-safari-vidhub")
            }
        }
        Section("Read") {
            if matches("Manga manhwa webtoon source extensions Keiyoushi") {
                NavigationLink { MangaExtensionsView() } label: {
                    SettingsCategoryLabel(title: "Reading extensions", detail: "\(manga.state.installations.count) installed · Manga & webtoon sources", symbol: "book.closed", tint: .teal)
                }.accessibilityIdentifier("settings-manga-extensions")
            }
        }
    }
}

struct AppearanceSettingsView: View {
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.system.rawValue
    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Color scheme", selection: $appearance) {
                    ForEach(AppAppearance.allCases) { Text($0.label).tag($0.rawValue) }
                }.accessibilityIdentifier("appearance-scheme")
            }
            Section("Make it yours") {
                NavigationLink { HomeCustomizationView() } label: { Label("Home sections", systemImage: "house") }
                    .accessibilityIdentifier("settings-home-sections")
                NavigationLink { ExploreDesignSettingsView() } label: { Label("Explore layout", systemImage: "rectangle.stack") }
                    .accessibilityIdentifier("settings-explore-design")
                NavigationLink { TabCustomizationView() } label: { Label("Navigation", systemImage: "rectangle.bottomthird.inset.filled") }
                    .accessibilityIdentifier("settings-bottom-tabs")
                if UIDevice.current.userInterfaceIdiom == .pad {
                    NavigationLink { TabletLayoutSettingsView() } label: { Label("iPad layout", systemImage: "sidebar.left") }
                        .accessibilityIdentifier("settings-ipad-layout")
                }
            } footer: { Text("Your existing layouts, hidden tabs, sources and progress stay saved. Home and Explore layouts can also be adjusted from their own screens.") }
        }.navigationTitle("Appearance & layout").navigationBarTitleDisplayMode(.inline)
    }
}
