import SwiftUI
import Security
import CryptoKit
import AuthenticationServices
import AnimeCore

private enum MangaBakaKeychain {
    private static let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.animecompanion.mangabaka", kSecAttrAccount as String: "connection"]
    static func load() throws -> MangaBakaCredential? {
        var q = base; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &value)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = value as? Data else { throw MangaBakaError.message("The saved MangaBaka connection could not be read.") }
        return try JSONDecoder().decode(MangaBakaCredential.self, from: data)
    }
    static func save(_ credential: MangaBakaCredential) throws {
        let data = try JSONEncoder().encode(credential)
        let status = SecItemUpdate(base as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var q = base; q[kSecValueData as String] = data
            q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(q as CFDictionary, nil) == errSecSuccess else { throw MangaBakaError.message("The MangaBaka connection could not be saved securely.") }
        } else if status != errSecSuccess { throw MangaBakaError.message("The MangaBaka connection could not be updated.") }
    }
    static func delete() throws {
        let result = SecItemDelete(base as CFDictionary)
        guard result == errSecSuccess || result == errSecItemNotFound else { throw MangaBakaError.message("The MangaBaka connection could not be removed.") }
    }
}

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
    func signIn(clientID: String, api: MangaBakaClient) async throws -> MangaBakaCredential {
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
            web.presentationContextProvider = self; web.prefersEphemeralWebBrowserSession = false
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
    let api = MangaBakaClient()
    @Published private(set) var connected = false
    @Published private(set) var connecting = false
    @Published private(set) var profile: MangaBakaProfile?
    @Published private(set) var revision = UUID()
    @Published private(set) var recommendationState = MangaBakaRecommendationsState()
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
    private var refreshTask: Task<MangaBakaCredential, Error>?
    private var recommendationTask: Task<Void, Never>?
    private var generation = UUID()
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
    func restore() async {
        guard !restored else { return }; restored = true
        do {
            guard let saved = try MangaBakaKeychain.load() else { return }
            credential = saved; connected = true
            let attempt = generation
            let value = try await api.profile(validCredential())
            guard attempt == generation else { return }
            profile = value; revision = UUID()
        } catch { accountError = error.localizedDescription }
    }
    func connect(apiKey: String? = nil) async {
        guard !connecting, saving.isEmpty else { return }; connecting = true; accountError = nil; notice = nil
        let attempt = generation
        defer { connecting = false }
        do {
            let candidate: MangaBakaCredential
            if let apiKey { candidate = try MangaBakaCredential(kind: .apiKey, secret: apiKey) }
            else { candidate = try await authentication.signIn(clientID: clientID, api: api) }
            let value = try await api.profile(candidate)
            guard generation == attempt else { return }
            try MangaBakaKeychain.save(candidate)
            generation = UUID(); refreshTask?.cancel(); refreshTask = nil
            clearLibrary(); credential = candidate; connected = true; profile = value; revision = UUID()
        } catch is CancellationError {} catch {
            if (error as NSError).domain != ASWebAuthenticationSessionError.errorDomain || (error as NSError).code != ASWebAuthenticationSessionError.canceledLogin.rawValue {
                accountError = error.localizedDescription
            }
        }
    }
    func disconnect() {
        do {
            try MangaBakaKeychain.delete(); generation = UUID(); authentication.cancel(); refreshTask?.cancel(); refreshTask = nil
            credential = nil; connected = false; profile = nil; accountError = nil; notice = nil; clearLibrary(); revision = UUID()
        } catch { accountError = error.localizedDescription }
    }
    private func clearLibrary() {
        recommendationTask?.cancel(); recommendationTask = nil
        recommendationState.reset()
        libraryGeneration = UUID(); library = []; entries = [:]; libraryState = nil; libraryPage = 0
        loadingLibrary = false; hasMoreLibrary = false; libraryTotal = nil; libraryError = nil
    }
    private func validCredential() async throws -> MangaBakaCredential {
        guard let current = credential else { throw MangaBakaError.unauthorized }
        guard current.needsRefresh() else { return current }
        let attempt = generation
        let work: Task<MangaBakaCredential, Error>
        if let existing = refreshTask { work = existing }
        else { work = Task { try await api.refresh(current) }; refreshTask = work }
        defer { if generation == attempt { refreshTask = nil } }
        let renewed = try await work.value
        guard generation == attempt else { throw CancellationError() }
        try MangaBakaKeychain.save(renewed); credential = renewed
        return renewed
    }
    func loadRecommendations(includeAdult: Bool, refresh: Bool = false) async {
        guard connected, !Task.isCancelled else { return }
        guard let attempt = recommendationState.begin(account: generation, revision: revision,
            includeAdult: includeAdult, refresh: refresh) else {
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
                let result = try await api.recommendations(validCredential(), includeAdult: includeAdult)
                try Task.checkCancellation()
                recommendationState.complete(result, for: attempt)
            } catch is CancellationError {} catch {
                if !Task.isCancelled { recommendationState.fail(error.localizedDescription, for: attempt) }
            }
        }
        recommendationTask = work
        await work.value
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
        let attempt = generation, request = libraryGeneration, page = next ? libraryPage + 1 : 1
        defer { if libraryGeneration == request { loadingLibrary = false } }
        do {
            let response = try await api.library(validCredential(), page: page, state: state)
            try Task.checkCancellation()
            guard generation == attempt, libraryGeneration == request else { return }
            var known = Set(next ? library.map(\.id) : [])
            let additions = response.items.filter { known.insert($0.id).inserted }
            if next && additions.isEmpty && response.hasNext { throw MangaBakaError.message("This page returned no new entries. Pull to refresh your library.") }
            library = next ? library + additions : additions
            for entry in response.items { entries[entry.id] = entry }
            libraryPage = page; hasMoreLibrary = response.hasNext; libraryTotal = response.total
        } catch is CancellationError {} catch { if generation == attempt, libraryGeneration == request { libraryError = error.localizedDescription } }
    }
    func loadEntry(_ series: MangaBakaSeries) async throws -> MangaBakaLibraryEntry? {
        let attempt = generation
        let value = try await api.entry(id: series.id, credential: validCredential())?.attaching(series)
        guard attempt == generation else { throw CancellationError() }
        entries[series.id] = value
        return value
    }
    func save(_ series: MangaBakaSeries, update: MangaBakaLibraryUpdate, existing: Bool) async throws {
        guard saving.insert(series.id).inserted else { throw MangaBakaError.message("This entry is already being saved.") }
        let attempt = generation
        defer { saving.remove(series.id) }
        let key = try await validCredential()
        try await api.save(id: series.id, update: update, existing: existing, credential: key)
        guard attempt == generation else { throw CancellationError() }
        do {
            guard let confirmed = try await api.entry(id: series.id, credential: key)?.attaching(series) else { throw MangaBakaError.invalidResponse }
            guard attempt == generation else { throw CancellationError() }
            entries[series.id] = confirmed
            notice = "Saved to MangaBaka."
        } catch is CancellationError { throw CancellationError() }
        catch {
            guard attempt == generation else { throw CancellationError() }
            notice = "Saved on MangaBaka. Refresh to load the latest progress."
        }
        libraryPage = 0; revision = UUID()
    }
    func remove(_ series: MangaBakaSeries) async throws {
        guard saving.insert(series.id).inserted else { return }
        let attempt = generation
        defer { saving.remove(series.id) }
        try await api.remove(id: series.id, credential: validCredential())
        guard attempt == generation else { throw CancellationError() }
        entries[series.id] = nil; library.removeAll { $0.id == series.id }; libraryPage = 0
        notice = "Removed from your MangaBaka library."; revision = UUID()
    }
}
