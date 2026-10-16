import SwiftUI
import AnimeCore

/// Expands in the result list. File selection and player handoff stay on the
/// search screen, while accepted/uncertain submissions survive closing it.
struct TorBoxPlaybackControls: View {
    @EnvironmentObject private var seanime: SeanimeStore
    @EnvironmentObject private var playback: PlaybackStore
    @EnvironmentObject private var store: AppStore
    @Environment(\.scenePhase) private var scenePhase
    let providerID: UUID
    let torrent: SeanimeTorrent
    let anime: Anime?
    let episode: Int
    var restart = false
    @State private var needsDownload = false
    @State private var forgetConfirmed = false
    @State private var job: TorBoxJob?
    @State private var cloud: TorBoxTorrent?
    @State private var busy = false
    @State private var activity = "Checking existing files…"
    @State private var checked = false
    @State private var magnet: String?
    @State private var error: String?
    @State private var work: Task<Void, Never>?
    @State private var statusWork: Task<Void, Never>?
    @State private var runner: SeanimeRunner?
    @State private var generation = UUID()
    private var provider: SeanimeInstallation? {
        seanime.installations.first { $0.id == providerID && $0.enabled && (store.includeAdult || !$0.adult) }
    }
    private var progress: Double? {
        guard let value = cloud?.progress, value.isFinite else { return nil }
        return min(1, max(0, value))
    }
    private var status: String {
        if cloud?.ready == true { return "Ready to play" }
        if let cloud {
            let state = cloud.download_state?.lowercased() ?? ""
            if state.contains("fail") || state.contains("error") { return "TorBox needs attention · Check your dashboard" }
            if state.contains("stall") { return "Waiting for peers" }
            if state.contains("meta") { return "Fetching torrent details" }
            if state.contains("queue") { return "Queued in TorBox" }
            return progress.map { "Downloading · \(Int(($0 * 100).rounded()))%" } ?? "Preparing download"
        }
        return job?.queuedID != nil ? "Queued in TorBox" : "Checking submitted request"
    }
    private var needsAttention: Bool {
        let state = cloud?.download_state?.lowercased() ?? ""
        return state.contains("fail") || state.contains("error")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !seanime.hasTorBoxKey {
                Text("Connect TorBox to open torrent releases.").font(.subheadline).foregroundStyle(.secondary)
                NavigationLink("Connect TorBox") { TorBoxSettingsView() }
            } else if job == nil {
                if busy {
                    ProgressView(activity).font(.caption).accessibilityIdentifier("torbox-loading")
                } else if checked {
                    if needsDownload {
                        Text("Download required").font(.subheadline.weight(.semibold)).accessibilityIdentifier("torbox-cache-miss")
                            .accessibilityLabel("Not cached on TorBox · Download required")
                        Text("Not cached on TorBox. Download it to your account, then choose a video file.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button { add(cachedOnly: false) } label: {
                            Label("Download with TorBox", systemImage: "arrow.down.to.line").frame(maxWidth: .infinity)
                        }.buttonStyle(.borderedProminent).controlSize(.large).tint(.mint).foregroundStyle(.black)
                            .disabled(provider == nil).accessibilityIdentifier("torbox-download-torrent")
                        Text("Uses your TorBox storage and download limits.").font(.caption2).foregroundStyle(.secondary)
                    } else {
                        Button { add(cachedOnly: true) } label: {
                            Label("Add cached copy", systemImage: "cloud").frame(maxWidth: .infinity)
                        }.buttonStyle(.borderedProminent).controlSize(.large).tint(.mint).foregroundStyle(.black)
                            .disabled(provider == nil).accessibilityIdentifier("torbox-add-torrent")
                        Text("Cached only · Won’t start an uncached download").font(.caption2).foregroundStyle(.secondary)
                    }
                } else {
                    Button("Check existing TorBox files") { load() }.accessibilityIdentifier("torbox-check-existing")
                }
            } else {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(cloud?.ready == true && cloud?.videoFiles.isEmpty == true ? "No playable video files" : status)
                            .font(.subheadline.weight(.semibold)).foregroundStyle(cloud?.ready == true ? Color.mint : .primary)
                            .accessibilityIdentifier("torbox-job-status")
                        if cloud?.ready != true && error == nil && !needsAttention {
                            Text("Updates automatically · Safe to leave and return").font(.caption2).foregroundStyle(.secondary)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Button { load() } label: { Image(systemName: "arrow.clockwise").frame(width: 44, height: 44) }
                        .buttonStyle(.borderless).disabled(busy || provider == nil).accessibilityLabel("Refresh TorBox files")
                        .accessibilityIdentifier("torbox-refresh-files")
                    Menu {
                        if let id = job?.torrentID { Text("TorBox #\(String(id))") }
                        Button("Forget local reference", role: .destructive) { forgetConfirmed = true }
                    } label: { Image(systemName: "ellipsis.circle").frame(width: 44, height: 44) }
                        .disabled(busy).accessibilityLabel("TorBox options").accessibilityIdentifier("torbox-options")
                }
                if cloud?.ready != true, let progress {
                    ProgressView(value: progress).tint(.mint).accessibilityLabel("Download progress")
                        .accessibilityValue("\(Int((progress * 100).rounded())) percent").accessibilityIdentifier("torbox-download-progress")
                }
                if busy { ProgressView(activity).font(.caption).accessibilityIdentifier("torbox-loading") }
                if needsAttention { Link("Open TorBox dashboard", destination: URL(string: "https://torbox.app")!).font(.subheadline) }
            }
            if let error {
                Text(error).font(.caption).foregroundStyle(.orange).accessibilityIdentifier("torbox-playback-error")
            }
            if let cloud, cloud.ready {
                if cloud.videoFiles.isEmpty {
                    Text("Try another release or refresh its files.").font(.caption).foregroundStyle(.secondary)
                } else {
                    HStack {
                        Text(cloud.videoFiles.count == 1 ? "Video file" : "Choose a file").font(.subheadline.weight(.semibold))
                        Spacer()
                        if cloud.videoFiles.count > 1 { Text("\(cloud.videoFiles.count) videos").font(.caption).foregroundStyle(.secondary) }
                    }
                    ForEach(cloud.videoFiles) { file in
                        Button { play(file, cloud: cloud) } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "play.circle.fill").font(.title2).foregroundStyle(.mint).padding(.top, 3)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(file.short_name?.isEmpty == false ? file.short_name! : file.name)
                                        .font(.subheadline).foregroundStyle(.primary).lineLimit(3)
                                    PlaybackAudioBadge(audio: StreamAudioInfo(texts: [file.name]), compact: true)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }.padding(.vertical, 8).contentShape(Rectangle())
                        }.buttonStyle(.plain).disabled(busy || provider == nil)
                            .accessibilityLabel("Play in VidHub · \(file.name) · \(StreamAudioInfo(texts: [file.name]).label)")
                            .accessibilityIdentifier("torbox-file-\(file.id)")
                        if file.id != cloud.videoFiles.last?.id { Divider() }
                    }
                }
            }
            if anime == nil, let message = playback.playerMessage {
                Text(message).font(.caption).accessibilityIdentifier("torbox-player-message")
            }
        }
        .confirmationDialog("Forget this local reference?", isPresented: $forgetConfirmed, titleVisibility: .visible) {
            Button("Forget reference", role: .destructive) { seanime.forgetJob(for: torrent); job = nil; cloud = nil; checked = false; load() }
        } message: { Text("The next check will look for this release in TorBox before offering to add it.") }
        .onAppear { job = seanime.job(for: torrent); if seanime.hasTorBoxKey { load() } }
        .onDisappear { cancel() }
        .onChange(of: seanime.revision) { _, _ in cancel(); job = seanime.job(for: torrent); cloud = nil; checked = false; magnet = nil; needsDownload = false; if seanime.hasTorBoxKey { load() } }
        .onChange(of: store.includeAdult) { _, _ in cancel(); cloud = nil; checked = false; needsDownload = false }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { cancel() }
            else if job != nil { load() }
        }
    }
    private func cancel() { generation = UUID(); work?.cancel(); statusWork?.cancel(); runner?.cancel(); busy = false }
    private func followStatus() {
        statusWork?.cancel()
        guard job != nil, cloud?.ready != true, !needsAttention, scenePhase == .active, provider != nil else { return }
        statusWork = Task {
            do { try await Task.sleep(for: .seconds(5)); try Task.checkCancellation(); load() }
            catch {}
        }
    }
    private func resolveMagnet(_ provider: SeanimeInstallation) async throws -> String {
        if let magnet { return magnet }
        let engine = SeanimeRunner(client: seanime.client); runner = engine
        let value = try await engine.magnet(provider, torrent: torrent, allowAdult: store.includeAdult)
        try Task.checkCancellation(); magnet = value; return value
    }
    private func save(_ value: TorBoxJob) throws {
        guard seanime.recordJob(value, for: torrent) else { throw ServiceError.message("The TorBox reference could not be saved on this device. Check your TorBox dashboard before submitting again.") }
        job = value
    }
    private func load() {
        guard !busy, let provider, seanime.hasTorBoxKey else { return }
        statusWork?.cancel(); busy = true; activity = job == nil ? "Checking existing files…" : "Updating download status…"
        error = nil; let attempt = UUID(); generation = attempt
        work = Task {
            var follow = false
            defer { if generation == attempt { busy = false; if follow { followStatus() } } }
            do {
                let lookup: TorBoxJob
                if let job { lookup = job }
                else { let value = try await resolveMagnet(provider); lookup = try TorBoxJob(magnet: value) }
                let value = try await seanime.torBox().resolve(lookup)
                try Task.checkCancellation(); guard generation == attempt else { return }
                cloud = value; checked = true
                if let value { try save(TorBoxJob(torrentID: value.id, infoHash: lookup.infoHash)) }
                follow = job != nil
            } catch is CancellationError {} catch {
                if generation == attempt { self.error = "Could not retrieve TorBox files. \(error.localizedDescription)" }
            }
        }
    }
    private func add(cachedOnly: Bool) {
        guard job == nil, checked, !busy, let provider else { return }
        busy = true; activity = cachedOnly ? "Finding cached files…" : "Starting TorBox download…"
        error = nil; let attempt = UUID(); generation = attempt
        work = Task {
            var follow = false
            defer { if generation == attempt { busy = false; if follow { followStatus() } } }
            var submitted = false
            var accepted = false
            do {
                let magnet = try await resolveMagnet(provider)
                let pending = try TorBoxJob(magnet: magnet)
                let client = try seanime.torBox()
                // Persist before POST: cancellation or an unreadable receipt must
                // leave a read-only recovery path, including after app relaunch.
                try save(pending); submitted = true
                let receipt = try await client.add(magnet: magnet, cachedOnly: cachedOnly)
                accepted = true
                try Task.checkCancellation(); guard generation == attempt else { return }
                try save(receipt)
                activity = "Retrieving TorBox files…"
                cloud = try await client.resolve(receipt)
                try Task.checkCancellation(); guard generation == attempt else { return }
                if let cloud { try save(TorBoxJob(torrentID: cloud.id, infoHash: receipt.infoHash)) }
                follow = true
            } catch is CancellationError {} catch {
                guard generation == attempt else { return }
                // Only an explicit rejection makes another confirmed add safe.
                if !accepted, let rejection = error as? TorBoxError, rejection.definitivelyRejectedSubmission {
                    seanime.forgetJob(for: torrent); job = nil; submitted = false
                    if rejection == .notCached { needsDownload = true; return }
                }
                self.error = submitted ? "The request may have reached TorBox. Check its status before trying again. \(error.localizedDescription)" : error.localizedDescription
            }
        }
    }
    private func play(_ file: TorBoxFile, cloud: TorBoxTorrent) {
        guard !busy, provider != nil else { return }
        statusWork?.cancel(); busy = true; activity = "Opening VidHub…"; error = nil; let attempt = UUID(); generation = attempt
        work = Task {
            defer { if generation == attempt { busy = false } }
            do {
                let url = try seanime.torBox().playbackURL(torrent: cloud, fileID: file.id)
                try Task.checkCancellation(); guard generation == attempt, provider != nil, seanime.hasTorBoxKey else { return }
                let data = try JSONSerialization.data(withJSONObject: ["name": file.name, "url": url.absoluteString, "behaviorHints": ["filename": file.name]])
                let stream = try JSONDecoder().decode(StremioStream.self, from: data)
                if let anime { await playback.play(stream: stream, anime: anime, episode: episode, subtitle: nil, restart: restart) }
                else { await playback.playUntracked(stream: stream, title: file.name) }
            } catch is CancellationError {} catch {
                if generation == attempt { self.error = "Could not get this file's playback link. \(error.localizedDescription)" }
            }
        }
    }
}

private extension TorBoxError {
    var definitivelyRejectedSubmission: Bool {
        switch self {
        case .missingKey, .unauthorized, .rateLimited, .notCached, .quota, .invalidTorrent, .planRestricted, .missingTorrent: return true
        case let .rejected(status, _): return (400..<500).contains(status)
        default: return false
        }
    }
}
