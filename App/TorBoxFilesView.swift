import SwiftUI
import AnimeCore

struct TorBoxFilesView: View {
    @Environment(\.dismiss) private var dismiss
    var anime: Anime? = nil
    var episode = 1
    var restart = false
    var body: some View {
        NavigationStack {
            folder(nil)
                .navigationDestination(for: TorBoxWebDAVEntry.self) { entry in folder(entry) }
        }
    }
    private func folder(_ entry: TorBoxWebDAVEntry?) -> some View {
        TorBoxFolderView(folder: entry, anime: anime, episode: episode, restart: restart, close: { dismiss() })
    }
}

private struct TorBoxFolderView: View {
    @EnvironmentObject private var seanime: SeanimeStore
    @EnvironmentObject private var playback: PlaybackStore
    let folder: TorBoxWebDAVEntry?
    let anime: Anime?
    let episode: Int
    let restart: Bool
    let close: () -> Void
    @State private var entries: [TorBoxWebDAVEntry] = []
    @State private var query = ""
    @State private var key = ""
    @State private var loading = false
    @State private var error: String?
    @State private var message: String?
    @State private var generation = UUID()
    @State private var loadedRevision: UUID?
    @State private var work: Task<Void, Never>?
    @State private var playWork: Task<Void, Never>?
    @FocusState private var enteringKey: Bool
    private var visible: [TorBoxWebDAVEntry] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? entries : entries.filter { $0.name.localizedStandardContains(text) }
    }
    var body: some View {
        List {
            if !seanime.hasTorBoxKey {
                Section("Connect TorBox") {
                    SecureField("TorBox API key", text: $key).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .focused($enteringKey).submitLabel(.go).onSubmit { connect() }
                        .accessibilityIdentifier("webdav-torbox-key")
                    Button("Connect TorBox") { connect() }
                        .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("webdav-connect-torbox")
                    Link("Find your TorBox API key", destination: URL(string: "https://torbox.app/settings")!)
                    Text("Use your TorBox API key to browse files. A Seanime extension is not required.").font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Section {
                    if let anime { Text("\(anime.displayTitle) · Episode \(episode)").font(.subheadline) }
                    Text("Browse your TorBox folders and tap a video to open it in VidHub.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text("Uses your saved TorBox key. Play sends the file’s private WebDAV address to VidHub.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if loading && entries.isEmpty { ProgressView("Loading TorBox files…").accessibilityIdentifier("torbox-webdav-loading") }
                if let error { Text(error).foregroundStyle(.orange).accessibilityIdentifier("torbox-webdav-error") }
                Section {
                    ForEach(visible) { entry in
                        if entry.isDirectory {
                            NavigationLink(value: entry) { row(entry) }
                                .accessibilityIdentifier("torbox-webdav-folder-\(entry.url.lastPathComponent)")
                        } else if entry.isVideo {
                            Button { play(entry) } label: { row(entry) }
                                .disabled(playback.openingPlayer)
                                .accessibilityIdentifier("torbox-webdav-video-\(entry.url.lastPathComponent)")
                        } else { row(entry).foregroundStyle(.secondary) }
                    }
                }
                if !loading && visible.isEmpty && error == nil {
                    ContentUnavailableView(query.isEmpty ? "This folder is empty" : "No matching files", systemImage: "folder",
                                           description: Text(query.isEmpty ? "Refresh to check for recently added files." : "Try another filename in this folder."))
                }
                if let message { Text(message).font(.caption).accessibilityIdentifier("torbox-webdav-player-message") }
            }
        }.accessibilityIdentifier("torbox-webdav-list")
            .navigationTitle(folder?.name ?? "TorBox files").navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Search this folder")
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { work?.cancel(); work = Task { await load(refresh: true) } } label: { Image(systemName: "arrow.clockwise") }
                        .disabled(loading || !seanime.hasTorBoxKey).accessibilityLabel("Refresh TorBox files")
                        .accessibilityIdentifier("torbox-webdav-refresh")
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done", action: close) }
            }
            .task(id: seanime.revision) {
                if loadedRevision != seanime.revision { entries = []; loadedRevision = seanime.revision }
                await load()
            }
            .refreshable { await load(refresh: true) }
            .onDisappear { generation = UUID(); work?.cancel(); playWork?.cancel(); key = "" }
    }
    private func connect() { if seanime.saveKey(key) { key = ""; enteringKey = false } }
    private func row(_ entry: TorBoxWebDAVEntry) -> some View {
        HStack(spacing: 12) {
            Image(systemName: entry.isDirectory ? "folder.fill" : entry.isVideo ? "play.rectangle.fill" : "doc")
                .font(.title2).foregroundStyle(entry.isDirectory ? Color.yellow : entry.isVideo ? Color.mint : Color.secondary)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 5) {
                Text(entry.name).font(.body).foregroundStyle(.primary).lineLimit(3)
                if !entry.isDirectory {
                    HStack {
                        if let size = entry.size { Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)) }
                        Text(entry.isVideo ? "Play in VidHub" : "Document")
                    }.font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }.padding(.vertical, 6)
    }
    private func load(refresh: Bool = false) async {
        let attempt = UUID(); generation = attempt
        guard seanime.hasTorBoxKey else { entries = []; loading = false; error = nil; return }
        loading = true; error = nil
        defer { if generation == attempt { loading = false } }
        do {
            let client = try seanime.webDAV()
            if refresh { try await client.refreshIndex() }
            let values = try await client.list(folder: folder?.url ?? TorBoxWebDAVClient.root)
            try Task.checkCancellation(); guard generation == attempt else { return }
            entries = values
        } catch is CancellationError {} catch { if generation == attempt { self.error = error.localizedDescription } }
    }
    private func play(_ entry: TorBoxWebDAVEntry) {
        guard !playback.openingPlayer, seanime.hasTorBoxKey else { return }
        playWork?.cancel(); error = nil; message = nil
        playWork = Task {
            do {
                let url = try seanime.webDAV().playbackURL(for: entry)
                let data = try JSONSerialization.data(withJSONObject: ["name": entry.name, "url": url.absoluteString, "behaviorHints": ["filename": entry.name]])
                let stream = try JSONDecoder().decode(StremioStream.self, from: data)
                try Task.checkCancellation()
                if let anime { await playback.play(stream: stream, anime: anime, episode: episode, subtitle: nil, restart: restart) }
                else { await playback.playUntracked(stream: stream, title: entry.name) }
                if !Task.isCancelled { message = playback.playerMessage ?? "Opened in VidHub." }
            } catch is CancellationError {} catch { self.error = error.localizedDescription }
        }
    }
}
