import SwiftUI
import AnimeCore

struct WatchAnimeView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var playback: PlaybackStore
    @EnvironmentObject private var seanime: SeanimeStore
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var torrents = SeanimeSearchModel()
    @Environment(\.dismiss) private var dismiss
    let anime: Anime
    var requestedEpisode: Int? = nil
    @State private var episode = 1
    @State private var episodeText = "1"
    @State private var sourceResults: AddonStreamSnapshot?
    @State private var loading = false
    @State private var searched = false
    @State private var error: String?
    @State private var trackingError: String?
    @State private var filter = ""
    @State private var playableOnly = true
    @AppStorage("playback.audioFilter") private var audioFilterValue = StreamAudioFilter.all.rawValue
    @State private var options = false
    @State private var help = false
    @State private var restart = false
    @State private var searchTask: Task<Void, Never>?
    @State private var lookupID = UUID()
    @State private var initialized = false
    @State private var episodeChangedByUser = false
    @State private var sourceInformation: AddonStreamSource?
    @State private var sourceKind = "all"
    @State private var torBoxFiles = false
    @FocusState private var episodeFocused: Bool
    private var limit: Int { anime.format == "MOVIE" ? 1 : min(100_000, max(1, anime.episodes.flatMap { $0 > 0 ? $0 : nil } ?? 100_000)) }
    private var initializationKey: String {
        "\(anime.id)-\(store.isSignedIn)-\(store.loadingLibrary)-\(store.entry(for: anime.id)?.progressValue ?? -1)-\(store.libraryError ?? "")"
    }
    private var audioFilter: StreamAudioFilter { StreamAudioFilter(rawValue: audioFilterValue) ?? .all }
    private var streams: [StremioStream] { sourceResults?.sources.map(\.stream) ?? [] }
    private var skipped: Int { sourceResults?.skippedCount ?? 0 }
    private struct SourceChoice: Identifiable {
        let index: Int
        let source: AddonStreamSource
        var id: AddonStreamSource.ID { source.id }
    }
    private var choices: [SourceChoice] {
        guard let sources = sourceResults?.sources else { return [] }
        return visible.map { SourceChoice(index: $0, source: sources[$0]) }
    }
    private var visible: [Int] {
        StreamSourceSelection.indices(in: streams, audio: audioFilter, playableOnly: playableOnly, search: filter)
    }
    private var englishDirect: Int {
        streams.filter { $0.unavailableReason == nil && StreamSourceMetadata(stream: $0).audio.english }.count
    }
    private var englishTorrents: Int { torrents.results.filter { $0.audio.english }.count }
    private var englishSummary: String? {
        if playback.ready && sourceKind != "torrents" && !searched { return nil }
        guard searched || torrents.searched else { return nil }
        if sourceKind == "torrents" || !playback.ready {
            return englishTorrents > 0 ? "English audio · \(englishTorrents) TorBox \(englishTorrents == 1 ? "release" : "releases")" : "No English audio listed yet"
        }
        if sourceKind == "all" && !torrents.providers.isEmpty {
            return "English audio · \(englishDirect) direct · \(englishTorrents) TorBox"
        }
        return englishDirect > 0 ? "English audio · \(englishDirect) playable \(englishDirect == 1 ? "source" : "sources")" : "No playable English source listed"
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    episodeHeader
                    StreamPickerFilters(kind: $sourceKind, audio: $audioFilterValue, query: $filter,
                        englishSummary: englishSummary, hasEnglish: sourceKind == "torrents" ? englishTorrents > 0 : englishDirect + englishTorrents > 0)
                    if let message = playback.playerMessage {
                        StreamPickerCard {
                            Text(message).font(.subheadline).accessibilityIdentifier("playback-player-message")
                            if playback.saved(animeID: anime.id, episode: episode)?.finished == true && store.isSignedIn {
                                Button("Mark episode watched on AniList") { markWatched() }
                                    .disabled(store.loadingLibrary || store.savingMedia.contains(anime.id))
                            }
                            if let trackingError { Text(trackingError).font(.caption).foregroundStyle(.orange).accessibilityIdentifier("playback-tracking-error") }
                        }
                    }
                    if sourceKind != "torrents" { streamingSources }
                    if initialized && sourceKind != "streaming" {
                        SeanimeSourcesSections(search: torrents, anime: anime, episode: episode, restart: restart,
                            resultFilter: filter, showsAudioControls: false)
                    }
                }.frame(maxWidth: 780).padding(16).padding(.bottom, 16).frame(maxWidth: .infinity)
            }.background(Theme.background).accessibilityIdentifier("stream-picker-scroll")
                .scrollDismissesKeyboard(.interactively)
                .navigationTitle("Find streams").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { loadSources(); torrents.search() } label: { Image(systemName: "arrow.clockwise") }
                            .disabled(!initialized || loading || playback.openingPlayer).accessibilityLabel("Reload sources")
                            .accessibilityIdentifier("reload-playback-sources")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button { commitEpisode(); torBoxFiles = true } label: { Label("Browse TorBox files", systemImage: "folder") }
                                .disabled(!initialized).accessibilityIdentifier("watch-torbox-files")
                            Button { options = true } label: { Label("Sources & options", systemImage: "slider.horizontal.3") }
                            Button { help = true } label: { Label("Playback help", systemImage: "questionmark.circle") }
                        } label: { Image(systemName: "ellipsis.circle") }
                            .accessibilityLabel("Stream options").accessibilityIdentifier("stream-picker-options")
                    }
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                    ToolbarItemGroup(placement: .keyboard) {
                        if episodeFocused { Spacer(); Button("Apply episode") { commitEpisode() } }
                    }
                }
                .task(id: initializationKey) { initializeEpisode() }
                .task(id: "\(initialized)-\(episode)-\(seanime.revision)-\(store.includeAdult)") {
                    guard initialized else { return }
                    torrents.configure(store: seanime, anime: anime, allowAdult: store.includeAdult)
                    torrents.search()
                }
                .sheet(item: $sourceInformation) { source in SourceInformationView(stream: source.stream, addonName: source.addonName) }
                .sheet(isPresented: $torBoxFiles) { TorBoxFilesView(anime: anime, episode: episode, restart: restart) }
                .sheet(isPresented: $options) { NavigationStack { StreamPickerOptionsView(playableOnly: $playableOnly) } }
                .sheet(isPresented: $help) { NavigationStack { StreamPickerHelpView().toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { help = false } } } } }
                .onChange(of: playback.enabled) { _, _ in resetSources(); loadSources() }
                .onChange(of: playback.addonRevision) { _, _ in resetSources(); loadSources() }
                .onDisappear {
                    searchTask?.cancel(); torrents.stop()
                    if loading { lookupID = UUID(); loading = false }
                }
                .onChange(of: scenePhase) { _, phase in if phase != .active { torrents.stop() } }
        }.disabled(playback.openingPlayer)
    }
    private var episodeHeader: some View {
        StreamPickerCard {
            HStack(alignment: .top, spacing: 12) {
                ArtworkImage(url: anime.coverURL, pointSize: 64) { image in image.resizable().scaledToFill() } placeholder: { Color.white.opacity(0.06) }
                    .frame(width: 48, height: 68).clipShape(RoundedRectangle(cornerRadius: 8)).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(anime.displayTitle).font(.headline).lineLimit(2).accessibilityIdentifier("stream-picker-title")
                    if let entry = store.entry(for: anime.id) {
                        let completed = anime.episodes.map { $0 > 0 && entry.progressValue >= $0 } ?? false
                        Text("AniList · \(entry.progressValue) episodes watched\(completed ? " · Completed" : "")").font(.caption).foregroundStyle(.secondary)
                            .accessibilityIdentifier("playback-anilist-progress")
                    } else { Text(anime.format == "MOVIE" ? "Movie · VidHub" : "Choose an episode · VidHub").font(.caption).foregroundStyle(.secondary) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            if anime.format != "MOVIE" {
                if initialized { episodeControls } else { ProgressView("Loading AniList progress…").font(.caption) }
            }
            if let notice = store.libraryError { Text("Progress could not refresh. Choose the episode manually if needed. \(notice)").font(.caption).foregroundStyle(.orange) }
            if let saved = playback.saved(animeID: anime.id, episode: episode) {
                if saved.finished { Label("Finished on this device", systemImage: "checkmark.circle").font(.caption).foregroundStyle(.mint) }
                else if saved.position > 0 {
                    Text("Resume at \(timeLabel(saved.position))").font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("playback-resume-position")
                    Toggle("Start from beginning", isOn: $restart).font(.caption)
                }
            }
        }
    }
    @ViewBuilder private var streamingSources: some View {
        let visibleSources = choices
        if !playback.ready {
            StreamPickerCard {
                Label("Streaming add-ons", systemImage: "play.rectangle").font(.subheadline.weight(.semibold))
                Text(playback.installations.isEmpty ? "Add a streaming manifest to include direct video sources." : "No compatible streaming add-ons are enabled.")
                    .font(.caption).foregroundStyle(.secondary)
                NavigationLink("Set up add-on & VidHub") { PlaybackSettingsView() }
            }
        } else {
            StreamPickerHeading(title: "Streaming", count: visibleSources.count, loading: loading, countID: "playback-result-count")
            if loading && streams.isEmpty {
                ProgressView("Checking streaming add-ons…").font(.caption).padding(12).accessibilityIdentifier("playback-loading")
            }
            if let error {
                StreamPickerCard {
                    Text(error).font(.caption).foregroundStyle(.orange)
                    if !streams.isEmpty { Text("Showing the previously loaded sources for episode \(episode).").font(.caption).foregroundStyle(.secondary) }
                    Button("Try again") { loadSources() }
                }
            }
            ForEach(sourceResults?.issues ?? []) { issue in
                StreamPickerCard {
                    Text("\(issue.addonName): \(issue.error.localizedDescription)").font(.caption).foregroundStyle(.orange)
                    if issue.usingSavedSources { Text("Showing the previously loaded sources for episode \(episode) from this add-on.").font(.caption).foregroundStyle(.secondary) }
                    Button("Retry source") { loadSources() }
                }
            }
            if searched && streams.isEmpty && !loading {
                StreamPickerEmptyState(title: "No streaming sources", message: "Try another episode or check your enabled add-ons.", symbol: "play.slash")
                    .accessibilityIdentifier("playback-empty-results")
            }
            if !streams.isEmpty && visibleSources.isEmpty {
                StreamPickerCard {
                    Text(audioFilter == .english ? "No sources match English audio. Unlisted sources may still include it." : "No sources match these filters.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Button("Show all sources") { audioFilterValue = StreamAudioFilter.all.rawValue; filter = ""; playableOnly = false }
                        .accessibilityIdentifier("playback-reset-source-filters")
                }
            }
            LazyVStack(spacing: 12) {
                ForEach(visibleSources) { choice in
                    let stream = choice.source.stream
                    let sourceEpisode = episode
                    StreamPickerCard {
                        PlaybackSourceRow(stream: stream, index: choice.index,
                            preferred: choice.id == visibleSources.first?.id && stream.unavailableReason == nil,
                            openingPlayer: playback.openingPlayer, addonName: choice.source.addonName,
                            play: { play(stream, expectedEpisode: sourceEpisode) }, information: { sourceInformation = choice.source })
                            .contextMenu {
                                if stream.unavailableReason == nil {
                                    Button("Play from beginning", systemImage: "backward.end.fill") { play(stream, expectedEpisode: sourceEpisode, fromBeginning: true) }
                                    ForEach(Array((stream.subtitles ?? []).filter { $0.videoURL != nil }.enumerated()), id: \.offset) { index, subtitle in
                                        Button("Play with \(subtitle.lang ?? "track \(index + 1)") subtitles") { play(stream, expectedEpisode: sourceEpisode, subtitle: subtitle.videoURL) }
                                    }
                                }
                            }
                    }
                }
            }
            if skipped > 0 { Text("\(skipped) malformed source entries were skipped.").font(.caption2).foregroundStyle(.secondary) }
        }
    }
    private func initializeEpisode() {
        guard !episodeChangedByUser else { return }
        if requestedEpisode == nil && store.isSignedIn && store.savedAt == nil && store.libraryError == nil {
            resetSources(); initialized = false; return
        }
        let next = PlaybackEpisodeSelection.initial(anime: anime, entry: store.entry(for: anime.id),
                                                   resumeEpisode: playback.resumeEpisode(animeID: anime.id), requestedEpisode: requestedEpisode)
        if !initialized || next != episode {
            resetSources(); episode = next; episodeText = String(next); restart = false
            playback.playerMessage = nil; initialized = true
        }
        if !loading && (!searched || (sourceResults?.pendingCount ?? 0) > 0) { loadSources() }
    }
    private var episodeControls: some View {
        HStack {
            Text("Episode")
            TextField("Episode number", text: $episodeText).keyboardType(.numberPad).frame(width: 70)
                .textFieldStyle(.roundedBorder).focused($episodeFocused).accessibilityIdentifier("playback-episode-number")
                .onSubmit { commitEpisode() }
            Button("Go") { commitEpisode() }.buttonStyle(.borderless).disabled(Int(episodeText) == nil)
                .accessibilityIdentifier("playback-episode-go")
            Spacer()
            Stepper("Episode", value: Binding(get: { episode }, set: { selectEpisode($0) }), in: 1...limit).labelsHidden().accessibilityLabel("Choose episode")
        }
    }
    private func selectEpisode(_ value: Int) {
        episodeChangedByUser = true
        let next = min(limit, max(1, value))
        if next != episode {
            resetSources(); episode = next; restart = false
            playback.playerMessage = nil
            loadSources()
        }
        episodeText = String(episode)
    }
    private func commitEpisode() { episodeFocused = false; selectEpisode(Int(episodeText) ?? episode) }
    private func resetSources() {
        searchTask?.cancel(); lookupID = UUID(); sourceResults = nil; searched = false; loading = false; error = nil; trackingError = nil; filter = ""
    }
    private func loadSources() {
        guard initialized, playback.ready else { return }
        searchTask?.cancel()
        let attempt = UUID(); lookupID = attempt
        let requestedEpisode = episode
        let installations = playback.activeAddons
        let previous = sourceResults?.sources ?? []
        loading = true; error = nil
        searchTask = Task {
            defer { if lookupID == attempt { loading = false } }
            do {
                _ = try await playback.client.streams(installations: installations, anime: anime, episode: requestedEpisode, previous: previous) { snapshot in
                    await MainActor.run {
                        guard lookupID == attempt, episode == requestedEpisode else { return }
                        sourceResults = snapshot
                        searched = !snapshot.sources.isEmpty || snapshot.pendingCount == 0
                    }
                }
            } catch is CancellationError {} catch { if lookupID == attempt { self.error = error.localizedDescription } }
        }
    }
    private func play(_ stream: StremioStream, expectedEpisode: Int, subtitle: URL? = nil, fromBeginning: Bool? = nil) {
        guard expectedEpisode == episode else { return }
        trackingError = nil
        let requestedEpisode = episode, requestedRestart = fromBeginning ?? restart
        Task { await playback.play(stream: stream, anime: anime, episode: requestedEpisode, subtitle: subtitle, restart: requestedRestart) }
    }
    private func markWatched() {
        trackingError = nil
        let progress = max(episode, store.entry(for: anime.id)?.progressValue ?? 0)
        let complete = anime.episodes.map { $0 > 0 && progress >= $0 } ?? false
        Task {
            do {
                try await store.save(anime: anime, progress: progress, status: complete ? .completed : .watching)
                playback.playerMessage = "Watched progress saved to AniList."
            } catch { self.trackingError = error.localizedDescription }
        }
    }
    private func timeLabel(_ seconds: Double) -> String {
        let value = Int(min(VidHubPlayback.maximumPosition, max(0, seconds.isFinite ? seconds : 0)))
        return value >= 3600 ? String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60) : String(format: "%d:%02d", value / 60, value % 60)
    }
}

/// Shared by tracked anime playback and exact-ID add-on catalog playback.
struct SourceInformationView: View {
    let stream: StremioStream
    let addonName: String
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section(stream.displayName) {
                    Text("Add-on · \(addonName)").font(.caption).foregroundStyle(.secondary)
                    PlaybackAudioBadge(audio: StreamSourceMetadata(stream: stream).audio)
                    Text(stream.details).textSelection(.enabled)
                }
                if let reason = stream.unavailableReason { Section("Playback") { Text(reason) } }
                Section {
                    DisclosureGroup("Original add-on text") {
                        Text([stream.name, stream.description, stream.title, stream.behaviorHints?.filename]
                            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n\n"))
                            .font(.caption.monospaced()).textSelection(.enabled)
                    }.accessibilityIdentifier("playback-original-source-text")
                } footer: { Text("Source descriptions are supplied by your add-on. You can review its original text here.") }
            }.navigationTitle("Source information").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("close-source-information") } }
        }
    }
}

