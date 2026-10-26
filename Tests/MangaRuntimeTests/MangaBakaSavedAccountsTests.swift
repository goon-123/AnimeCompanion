import XCTest
import Security
import AnimeCore
@testable import AnimeCompanion

private actor SavedAccountsTransport: HTTPTransport {
    private var holdFirstLibrary: Bool
    private var started = false
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var pendingLibrary: CheckedContinuation<Void, Never>?
    private var refreshStarted = false
    private var refreshWaiter: CheckedContinuation<Void, Never>?
    private var pendingRefresh: CheckedContinuation<Void, Never>?
    private var recommendationCalls = 0
    private var writes = 0
    init(holdFirstLibrary: Bool = false) { self.holdFirstLibrary = holdFirstLibrary }
    func waitForFirstLibrary() async {
        if started { return }
        await withCheckedContinuation { startWaiter = $0 }
    }
    func releaseLibrary() { pendingLibrary?.resume(); pendingLibrary = nil }
    func waitForRefresh() async {
        if refreshStarted { return }
        await withCheckedContinuation { refreshWaiter = $0 }
    }
    func releaseRefresh() { pendingRefresh?.resume(); pendingRefresh = nil }
    func counts() -> (recommendations: Int, writes: Int) { (recommendationCalls, writes) }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let url = try XCTUnwrap(request.url)
        if url == MangaBakaOAuth.tokenURL {
            refreshStarted = true; refreshWaiter?.resume(); refreshWaiter = nil
            await withCheckedContinuation { pendingRefresh = $0 }
            let payload: [String: Any] = ["access_token": "owned-renewed-a", "refresh_token": "owned-rotated-refresh-a", "expires_in": 3600, "token_type": "Bearer"]
            return (try JSONSerialization.data(withJSONObject: payload), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let key = request.value(forHTTPHeaderField: "X-API-Key") ?? (request.value(forHTTPHeaderField: "Authorization") == "Bearer owned-renewed-a" ? "owned-a" : "")
        let second = key == "owned-b"
        let id = second ? 202 : 101
        let series: [String: Any] = ["id": id, "title": second ? "Owned library B" : "Owned library A", "content_rating": "safe", "type": "manga"]
        let entry: [String: Any] = ["series_id": id, "state": "reading", "progress_chapter": second ? 20 : 10, "series": series]
        var status = 200
        let payload: [String: Any]
        if key != "owned-a" && key != "owned-b" {
            status = 401; payload = ["data": NSNull()]
        } else if url.path == "/v1/my/profile" {
            payload = ["data": ["id": second ? "reader-b" : "reader-a", "nickname": second ? "Reader B" : "Reader A", "rating_steps": 1]]
        } else if url.path == "/v1/my/library" {
            if !second && holdFirstLibrary {
                holdFirstLibrary = false; started = true; startWaiter?.resume(); startWaiter = nil
                await withCheckedContinuation { pendingLibrary = $0 }
            }
            payload = ["data": [entry], "pagination": ["page": 1, "count": 1, "next": NSNull()]]
        } else if url.path == "/v1/my/series/recommendations" {
            recommendationCalls += 1; payload = ["results": [series]]
        } else if url.path.hasPrefix("/v1/my/library/") {
            if request.httpMethod == "GET" { payload = ["data": entry] }
            else { writes += 1; payload = ["data": true] }
        } else { throw MangaBakaError.message("Unexpected owned test endpoint") }
        return (try JSONSerialization.data(withJSONObject: payload), HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

final class MangaBakaSavedAccountsTests: XCTestCase {
    private func profile(_ id: String) throws -> MangaBakaProfile {
        try JSONDecoder().decode(MangaBakaProfile.self, from: JSONSerialization.data(withJSONObject: ["id": id, "nickname": id, "rating_steps": 1]))
    }
    private func clean(_ service: String, _ directory: URL) {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service] as CFDictionary)
        try? FileManager.default.removeItem(at: directory)
    }
    @MainActor func testSavedLoginsCachesLibrariesAndFailedAddRemainAccountScopedAcrossRestart() async throws {
        let service = "com.animecompanion.saved-accounts-test." + UUID().uuidString
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { clean(service, directory) }
        let keychain = MangaBakaAccountKeychain(service: service), transport = SavedAccountsTransport()
        let api = MangaBakaClient(transport: transport, directory: nil, minimumRequestInterval: 0)
        let store = MangaBakaStore(api: api, keychain: keychain, cacheDirectory: directory)
        await store.restore(); await store.connect(apiKey: "owned-a")
        let a = try XCTUnwrap(store.activeAccountID)
        await store.loadRecommendations(contentFilter: .init())
        let date = store.recommendationState.fetchedAt
        await store.connect(apiKey: "owned-b")
        let b = try XCTUnwrap(store.activeAccountID)
        XCTAssertNotEqual(a, b); XCTAssertEqual(store.savedAccounts.count, 2)
        await store.loadCompleteLibrary(state: "reading")
        XCTAssertEqual(store.library.map(\.id), [202])
        await store.loadRecommendations(contentFilter: .init())
        XCTAssertEqual(store.recommendationState.items.map(\.id), [202])
        await store.connect(apiKey: "owned-rejected-key")
        XCTAssertEqual(store.activeAccountID, b); XCTAssertEqual(store.savedAccounts.count, 2)
        XCTAssertEqual(store.library.map(\.id), [202])
        store.selectAccount(a)
        XCTAssertTrue(store.library.isEmpty); XCTAssertTrue(store.entries.isEmpty)
        XCTAssertEqual(store.recommendationState.items.map(\.id), [101])
        XCTAssertEqual(store.recommendationState.fetchedAt, date)
        await store.loadRecommendations(contentFilter: .init())
        let counts = await transport.counts(); XCTAssertEqual(counts.recommendations, 2)
        let restored = MangaBakaStore(api: api, keychain: keychain, cacheDirectory: directory)
        await restored.restore()
        XCTAssertEqual(restored.activeAccountID, a); XCTAssertEqual(restored.savedAccounts.count, 2)
        XCTAssertEqual(restored.recommendationState.items.map(\.id), [101])
        await restored.loadCompleteLibrary(state: "reading")
        XCTAssertEqual(restored.library.map(\.id), [101])
        restored.removeAccount(b)
        XCTAssertEqual(restored.activeAccountID, a); XCTAssertEqual(restored.savedAccounts.count, 1)
        XCTAssertEqual(restored.library.map(\.id), [101])
        XCTAssertNil(try MangaBakaRecommendationCache(directory: directory, accountID: b).load(credential: .init(kind: .apiKey, secret: "owned-b")))
    }
    @MainActor func testLateOldLibraryCannotRepopulateSelectedAccountAndOldEditorsCannotWrite() async throws {
        let service = "com.animecompanion.saved-accounts-test." + UUID().uuidString
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { clean(service, directory) }
        let keychain = MangaBakaAccountKeychain(service: service), transport = SavedAccountsTransport(holdFirstLibrary: true)
        let api = MangaBakaClient(transport: transport, directory: nil, minimumRequestInterval: 0)
        let store = MangaBakaStore(api: api, keychain: keychain, cacheDirectory: directory)
        await store.restore(); await store.connect(apiKey: "owned-a")
        let a = try XCTUnwrap(store.activeAccountID)
        await store.connect(apiKey: "owned-b"); let b = try XCTUnwrap(store.activeAccountID)
        store.selectAccount(a); let oldConnection = store.connectionID
        let pending = Task { await store.loadLibrary(state: "reading", refresh: true) }
        await transport.waitForFirstLibrary()
        store.selectAccount(b)
        await store.loadLibrary(state: "reading", refresh: true)
        await transport.releaseLibrary(); await pending.value
        XCTAssertEqual(store.profile?.id, "reader-b"); XCTAssertEqual(store.library.map(\.id), [202])
        XCTAssertNil(store.entries[101])
        let series = try XCTUnwrap(store.library.first?.series)
        let update = try MangaBakaLibraryUpdate(state: "reading", chapter: 10, volume: nil, rating: nil, note: nil, isPrivate: true)
        do { try await store.save(series, update: update, existing: true, expectedConnection: oldConnection); XCTFail("Old editor must not save into the new account") }
        catch is CancellationError {} catch { XCTFail("Unexpected error") }
        do { try await store.remove(series, expectedConnection: oldConnection); XCTFail("Old removal must not affect the new account") }
        catch is CancellationError {} catch { XCTFail("Unexpected error") }
        let counts = await transport.counts(); XCTAssertEqual(counts.writes, 0)
        XCTAssertEqual(store.activeAccountID, b); XCTAssertEqual(store.savedAccounts.count, 2)
    }
    func testLegacyKeychainMigrationAndEmptyRegistryDoNotResurrectRemovedLogin() throws {
        let service = "com.animecompanion.saved-accounts-test." + UUID().uuidString
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { clean(service, directory) }
        let credential = try MangaBakaCredential(kind: .apiKey, secret: "owned-legacy-session")
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "connection"]
        var old = query; old[kSecValueData as String] = try JSONEncoder().encode(credential)
        XCTAssertEqual(SecItemAdd(old as CFDictionary, nil), errSecSuccess)
        let keychain = MangaBakaAccountKeychain(service: service)
        let migrated = try XCTUnwrap(keychain.load())
        XCTAssertTrue(migrated.migrated); XCTAssertEqual(migrated.accounts.selected?.credential, credential)
        var probe = query; probe[kSecReturnData as String] = true
        var result: CFTypeRef?
        XCTAssertEqual(SecItemCopyMatching(probe as CFDictionary, &result), errSecItemNotFound)
        let reopened = try XCTUnwrap(MangaBakaAccountKeychain(service: service).load())
        XCTAssertFalse(reopened.migrated); XCTAssertEqual(reopened.accounts, migrated.accounts)
        var empty = reopened.accounts; empty.remove(try XCTUnwrap(empty.selectedID)); try keychain.save(empty)
        XCTAssertTrue(try XCTUnwrap(keychain.load()).accounts.sessions.isEmpty)
    }
    @MainActor func testUnreadableRegistryIsPreservedWhenAnotherSignInIsAttempted() async throws {
        let service = "com.animecompanion.saved-accounts-test." + UUID().uuidString
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { clean(service, directory) }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "accounts.v1"]
        let bytes = Data(#"{"schema":99,"sessions":[]}"#.utf8)
        var item = query; item[kSecValueData as String] = bytes
        XCTAssertEqual(SecItemAdd(item as CFDictionary, nil), errSecSuccess)
        let transport = SavedAccountsTransport()
        let store = MangaBakaStore(api: MangaBakaClient(transport: transport, directory: nil, minimumRequestInterval: 0),
            keychain: MangaBakaAccountKeychain(service: service), cacheDirectory: directory)
        await store.restore(); await store.connect(apiKey: "owned-a")
        XCTAssertFalse(store.connected); XCTAssertNotNil(store.accountError)
        var probe = query; probe[kSecReturnData as String] = true
        var result: CFTypeRef?
        XCTAssertEqual(SecItemCopyMatching(probe as CFDictionary, &result), errSecSuccess)
        XCTAssertEqual(result as? Data, bytes)
        // If storage becomes readable again, retain its accounts while adding
        // another login instead of using the failed restore's empty memory.
        let keychain = MangaBakaAccountKeychain(service: service)
        var recovered = MangaBakaAccounts()
        let first = try recovered.add(profile: profile("reader-a"), credential: .init(kind: .apiKey, secret: "owned-a"))
        try keychain.save(recovered)
        await store.connect(apiKey: "owned-b")
        XCTAssertEqual(store.savedAccounts.count, 2)
        XCTAssertTrue(store.savedAccounts.contains { $0.id == first })
        XCTAssertEqual(store.profile?.id, "reader-b")
    }
    @MainActor func testRotationFinishesForItsOwningAccountAfterSwitchWithoutLosingEitherLogin() async throws {
        let service = "com.animecompanion.saved-accounts-test." + UUID().uuidString
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { clean(service, directory) }
        let keychain = MangaBakaAccountKeychain(service: service), transport = SavedAccountsTransport()
        let api = MangaBakaClient(transport: transport, directory: nil, minimumRequestInterval: 0)
        var saved = MangaBakaAccounts()
        let old = try MangaBakaCredential(kind: .oauth, secret: "owned-expired-a", refreshToken: "owned-refresh-a", expiresAt: .distantPast, clientID: "owned-client")
        let a = try saved.add(profile: profile("reader-a"), credential: old)
        let b = try saved.add(profile: profile("reader-b"), credential: .init(kind: .apiKey, secret: "owned-b"))
        try saved.select(a); try keychain.save(saved)
        let snapshot = MangaBakaRecommendationSnapshot(payload: .init(response: Data(#"{"results":[{"id":101,"title":"Owned cache A","content_rating":"safe"}]}"#.utf8)))
        let cache = MangaBakaRecommendationCache(directory: directory, accountID: a)
        try cache.save(snapshot, credential: old)
        let store = MangaBakaStore(api: api, keychain: keychain, cacheDirectory: directory)
        let restoring = Task { await store.restore() }
        await transport.waitForRefresh()
        store.selectAccount(b)
        await transport.releaseRefresh(); await restoring.value
        let restored = try XCTUnwrap(keychain.load()?.accounts)
        XCTAssertEqual(store.activeAccountID, b); XCTAssertEqual(restored.selectedID, b)
        let rotated = try XCTUnwrap(restored.sessions.first { $0.id == a }?.credential)
        XCTAssertEqual(rotated.secret, "owned-renewed-a"); XCTAssertEqual(rotated.refreshToken, "owned-rotated-refresh-a")
        XCTAssertEqual(restored.sessions.first { $0.id == b }?.credential.secret, "owned-b")
        XCTAssertEqual(try cache.load(credential: rotated)?.fetchedAt, snapshot.fetchedAt)
        XCTAssertThrowsError(try cache.load(credential: old))
    }
}
