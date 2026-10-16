import SwiftUI
import AnimeCore

/// Expands in the result list. File selection and player handoff stay on the
/// search screen, while accepted/uncertain submissions survive closing it.
struct TorBoxPlaybackControls: View {
    @EnvironmentObject private var seanime: SeanimeStore
    @EnvironmentObject private var playback: PlaybackStore
    @EnvironmentObject private var store: AppStore
    let providerID: UUID
    let torrent: SeanimeTorrent
    let anime: Anime?
    let episode: Int
    var restart = false
    @State private var cachedOnly = true
    @State private var confirmed = false
    @State private var forgetConfirmed = false
    @State private var job: TorBoxJob?
    @State private var cloud: TorBoxTorrent?
    @State private var busy = false
    @State private var checked = false
    @State private var magnet: String?
    @State private var error: String?
    @State private var work: Task<Void, Never>?
    @State private var runner: SeanimeRunner?
    @State private var generation = UUID()
    private var provider: SeanimeInstallation? {
        seanime.installations.first { $0.id == providerID && $0.enabled && (store.includeAdult || !$0.adult) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let anime { Text("Episode \(episode) · \(anime.displayTitle)").font(.caption).foregroundStyle(.secondary) }
            if !seanime.hasTorBoxKey {
                Text("Save your TorBox key in Settings to play torrents.").foregroundStyle(.orange)
            } else if job == nil {
                if checked {
                    Toggle("Cached only", isOn: $cachedOnly).accessibilityIdentifier("torbox-cached-only")
                    Text(cachedOnly ? "Only releases already cached on TorBox. Turn this off to let TorBox download an uncached release." : "Uncached releases may need time to download in TorBox.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Add to TorBox & show files") { confirmed = true }
                        .disabled(busy || provider == nil).accessibilityIdentifier("torbox-add-torrent")
                } else {
                    Button("Check existing TorBox files") { load() }.disabled(busy)
                        .accessibilityIdentifier("torbox-check-existing")
                }
            } else {
                Text(job?.torrentID.map { "TorBox #\($0) · \(cloud?.download_state ?? "Preparing files")" }
                     ?? job?.queuedID.map { "Queued in TorBox · #\($0)" }
                     ?? "Submitted to TorBox · checking files")
                    .font(.subheadline).accessibilityIdentifier("torbox-job-status")
                if cloud == nil {
                    Text("TorBox accepted or may have received this release. Refresh checks existing files without adding it again.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button("Refresh TorBox files") { load() }.disabled(busy || provider == nil)
                    .accessibilityIdentifier("torbox-refresh-files")
                DisclosureGroup("TorBox options") {
                    Button("Forget local reference", role: .destructive) { forgetConfirmed = true }.disabled(busy)
                    Text("This does not delete the torrent in TorBox.").font(.caption).foregroundStyle(.secondary)
                }
            }
            if busy { ProgressView("Checking TorBox…").accessibilityIdentifier("torbox-loading") }
            if let cloud {
                if !cloud.ready {
                    Text("TorBox is still downloading or preparing this release. Refresh when it is ready.")
                        .font(.caption).foregroundStyle(.secondary)
                } else if cloud.videoFiles.isEmpty {
                    Text("TorBox has not supplied a playable video file. Refresh files or choose another release.").font(.caption).foregroundStyle(.secondary)
                }
                if !cloud.videoFiles.isEmpty {
                    Text(cloud.videoFiles.count == 1 ? "Video file" : "Choose your episode’s file").font(.headline)
                    Text("Play sends a private TorBox playback link to VidHub.").font(.caption).foregroundStyle(.secondary)
                    ForEach(cloud.videoFiles) { file in
                        Button { play(file, cloud: cloud) } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                PlaybackAudioBadge(audio: StreamAudioInfo(texts: [file.name]))
                                Text(file.short_name?.isEmpty == false ? file.short_name! : file.name).foregroundStyle(.primary)
                                Label("Play in VidHub", systemImage: "play.fill").font(.caption)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5)
                        }.buttonStyle(.borderless).disabled(!cloud.ready || busy || provider == nil)
                            .accessibilityIdentifier("torbox-file-\(file.id)")
                    }
                }
            }
            if let error { Text(error).font(.callout).foregroundStyle(.orange).accessibilityIdentifier("torbox-playback-error") }
            if let message = playback.playerMessage { Text(message).font(.caption).accessibilityIdentifier("torbox-player-message") }
        }
        .confirmationDialog("Add this release to your TorBox account?", isPresented: $confirmed, titleVisibility: .visible) {
            Button("Confirm add to TorBox") { add() }
        } message: {
            Text(cachedOnly ? "Cached-only is on. Uncached releases will not be queued." : "TorBox may download this release using your account’s storage and download limits.")
        }
        .confirmationDialog("Forget this local reference?", isPresented: $forgetConfirmed, titleVisibility: .visible) {
            Button("Forget reference", role: .destructive) { seanime.forgetJob(for: torrent); job = nil; cloud = nil; checked = false; load() }
        } message: { Text("The next check will look for this release in TorBox before offering to add it.") }
        .onAppear { job = seanime.job(for: torrent); if seanime.hasTorBoxKey { load() } }
        .onDisappear { cancel() }
        .onChange(of: seanime.revision) { _, _ in cancel(); job = seanime.job(for: torrent); cloud = nil; checked = false; magnet = nil }
        .onChange(of: store.includeAdult) { _, _ in cancel(); cloud = nil; checked = false }
    }
    private func cancel() { generation = UUID(); work?.cancel(); runner?.cancel(); busy = false }
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
        busy = true; error = nil; let attempt = UUID(); generation = attempt
        work = Task {
            defer { if generation == attempt { busy = false } }
            do {
                let lookup: TorBoxJob
                if let job { lookup = job }
                else { let value = try await resolveMagnet(provider); lookup = try TorBoxJob(magnet: value) }
                let value = try await seanime.torBox().resolve(lookup)
                try Task.checkCancellation(); guard generation == attempt else { return }
                cloud = value; checked = true
                if let value { try save(TorBoxJob(torrentID: value.id, infoHash: lookup.infoHash)) }
            } catch is CancellationError {} catch {
                if generation == attempt { self.error = "Could not retrieve TorBox files. \(error.localizedDescription)" }
            }
        }
    }
    private func add() {
        guard job == nil, checked, !busy, let provider else { return }
        busy = true; error = nil; let attempt = UUID(); generation = attempt
        work = Task {
            defer { if generation == attempt { busy = false } }
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
                cloud = try await client.resolve(receipt)
                try Task.checkCancellation(); guard generation == attempt else { return }
                if let cloud { try save(TorBoxJob(torrentID: cloud.id, infoHash: receipt.infoHash)) }
            } catch is CancellationError {} catch {
                guard generation == attempt else { return }
                // Only an explicit rejection makes another confirmed add safe.
                if !accepted, let rejection = error as? TorBoxError, rejection.definitivelyRejectedSubmission {
                    seanime.forgetJob(for: torrent); job = nil; submitted = false
                }
                self.error = submitted ? "The release was submitted. Refresh TorBox files to continue. \(error.localizedDescription)" : error.localizedDescription
            }
        }
    }
    private func play(_ file: TorBoxFile, cloud: TorBoxTorrent) {
        guard !busy, provider != nil else { return }
        busy = true; error = nil; let attempt = UUID(); generation = attempt
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
