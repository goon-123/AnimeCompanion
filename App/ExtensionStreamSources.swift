import SwiftUI
import AnimeCore

@MainActor
final class AnymeXStreamClient: ExtensionStreamClient {
    let store = UnifiedExtensionStore()
    func search(source: UnifiedExtensionSource, query: String) async throws -> ExtensionMediaPage {
        try await store.request("browse", source: source, arguments: ["mode": "search", "query": query, "page": 1])
    }
    func detail(source: UnifiedExtensionSource, media: ExtensionMedia) async throws -> ExtensionMedia {
        try await store.request("detail", source: source, arguments: ["media": media.payload.foundation])
    }
    func videos(source: UnifiedExtensionSource, episode: ExtensionEpisode) async throws -> [ExtensionVideo] {
        try await store.request("videos", source: source, arguments: ["episode": episode.payload.foundation])
    }
}

@MainActor
final class ExtensionStreamModel: ObservableObject {
    @Published private(set) var sources: [UnifiedExtensionSource] = []
    @Published private(set) var results: [String: ExtensionStreamResult] = [:]
    @Published private(set) var loading = false
    @Published private(set) var searched = false
    @Published private(set) var error: String?
    let client = AnymeXStreamClient()
    private var task: Task<Void, Never>?
    private(set) var generation = UUID()
    func cancel(clear: Bool = false) {
        task?.cancel(); generation = UUID(); loading = false
        if clear { sources = []; results = [:]; searched = false; error = nil }
    }
    func search(anime: Anime, episode: Int, includeAdult: Bool) {
        cancel(clear: true)
        let attempt = generation
        loading = true
        task = Task {
            defer { if generation == attempt { loading = false; searched = true } }
            do {
                let snapshot: UnifiedExtensionSnapshot = try await client.store.runtime.call("snapshot")
                try Task.checkCancellation()
                guard generation == attempt else { return }
                sources = snapshot.installed.filter { $0.kind == .anime && ($0.isNsfw != true || includeAdult) }
                let installed = sources
                await withTaskGroup(of: ExtensionStreamResult?.self) { group in
                    var next = 0
                    func enqueue(_ source: UnifiedExtensionSource) {
                        group.addTask { [client] in
                            do { return try await ExtensionStreamLookup.resolve(source: source, anime: anime, episode: episode, client: client) }
                            catch is CancellationError { return nil }
                            catch { return .init(source: source, message: "This source could not complete the search. Retry or choose a title manually.") }
                        }
                    }
                    while next < min(3, installed.count) { enqueue(installed[next]); next += 1 }
                    for await result in group {
                        guard !Task.isCancelled, generation == attempt else { group.cancelAll(); break }
                        if let result { results[result.id] = result }
                        if next < installed.count { enqueue(installed[next]); next += 1 }
                    }
                }
            } catch is CancellationError {} catch {
                if generation == attempt { self.error = "Anime extensions could not load. Open Manage extensions to check your installed sources, then reload." }
            }
        }
    }
    func accept(_ result: ExtensionStreamResult, generation attempt: UUID) {
        guard generation == attempt else { return }
        results[result.id] = result
    }
    var englishDirect: Int {
        results.values.flatMap(\.videos).filter { !$0.isMagnet && $0.canPlay && ((try? $0.stream(sourceName: "" )).map { StreamSourceMetadata(stream: $0).audio.english } ?? false) }.count
    }
}

struct ExtensionStreamSources: View {
    @ObservedObject var model: ExtensionStreamModel
    @EnvironmentObject private var playback: PlaybackStore
    @ObservedObject private var runtime = AnymeXRuntime.shared
    let anime: Anime
    let episode: Int
    let restart: Bool
    let kind: String
    let query: String
    let audio: StreamAudioFilter
    let playableOnly: Bool
    let reload: () -> Void
    @State private var matching: UnifiedExtensionSource?
    @State private var managing = false
    @State private var opening = false
    @State private var playError: String?
    private func visible(_ videos: [ExtensionVideo], source: UnifiedExtensionSource) -> [Int] {
        videos.indices.filter { index in
            let video = videos[index]
            guard kind == "all" || (kind == "torrents" ? video.isMagnet : !video.isMagnet),
                  !playableOnly || video.canPlay, let stream = try? video.stream(sourceName: source.label),
                  audio.includes(StreamSourceMetadata(stream: stream).audio) else { return false }
            let text = [source.label, video.title ?? "", video.quality].joined(separator: " ")
            return query.isEmpty || text.localizedCaseInsensitiveContains(query)
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                StreamPickerHeading(title: "Extension sources", count: model.sources.reduce(0) { $0 + visible(model.results[$1.id]?.videos ?? [], source: $1).count }, loading: model.loading)
                Spacer()
                Button { managing = true } label: { Image(systemName: "puzzlepiece.extension") }
                    .accessibilityLabel("Manage anime extensions")
            }
            if let error = model.error { StreamPickerCard { Text(error).font(.caption).foregroundStyle(.orange); Button("Retry extensions", action: reload) } }
            if model.loading && model.sources.isEmpty { ProgressView("Loading installed anime extensions…").font(.caption) }
            if model.searched && model.sources.isEmpty && model.error == nil {
                StreamPickerCard {
                    Text("Install an anime source to include its streams here.").font(.caption).foregroundStyle(.secondary)
                    Button("Manage extensions") { managing = true }
                }
            }
            ForEach(model.sources) { source in
                StreamPickerCard {
                    HStack { Text(source.label).font(.headline); Spacer(); if model.results[source.id] == nil && model.loading { ProgressView() } }
                    if let result = model.results[source.id] {
                        if let message = result.message { Text(message).font(.caption).foregroundStyle(.secondary) }
                        let indices = visible(result.videos, source: source)
                        if !result.videos.isEmpty && indices.isEmpty { Text("No extension streams match these filters.").font(.caption).foregroundStyle(.secondary) }
                        ForEach(indices, id: \.self) { index in
                            videoRow(result.videos[index], source: source)
                        }
                        Button("Choose title or episode") { matching = source }.font(.caption)
                    } else { Text("Searching this anime and episode…").font(.caption).foregroundStyle(.secondary) }
                }
            }
            if opening { ProgressView("Opening video…") }
            if let playError { Text(playError).font(.caption).foregroundStyle(.orange) }
        }.accessibilityIdentifier("extension-stream-sources")
            .sheet(isPresented: $managing, onDismiss: reload) {
                AppNavigationStack {
                    UnifiedExtensionsView(initialKind: .anime)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { managing = false } } }
                }
            }
            .sheet(item: $matching) { source in
                ExtensionStreamMatchView(client: model.client, source: source, anime: anime, episode: episode) { result, attempt in
                    model.accept(result, generation: attempt); matching = nil
                } generation: { model.generation }
            }
            .fullScreenCover(isPresented: Binding(get: { !managing && runtime.showingPlayer }, set: { runtime.showingPlayer = $0 }), onDismiss: { runtime.stopVideo() }) { AnymeXPlayerContainer().ignoresSafeArea() }
            .sheet(item: Binding(get: { matching == nil && !managing ? runtime.website : nil }, set: { runtime.website = $0 }), onDismiss: { runtime.finishWebsite() }) { request in
                ExtensionWebsiteSessionView(request: request)
            }
    }
    @ViewBuilder private func videoRow(_ video: ExtensionVideo, source: UnifiedExtensionSource) -> some View {
        if video.isMagnet {
            ExtensionTorBoxVideo(video: video, title: anime.displayTitle, anime: anime, episode: episode, restart: restart)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text([video.title, video.quality].compactMap { $0 }.joined(separator: " · ")).font(.subheadline.weight(.semibold))
                if let stream = try? video.stream(sourceName: source.label) { PlaybackAudioBadge(audio: StreamSourceMetadata(stream: stream).audio) }
                if video.headers?.isEmpty == false { Text("Plays in the app with this source’s video headers.").font(.caption).foregroundStyle(.secondary) }
                Button { Task { await play(video, source: source) } } label: {
                    Label(video.headers?.isEmpty == false ? "Play here" : "Play in \(playback.player.label)", systemImage: "play.fill")
                }.disabled(opening || !video.canPlay)
                ForEach(Array((video.subtitles ?? []).enumerated()), id: \.offset) { _, subtitle in
                    if video.headers?.isEmpty != false, let url = StremioStream.networkURL(subtitle.file) {
                        Button("Play with \(subtitle.label ?? "selected") subtitles") { Task { await play(video, source: source, subtitle: url) } }.font(.caption).disabled(opening || !video.canPlay)
                    }
                }
                if !video.canPlay { Text("This source did not return a supported video URL.").font(.caption).foregroundStyle(.orange) }
            }.padding(.vertical, 8)
        }
    }
    private func play(_ video: ExtensionVideo, source: UnifiedExtensionSource, subtitle: URL? = nil) async {
        opening = true; playError = nil
        defer { opening = false }
        do {
            if video.headers?.isEmpty == false { try await runtime.playInline(video, title: "\(anime.displayTitle) · Episode \(episode)") }
            else { await playback.play(stream: try video.stream(sourceName: source.label), anime: anime, episode: episode,
                                       subtitle: subtitle ?? video.subtitles?.first.flatMap { StremioStream.networkURL($0.file) }, restart: restart) }
        } catch { playError = "The video could not open. Try another stream." }
    }
}

/// An explicit match stays in the stream picker and retains AniList context.
private struct ExtensionStreamMatchView: View {
    let client: AnymeXStreamClient
    let source: UnifiedExtensionSource
    let anime: Anime
    let episode: Int
    let completion: (ExtensionStreamResult, UUID) -> Void
    let generation: () -> UUID
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var runtime = AnymeXRuntime.shared
    @State private var query = ""
    @State private var submitted = ""
    @State private var media: [ExtensionMedia] = []
    @State private var detail: ExtensionMedia?
    @State private var selected: ExtensionEpisode?
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        AppNavigationStack {
            List {
                Section { Text("Match \(anime.displayTitle) · Episode \(episode)").font(.subheadline) }
                if busy { ProgressView("Checking \(source.label)…") }
                if let error { Text(error).foregroundStyle(.orange) }
                if let detail {
                    Section(detail.title) {
                        Button("Choose another title") { self.detail = nil }
                        if !busy && detail.episodes.isEmpty { Text("This source returned no episodes for this title.").foregroundStyle(.secondary) }
                        ForEach(Array(detail.episodes.enumerated()), id: \.offset) { _, item in
                            Button(item.label) { selected = item }.disabled(busy)
                        }
                    }
                } else {
                    ForEach(Array(media.enumerated()), id: \.offset) { _, item in
                        Button(item.title) { detail = item }.disabled(busy)
                    }
                    if !busy && media.isEmpty { Text("No matches. Try an English or romaji title.").foregroundStyle(.secondary) }
                }
            }.navigationTitle(source.label).navigationBarTitleDisplayMode(.inline)
                .searchable(text: $query, prompt: "Search this source")
                .onSubmit(of: .search) { detail = nil; submitted = query }
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
                .task(id: submitted) {
                    busy = true; error = nil
                    defer { busy = false }
                    do { media = try await client.search(source: source, query: submitted.isEmpty ? anime.displayTitle : submitted).list }
                    catch is CancellationError {} catch { self.error = "This source could not search. Try again." }
                }
                .task(id: detail?.id) {
                    guard let item = detail, item.episodes.isEmpty else { return }
                    busy = true; error = nil
                    defer { busy = false }
                    do { let loaded = try await client.detail(source: source, media: item); try Task.checkCancellation(); detail = loaded }
                    catch is CancellationError {} catch { self.error = "The episode list could not load. Choose another title to retry." }
                }
                .task(id: selected?.id) {
                    guard let selected else { return }
                    let attempt = generation()
                    busy = true; error = nil
                    defer { busy = false; self.selected = nil }
                    do {
                        let videos = try await client.videos(source: source, episode: selected)
                        try Task.checkCancellation()
                        completion(.init(source: source, videos: videos, message: videos.isEmpty ? "This episode returned no videos." : nil), attempt)
                    } catch is CancellationError {} catch { self.error = "Videos could not load. Try this episode again." }
                }
                .onAppear { query = anime.displayTitle }
                .sheet(item: $runtime.website, onDismiss: { runtime.finishWebsite() }) { ExtensionWebsiteSessionView(request: $0) }
        }
    }
}
