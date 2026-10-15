import SwiftUI
import AnimeCore

struct AddonCatalogHome: View {
    @EnvironmentObject private var playback: PlaybackStore
    @EnvironmentObject private var store: AppStore
    private var enabled: [AddonInstallation] {
        playback.enabledAddons.filter { store.includeAdult || $0.addon.manifest.behaviorHints?.adult != true }
    }
    var body: some View {
        List {
            Section {
                Text("Catalogs use the provider’s exact title and video IDs, including IMDb and Kitsu IDs. They are separate from your AniList library.")
                Text("Third-party catalogs may contain unrated content. Known adult add-ons are hidden when Show adult anime is off; providers do not always supply content ratings.")
            }.font(.caption).foregroundStyle(.secondary)
            ForEach(enabled) { installation in
                if installation.addon.manifest.advertises("catalog") {
                    Section(installation.addon.manifest.name) {
                        ForEach(Array((installation.addon.manifest.catalogs ?? []).enumerated()), id: \.offset) { _, catalog in
                            NavigationLink {
                                AddonCatalogView(installationID: installation.id, catalog: catalog)
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(catalog.displayName)
                                    Text(catalog.type).font(.caption).foregroundStyle(.secondary)
                                }
                            }.accessibilityIdentifier("installed-addon-catalog-\(catalog.id)")
                        }
                        if (installation.addon.manifest.catalogs ?? []).isEmpty { Text("This manifest does not list any catalogs.").font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
            Section {
                NavigationLink("Open an exact video ID") { AddonExactVideoView() }
                    .accessibilityIdentifier("addon-exact-video")
                Text("For stream-only or metadata-only add-ons: use the exact type and ID from the provider. An IMDb series video usually includes its season and episode, for example tt1234567:2:3. This never changes AniList progress.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if enabled.isEmpty { Text("Enable an add-on in Add-ons & playback to browse its resources.").foregroundStyle(.secondary) }
        }.navigationTitle("Installed catalogs").navigationBarTitleDisplayMode(.inline)
    }
}

private struct AddonCatalogView: View {
    @EnvironmentObject private var playback: PlaybackStore
    @EnvironmentObject private var store: AppStore
    let installationID: UUID
    let catalog: AddonCatalog
    @State private var fields: [String: String] = [:]
    @State private var applied: [String: String] = [:]
    @State private var items: [StremioMeta] = []
    @State private var offset = 0
    @State private var complete = false
    @State private var loading = false
    @State private var error: String?
    @State private var skipped = 0
    @State private var revision = 0
    @State private var generation = UUID()
    private var installation: AddonInstallation? {
        playback.enabledAddons.first { $0.id == installationID && (store.includeAdult || $0.addon.manifest.behaviorHints?.adult != true) }
    }
    private var requiredFilled: Bool { catalog.extras.filter { $0.isRequired == true }.allSatisfy { fields[$0.name]?.isEmpty == false } }
    var body: some View {
        List {
            if !catalog.extras.filter({ $0.name != "skip" }).isEmpty {
                Section("Catalog filters") {
                    ForEach(Array(catalog.extras.filter { $0.name != "skip" }.enumerated()), id: \.offset) { _, extra in
                        extraField(extra)
                    }
                    Button("Apply filters") { applied = fields.filter { !$0.value.isEmpty }; revision += 1 }.disabled(!requiredFilled)
                        .accessibilityIdentifier("addon-catalog-apply")
                }
            }
            if installation == nil { Text("This add-on is disabled, removed, or hidden by your content setting.") }
            else {
                Section {
                    ForEach(items, id: \.catalogKey) { meta in
                        NavigationLink {
                            AddonMetaView(seed: meta, preferredAddonID: installationID)
                        } label: { AddonCatalogRow(meta: meta) }
                            .accessibilityIdentifier("addon-catalog-title-\(meta.id)")
                    }
                    if let error { Text(error).foregroundStyle(.orange); Button("Retry catalog") { self.error = nil } }
                    else if !complete && requiredApplied {
                        ProgressView("Loading titles…").task { await loadNext() }.id(offset)
                    } else if items.isEmpty {
                        Text(requiredApplied ? "No titles returned for these filters." : "Fill the required filters and tap Apply filters.").foregroundStyle(.secondary)
                    }
                    if skipped > 0 { Text("\(skipped) malformed catalog entries were skipped.").font(.caption).foregroundStyle(.secondary) }
                }
            }
        }.navigationTitle(catalog.displayName).navigationBarTitleDisplayMode(.inline)
            .task(id: "\(revision)-\(playback.addonRevision)-\(playback.enabled)-\(store.includeAdult)") {
                generation = UUID(); loading = false
                items = []; offset = 0; complete = false; error = nil; skipped = 0
                if requiredApplied { await loadNext() }
            }
    }
    private var requiredApplied: Bool { catalog.extras.filter { $0.isRequired == true }.allSatisfy { applied[$0.name]?.isEmpty == false } }
    @ViewBuilder private func extraField(_ extra: AddonCatalogExtra) -> some View {
        let label = extra.name.capitalized + (extra.isRequired == true ? " (required)" : "")
        let value = Binding(get: { fields[extra.name] ?? "" }, set: { fields[extra.name] = $0 })
        if let options = extra.options, !options.isEmpty {
            Picker(label, selection: value) {
                Text("Any").tag("")
                ForEach(options, id: \.self) { Text($0).tag($0) }
            }
        } else { TextField(label, text: value).textInputAutocapitalization(.never).autocorrectionDisabled().submitLabel(.done) }
    }
    private func loadNext() async {
        guard !loading, !complete, error == nil, requiredApplied, let installation else { return }
        loading = true
        let started = generation, addonRevision = playback.addonRevision
        defer { if started == generation { loading = false } }
        do {
            var extra = applied
            if catalog.accepts("skip") { extra["skip"] = String(offset) }
            let result = try await playback.client.catalog(addon: installation.addon, catalog: catalog, extra: extra)
            try Task.checkCancellation()
            guard started == generation, addonRevision == playback.addonRevision, self.installation != nil else { return }
            var seen = Set(items.map(\.catalogKey))
            let new = result.metas.filter { seen.insert($0.catalogKey).inserted }
            items += new; offset += result.receivedCount; skipped += result.skippedCount
            complete = result.receivedCount == 0 || new.isEmpty || !catalog.accepts("skip")
        } catch is CancellationError {} catch {
            guard !Task.isCancelled, started == generation, addonRevision == playback.addonRevision else { return }
            self.error = error.localizedDescription
        }
    }
}

private extension StremioMeta { var catalogKey: String { "\(type):\(id)" } }

private struct AddonCatalogRow: View {
    let meta: StremioMeta
    var body: some View {
        HStack(spacing: 12) {
            ArtworkImage(url: StremioStream.networkURL(meta.poster), pointSize: 90) { $0.resizable().scaledToFill() } placeholder: { Color.secondary.opacity(0.2) }
                .frame(width: 54, height: 78).clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 4) {
                Text(meta.displayName).font(.headline)
                Text(meta.type).font(.caption).foregroundStyle(.secondary)
                if let genres = meta.genres { Text(genres.prefix(3).joined(separator: " · ")).font(.caption).foregroundStyle(.secondary) }
            }
        }
    }
}

private struct AddonMetaView: View {
    @EnvironmentObject private var playback: PlaybackStore
    @EnvironmentObject private var store: AppStore
    let seed: StremioMeta
    let preferredAddonID: UUID
    @State private var loaded: StremioMeta?
    @State private var metadataProviderID: UUID?
    @State private var loading = true
    @State private var notice: String?
    @State private var retry = 0
    private var meta: StremioMeta { loaded ?? seed }
    private var providers: [AddonInstallation] {
        playback.enabledAddons.filter { (store.includeAdult || $0.addon.manifest.behaviorHints?.adult != true) && $0.addon.manifest.supports(resource: "meta", type: seed.type, id: seed.id) }
            .sorted { ($0.id == preferredAddonID ? 0 : 1) < ($1.id == preferredAddonID ? 0 : 1) }
    }
    var body: some View {
        List {
            Section {
                AddonCatalogRow(meta: meta)
                if let description = PlaybackSourceText.clean(meta.description, maximumLines: 12, maximumCharacters: 2000) { Text(description).font(.subheadline) }
                Text("Provider ID · \(meta.id)").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                Text("Not linked to AniList. Playback here does not update watched progress or local resume.").font(.caption).foregroundStyle(.secondary)
            }
            if loading { ProgressView("Loading title details…") }
            if let notice { Text(notice).font(.caption).foregroundStyle(.orange); Button("Retry metadata") { retry += 1 } }
            Section("Videos") {
                if meta.type == "tv" || ((meta.videos ?? []).isEmpty && meta.type != "series") {
                    NavigationLink("Find sources") {
                        AddonVideoSourcesView(request: .init(type: meta.type, id: meta.id), title: meta.displayName)
                    }.accessibilityIdentifier("addon-meta-find-sources")
                } else {
                    ForEach(Array((meta.videos ?? []).enumerated()), id: \.offset) { _, video in
                        NavigationLink {
                            AddonVideoSourcesView(request: .init(type: meta.type, id: video.id), title: "\(meta.displayName) · \(video.displayTitle)", embedded: video.streams, embeddedProviderID: metadataProviderID ?? preferredAddonID)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(video.displayTitle)
                                if let season = video.season, let episode = video.episode { Text("Season \(season) · Episode \(episode)").font(.caption).foregroundStyle(.secondary) }
                            }
                        }.accessibilityIdentifier("addon-meta-video-\(video.id)")
                    }
                    if !loading && (meta.videos ?? []).isEmpty {
                        Text("No episode IDs were provided. Install a compatible metadata add-on, or enter an exact video ID. Seasons will not be guessed.").font(.caption).foregroundStyle(.secondary)
                        NavigationLink("Open an exact video ID") { AddonExactVideoView() }
                    }
                }
            }
        }.navigationTitle(meta.displayName).navigationBarTitleDisplayMode(.inline)
            .task(id: "\(retry)-\(playback.addonRevision)-\(playback.enabled)-\(store.includeAdult)") { await load() }
    }
    private func load() async {
        loaded = nil; metadataProviderID = nil; notice = nil; loading = true
        defer { loading = false }
        for provider in providers {
            do {
                if let result = try await playback.client.meta(addon: provider.addon, request: .init(type: seed.type, id: seed.id)) {
                    try Task.checkCancellation(); loaded = result; metadataProviderID = provider.id; notice = nil; return
                }
            } catch is CancellationError { return }
            catch { notice = "Some metadata could not load. Showing available catalog information." }
        }
    }
}

struct AddonExactVideoView: View {
    @State private var type = "series"
    @State private var videoID = ""
    var body: some View {
        Form {
            Section("Exact provider identifiers") {
                TextField("Type, e.g. series or movie", text: $type).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("addon-video-type")
                TextField("Video ID, e.g. tt1234567:2:3", text: $videoID).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("addon-video-id")
                NavigationLink("Find sources") {
                    AddonVideoSourcesView(request: .init(type: type.trimmingCharacters(in: .whitespacesAndNewlines), id: videoID.trimmingCharacters(in: .whitespacesAndNewlines)), title: videoID)
                }.disabled(type.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || videoID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("addon-video-find-sources")
                Text("Copy the complete video ID from your provider, including season/episode if required. This is independent of AniList and never writes watched progress.").font(.caption).foregroundStyle(.secondary)
            }
        }.navigationTitle("Exact video ID").navigationBarTitleDisplayMode(.inline)
    }
}

struct AddonVideoSourcesView: View {
    @EnvironmentObject private var playback: PlaybackStore
    @EnvironmentObject private var store: AppStore
    let request: StremioVideoRequest
    let title: String
    var embedded: [StremioStream]? = nil
    var embeddedProviderID: UUID? = nil
    @State private var snapshot: AddonStreamSnapshot?
    @State private var loading = true
    @State private var error: String?
    @State private var retry = 0
    @State private var information: AddonStreamSource?
    @State private var subtitleSource: AddonStreamSource?
    @State private var audio = StreamAudioFilter.all
    @State private var lookupID = UUID()
    private var enabled: [AddonInstallation] { playback.enabledAddons.filter { store.includeAdult || $0.addon.manifest.behaviorHints?.adult != true } }
    private var sources: [AddonStreamSource] { snapshot?.sources ?? [] }
    private var visible: [Int] { StreamSourceSelection.indices(in: sources.map(\.stream), audio: audio, playableOnly: false, search: "") }
    var body: some View {
        List {
            Section {
                Text(title).font(.headline)
                Text("\(request.type) · \(request.id)").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                Text("Catalog playback is not linked to AniList or local resume.").font(.caption).foregroundStyle(.secondary)
                Picker("Audio", selection: $audio) { ForEach(StreamAudioFilter.allCases, id: \.self) { Text($0.label).tag($0) } }.pickerStyle(.segmented)
                    .accessibilityIdentifier("addon-video-audio")
            }
            if loading { ProgressView("Checking enabled add-ons…") }
            if let error { Text(error).foregroundStyle(.orange) }
            ForEach(snapshot?.issues ?? []) { issue in Text("\(issue.addonName): \(issue.error.localizedDescription)").font(.caption).foregroundStyle(.orange) }
            if !loading && sources.isEmpty { Text("No sources returned. Check enabled add-ons and their supported video IDs. Torrent-only add-ons also need a streaming service.").foregroundStyle(.secondary) }
            ForEach(visible, id: \.self) { index in
                let source = sources[index]
                PlaybackSourceRow(stream: source.stream, index: index, preferred: index == visible.first && source.stream.unavailableReason == nil,
                    openingPlayer: playback.openingPlayer, addonName: source.addonName,
                    play: { Task { await playback.playUntracked(stream: source.stream, title: title) } }, information: { information = source })
                    .contextMenu {
                        if source.stream.unavailableReason == nil {
                            Button("Choose subtitles") { subtitleSource = source }
                        }
                    }
            }
            if let message = playback.playerMessage { Text(message).font(.caption).accessibilityIdentifier("addon-video-player-message") }
        }.navigationTitle("Add-on sources").navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Reload") { retry += 1 }.disabled(loading) }
            .task(id: "\(retry)-\(playback.addonRevision)-\(playback.enabled)-\(store.includeAdult)") {
                let lookup = UUID(); lookupID = lookup
                loading = true; error = nil; snapshot = nil
                defer { if lookupID == lookup { loading = false } }
                do {
                    if let embedded {
                        if let provider = enabled.first(where: { $0.id == embeddedProviderID }) {
                            snapshot = AddonStreamSnapshot.embedded(embedded, addonID: provider.id, addonName: provider.addon.manifest.name)
                        } else { error = "The provider of these embedded video sources is disabled, removed, or hidden by your content setting." }
                    } else {
                        snapshot = try await playback.client.streams(installations: enabled, request: request) { update in
                            guard !Task.isCancelled else { return }
                            await MainActor.run { if lookupID == lookup { snapshot = update } }
                        }
                    }
                } catch is CancellationError {} catch { if lookupID == lookup { self.error = error.localizedDescription } }
            }
            .sheet(item: $information) { source in SourceInformationView(stream: source.stream, addonName: source.addonName) }
            .sheet(item: $subtitleSource) { source in
                NavigationStack { AddonSubtitlePicker(request: request, source: source, title: title, providers: enabled) }
            }
    }
}

private struct AddonSubtitlePicker: View {
    @EnvironmentObject private var playback: PlaybackStore
    @Environment(\.dismiss) private var dismiss
    let request: StremioVideoRequest
    let source: AddonStreamSource
    let title: String
    let providers: [AddonInstallation]
    @State private var tracks: [StreamSubtitle] = []
    @State private var loading = true
    @State private var errors: [String] = []
    var body: some View {
        List {
            Button("Play without external subtitles") { play(nil) }
            ForEach(Array(tracks.enumerated()), id: \.offset) { index, track in
                Button("Play with \(track.lang ?? "track \(index + 1)") subtitles") { play(track.videoURL) }
            }
            if loading { ProgressView("Checking subtitle add-ons…") }
            if !loading && tracks.isEmpty { Text("No external subtitle tracks returned. Embedded video tracks may still be available in VidHub.").font(.caption).foregroundStyle(.secondary) }
            ForEach(Array(errors.enumerated()), id: \.offset) { _, error in Text(error).font(.caption).foregroundStyle(.orange) }
        }.navigationTitle("Subtitles").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .task {
                tracks = (source.stream.subtitles ?? []).filter { $0.videoURL != nil }; loading = true; errors = []
                defer { loading = false }
                for provider in providers where provider.addon.manifest.supports(resource: "subtitles", type: request.type, id: request.id) {
                    do {
                        let result = try await playback.client.subtitles(addon: provider.addon, request: request, stream: source.stream)
                        try Task.checkCancellation()
                        var urls = Set(tracks.map(\.url)); tracks += result.filter { urls.insert($0.url).inserted }
                    } catch is CancellationError { return }
                    catch { errors.append("\(provider.addon.manifest.name): \(error.localizedDescription)") }
                }
            }
    }
    private func play(_ url: URL?) { Task { await playback.playUntracked(stream: source.stream, title: title, subtitle: url); dismiss() } }
}
