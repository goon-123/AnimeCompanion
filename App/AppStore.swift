import SwiftUI
import AuthenticationServices
import AnimeCore

@MainActor
final class AppStore: ObservableObject {
    let aniList = AniListClient()
    let liveChart = LiveChartClient()
    let exploreCache = ExploreCache()
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
    @Published var includeAdult = UserDefaults.standard.bool(forKey: "content.includeAdult") {
        didSet { UserDefaults.standard.set(includeAdult, forKey: "content.includeAdult") }
    }
    @Published var metadataSource = MetadataSource(rawValue: UserDefaults.standard.string(forKey: "metadata.source") ?? "") ?? .aniList {
        didSet { UserDefaults.standard.set(metadataSource.rawValue, forKey: "metadata.source") }
    }
    @Published var automaticallyComplete = UserDefaults.standard.object(forKey: "tracking.automaticallyComplete") as? Bool ?? true {
        didSet { UserDefaults.standard.set(automaticallyComplete, forKey: "tracking.automaticallyComplete") }
    }
    @Published var airingProgressSource = AiringProgressSource(rawValue: UserDefaults.standard.string(forKey: "library.airingProgressSource") ?? "") ?? .broadcast {
        didSet { UserDefaults.standard.set(airingProgressSource.rawValue, forKey: "library.airingProgressSource") }
    }
    private struct UndoRecord { let previous: LibraryEntry?; let confirmed: LibraryEntry }
    @Published private var undoRecords: [Int: UndoRecord] = [:]
    @Published var trackingMessages: [Int: String] = [:]
    @Published var lastTrackedAnime: Anime?

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-reset-content-preferences") {
            includeAdult = false; metadataSource = .aniList; automaticallyComplete = true
            airingProgressSource = .broadcast
            // Property observers do not run for assignments during initialization.
            UserDefaults.standard.set(false, forKey: "content.includeAdult")
            UserDefaults.standard.set(MetadataSource.aniList.rawValue, forKey: "metadata.source")
            UserDefaults.standard.set(true, forKey: "tracking.automaticallyComplete")
            UserDefaults.standard.set(AiringProgressSource.broadcast.rawValue, forKey: "library.airingProgressSource")
            UserDefaults.standard.set("All", forKey: "schedule.releaseType")
            UserDefaults.standard.set(false, forKey: "schedule.libraryOnly")
        }
        #endif
    }

    func isVisible(_ anime: Anime) -> Bool { includeAdult || anime.isAdult != true }
    var visibleEntries: [LibraryEntry] { entries.filter { $0.media.map(isVisible) ?? true } }
    var watching: [LibraryEntry] { visibleEntries.filter { $0.status == .watching || $0.status == .rewatching } }
    func entry(for mediaId: Int) -> LibraryEntry? { entries.first { $0.mediaId == mediaId } }

    func restore() async {
        guard !restored else { return }; restored = true
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-library-preview") {
            if ProcessInfo.processInfo.arguments.contains("--ui-airing-preview") {
                UserDefaults.standard.set("list", forKey: "library.layout")
                UserDefaults.standard.set("Airing schedule", forKey: "library.sort")
            }
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
                if ProcessInfo.processInfo.arguments.contains("--ui-detail-airing-preview"), anime.id == 1 {
                    object["status"] = "RELEASING"
                    object["nextAiringEpisode"] = ["episode": 9, "airingAt": Int(Date().addingTimeInterval(86400).timeIntervalSince1970)]
                }
                return ["id": 900000 + index, "mediaId": anime.id, "status": anime.id == 5 ? "COMPLETED" : "CURRENT",
                        "progress": anime.id == 1 ? 8 : (anime.id == 5 ? 1 : 0), "updatedAt": 1700000000 + index, "media": object]
            }
            entries = try JSONDecoder().decode([LibraryEntry].self, from: JSONSerialization.data(withJSONObject: records))
            if ProcessInfo.processInfo.arguments.contains("--ui-content-preview") {
                let fixture = Data(#"{"id":990001,"mediaId":990001,"status":"CURRENT","progress":2,"media":{"id":990001,"title":{"english":"Adult content setting fixture"},"isAdult":true}}"#.utf8)
                entries.append(try JSONDecoder().decode(LibraryEntry.self, from: fixture))
            }
            if ProcessInfo.processInfo.arguments.contains("--ui-airing-preview") {
                let next = Int(Date().addingTimeInterval(86400).timeIntervalSince1970)
                let records: [[String: Any]] = [
                    ["id": 990101, "mediaId": 990101, "status": "CURRENT", "progress": 4,
                     "media": ["id": 990101, "title": ["english": "Airing preview · behind"], "status": "RELEASING", "episodes": 12,
                               "nextAiringEpisode": ["episode": 7, "airingAt": next]]],
                    ["id": 990102, "mediaId": 990102, "status": "CURRENT", "progress": 6,
                     "media": ["id": 990102, "title": ["english": "Airing preview · caught up"], "status": "RELEASING", "episodes": 12,
                               "nextAiringEpisode": ["episode": 7, "airingAt": next]]],
                    ["id": 990103, "mediaId": 990103, "status": "CURRENT", "progress": 2,
                     "media": ["id": 990103, "title": ["english": "Finished preview"], "status": "FINISHED", "episodes": 12]],
                ]
                entries.insert(contentsOf: try JSONDecoder().decode([LibraryEntry].self, from: JSONSerialization.data(withJSONObject: records)), at: 0)
            }
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
        undoRecords = [:]; trackingMessages = [:]
        lastTrackedAnime = nil
    }
    private func validToken() throws -> OAuthToken {
        guard let token, !token.isExpired else { throw ServiceError.unauthorized }
        return token
    }
    func reloadLibrary(preserveUndo: Bool = false) async {
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
            if preserveUndo {
                undoRecords = undoRecords.filter { id, record in entries.contains { $0.mediaId == id && $0.hasSameTracking(as: record.confirmed) } }
                trackingMessages = trackingMessages.filter { undoRecords[$0.key] != nil }
                if let anime = lastTrackedAnime, undoRecords[anime.id] == nil { lastTrackedAnime = nil }
            } else {
                undoRecords = [:]; trackingMessages = [:]; lastTrackedAnime = nil
            }
            savedAt = Date()
        } catch {
            guard generation == attempt else { return }
            if (error as? ServiceError) == .unauthorized { disconnect(); accountError = error.localizedDescription }
            else { libraryError = error.localizedDescription }
        }
    }
    func refreshLibraryIfNeeded(now: Date = Date()) async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-library-preview") { return }
        #endif
        guard isSignedIn, let savedAt, now.timeIntervalSince(savedAt) >= 300 else { return }
        await reloadLibrary(preserveUndo: true)
    }
    /// UI updates only after the server confirms; failed writes preserve confirmed progress.
    func save(anime: Anime, progress: Int, status: LibraryStatus) async throws {
        try await save(anime: anime, edit: TrackingEdit(progress: LibraryEntry.clampedProgress(progress, total: anime.episodes), status: status))
    }
    func markNextWatched(anime: Anime) async throws {
        let existing = entry(for: anime.id)
        guard anime.episodes.map({ $0 <= 0 || (existing?.progressValue ?? 0) < $0 }) ?? true else {
            throw ServiceError.message("All known episodes are already marked watched.")
        }
        try await save(anime: anime, edit: .next(entry: existing, total: anime.episodes, automaticallyComplete: automaticallyComplete))
    }
    func canUndo(_ mediaID: Int) -> Bool { undoRecords[mediaID] != nil }
    func save(anime: Anime, edit: TrackingEdit, rememberUndo: Bool = true) async throws {
        guard !savingMedia.contains(anime.id), !loadingLibrary else { throw ServiceError.message("AniList is syncing. Try again when it finishes.") }
        guard savedAt != nil else { throw ServiceError.message("Refresh your AniList library before editing progress.") }
        let edit = try edit.validated(total: anime.episodes)
        let credential = try validToken()
        let existing = entry(for: anime.id)
        let attempt = generation
        savingMedia.insert(anime.id)
        defer { if generation == attempt { savingMedia.remove(anime.id) } }
        do {
            let saved = try await aniList.save(mediaId: anime.id, entryId: existing?.id,
                progress: edit.progress, status: edit.status, token: credential.accessToken,
                scoreRaw: edit.scoreRaw, notes: edit.notes, repeatCount: edit.repeatCount)
            guard generation == attempt else { throw CancellationError() }
            entries.removeAll { $0.mediaId == anime.id }; entries.insert(saved, at: 0); savedAt = Date()
            if rememberUndo {
                undoRecords[anime.id] = UndoRecord(previous: existing, confirmed: saved)
            } else { undoRecords.removeValue(forKey: anime.id) }
            trackingMessages[anime.id] = rememberUndo ? "Saved to AniList" : "Change undone in AniList"
            lastTrackedAnime = anime
        } catch {
            if (error as? ServiceError) == .unauthorized, generation == attempt { disconnect(); accountError = error.localizedDescription }
            throw error
        }
    }
    func undo(anime: Anime) async throws {
        guard let record = undoRecords[anime.id], let current = entry(for: anime.id),
              current.hasSameTracking(as: record.confirmed) else {
            throw ServiceError.message("Refresh your library before undoing this change.")
        }
        if let previous = record.previous {
            // Restore the previous confirmed values; no completion normalization on Undo.
            try await restoreTracking(anime: anime, previous: previous)
        } else { try await remove(anime: anime); trackingMessages[anime.id] = "Addition undone in AniList" }
    }
    private func restoreTracking(anime: Anime, previous: LibraryEntry) async throws {
        guard !savingMedia.contains(anime.id), !loadingLibrary else { throw ServiceError.message("AniList is syncing. Try again when it finishes.") }
        let credential = try validToken(); let attempt = generation
        savingMedia.insert(anime.id)
        defer { if generation == attempt { savingMedia.remove(anime.id) } }
        let saved = try await aniList.save(mediaId: anime.id, entryId: entry(for: anime.id)?.id,
            progress: previous.progressValue, status: previous.status ?? .planning, token: credential.accessToken,
            scoreRaw: Int((previous.score ?? 0).rounded()), notes: previous.notes ?? "", repeatCount: previous.repeatCount ?? 0)
        guard generation == attempt else { throw CancellationError() }
        entries.removeAll { $0.mediaId == anime.id }; entries.insert(saved, at: 0); savedAt = Date()
        undoRecords.removeValue(forKey: anime.id); trackingMessages[anime.id] = "Change undone in AniList"
    }
    func remove(anime: Anime) async throws {
        guard !savingMedia.contains(anime.id), !loadingLibrary, let existing = entry(for: anime.id) else {
            throw ServiceError.message("Refresh your library before removing this entry.")
        }
        let credential = try validToken(); let attempt = generation
        savingMedia.insert(anime.id)
        defer { if generation == attempt { savingMedia.remove(anime.id) } }
        try await aniList.delete(entryId: existing.id, token: credential.accessToken)
        guard generation == attempt else { throw CancellationError() }
        entries.removeAll { $0.mediaId == anime.id }; savedAt = Date()
        undoRecords.removeValue(forKey: anime.id); trackingMessages[anime.id] = "Removed from AniList"
    }
}
