import SwiftUI
import AnimeCore

struct WatchAnimeView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var playback: PlaybackStore
    @Environment(\.dismiss) private var dismiss
    let anime: Anime
    var requestedEpisode: Int? = nil
    @State private var episode = 1
    @State private var episodeText = "1"
    @State private var streams: [StremioStream] = []
    @State private var skipped = 0
    @State private var loading = false
    @State private var searched = false
    @State private var error: String?
    @State private var filter = ""
    @State private var playableOnly = true
    @AppStorage("playback.audioFilter") private var audioFilterValue = StreamAudioFilter.all.rawValue
    @State private var sourceOptionsExpanded = false
    @State private var restart = false
    @State private var searchTask: Task<Void, Never>?
    @State private var lookupID = UUID()
    @State private var initialized = false
    @State private var episodeChangedByUser = false
    @State private var sourceInformation: StremioStream?
    @FocusState private var episodeFocused: Bool
    private var limit: Int { anime.format == "MOVIE" ? 1 : min(100_000, max(1, anime.episodes.flatMap { $0 > 0 ? $0 : nil } ?? 100_000)) }
    private var initializationKey: String {
        "\(anime.id)-\(store.isSignedIn)-\(store.loadingLibrary)-\(store.entry(for: anime.id)?.progressValue ?? -1)-\(store.libraryError ?? "")"
    }
    private var audioFilter: StreamAudioFilter { StreamAudioFilter(rawValue: audioFilterValue) ?? .all }
    private var visible: [Int] {
        StreamSourceSelection.indices(in: streams, audio: audioFilter, playableOnly: playableOnly, search: filter)
    }
    var body: some View {
        let visibleSources = visible
        NavigationStack {
            List {
                Section {
                    Text(anime.displayTitle).font(.title3.bold())
                    if anime.format != "MOVIE" {
                        if initialized {
                            episodeControls
                            if let entry = store.entry(for: anime.id) {
                                Text("AniList · \(entry.progressValue) episodes watched").font(.caption).foregroundStyle(.secondary)
                                    .accessibilityIdentifier("playback-anilist-progress")
                                if let total = anime.episodes, total > 0, entry.progressValue >= total {
                                    Text("All known episodes are watched. Choose an episode to replay.").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        } else { ProgressView("Loading AniList progress…") }
                    }
                    if let notice = store.libraryError {
                        Text("AniList progress could not refresh: \(notice) Choose the episode manually if needed.")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    if let saved = playback.saved(animeID: anime.id, episode: episode) {
                        if saved.finished { Label("Finished in VidHub on this device", systemImage: "checkmark.circle").foregroundStyle(.mint) }
                        else if saved.position > 0 {
                            Text("Resume at \(timeLabel(saved.position))").font(.subheadline)
                                .accessibilityIdentifier("playback-resume-position")
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
                if let error {
                    Section {
                        NoticeView(message: error) { loadSources() }
                        if !streams.isEmpty { Text("Showing the previously loaded sources for episode \(episode).").font(.caption).foregroundStyle(.secondary) }
                    }
                }
                if let message = playback.playerMessage {
                    Section("Playback") {
                        Text(message).font(.subheadline)
                        if playback.saved(animeID: anime.id, episode: episode)?.finished == true && store.isSignedIn {
                            Button("Mark episode watched on AniList") { markWatched() }
                                .disabled(store.loadingLibrary || store.savingMedia.contains(anime.id))
                        }
                    }
                }
                if searched {
                    Section("Sources · \(streams.count)") {
                        if streams.isEmpty {
                            Text("No sources were returned for this episode. Check your AIOStreams providers or try another episode.")
                                .foregroundStyle(.secondary).accessibilityIdentifier("playback-empty-results")
                        } else {
                            audioControls
                            DisclosureGroup("Source options", isExpanded: $sourceOptionsExpanded) {
                                TextField("Search source details", text: $filter).autocorrectionDisabled()
                                    .accessibilityIdentifier("playback-source-search")
                                Toggle("Playable sources only", isOn: $playableOnly)
                            }
                            if visibleSources.isEmpty {
                                Text(audioFilter == .english ? "No sources match English audio. Sources with unlisted languages may still include it." : "No sources match these audio or search filters.")
                                    .font(.subheadline).foregroundStyle(.secondary)
                                Button("Show all sources") { audioFilterValue = StreamAudioFilter.all.rawValue; filter = ""; playableOnly = false }
                                    .accessibilityIdentifier("playback-reset-source-filters")
                            }
                            ForEach(visibleSources, id: \.self) { index in
                                let stream = streams[index]
                                let sourceEpisode = episode
                                PlaybackSourceRow(stream: stream, index: index,
                                    preferred: index == visibleSources.first && stream.unavailableReason == nil,
                                    openingPlayer: playback.openingPlayer,
                                    play: { play(stream, expectedEpisode: sourceEpisode) }, information: { sourceInformation = stream })
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
                        if skipped > 0 { Text("\(skipped) malformed source entries were skipped.").font(.caption).foregroundStyle(.secondary) }
                    }
                    Section {
                        DisclosureGroup("Playback information") {
                            Text("Tap a source to open VidHub. Touch and hold for subtitles or to play from the beginning.")
                            Text("Audio labels come from each source's reported languages, names and filename. English subtitles alone do not indicate English audio. Multi audio without named languages stays unconfirmed.")
                            Text("VidHub resume is saved on this device. AniList progress changes only when you use the watched-progress controls.")
                        }
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
                .task(id: initializationKey) { initializeEpisode() }
                .sheet(isPresented: Binding(get: { sourceInformation != nil }, set: { if !$0 { sourceInformation = nil } })) {
                    if let sourceInformation { SourceInformationView(stream: sourceInformation) }
                }
                .onChange(of: playback.enabled) { _, _ in resetSources(); loadSources() }
                .onChange(of: playback.addon?.endpoint) { _, _ in resetSources(); loadSources() }
                .onDisappear {
                    searchTask?.cancel()
                    if loading { lookupID = UUID(); loading = false }
                }
        }.disabled(playback.openingPlayer)
    }
    private var audioControls: some View {
        let playable = streams.filter { $0.unavailableReason == nil }
        let audio = playable.map { StreamSourceMetadata(stream: $0).audio }
        let englishCount = audio.filter(\.english).count
        let unlisted = audio.filter { !$0.english && !$0.japanese }.count
        return VStack(alignment: .leading, spacing: 10) {
            Text(englishCount > 0 ? "English audio · \(englishCount) playable \(englishCount == 1 ? "source" : "sources")" : "No playable English source listed")
                .font(.headline).foregroundStyle(englishCount > 0 ? Color.green : Color.secondary)
                .accessibilityIdentifier("playback-english-availability")
            if unlisted > 0 {
                Text("\(unlisted) \(unlisted == 1 ? "source does" : "sources do") not confirm an audio language. Open source information to review the original text.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Picker("Audio language", selection: $audioFilterValue) {
                ForEach(StreamAudioFilter.allCases, id: \.self) { Text($0.label).tag($0.rawValue) }
            }.pickerStyle(.segmented).accessibilityIdentifier("playback-audio-filter")
        }.padding(.vertical, 4)
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
        if !searched && !loading { loadSources() }
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
        searchTask?.cancel(); lookupID = UUID(); streams = []; skipped = 0; searched = false; loading = false; error = nil; filter = ""
    }
    private func loadSources() {
        guard initialized, let addon = playback.addon, playback.enabled else { return }
        searchTask?.cancel()
        let attempt = UUID(); lookupID = attempt
        let requestedEpisode = episode
        loading = true; error = nil
        searchTask = Task {
            defer { if lookupID == attempt { loading = false } }
            do {
                let result = try await playback.client.streams(addon: addon, anime: anime, episode: requestedEpisode)
                try Task.checkCancellation(); guard lookupID == attempt else { return }
                streams = result.streams; skipped = result.skippedCount; searched = true
            } catch is CancellationError {} catch { if lookupID == attempt { self.error = error.localizedDescription } }
        }
    }
    private func play(_ stream: StremioStream, expectedEpisode: Int, subtitle: URL? = nil, fromBeginning: Bool? = nil) {
        guard expectedEpisode == episode else { return }
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

private struct SourceInformationView: View {
    let stream: StremioStream
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section(stream.displayName) {
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

