import SwiftUI
import AnimeCore

struct WatchAnimeView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var playback: PlaybackStore
    @Environment(\.dismiss) private var dismiss
    let anime: Anime
    @State private var episode = 1
    @State private var episodeText = "1"
    @State private var streams: [StremioStream] = []
    @State private var skipped = 0
    @State private var loading = false
    @State private var searched = false
    @State private var error: String?
    @State private var filter = ""
    @State private var playableOnly = true
    @State private var restart = false
    @State private var searchTask: Task<Void, Never>?
    @State private var lookupID = UUID()
    @State private var initialized = false
    @FocusState private var episodeFocused: Bool
    private var limit: Int { anime.format == "MOVIE" ? 1 : max(1, anime.episodes ?? 100_000) }
    private var visible: [(offset: Int, element: StremioStream)] {
        streams.enumerated().filter { (!playableOnly || $0.element.unavailableReason == nil) &&
            (filter.isEmpty || ($0.element.displayName + " " + $0.element.details).localizedCaseInsensitiveContains(filter)) }
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(anime.displayTitle).font(.title3.bold())
                    if anime.format != "MOVIE" { episodeControls }
                    if let saved = playback.saved(animeID: anime.id, episode: episode) {
                        if saved.finished { Label("Finished in VidHub on this device", systemImage: "checkmark.circle").foregroundStyle(.mint) }
                        else if saved.position > 0 {
                            Text("Resume at \(timeLabel(saved.position))").font(.subheadline)
                            Toggle("Start from beginning", isOn: $restart)
                        }
                    }
                    if playback.ready {
                        if loading { ProgressView("Finding sources…").accessibilityIdentifier("playback-loading") }
                    } else {
                        Text(playback.addon == nil ? "Connect your streaming add-on to find sources." : "Your streaming add-on is disabled.")
                        NavigationLink("Set up add-on & VidHub") { PlaybackSettingsView() }
                    }
                }
                if let error { Section { NoticeView(message: error) { loadSources() } } }
                if let message = playback.playerMessage {
                    Section("Playback") {
                        Text(message).font(.subheadline)
                        if playback.saved(animeID: anime.id, episode: episode)?.finished == true && store.isSignedIn {
                            Button("Mark episode watched on AniList") { markWatched() }
                                .disabled(store.loadingLibrary || store.savingMedia.contains(anime.id))
                        }
                    }
                }
                if searched && !loading {
                    Section("Sources · \(streams.count)") {
                        if streams.isEmpty {
                            Text("No sources were returned for this episode. Check your AIOStreams providers or try another episode.")
                                .foregroundStyle(.secondary).accessibilityIdentifier("playback-empty-results")
                        } else {
                            TextField("Search source details", text: $filter).autocorrectionDisabled()
                            Toggle("Playable sources only", isOn: $playableOnly)
                            if visible.isEmpty { Text("No sources match. Clear the search or show all sources.").foregroundStyle(.secondary) }
                            ForEach(visible, id: \.offset) { index, stream in
                                Button { play(stream) } label: {
                                    VStack(alignment: .leading, spacing: 7) {
                                        Label(stream.displayName, systemImage: stream.unavailableReason == nil ? "play.circle.fill" : "exclamationmark.circle").font(.headline)
                                        Text(stream.details).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                                        if let reason = stream.unavailableReason { Text(reason).font(.caption).foregroundStyle(.orange) }
                                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
                                }.buttonStyle(.plain).disabled(stream.unavailableReason != nil || playback.openingPlayer)
                                    .accessibilityIdentifier("playback-source-\(index)")
                                    .contextMenu {
                                        if stream.unavailableReason == nil {
                                            Button("Play from beginning", systemImage: "backward.end.fill") { play(stream, fromBeginning: true) }
                                            ForEach(Array((stream.subtitles ?? []).filter { $0.videoURL != nil }.enumerated()), id: \.offset) { index, subtitle in
                                                Button("Play with \(subtitle.lang ?? "track \(index + 1)") subtitles") { play(stream, subtitle: subtitle.videoURL) }
                                            }
                                        }
                                    }
                            }
                        }
                        if skipped > 0 { Text("\(skipped) malformed source entries were skipped.").font(.caption).foregroundStyle(.secondary) }
                    }
                    Section {
                        Text("Tap a source to open VidHub. Touch and hold for subtitles or to play from the beginning.")
                        Text("Source names, quality and language information come from your add-on. Dub availability on the anime page does not guarantee that each source includes English audio.")
                        Text("VidHub resume is saved on this device. AniList progress changes only when you use the watched-progress controls.")
                    }.font(.caption).foregroundStyle(.secondary)
                }
            }.navigationTitle("Watch in VidHub").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        if playback.ready {
                            Button { loadSources() } label: { Image(systemName: "arrow.clockwise") }
                                .disabled(loading || playback.openingPlayer).accessibilityLabel("Reload sources")
                                .accessibilityIdentifier("reload-playback-sources")
                        }
                    }
                }
                .onAppear {
                    if !initialized {
                        initialized = true
                        episode = min(limit, max(1, playback.resumeEpisode(animeID: anime.id) ?? ((store.entry(for: anime.id)?.progressValue ?? 0) + 1)))
                        episodeText = String(episode)
                        playback.playerMessage = nil
                    }
                    if !searched && !loading { loadSources() }
                }
                .onChange(of: playback.enabled) { _, _ in resetSources(); loadSources() }
                .onChange(of: playback.addon?.endpoint) { _, _ in resetSources(); loadSources() }
                .onDisappear {
                    searchTask?.cancel()
                    if loading { lookupID = UUID(); loading = false }
                }
        }.disabled(playback.openingPlayer)
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
        searchTask?.cancel(); lookupID = UUID(); streams = []; skipped = 0; searched = false; loading = false; error = nil; filter = ""
    }
    private func loadSources() {
        guard let addon = playback.addon, playback.enabled else { return }
        searchTask?.cancel()
        let attempt = UUID(); lookupID = attempt
        let requestedEpisode = episode
        loading = true; error = nil; streams = []; searched = false
        searchTask = Task {
            defer { if lookupID == attempt { loading = false } }
            do {
                let result = try await playback.client.streams(addon: addon, anime: anime, episode: requestedEpisode)
                try Task.checkCancellation(); guard lookupID == attempt else { return }
                streams = result.streams; skipped = result.skippedCount; searched = true
            } catch is CancellationError {} catch { if lookupID == attempt { self.error = error.localizedDescription } }
        }
    }
    private func play(_ stream: StremioStream, subtitle: URL? = nil, fromBeginning: Bool? = nil) {
        let requestedEpisode = episode, requestedRestart = fromBeginning ?? restart
        Task { await playback.play(stream: stream, anime: anime, episode: requestedEpisode, subtitle: subtitle, restart: requestedRestart) }
    }
    private func markWatched() {
        let progress = max(episode, store.entry(for: anime.id)?.progressValue ?? 0)
        let complete = anime.episodes.map { $0 > 0 && progress >= $0 } ?? false
        Task {
            do {
                try await store.save(anime: anime, progress: progress, status: complete ? .completed : .watching)
                playback.playerMessage = "Watched progress saved to AniList."
            } catch { self.error = error.localizedDescription }
        }
    }
    private func timeLabel(_ seconds: Double) -> String {
        let value = Int(min(VidHubPlayback.maximumPosition, max(0, seconds.isFinite ? seconds : 0)))
        return value >= 3600 ? String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60) : String(format: "%d:%02d", value / 60, value % 60)
    }
}

