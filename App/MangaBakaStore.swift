import SwiftUI
import Security
import CryptoKit
import AuthenticationServices
import AnimeCore

@MainActor
private final class MangaBakaSignIn: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?
    private var continuation: CheckedContinuation<URL, Error>?
    private func random() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = bytes.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, $0.count, $0.baseAddress!) }
        guard status == errSecSuccess else { throw MangaBakaError.message("Could not prepare a secure sign-in attempt.") }
        return urlBase64(Data(bytes))
    }
    private func urlBase64(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    func signIn(clientID: String, api: MangaBakaClient, addingAccount: Bool) async throws -> MangaBakaCredential {
        guard session == nil else { throw MangaBakaError.message("MangaBaka sign-in is already open.") }
        let state = try random(), verifier = try random(), started = Date()
        let challenge = urlBase64(Data(SHA256.hash(data: Data(verifier.utf8))))
        let url = try MangaBakaOAuth.authorize(clientID: clientID, state: state, challenge: challenge)
        let callback: URL = try await withCheckedThrowingContinuation { c in
            continuation = c
            let web = ASWebAuthenticationSession(url: url, callbackURLScheme: MangaBakaOAuth.callback.scheme) { [weak self] callback, error in
                Task { @MainActor in
                    if let error { self?.finish(.failure(error)) }
                    else if let callback { self?.finish(.success(callback)) }
                    else { self?.finish(.failure(MangaBakaError.invalidResponse)) }
                }
            }
            web.presentationContextProvider = self; web.prefersEphemeralWebBrowserSession = addingAccount
            session = web
            if !web.start() { finish(.failure(MangaBakaError.message("MangaBaka sign-in could not be opened."))) }
        }
        let code = try MangaBakaOAuth.code(from: callback, expectedState: state, startedAt: started)
        return try await api.exchange(code: code, verifier: verifier, clientID: clientID)
    }
    private func finish(_ result: Result<URL, Error>) {
        let c = continuation; continuation = nil; session = nil; c?.resume(with: result)
    }
    func cancel() { session?.cancel(); finish(.failure(CancellationError())) }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?.windows.first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}

@MainActor
final class MangaBakaStore: ObservableObject {
    let api: MangaBakaClient
    private let keychain: MangaBakaAccountKeychain
    private let cacheDirectory: URL?
    private var accounts = MangaBakaAccounts()
    private let previewAccounts: Bool
    init(api: MangaBakaClient? = nil, keychain: MangaBakaAccountKeychain? = nil, cacheDirectory: URL? = nil) {
        self.cacheDirectory = cacheDirectory
        #if DEBUG
        let usePreviewAccounts = api == nil && LibraryCustomizationPreview.active
        previewAccounts = usePreviewAccounts
        self.keychain = keychain ?? MangaBakaAccountKeychain(service: usePreviewAccounts
            ? "com.animecompanion.mangabaka.owned-preview" : "com.animecompanion.mangabaka")
        self.api = api ?? (MangaBakaAccountsPreview.active
            ? MangaBakaClient(transport: LibraryCustomizationTransport(), directory: nil, minimumRequestInterval: 0)
            : UnifiedExplorePreview.active
            ? MangaBakaClient(transport: UnifiedReadingPreviewTransport(), directory: nil, minimumRequestInterval: 0)
            : LibraryCustomizationPreview.active
            ? MangaBakaClient(transport: LibraryCustomizationTransport(), directory: nil, minimumRequestInterval: 0)
            : MangaBakaClient())
        if usePreviewAccounts && ProcessInfo.processInfo.arguments.contains("--ui-reset-content-preferences") {
            try? self.keychain.save(.init())
        }
        #else
        previewAccounts = false
        self.keychain = keychain ?? MangaBakaAccountKeychain()
        self.api = api ?? MangaBakaClient()
        #endif
    }
    @Published private(set) var savedAccounts: [MangaBakaAccountIdentity] = []
    @Published private(set) var activeAccountID: UUID?
    @Published private(set) var connected = false
    @Published private(set) var connecting = false
    @Published private(set) var profile: MangaBakaProfile?
    @Published private(set) var revision = UUID()
    @Published private(set) var recommendationState = MangaBakaRecommendationsState()
    @Published private(set) var recommendationCacheNotice: String?
    @Published private(set) var library: [MangaBakaLibraryEntry] = []
    @Published private(set) var entries: [Int: MangaBakaLibraryEntry] = [:]
    @Published private(set) var loadingLibrary = false
    @Published private(set) var hasMoreLibrary = false
    @Published private(set) var libraryTotal: Int?
    @Published private(set) var saving = Set<Int>()
    @Published var accountError: String?
    @Published var libraryError: String?
    @Published var notice: String?
    @Published private(set) var catalogGenres: [MangaBakaGenre] = []
    @Published private(set) var catalogTags: [MangaBakaTag] = []
    @Published private(set) var loadingTaxonomy = false
    @Published private(set) var taxonomyError: String?
    private var tagsByName: [String: MangaBakaTag] = [:]
    private var credential: MangaBakaCredential?
    private struct CredentialRefresh { let id = UUID(); let task: Task<MangaBakaCredential, Error> }
    private var refreshTasks: [UUID: CredentialRefresh] = [:]
    private var recommendationTask: Task<Void, Never>?
    private var recommendationCache = MangaBakaRecommendationCache()
    private var recommendationSnapshot: MangaBakaRecommendationSnapshot?
    @Published private(set) var connectionID = UUID()
    private var libraryGeneration = UUID()
    private var restored = false
    private var libraryState: String?
    private var libraryPage = 0
    private let authentication = MangaBakaSignIn()
    var bundledClientID: String {
        (Bundle.main.object(forInfoDictionaryKey: "MangaBakaClientID") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    var clientID: String {
        let stored = (UserDefaults.standard.string(forKey: "mangabaka.clientID") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return stored.isEmpty ? bundledClientID : stored
    }
    func resolvedTag(_ tag: MangaBakaTag) -> MangaBakaTag {
        tagsByName[tag.name.lowercased()].map { tag.withMetadata($0) } ?? tag
    }
    func loadTaxonomy(refresh: Bool = false) async {
        guard !loadingTaxonomy, refresh || catalogTags.isEmpty || catalogGenres.isEmpty else { return }
        loadingTaxonomy = true; taxonomyError = nil
        defer { loadingTaxonomy = false }
        var failures: [String] = []
        do { catalogGenres = try await api.genres(refresh: refresh).sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending } }
        catch { failures.append("Genres: " + error.localizedDescription) }
        do {
            let values = try await api.tags(refresh: refresh).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            tagsByName = Dictionary(values.map { ($0.name.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
            catalogTags = values
        } catch { failures.append("Tags: " + error.localizedDescription) }
        taxonomyError = failures.isEmpty ? nil : failures.joined(separator: "\n")
    }
    private func cache(for id: UUID? = nil) -> MangaBakaRecommendationCache {
        if let cacheDirectory { return MangaBakaRecommendationCache(directory: cacheDirectory, accountID: id) }
        return MangaBakaRecommendationCache(accountID: id)
    }
    private var contentFilter: MangaBakaContentFilter {
        MangaBakaContentFilter(saved: UserDefaults.standard.string(forKey: MangaBakaContentFilter.storageKey),
            legacyIncludeAdult: UserDefaults.standard.bool(forKey: "content.includeAdult"))
    }
    private func activate(_ value: MangaBakaAccounts, snapshot: MangaBakaRecommendationSnapshot? = nil) {
        // Invalidate responses before cancelling work or publishing another identity.
        connectionID = UUID(); authentication.cancel()
        clearLibrary(); accounts = value; savedAccounts = value.identities
        activeAccountID = value.selectedID; credential = value.selected?.credential
        profile = value.selected?.profile; connected = credential != nil
        accountError = nil; notice = nil
        recommendationCache = cache(for: activeAccountID)
        if let credential {
            let scoped = try? recommendationCache.load(credential: credential)
            // The old file is still encrypted with this exact connection. Retry
            // migration if a previous launch stopped after migrating Keychain.
            if let stored = snapshot ?? scoped ?? (try? cache().load(credential: credential)),
               (try? recommendationState.restore(stored, account: connectionID, contentFilter: contentFilter)) == true {
                recommendationSnapshot = stored
                if snapshot != nil || scoped == nil {
                    saveRecommendationCache(stored, credential: credential)
                    if recommendationCacheNotice == nil { try? cache().clear() }
                }
            }
        }
        revision = UUID()
    }
    func restore() async {
        guard !restored else { return }; restored = true
        #if DEBUG
        if previewAccounts {
            if AccountSwitcherPreview.active && !AccountSwitcherPreview.mangaBakaConnected { return }
            do {
                var saved = try keychain.load()?.accounts ?? .init()
                if saved.sessions.isEmpty {
                    let credential = try MangaBakaCredential(kind: .apiKey, secret: "owned-preview-not-a-real-credential")
                    let first = saved.add(profile: try AccountSwitcherPreview.profile(), credential: credential)
                    if MangaBakaAccountsPreview.active {
                        saved.add(profile: try MangaBakaAccountsPreview.secondProfile(), credential: try MangaBakaCredential(kind: .apiKey, secret: "owned-preview-second-account"))
                        try saved.select(first)
                    }
                    try keychain.save(saved)
                }
                activate(saved)
                library = try LibraryCustomizationPreview.library().filter {
                    !MangaBakaAccountsPreview.active || $0.id == (profile?.id == "owned-reader-two" ? 74 : 73)
                }
                libraryTotal = library.count
                if ProcessInfo.processInfo.arguments.contains("--ui-home-library-delay") { library = []; libraryTotal = nil }
            } catch { accountError = error.localizedDescription }
            return
        }
        #endif
        do {
            guard let saved = try keychain.load() else { return }
            activate(saved.accounts)
            await refreshProfile()
        } catch { accountError = error.localizedDescription }
    }
    private func refreshProfile() async {
        guard let id = activeAccountID, connected else { return }
        let attempt = connectionID
        do {
            let profile = try await api.profile(validCredential())
            guard attempt == connectionID else { return }
            var next = accounts
            let resolved = try next.updateProfile(profile, for: id)
            try keychain.save(next)
            if resolved != id {
                let retained = recommendationSnapshot
                activate(next, snapshot: retained); try? cache(for: id).clear()
            } else {
                accounts = next; savedAccounts = next.identities; self.profile = profile; revision = UUID()
            }
        } catch is CancellationError {} catch {
            if attempt == connectionID { accountError = error.localizedDescription }
        }
    }
    func connect(apiKey: String? = nil) async {
        guard !connecting, saving.isEmpty else { return }; connecting = true; accountError = nil; notice = nil
        let attempt = connectionID
        defer { connecting = false }
        do {
            // Do not replace an unreadable or newer registry with an empty list
            // merely because restoring it failed earlier in this launch.
            _ = try keychain.load()
            let candidate: MangaBakaCredential
            if let apiKey { candidate = try MangaBakaCredential(kind: .apiKey, secret: apiKey) }
            else { candidate = try await authentication.signIn(clientID: clientID, api: api, addingAccount: !accounts.sessions.isEmpty) }
            let profile = try await api.profile(candidate)
            guard connectionID == attempt else { return }
            // Reload immediately before the transaction. Keychain may have
            // recovered since launch, or another session may have renewed.
            var next = try keychain.load()?.accounts ?? .init()
            // Reconnecting the same person rotates their credentials, not their cache age.
            let old = next.sessions.first { $0.profile?.id == profile.id }
            let retained = old.flatMap { try? cache(for: $0.id).load(credential: $0.credential) }
            next.add(profile: profile, credential: candidate)
            try keychain.save(next)
            activate(next, snapshot: retained)
        } catch is CancellationError {} catch {
            if (error as NSError).domain != ASWebAuthenticationSessionError.errorDomain || (error as NSError).code != ASWebAuthenticationSessionError.canceledLogin.rawValue {
                accountError = error.localizedDescription
            }
        }
    }
    func selectAccount(_ id: UUID) {
        guard id != activeAccountID, !connecting, saving.isEmpty else { return }
        do {
            var next = accounts; try next.select(id)
            try keychain.save(next); activate(next)
            let attempt = connectionID
            Task { if attempt == connectionID { await refreshProfile() } }
        } catch { accountError = error.localizedDescription }
    }
    func removeAccount(_ id: UUID) {
        guard !connecting, saving.isEmpty, accounts.sessions.contains(where: { $0.id == id }) else { return }
        do {
            var next = accounts; next.remove(id)
            try keychain.save(next)
            refreshTasks.removeValue(forKey: id)?.task.cancel()
            if id == activeAccountID { activate(next) }
            else { accounts = next; savedAccounts = next.identities }
            try? cache(for: id).clear()
        } catch { accountError = error.localizedDescription }
    }
    func disconnect() { if let id = activeAccountID { removeAccount(id) } }
    private func clearLibrary() {
        recommendationTask?.cancel(); recommendationTask = nil
        recommendationState.reset()
        recommendationSnapshot = nil; recommendationCacheNotice = nil
        libraryGeneration = UUID(); library = []; entries = [:]; libraryState = nil; libraryPage = 0
        loadingLibrary = false; hasMoreLibrary = false; libraryTotal = nil; libraryError = nil
    }
    private func validCredential() async throws -> MangaBakaCredential {
        guard let current = credential else { throw MangaBakaError.unauthorized }
        guard current.needsRefresh() else { return current }
        let attempt = connectionID
        guard let id = activeAccountID else { throw MangaBakaError.unauthorized }
        let work: CredentialRefresh
        if let existing = refreshTasks[id] { work = existing }
        else {
            work = CredentialRefresh(task: Task { try await api.refresh(current) })
            refreshTasks[id] = work
        }
        defer { if refreshTasks[id]?.id == work.id { refreshTasks[id] = nil } }
        let renewed = try await work.task.value
        guard let saved = accounts.sessions.first(where: { $0.id == id }) else { throw CancellationError() }
        if saved.credential == current {
            // Finish rotation for its owning account even if it is no longer
            // visible. Discarding a rotated refresh token would lose that login.
            var next = accounts; try next.updateCredential(renewed, for: id)
            try keychain.save(next); accounts = next
            if activeAccountID == id {
                credential = renewed
                if let snapshot = recommendationSnapshot { saveRecommendationCache(snapshot, credential: renewed) }
            } else if let snapshot = try? cache(for: id).load(credential: current) {
                try? cache(for: id).save(snapshot, credential: renewed)
            }
        } else if saved.credential != renewed {
            // A separate sign-in replaced this session while renewal was open.
            throw CancellationError()
        }
        guard connectionID == attempt else { throw CancellationError() }
        return renewed
    }
    func loadRecommendations(contentFilter: MangaBakaContentFilter, refresh: Bool = false) async {
        guard connected, !Task.isCancelled else { return }
        guard let attempt = recommendationState.begin(account: connectionID,
            contentFilter: contentFilter, refresh: refresh) else {
            await recommendationTask?.value
            return
        }
        recommendationTask?.cancel()
        // The account owns this work. A disappearing screen must not cancel a
        // request that the next screen appearance will reuse.
        let work = Task {
            defer {
                if recommendationState.isCurrent(attempt) {
                    recommendationState.finish(attempt); recommendationTask = nil
                }
            }
            do {
                let payload = try await api.recommendationPayload(validCredential(), contentFilter: contentFilter)
                let result = try payload.records()
                var status: MangaBakaRecommendationStatus?
                if result.isEmpty {
                    // Readiness is supplementary: an unavailable status endpoint
                    // must not erase a successful recommendation response.
                    status = try? await api.recommendationStatus(validCredential())
                }
                try Task.checkCancellation()
                let snapshot = MangaBakaRecommendationSnapshot(payload: payload, status: status)
                if recommendationState.complete(result, for: attempt, status: status, now: snapshot.fetchedAt) {
                    recommendationSnapshot = snapshot
                    if let credential { saveRecommendationCache(snapshot, credential: credential) }
                }
            } catch is CancellationError {} catch {
                if !Task.isCancelled { recommendationState.fail(error.localizedDescription, for: attempt) }
            }
        }
        recommendationTask = work
        await work.value
    }
    private func saveRecommendationCache(_ snapshot: MangaBakaRecommendationSnapshot, credential: MangaBakaCredential) {
        #if DEBUG
        if previewAccounts { return }
        #endif
        do { try recommendationCache.save(snapshot, credential: credential); recommendationCacheNotice = nil }
        catch { recommendationCacheNotice = "For you could not be saved on this device. These recommendations are available until the app closes." }
    }
    /// Complete the selected list before presenting its final sort order.
    /// Existing pages appear progressively and a failed page remains retryable.
    func loadCompleteLibrary(state: String?, refresh: Bool = false) async {
        let account = connectionID
        if !refresh, libraryState == state, libraryPage > 0, hasMoreLibrary {
            await loadLibrary(state: state, next: true)
        } else {
            await loadLibrary(state: state, refresh: refresh)
        }
        let request = libraryGeneration
        while !Task.isCancelled, account == connectionID, request == libraryGeneration,
              libraryState == state, hasMoreLibrary, libraryError == nil, !loadingLibrary {
            await loadLibrary(state: state, next: true)
        }
    }
    func loadSourceLinkingLibrary(refresh: Bool = false) async {
        guard connected else { return }
        let connection = connectionID
        if profile == nil { await refreshProfile() }
        guard !Task.isCancelled, connection == connectionID else { return }
        await loadCompleteLibrary(state: nil, refresh: refresh)
    }
    func loadLibrary(state: String?, refresh: Bool = false, next: Bool = false) async {
        guard connected else { return }
        if !next && (state != libraryState || refresh) {
            libraryGeneration = UUID(); libraryPage = 0; loadingLibrary = false
            if state != libraryState { library = []; libraryTotal = nil }
        }
        if !next && !refresh && state == libraryState && libraryPage > 0 { return }
        guard !loadingLibrary, !next || hasMoreLibrary else { return }
        libraryState = state; loadingLibrary = true; libraryError = nil
        let attempt = connectionID, request = libraryGeneration, page = next ? libraryPage + 1 : 1
        defer { if libraryGeneration == request { loadingLibrary = false } }
        do {
            let response = try await api.library(validCredential(), page: page, state: state)
            try Task.checkCancellation()
            guard connectionID == attempt, libraryGeneration == request else { return }
            var known = Set(next ? library.map(\.id) : [])
            let additions = response.items.filter { known.insert($0.id).inserted }
            if next && additions.isEmpty && response.hasNext { throw MangaBakaError.message("This page returned no new entries. Pull to refresh your library.") }
            library = next ? library + additions : additions
            for entry in response.items { entries[entry.id] = entry }
            libraryPage = page; hasMoreLibrary = response.hasNext; libraryTotal = response.total
        } catch is CancellationError {} catch { if connectionID == attempt, libraryGeneration == request { libraryError = error.localizedDescription } }
    }
    func loadEntry(_ series: MangaBakaSeries) async throws -> MangaBakaLibraryEntry? {
        let attempt = connectionID
        do {
            let value = try await api.entry(id: series.id, credential: validCredential())?.attaching(series)
            guard attempt == connectionID else { throw CancellationError() }
            entries[series.id] = value
            return value
        } catch {
            guard attempt == connectionID else { throw CancellationError() }
            throw error
        }
    }
    func save(_ series: MangaBakaSeries, update: MangaBakaLibraryUpdate, existing: Bool, expectedConnection: UUID? = nil) async throws {
        guard expectedConnection.map({ $0 == connectionID }) ?? true else { throw CancellationError() }
        guard saving.insert(series.id).inserted else { throw MangaBakaError.message("This entry is already being saved.") }
        let attempt = connectionID
        defer { saving.remove(series.id) }
        let key = try await validCredential()
        try await api.save(id: series.id, update: update, existing: existing, credential: key)
        guard attempt == connectionID else { throw CancellationError() }
        do {
            guard let confirmed = try await api.entry(id: series.id, credential: key)?.attaching(series) else { throw MangaBakaError.invalidResponse }
            guard attempt == connectionID else { throw CancellationError() }
            entries[series.id] = confirmed
            notice = "Saved to MangaBaka."
        } catch is CancellationError { throw CancellationError() }
        catch {
            guard attempt == connectionID else { throw CancellationError() }
            notice = "Saved on MangaBaka. Refresh to load the latest progress."
        }
        libraryPage = 0; revision = UUID()
    }
    func remove(_ series: MangaBakaSeries, expectedConnection: UUID? = nil) async throws {
        guard expectedConnection.map({ $0 == connectionID }) ?? true else { throw CancellationError() }
        guard saving.insert(series.id).inserted else { return }
        let attempt = connectionID
        defer { saving.remove(series.id) }
        try await api.remove(id: series.id, credential: validCredential())
        guard attempt == connectionID else { throw CancellationError() }
        entries[series.id] = nil; library.removeAll { $0.id == series.id }; libraryPage = 0
        notice = "Removed from your MangaBaka library."; revision = UUID()
    }
}
