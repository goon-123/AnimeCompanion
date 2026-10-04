import SwiftUI
import AuthenticationServices
import AnimeCore

@MainActor
final class AppStore: ObservableObject {
    let aniList = AniListClient()
    let dubs = DubClient()
    let exploreDubs = ExploreDubStore()
    let news = NewsClient()
    private let authentication = AuthSession()
    private var token: OAuthToken?
    private var generation = UUID()
    private var restored = false
    @Published var viewer: Viewer?
    @Published var entries: [LibraryEntry] = []
    @Published var isSignedIn = false
    @Published var connecting = false
    @Published var loadingLibrary = false
    @Published var libraryError: String?
    @Published var accountError: String?
    @Published var savingMedia = Set<Int>()
    @Published var savedAt: Date?

    var watching: [LibraryEntry] { entries.filter { $0.status == .watching || $0.status == .rewatching } }
    func entry(for mediaId: Int) -> LibraryEntry? { entries.first { $0.mediaId == mediaId } }

    func restore() async {
        guard !restored else { return }; restored = true
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-library-preview") {
            await loadPreviewLibrary()
            return
        }
        #endif
        do {
            guard let stored = try KeychainTokenStore.load() else { return }
            guard !stored.isExpired else { try KeychainTokenStore.delete(); accountError = "Your AniList connection expired. Please sign in again."; return }
            token = stored; isSignedIn = true
            await reloadLibrary()
        } catch { accountError = error.localizedDescription }
    }
    #if DEBUG
    /// Simulator UI fixture: public metadata with synthetic progress, no credentials or server writes.
    private func loadPreviewLibrary() async {
        isSignedIn = true; loadingLibrary = true
        defer { loadingLibrary = false }
        do {
            let media = try await aniList.media(ids: [1, 5, 199, 205])
            let records: [[String: Any]] = try media.enumerated().map { index, anime in
                var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(anime)) as! [String: Any]
                // Deterministic future release ONLY for artwork-sizing UI tests.
                // This is not a provider date and never appears in Release builds.
                if ProcessInfo.processInfo.arguments.contains("--ui-layout-preview"), anime.id == 1 {
                    object["nextAiringEpisode"] = ["episode": 9, "airingAt": Int(Date().addingTimeInterval(86400).timeIntervalSince1970)]
                }
                return ["id": 900000 + index, "mediaId": anime.id, "status": anime.id == 5 ? "COMPLETED" : "CURRENT",
                        "progress": anime.id == 1 ? 8 : (anime.id == 5 ? 1 : 0), "updatedAt": 1700000000 + index, "media": object]
            }
            entries = try JSONDecoder().decode([LibraryEntry].self, from: JSONSerialization.data(withJSONObject: records))
            savedAt = Date()
        } catch { libraryError = error.localizedDescription }
    }
    #endif
    func connect() async {
        guard !connecting else { return }
        guard let clientID = AppConfiguration.clientID else { accountError = "Configure the AniList app ID in Settings first."; return }
        connecting = true; accountError = nil
        defer { connecting = false }
        let attempt = generation
        do {
            let candidate = try await authentication.signIn(clientID: clientID)
            let profile = try await aniList.viewer(token: candidate.accessToken)
            guard generation == attempt else { return }
            try KeychainTokenStore.save(candidate)
            token = candidate; viewer = profile; isSignedIn = true
            await reloadLibrary()
        } catch {
            if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin { return }
            if generation == attempt { accountError = error.localizedDescription }
        }
    }
    func disconnect() {
        do { try KeychainTokenStore.delete() }
        catch { accountError = error.localizedDescription; return }
        generation = UUID(); token = nil; viewer = nil; entries = []; isSignedIn = false
        savedAt = nil; libraryError = nil; savingMedia = []; loadingLibrary = false
    }
    private func validToken() throws -> OAuthToken {
        guard let token, !token.isExpired else { throw ServiceError.unauthorized }
        return token
    }
    func reloadLibrary() async {
        guard !loadingLibrary, savingMedia.isEmpty else { return }
        let attempt = generation
        loadingLibrary = true; libraryError = nil
        defer { if generation == attempt { loadingLibrary = false } }
        do {
            let token = try validToken()
            let profile: Viewer
            if let viewer { profile = viewer } else { profile = try await aniList.viewer(token: token.accessToken) }
            let collection = try await aniList.library(userId: profile.id, token: token.accessToken)
            guard generation == attempt else { return }
            viewer = profile
            entries = collection.sorted { ($0.updatedAt ?? 0) > ($1.updatedAt ?? 0) }
            savedAt = Date()
        } catch {
            guard generation == attempt else { return }
            if (error as? ServiceError) == .unauthorized { disconnect(); accountError = error.localizedDescription }
            else { libraryError = error.localizedDescription }
        }
    }
    /// UI updates only after the server confirms; failed writes preserve confirmed progress.
    func save(anime: Anime, progress: Int, status: LibraryStatus) async throws {
        guard !savingMedia.contains(anime.id), !loadingLibrary else { return }
        let credential = try validToken()
        let existing = entry(for: anime.id)
        let attempt = generation
        savingMedia.insert(anime.id)
        defer { if generation == attempt { savingMedia.remove(anime.id) } }
        do {
            let saved = try await aniList.save(mediaId: anime.id, entryId: existing?.id,
                progress: LibraryEntry.clampedProgress(progress, total: anime.episodes), status: status, token: credential.accessToken)
            guard generation == attempt else { return }
            entries.removeAll { $0.mediaId == anime.id }; entries.insert(saved, at: 0); savedAt = Date()
        } catch {
            if (error as? ServiceError) == .unauthorized, generation == attempt { disconnect(); accountError = error.localizedDescription }
            throw error
        }
    }
}
