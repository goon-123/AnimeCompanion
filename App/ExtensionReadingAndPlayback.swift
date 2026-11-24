import SwiftUI
import WebKit
import CryptoKit
import AnimeCore

@MainActor
final class ExtensionSavedLibrary: ObservableObject {
    static let shared = ExtensionSavedLibrary()
    struct Entry: Codable, Identifiable {
        let source: UnifiedExtensionSource
        let media: ExtensionMedia
        var id: String { source.id + ":" + media.id }
    }
    @Published private(set) var entries: [Entry] = []
    @Published private var read: Set<String> = []
    private var observer: NSObjectProtocol?
    private init() {
        reload()
        observer = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.reload() } }
    }
    private func reload() {
        entries = (UserDefaults.standard.data(forKey: "extensions.savedTitles").flatMap { try? JSONDecoder().decode([Entry].self, from: $0) }) ?? []
        read = Set(UserDefaults.standard.stringArray(forKey: "extensions.readChapters") ?? [])
    }
    func contains(_ source: UnifiedExtensionSource, _ media: ExtensionMedia) -> Bool { entries.contains { $0.source.id == source.id && $0.media.id == media.id } }
    func toggle(source: UnifiedExtensionSource, media: ExtensionMedia) {
        if contains(source, media) { entries.removeAll { $0.source.id == source.id && $0.media.id == media.id } }
        else { entries.insert(Entry(source: source, media: media), at: 0); entries = Array(entries.prefix(1000)) }
        if let data = try? JSONEncoder().encode(entries), data.count < 8_000_000 { UserDefaults.standard.set(data, forKey: "extensions.savedTitles") }
    }
    private func chapterKey(_ source: UnifiedExtensionSource, _ chapter: ExtensionEpisode) -> String {
        SHA256.hash(data: Data((source.id + ":" + chapter.id).utf8)).map { String(format: "%02x", $0) }.joined()
    }
    func isRead(_ source: UnifiedExtensionSource, _ chapter: ExtensionEpisode) -> Bool { read.contains(chapterKey(source, chapter)) }
    func toggleRead(_ source: UnifiedExtensionSource, _ chapter: ExtensionEpisode) {
        let key = chapterKey(source, chapter)
        if read.contains(key) { read.remove(key) } else { read.insert(key) }
        UserDefaults.standard.set(Array(read.prefix(10000)), forKey: "extensions.readChapters")
    }
}

struct ExtensionSavedTitlesView: View {
    @EnvironmentObject private var store: UnifiedExtensionStore
    @EnvironmentObject private var preferences: AppStore
    @ObservedObject private var library = ExtensionSavedLibrary.shared
    private var visibleEntries: [ExtensionSavedLibrary.Entry] {
        library.entries.filter { $0.source.isVisible(includeAdultAnime: preferences.includeAdult, readingContent: preferences.mangaBakaContent) }
    }
    var body: some View {
        List {
            ForEach(visibleEntries) { entry in
                if store.snapshot.installed.contains(where: { $0.id == entry.source.id }) {
                    NavigationLink { ExtensionContentAccess(source: entry.source) { ExtensionMediaDetailView(source: entry.source, media: entry.media).environmentObject(store) } } label: { Text(entry.media.title) }
                } else { VStack(alignment: .leading) { Text(entry.media.title); Text("Install \(entry.source.label) to open this title.").font(.caption).foregroundStyle(.secondary) } }
            }.onDelete { indices in
                let removed = indices.map { visibleEntries[$0] }
                for entry in removed { library.toggle(source: entry.source, media: entry.media) }
            }
            if library.entries.isEmpty { ContentUnavailableView("No saved titles", systemImage: "bookmark", description: Text("Save a title from an extension to find it here.")) }
        }.navigationTitle("Saved extension titles")
    }
}

struct ExtensionChapterView: View {
    @EnvironmentObject private var store: UnifiedExtensionStore
    @EnvironmentObject private var playback: PlaybackStore
    @ObservedObject private var library = ExtensionSavedLibrary.shared
    let source: UnifiedExtensionSource
    let media: ExtensionMedia
    let episode: ExtensionEpisode
    @State private var images: [ExtensionImagePage] = []
    @State private var videos: [ExtensionVideo] = []
    @State private var novel = ""
    @State private var loading = false
    @State private var opening = false
    @State private var error: String?
    @State private var pageNumber = 0
    private var positionKey: String { "extensions.position." + SHA256.hash(data: Data((source.id + ":" + episode.id).utf8)).map { String(format: "%02x", $0) }.joined() }
    var body: some View {
        ScrollViewReader { reader in
            ScrollView {
                LazyVStack(spacing: source.kind == .manga ? 0 : 20) {
                    if loading { ProgressView(source.kind == .anime ? "Finding video sources…" : "Loading chapter…").padding(24) }
                    if let error { VStack { Text(error).foregroundStyle(.orange); Button("Retry") { Task { await load() } } }.padding() }
                    if source.kind == .anime { videoChoices }
                    else if source.kind == .novel {
                        ForEach(Array(novel.components(separatedBy: "\n\n").enumerated()), id: \.offset) { index, paragraph in
                            Text(paragraph).font(.system(size: 20)).lineSpacing(8).frame(maxWidth: 760, alignment: .leading).padding(.horizontal, 22).id(index)
                                .onAppear { pageNumber = index; UserDefaults.standard.set(index, forKey: positionKey) }
                        }
                    } else {
                        ForEach(Array(images.enumerated()), id: \.offset) { index, page in
                            ExtensionRemoteImage(url: page.url, headers: page.headers ?? [:], expands: true)
                                .frame(maxWidth: 1000).frame(maxWidth: .infinity).id(index)
                                .onAppear { pageNumber = index; UserDefaults.standard.set(index, forKey: positionKey) }
                        }
                    }
                    if !loading && source.kind != .anime {
                        Button(library.isRead(source, episode) ? "Mark unread" : "Mark chapter read") { library.toggleRead(source, episode) }.buttonStyle(.bordered).padding(24)
                    }
                }.padding(.vertical, source.kind == .novel ? 20 : 0)
            }.background(Theme.background)
                .task {
                    let saved = UserDefaults.standard.integer(forKey: positionKey)
                    await load()
                    if saved > 0 { try? await Task.sleep(for: .milliseconds(150)); reader.scrollTo(saved, anchor: .top) }
                }
        }.navigationTitle(episode.label).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { library.toggleRead(source, episode) } label: { Image(systemName: library.isRead(source, episode) ? "checkmark.circle.fill" : "checkmark.circle") }.accessibilityLabel("Toggle read or watched") } }
    }
    @ViewBuilder private var videoChoices: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(media.title).font(.headline)
            if videos.isEmpty && !loading && error == nil { Text("This source returned no playable videos. Try another source or episode.").foregroundStyle(.secondary) }
            if opening { ProgressView("Opening video…") }
            ForEach(Array(videos.enumerated()), id: \.offset) { _, video in
                if video.url.lowercased().hasPrefix("magnet:") {
                    ExtensionTorBoxVideo(video: video, title: media.title)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Button { Task { await play(video, inline: video.headers?.isEmpty == false) } } label: {
                            Label(video.title ?? video.quality, systemImage: "play.circle.fill").frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(.borderedProminent).disabled(opening)
                        HStack {
                            Button("Play here") { Task { await play(video, inline: true) } }.disabled(opening)
                            if video.headers?.isEmpty != false { Button("Open in \(playback.player.label)") { Task { await play(video, inline: false) } }.disabled(opening) }
                        }.font(.caption)
                    }
                }
            }
            if let message = playback.playerMessage { Text(message).font(.caption).foregroundStyle(.secondary) }
        }.padding(18)
    }
    private func load() async {
        loading = true; error = nil
        defer { loading = false }
        do {
            switch source.kind {
            case .anime: videos = try await store.request("videos", source: source, arguments: ["episode": episode.payload.foundation])
            case .manga: images = try await store.request("pages", source: source, arguments: ["episode": episode.payload.foundation])
            case .novel:
                let text: String? = try await store.request("novel", source: source, arguments: ["title": episode.label, "url": episode.id])
                novel = TextSanitizer.synopsis(text ?? "")
                if novel.isEmpty { throw ServiceError.message("This source returned an empty chapter.") }
            }
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
    private func play(_ video: ExtensionVideo, inline: Bool) async {
        opening = true; error = nil
        defer { opening = false }
        do {
            if inline { try await store.runtime.playInline(video, title: "\(media.title) · \(episode.label)") }
            else {
                let data = try JSONSerialization.data(withJSONObject: ["name": source.label, "title": video.title ?? video.quality, "url": video.url])
                let stream = try JSONDecoder().decode(StremioStream.self, from: data)
                await playback.playUntracked(stream: stream, title: "\(media.title) · \(episode.label)", subtitle: video.subtitles?.first?.file.flatMap(URL.init(string:)))
            }
        } catch { self.error = error.localizedDescription }
    }
}

struct ExtensionRemoteImage: View {
    let url: String?
    var headers: [String: String] = [:]
    var expands = false
    @State private var image: UIImage?
    @State private var failed = false
    @State private var retry = 0
    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFit() }
            else if expands {
                VStack(spacing: 12) {
                    if failed { Image(systemName: "photo.badge.exclamationmark"); Button("Retry page") { retry += 1 } }
                    else { ProgressView() }
                }.frame(maxWidth: .infinity).frame(minHeight: 360)
            } else { Rectangle().fill(.quaternary).overlay { Image(systemName: "photo").foregroundStyle(.tertiary) } }
        }.task(id: (url ?? "") + ":\(retry)") {
            image = nil; failed = false
            guard let url, let address = URL(string: url), ["https", "http"].contains(address.scheme?.lowercased() ?? "") else { failed = true; return }
            do {
                var request = URLRequest(url: address, timeoutInterval: 30)
                for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
                let (bytes, response) = try await URLSession.shared.data(for: request)
                try Task.checkCancellation()
                guard let response = response as? HTTPURLResponse, (200...299).contains(response.statusCode), bytes.count <= 32_000_000,
                      let decoded = UIImage(data: bytes) else { failed = true; return }
                image = decoded
            } catch is CancellationError {} catch { failed = true }
        }
    }
}

struct ExtensionTorBoxVideo: View {
    @EnvironmentObject private var seanime: SeanimeStore
    @EnvironmentObject private var playback: PlaybackStore
    let video: ExtensionVideo
    let title: String
    var anime: Anime? = nil
    var episode: Int = 1
    var restart = false
    @State private var torrent: TorBoxTorrent?
    @State private var job: TorBoxJob?
    @State private var busy = false
    @State private var error: String?
    private var savedKey: String { "extensions.torbox." + SHA256.hash(data: Data(video.url.utf8)).map { String(format: "%02x", $0) }.joined() }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(video.title ?? video.quality).font(.headline)
            if !seanime.hasTorBoxKey { NavigationLink("Connect TorBox") { TorBoxSettingsView() } }
            else {
                Button(job == nil ? "Check cached copy on TorBox" : "Refresh TorBox files") { Task { await resolve(cachedOnly: true) } }.disabled(busy)
                if job == nil { Button("Download with TorBox") { Task { await resolve(cachedOnly: false) } }.disabled(busy) }
            }
            if busy { ProgressView("Checking TorBox…") }
            if let torrent, torrent.ready {
                ForEach(torrent.videoFiles) { file in
                    Button(file.short_name ?? file.name) { Task {
                        do {
                            let url = try await seanime.torBox().download(torrent: torrent, fileID: file.id)
                            let data = try JSONSerialization.data(withJSONObject: ["url": url.absoluteString, "name": "TorBox"])
                            let stream = try JSONDecoder().decode(StremioStream.self, from: data)
                            if let anime { await playback.play(stream: stream, anime: anime, episode: episode, restart: restart) }
                            else { await playback.playUntracked(stream: stream, title: title) }
                        } catch { self.error = error.localizedDescription }
                    } }
                }
            } else if job != nil { Text("TorBox is preparing this release. Refresh to check its files; the request is saved if you leave.").font(.caption).foregroundStyle(.secondary) }
            if let error { Text(error).font(.caption).foregroundStyle(.orange) }
        }.padding().background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
            .task { if let data = UserDefaults.standard.data(forKey: savedKey) { job = try? JSONDecoder().decode(TorBoxJob.self, from: data) } }
    }
    private func resolve(cachedOnly: Bool) async {
        busy = true; error = nil
        defer { busy = false }
        do {
            let client = try seanime.torBox()
            if job == nil {
                job = try await client.add(magnet: video.url, cachedOnly: cachedOnly)
                if let job { UserDefaults.standard.set(try JSONEncoder().encode(job), forKey: savedKey) }
            }
            if let job { torrent = try await client.resolve(job) }
        } catch { self.error = error.localizedDescription }
    }
}
