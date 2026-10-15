import SwiftUI
import Security
import UIKit
import AnimeCore

private enum AddonKeychain {
    private static let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.animecompanion.playback", kSecAttrAccount as String: "streaming-addon"]
    static func load() throws -> (collection: AddonCollection, legacy: Bool)? {
        var request = query; request[kSecReturnData as String] = true; request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let collection = try? JSONDecoder().decode(AddonCollection.self, from: data) else {
            throw ServiceError.message("The saved add-on could not be read. Unlock your device and reopen the app.")
        }
        return (collection, (try? JSONDecoder().decode(InstalledAddon.self, from: data)) != nil)
    }
    static func save(_ collection: AddonCollection) throws {
        let data = try JSONEncoder().encode(collection)
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
    @Published private var collection = AddonCollection()
    @Published private(set) var addonRevision = UUID()
    @Published var enabled = UserDefaults.standard.object(forKey: "playback.enabled") as? Bool ?? true {
        didSet { defaults.set(enabled, forKey: "playback.enabled") }
    }
    @Published private(set) var progress: [String: PlaybackProgress] = [:]
    @Published private(set) var installing = false
    @Published private(set) var openingPlayer = false
    @Published var setupError: String?
    @Published var playerMessage: String?
    private var pending: PendingPlayback?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        #if DEBUG
        let multiple = ProcessInfo.processInfo.arguments.contains("--ui-multiple-addons-preview")
        let preview = multiple || ProcessInfo.processInfo.arguments.contains("--ui-playback-preview")
        let suite = multiple ? "com.animecompanion.ui-multiple-addons" : "com.animecompanion.ui-playback"
        self.defaults = preview ? UserDefaults(suiteName: suite)! : defaults
        if preview && !(multiple && ProcessInfo.processInfo.arguments.contains("--ui-keep-addon-preview")) {
            self.defaults.removePersistentDomain(forName: suite)
        }
        if preview {
            if multiple { client = StremioClient(transport: MultipleAddonPreviewTransport()) }
            else { client = StremioClient(transport: PlaybackPreviewTransport()) }
            if multiple, let data = self.defaults.data(forKey: "preview.addons"), let saved = try? JSONDecoder().decode(AddonCollection.self, from: data) {
                collection = saved
            } else if let addon = try? PlaybackPreviewTransport.addon() { collection.install(addon) }
            enabled = self.defaults.object(forKey: "playback.enabled") as? Bool ?? true
            if ProcessInfo.processInfo.arguments.contains("--ui-playback-stale-resume") {
                progress["1:1"] = PlaybackProgress(position: 120, duration: 1440, finished: false)
            }
            return
        }
        #else
        self.defaults = defaults
        #endif
        client = StremioClient()
        enabled = self.defaults.object(forKey: "playback.enabled") as? Bool ?? true
        if let data = defaults.data(forKey: "playback.positions"), let saved = try? JSONDecoder().decode([String: PlaybackProgress].self, from: data) { progress = saved }
        if let data = defaults.data(forKey: "playback.pending"), let saved = try? JSONDecoder().decode(PendingPlayback.self, from: data), Date().timeIntervalSince(saved.createdAt) < 86400 { pending = saved }
        do {
            if let saved = try AddonKeychain.load() {
                collection = saved.collection
                if saved.legacy { try AddonKeychain.save(collection) }
            }
        } catch { setupError = error.localizedDescription }
    }
    var installations: [AddonInstallation] { collection.installations }
    var enabledAddons: [AddonInstallation] { enabled ? collection.enabled.filter { $0.addon.manifest.behaviorHints?.configurationRequired != true } : [] }
    var activeAddons: [AddonInstallation] { enabledAddons.filter { $0.addon.manifest.advertises("stream") } }
    var ready: Bool { !activeAddons.isEmpty }
    func install(_ input: String) async -> Bool {
        guard !installing else { return false }
        installing = true; setupError = nil
        defer { installing = false }
        do {
            let candidate = try await client.install(input)
            try Task.checkCancellation()
            return saveInstallation(candidate)
        } catch is CancellationError { return false }
        catch { setupError = error.localizedDescription; return false }
    }
    @discardableResult
    func saveInstallation(_ candidate: InstalledAddon) -> Bool {
        do {
            guard candidate.manifest.behaviorHints?.configurationRequired != true else { throw PlaybackError.configurationRequired }
            var updated = collection; updated.install(candidate)
            try persist(updated); enabled = true; setupError = nil
            return true
        } catch { setupError = error.localizedDescription; return false }
    }
    func remove(id: UUID) {
        guard !installing else { return }
        var updated = collection; updated.remove(id: id)
        do { try persist(updated); setupError = nil }
        catch { setupError = error.localizedDescription }
    }
    func setEnabled(_ enabled: Bool, id: UUID) {
        guard !installing else { return }
        var updated = collection; updated.setEnabled(enabled, id: id)
        do { try persist(updated); setupError = nil }
        catch { setupError = error.localizedDescription }
    }
    private func persist(_ updated: AddonCollection) throws {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-multiple-addons-preview") {
            // Only synthetic fixture URLs use this isolated test defaults suite.
            defaults.set(try JSONEncoder().encode(updated), forKey: "preview.addons")
            collection = updated; addonRevision = UUID(); return
        }
        if ProcessInfo.processInfo.arguments.contains("--ui-playback-preview") {
            collection = updated; addonRevision = UUID(); return
        }
        #endif
        if updated.installations.isEmpty { try AddonKeychain.remove() }
        else { try AddonKeychain.save(updated) }
        collection = updated; addonRevision = UUID()
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
            if ProcessInfo.processInfo.arguments.contains("--ui-playback-preview") || ProcessInfo.processInfo.arguments.contains("--ui-multiple-addons-preview") {
                // Test the production URL builder and tap path without opening a third-party app.
                // No real add-on, Keychain change, network request or saved playback is involved.
                let parameters = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
                if ProcessInfo.processInfo.arguments.contains("--ui-playback-return-preview"),
                   let raw = parameters.first(where: { $0.name == "x-success" })?.value,
                   var callback = URLComponents(string: raw) {
                    pending = record
                    callback.queryItems = [URLQueryItem(name: "request-id", value: record.requestID.uuidString),
                        URLQueryItem(name: "status", value: "stopped"), URLQueryItem(name: "position", value: "125")]
                    if let returned = callback.url { handle(returned) }
                    return
                }
                playerMessage = "Preview launch · Episode \(episode)" + (parameters.contains { $0.name == "sub" } ? " · External subtitles" : "")
                if ProcessInfo.processInfo.arguments.contains("--ui-multiple-addons-preview") { playerMessage? += " · \(stream.displayName)" }
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
    func playUntracked(stream: StremioStream, title: String, subtitle: URL? = nil) async {
        guard !openingPlayer else { return }
        openingPlayer = true; playerMessage = nil
        defer { openingPlayer = false }
        do {
            let url = try VidHubPlayback.untrackedLaunchURL(stream: stream, title: title, subtitle: subtitle)
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-multiple-addons-preview") {
                playerMessage = "Preview catalog launch · \(title) · \(stream.displayName)"; return
            }
            #endif
            // Invalidate an older tracked request before an untracked handoff.
            // Catalog playback cannot write into that old episode on return.
            clearPending()
            let opened = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                UIApplication.shared.open(url, options: [:]) { continuation.resume(returning: $0) }
            }
            playerMessage = opened ? "Opened in VidHub. Catalog playback does not change AniList or save a resume position here." : "VidHub could not be opened. Install or update VidHub, then try again."
        } catch { playerMessage = error.localizedDescription }
    }
    private func clearPending() { pending = nil; defaults.removeObject(forKey: "playback.pending") }
}
