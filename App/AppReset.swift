import SwiftUI
import Security
import WebKit
import AnimeCore

struct AppSessionHost: View {
    @StateObject private var reset = AppResetCoordinator()
    var body: some View {
        Group {
            if reset.isResetting || reset.needsRecovery || reset.error != nil {
                VStack(spacing: 20) {
                    if let error = reset.error {
                        Image(systemName: "exclamationmark.circle").font(.largeTitle)
                        Text("Reset couldn’t finish").font(.title2.bold())
                        Text(error).multilineTextAlignment(.center)
                        Button("Retry Reset") { reset.start() }.buttonStyle(.borderedProminent)
                    } else {
                        ProgressView().tint(.white)
                        Text("Resetting AnimeCompanion…").font(.headline)
                    }
                }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.ignoresSafeArea()).foregroundStyle(.white)
                    .accessibilityIdentifier("app-reset-progress")
            } else {
                AppSessionView().id(reset.sessionID).environmentObject(reset)
            }
        }.task { if reset.needsRecovery { reset.start() } }
    }
}

@MainActor
final class AppResetCoordinator: ObservableObject {
    static let pendingKey = "app.reset.inProgress"
    @Published private(set) var isResetting = false
    @Published private(set) var needsRecovery = UserDefaults.standard.bool(forKey: AppResetCoordinator.pendingKey)
    @Published private(set) var error: String?
    private(set) var sessionID = UUID()
    var prepareForReset: (() -> Void)?

    func start() {
        guard !isResetting else { return }
        guard let domain = Bundle.main.bundleIdentifier else { error = "The app could not identify its local storage."; return }
        let setupKey = FirstRunSetupState.lifecycleKey
        AppDataEpoch.shared.beginReset()
        UserDefaults.standard.set(true, forKey: Self.pendingKey)
        prepareForReset?(); prepareForReset = nil
        error = nil; isResetting = true
        Task {
            // Remove the old UI and cancel its view tasks before clearing data.
            await Task.yield()
            await AppNetworkSessions.shared.cancelAndClear()
            LiveChartPageTransport.cancelAllForReset()
            await MangaRuntimeBrowser.closeAllForReset()
            let profiles = Array(MangaWebsiteProfiles.stores.values) + [WKWebsiteDataStore.default()]
            MangaWebsiteProfiles.stores.removeAll()
            for profile in profiles {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    profile.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) {
                        continuation.resume()
                    }
                }
            }
            MangaSourceCookieJar.shared.clearAll()
            HTTPCookieStorage.shared.removeCookies(since: .distantPast)
            let credentials = URLCredentialStorage.shared
            for (space, entries) in credentials.allCredentials {
                for credential in entries.values { credentials.remove(credential, for: space) }
            }
            URLCache.shared.removeAllCachedResponses()
            await ArtworkPipeline.shared.clearMemory()
            await MangaImagePipeline.shared.clearMemory()
            do {
                try await Task.detached(priority: .userInitiated) {
                    try AppResetKeychain.clear()
                    let files = FileManager.default
                    let directories = [FileManager.SearchPathDirectory.documentDirectory, .applicationSupportDirectory, .cachesDirectory]
                        .compactMap { files.urls(for: $0, in: .userDomainMask).first } + [files.temporaryDirectory]
                    try AppLocalDataReset.eraseContents(of: directories, inside: URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true))
                    UserDefaults.standard.removePersistentDomain(forName: domain)
                    UserDefaults.standard.set("inProgress", forKey: setupKey)
                }.value
                AppDataEpoch.shared.finishReset()
                sessionID = UUID(); needsRecovery = false; isResetting = false
            } catch {
                self.error = "Some local data could not be cleared. Unlock this device and retry. The reset will also resume if you reopen the app."
                needsRecovery = true; isResetting = false
            }
        }
    }
}

enum AppResetKeychain {
    static func clear(servicePrefix: String = "com.animecompanion.") throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecReturnAttributes as String: true, kSecMatchLimit as String: kSecMatchLimitAll,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return }
        guard status == errSecSuccess else { throw ServiceError.message("Saved connections could not be read for reset.") }
        let entries = (result as? [[String: Any]]) ?? (result as? [String: Any]).map { [$0] } ?? []
        for entry in entries {
            guard let service = entry[kSecAttrService as String] as? String, service.hasPrefix(servicePrefix) else { continue }
            var deletion: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service, kSecAttrSynchronizable as String: kSecAttrSynchronizableAny]
            if let account = entry[kSecAttrAccount as String] { deletion[kSecAttrAccount as String] = account }
            if let group = entry[kSecAttrAccessGroup as String] { deletion[kSecAttrAccessGroup as String] = group }
            let removed = SecItemDelete(deletion as CFDictionary)
            guard removed == errSecSuccess || removed == errSecItemNotFound else {
                throw ServiceError.message("A saved connection could not be removed.")
            }
        }
    }
}
