import XCTest
@testable import AnimeCore

final class MangaBakaAccountsTests: XCTestCase {
    private func profile(_ id: String, name: String? = nil) throws -> MangaBakaProfile {
        try JSONDecoder().decode(MangaBakaProfile.self, from: JSONSerialization.data(withJSONObject: ["id": id, "nickname": name ?? id, "rating_steps": 5]))
    }
    private func credential(_ name: String) throws -> MangaBakaCredential { try .init(kind: .apiKey, secret: "owned-test-" + name) }
    private func reopen(_ value: MangaBakaAccounts) throws -> MangaBakaAccounts {
        try JSONDecoder().decode(MangaBakaAccounts.self, from: JSONEncoder().encode(value))
    }
    func testMultipleAccountsAndSelectedIdentitySurviveRestart() throws {
        var accounts = MangaBakaAccounts()
        let first = try accounts.add(profile: profile("reader-a"), credential: credential("a"))
        let second = try accounts.add(profile: profile("reader-b"), credential: credential("b"))
        XCTAssertNotEqual(first, second); XCTAssertEqual(accounts.selectedID, second)
        try accounts.select(first)
        let restored = try reopen(accounts)
        XCTAssertEqual(restored, accounts); XCTAssertEqual(restored.selected?.credential, try credential("a"))
        XCTAssertEqual(restored.identities.map(\.name), ["reader-a", "reader-b"])
    }
    func testReconnectDeduplicatesByServerIdentityAndKeepsStableCacheID() throws {
        var accounts = MangaBakaAccounts()
        let first = try accounts.add(profile: profile("reader-a"), credential: credential("a"))
        let second = try accounts.add(profile: profile("reader-b"), credential: credential("b"))
        let reconnected = try accounts.add(profile: profile("reader-a", name: "Updated name"), credential: credential("renewed-a"))
        XCTAssertEqual(reconnected, first); XCTAssertEqual(accounts.sessions.count, 2)
        XCTAssertEqual(accounts.selected?.profile?.name, "Updated name")
        XCTAssertEqual(accounts.sessions.first { $0.id == second }?.credential, try credential("b"))
    }
    func testMigratedConnectionBindsToVerifiedProfileWithoutChangingLocalID() throws {
        var accounts = MangaBakaAccounts(legacy: try credential("old"))
        let id = try XCTUnwrap(accounts.selectedID)
        XCTAssertNil(accounts.selected?.profile)
        XCTAssertEqual(try accounts.updateProfile(profile("reader-a"), for: id), id)
        XCTAssertEqual(try reopen(accounts).selected?.profile?.id, "reader-a")
        let before = accounts
        XCTAssertThrowsError(try accounts.updateProfile(profile("wrong-person"), for: id))
        XCTAssertEqual(accounts, before)
    }
    func testDuplicateLegacyIdentityMergesOnlyItsOwnSession() throws {
        var accounts = MangaBakaAccounts(legacy: try credential("legacy-a"))
        let legacy = try XCTUnwrap(accounts.selectedID)
        let canonical = try accounts.add(profile: profile("reader-a"), credential: credential("new-a"))
        let other = try accounts.add(profile: profile("reader-b"), credential: credential("b"))
        try accounts.select(legacy)
        XCTAssertEqual(try accounts.updateProfile(profile("reader-a"), for: legacy), canonical)
        XCTAssertEqual(accounts.selectedID, canonical); XCTAssertEqual(accounts.sessions.count, 2)
        XCTAssertEqual(accounts.sessions.first { $0.id == other }?.credential, try credential("b"))
        XCTAssertEqual(try reopen(accounts), accounts)
    }
    func testCredentialRotationUpdatesOnlyTheRequestedSavedAccount() throws {
        var accounts = MangaBakaAccounts()
        let a = try accounts.add(profile: profile("a"), credential: credential("a"))
        let b = try accounts.add(profile: profile("b"), credential: credential("b"))
        try accounts.updateCredential(credential("rotated-a"), for: a)
        XCTAssertEqual(accounts.selectedID, b); XCTAssertEqual(accounts.selected?.credential, try credential("b"))
        XCTAssertEqual(accounts.sessions.first { $0.id == a }?.credential, try credential("rotated-a"))
        XCTAssertThrowsError(try accounts.updateCredential(credential("missing"), for: UUID()))
    }
    func testRemovingOneAccountPreservesTheOthersAndTheLastRemovalPersistsEmpty() throws {
        var accounts = MangaBakaAccounts()
        let a = try accounts.add(profile: profile("a"), credential: credential("a"))
        let b = try accounts.add(profile: profile("b"), credential: credential("b"))
        let c = try accounts.add(profile: profile("c"), credential: credential("c"))
        accounts.remove(b); XCTAssertEqual(accounts.selectedID, c)
        accounts.remove(c); XCTAssertEqual(accounts.selectedID, a)
        XCTAssertEqual(try reopen(accounts).selected?.credential, try credential("a"))
        accounts.remove(a); XCTAssertTrue(try reopen(accounts).sessions.isEmpty)
        XCTAssertNil(try reopen(accounts).selected)
    }
    func testInvalidSelectionAndFutureOrDuplicateSavedRegistriesAreRejected() throws {
        var accounts = MangaBakaAccounts()
        try accounts.add(profile: profile("a"), credential: credential("a"))
        let before = accounts
        XCTAssertThrowsError(try accounts.select(UUID())); XCTAssertEqual(accounts, before)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(accounts)) as? [String: Any])
        let records = try XCTUnwrap(object["sessions"] as? [[String: Any]])
        object["sessions"] = records + records
        XCTAssertThrowsError(try JSONDecoder().decode(MangaBakaAccounts.self, from: JSONSerialization.data(withJSONObject: object)))
        object["sessions"] = records; object["schema"] = 99
        XCTAssertThrowsError(try JSONDecoder().decode(MangaBakaAccounts.self, from: JSONSerialization.data(withJSONObject: object)))
    }
}
