import SwiftUI
import Security
import UIKit
import AnimeCore

private enum AddonKeychain {
    private static let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.animecompanion.playback", kSecAttrAccount as String: "streaming-addon"]
    static func load() throws -> InstalledAddon? {
        var request = query; request[kSecReturnData as String] = true; request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let addon = try? JSONDecoder().decode(InstalledAddon.self, from: data) else {
            throw ServiceError.message("The saved add-on could not be read. Unlock your device and reopen the app.")
        }
        return addon
    }
    static func save(_ addon: InstalledAddon) throws {
        let data = try JSONEncoder().encode(addon)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var request = query; request[kSecValueData as String] = data
            request[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(request as CFDictionary, nil) == errSecSuccess else {
                throw ServiceError.message("The add-on could not be saved securely. Your previous setup has not changed.")
            }
        } else if status != errSecSuccess { throw ServiceError.message("The add-on could not be saved securely.") }
    }
    static func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw ServiceError.message("The saved add-on could not be removed.") }
    }
}

@MainActor
final class PlaybackStore: ObservableObject {
    let client: StremioClient
    @Published private(set) var addon: InstalledAddon?
    @Published var enabled = UserDefaults.standard.object(forKey: "playback.enabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(enabled, forKey: "playback.enabled") }
    }
    @Published private(set) var progress: [String: PlaybackProgress] = [:]
    @Published private(set) var installing = false
    @Published private(set) var openingPlayer = false
    @Published var setupError: String?
    @Published var playerMessage: String?
    private var pending: PendingPlayback?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-playback-preview") {
            client = StremioClient(transport: PlaybackPreviewTransport())
            addon = try? PlaybackPreviewTransport.addon()
            enabled = true
            if ProcessInfo.processInfo.arguments.contains("--ui-playback-stale-resume") {
                progress["1:1"] = PlaybackProgress(position: 120, duration: 1440, finished: false)
            }
            return
        }
        #endif
        client = StremioClient()
        if let data = defaults.data(forKey: "playback.positions"), let saved = try? JSONDecoder().decode([String: PlaybackProgress].self, from: data) { progress = saved }
        if let data = defaults.data(forKey: "playback.pending"), let saved = try? JSONDecoder().decode(PendingPlayback.self, from: data), Date().timeIntervalSince(saved.createdAt) < 86400 { pending = saved }
        do { addon = try AddonKeychain.load() } catch { setupError = error.localizedDescription }
    }
    var ready: Bool { addon != nil && enabled }
    func install(_ input: String) async -> Bool {
        guard !installing else { return false }
        installing = true; setupError = nil
        defer { installing = false }
        do {
            let candidate = try await client.install(input)
            try Task.checkCancellation()
            guard candidate.manifest.supports(type: "series", id: "anilist:1:1") || candidate.manifest.supports(type: "series", id: "mal:1:1") ||
                    candidate.manifest.supports(type: "anime", id: "anilist:1:1") || candidate.manifest.supports(type: "anime", id: "mal:1:1") ||
                    candidate.manifest.supports(type: "movie", id: "anilist:1") || candidate.manifest.supports(type: "movie", id: "mal:1") else { throw PlaybackError.unsupportedAnime }
            try AddonKeychain.save(candidate)
            addon = candidate; enabled = true
            return true
        } catch is CancellationError { return false }
        catch { setupError = error.localizedDescription; return false }
    }
    func remove() {
        guard !installing else { return }
        do { try AddonKeychain.remove(); addon = nil; setupError = nil }
        catch { setupError = error.localizedDescription }
    }
    func saved(animeID: Int, episode: Int) -> PlaybackProgress? { progress[PlaybackEpisode(animeID: animeID, episode: episode).key] }
    func resumeEpisode(animeID: Int) -> Int? {
        progress.filter { $0.key.hasPrefix("\(animeID):") && !$0.value.finished && $0.value.position > 0 }
            .max { $0.value.updatedAt < $1.value.updatedAt }?.key.split(separator: ":").last.flatMap { Int($0) }
    }
    func play(stream: StremioStream, anime: Anime, episode: Int, subtitle: URL?, restart: Bool) async {
        guard !openingPlayer else { return }
        openingPlayer = true; playerMessage = nil
        defer { openingPlayer = false }
        let record = PendingPlayback(episode: PlaybackEpisode(animeID: anime.id, episode: episode),
                                     title: anime.format == "MOVIE" ? anime.displayTitle : "\(anime.displayTitle) · Episode \(episode)")
        do {
            let start = restart ? 0 : saved(animeID: anime.id, episode: episode)?.position ?? 0
            let url = try VidHubPlayback.launchURL(stream: stream, pending: record, position: start, subtitle: subtitle)
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-playback-preview") {
                // Test the production URL builder and tap path without opening a third-party app.
                // No real add-on, Keychain change, network request or saved playback is involved.
                let parameters = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
                playerMessage = "Preview launch · Episode \(episode)" + (parameters.contains { $0.name == "sub" } ? " · External subtitles" : "")
                return
            }
            #endif
            pending = record
            defaults.set(try JSONEncoder().encode(record), forKey: "playback.pending")
            let opened = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                UIApplication.shared.open(url, options: [:]) { continuation.resume(returning: $0) }
            }
            if !opened {
                clearPending()
                playerMessage = "VidHub could not be opened. Install or update VidHub on this device, then try again."
            }
        } catch { clearPending(); playerMessage = error.localizedDescription }
    }
    func handle(_ url: URL) {
        guard let pending else { return }
        do {
            guard let outcome = try VidHubPlayback.outcome(url: url, pending: pending) else { return }
            switch outcome {
            case .success(let position, let duration, let finished):
                progress[pending.episode.key] = PlaybackProgress(position: position, duration: duration, finished: finished)
                defaults.set(try JSONEncoder().encode(progress), forKey: "playback.positions")
                playerMessage = finished ? "Finished \(pending.title). Playback saved on this device." : "Resume position saved for \(pending.title)."
            case .cancelled: playerMessage = "Playback cancelled. Your saved position has not changed."
            case .failed(let code):
                playerMessage = code == 201 ? "VidHub is already playing another video. Close that playback and try again." : "VidHub could not play this source. Try another source or check its configuration in AIOStreams."
            }
            clearPending()
        } catch { playerMessage = error.localizedDescription }
    }
    private func clearPending() { pending = nil; defaults.removeObject(forKey: "playback.pending") }
}
