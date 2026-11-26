import SwiftUI
import AnimeCore

struct WatchSourceSetupView: View {
    @EnvironmentObject private var playback: PlaybackStore
    @EnvironmentObject private var seanime: SeanimeStore
    @EnvironmentObject private var app: AppStore
    @AppStorage(SetupPlaybackRoute.storageKey) private var routeValue = SetupPlaybackRoute.stremio.rawValue
    @AppStorage("setup.player.confirmed.v1") private var playerConfirmed = false
    private var route: SetupPlaybackRoute { SetupPlaybackRoute(rawValue: routeValue) ?? .stremio }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Choose one way to find videos", systemImage: "1.circle.fill").font(.headline)
            Text("AIOStreams is the recommended starting point. Seanime is an alternative: its torrent extension and TorBox must both be set up. You do not need both routes.")
                .font(.subheadline).foregroundStyle(.secondary)
            Picker("Video source route", selection: $routeValue) {
                ForEach(SetupPlaybackRoute.allCases) { Text($0.label).tag($0.rawValue) }
            }.pickerStyle(.segmented).accessibilityIdentifier("setup-playback-route")
            if route == .stremio {
                VStack(alignment: .leading, spacing: 14) {
                    Label("AIOStreams / Stremio add-on", systemImage: "puzzlepiece.extension.fill").font(.headline)
                    Text("Configure AIOStreams with your providers and any service it requires, then install its configured manifest in this app. Enable a compatible stream add-on to get video results.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    setupStatus("Compatible stream add-on", complete: playback.enabledAddons.contains { $0.addon.supportsAnime },
                                detail: "A catalog-only add-on does not provide native anime streams.")
                    NavigationLink { PlaybackSettingsView() } label: { Label("Set up AIOStreams / Stremio", systemImage: "plus.circle") }
                        .accessibilityIdentifier("setup-aiostreams")
                    Text("TorBox is highly recommended when your AIOStreams configuration uses torrents. Connect it inside AIOStreams; the separate app TorBox key is used by the Seanime route.")
                        .font(.caption).foregroundStyle(.secondary)
                }.companionPanel(padding: 18)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    Label("Seanime torrent extension + TorBox", systemImage: "shippingbox.fill").font(.headline)
                    Text("Seanime extensions find torrents. TorBox turns supported releases into playable video links. An extension by itself cannot provide playback here.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    NavigationLink { SeanimeSettingsView() } label: {
                        setupStatus("Install & enable a torrent extension", complete: !enabledTorrentProviders.isEmpty, detail: "Choose a compatible Seanime provider and finish any provider preferences.")
                    }.buttonStyle(.plain).accessibilityIdentifier("setup-seanime")
                    NavigationLink { TorBoxSettingsView() } label: {
                        setupStatus("Connect TorBox", complete: seanime.hasTorBoxKey, detail: "Add your TorBox API key. Both steps are required for this route.")
                    }.buttonStyle(.plain).accessibilityIdentifier("setup-torbox")
                }.companionPanel(padding: 18)
            }
            VStack(alignment: .leading, spacing: 14) {
                Label("Choose your video player", systemImage: "2.circle.fill").font(.headline)
                Text("Required for either route. Install VidHub, Outplayer or Infuse separately, then choose the same app here.")
                    .font(.subheadline).foregroundStyle(.secondary)
                VideoPlayerSelection()
                Link("Install / learn about \(playback.player.label)", destination: playback.player.helpURL)
                Toggle("I have \(playback.player.label) installed", isOn: $playerConfirmed)
                    .accessibilityIdentifier("setup-player-confirmed")
            }.companionPanel(padding: 18).accessibilityIdentifier("setup-video-player")
            Text("Configuration checks show what is saved and enabled. Available videos still depend on your sources, service account and the selected title.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private var enabledTorrentProviders: [SeanimeInstallation] { SeanimeProviderAvailability(seanime.installations, allowAdult: app.includeAdult).searchable }
}

struct ReadingSourceSetupView: View {
    @EnvironmentObject private var manga: MangaExtensionStore
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 14) {
                Label("Keiyoushi manga extensions", systemImage: "books.vertical.fill").font(.headline)
                Text("Add the Keiyoushi repository, install a manga source you use, and leave that extension enabled. Adding only the repository does not install a reading source.")
                    .font(.subheadline).foregroundStyle(.secondary)
                setupStatus("Keiyoushi repository", complete: manga.state.repositoryAdded, detail: "The catalog lets you find and install extensions.")
                setupStatus("Installed & enabled manga source", complete: manga.state.installations.contains { $0.enabled && !$0.sources.isEmpty }, detail: "At least one enabled source is needed to search for chapters and read.")
                NavigationLink { MangaExtensionsView() } label: { Label("Add Keiyoushi & manga sources", systemImage: "plus.circle") }
                    .accessibilityIdentifier("setup-keiyoushi")
                if manga.loading { ProgressView("Checking installed sources…") }
                if let error = manga.error { Text(error).font(.caption).foregroundStyle(.orange) }
            }.companionPanel(padding: 18)
            Label("No video player or TorBox is needed for manga. Source compatibility and chapter availability vary.", systemImage: "book")
                .font(.subheadline).foregroundStyle(.secondary)
        }.task { await manga.load(refreshCatalog: false) }
    }
}

struct SourceSetupSummary: View {
    @EnvironmentObject private var playback: PlaybackStore
    @EnvironmentObject private var seanime: SeanimeStore
    @EnvironmentObject private var app: AppStore
    @EnvironmentObject private var manga: MangaExtensionStore
    @AppStorage("setup.player.confirmed.v1") private var playerConfirmed = false
    private var status: SourceSetupStatus {
        SourceSetupStatus(streamAddons: playback.enabledAddons.filter { $0.addon.supportsAnime }.count,
            torrentProviders: SeanimeProviderAvailability(seanime.installations, allowAdult: app.includeAdult).searchable.count,
            torBoxConnected: seanime.hasTorBoxKey, playerConfirmed: playerConfirmed,
            mangaSources: manga.state.installations.filter { $0.enabled }.reduce(0) { $0 + $1.sources.count })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            setupStatus("Video source route", complete: status.stremioConfigured || status.seanimeConfigured,
                detail: status.stremioConfigured ? "Compatible Stremio stream add-on enabled." : status.seanimeConfigured ? "Seanime torrent provider and TorBox configured." : "Add AIOStreams, or enable a Seanime torrent extension and connect TorBox.")
            setupStatus("Video player · \(playback.player.label)", complete: status.playerConfirmed,
                detail: status.playerConfirmed ? "You confirmed this player is installed." : "Choose a player and confirm it is installed in the playback step.")
            setupStatus("Manga reading", complete: status.readingConfigured,
                detail: status.readingConfigured ? "\(status.mangaSources) source(s) enabled." : "Install and enable a Keiyoushi manga source to read chapters.")
            if !status.videoConfigured || !status.readingConfigured {
                Text("Browsing works now. \(!status.videoConfigured ? "Video playback still needs setup. " : "")\(!status.readingConfigured ? "Manga reading still needs a source." : "")")
                    .font(.subheadline.weight(.medium)).accessibilityIdentifier("setup-incomplete")
            }
        }.companionPanel(padding: 18).task { await manga.load(refreshCatalog: false) }
    }
}

private func setupStatus(_ title: String, complete: Bool, detail: String) -> some View {
    HStack(alignment: .top, spacing: 12) {
        Image(systemName: complete ? "checkmark.circle.fill" : "circle.dashed")
            .foregroundStyle(complete ? Theme.accent : Color.secondary).frame(width: 24)
        VStack(alignment: .leading, spacing: 4) {
            HStack { Text(title).font(.subheadline.weight(.semibold)); Spacer(); Text(complete ? "Configured" : "Needs setup").font(.caption) }
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
    }.foregroundStyle(.primary).accessibilityElement(children: .combine)
}
