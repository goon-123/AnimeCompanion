#if canImport(CryptoKit)
import XCTest
@testable import AnimeCore

final class MangaBakaRecommendationCacheTests: XCTestCase {
    func testSavedAccountsKeepSeparateWeeklyCachesAndRemovalClearsOnlyOne() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let aID = UUID(), bID = UUID()
        let a = MangaBakaRecommendationCache(directory: directory, accountID: aID)
        let b = MangaBakaRecommendationCache(directory: directory, accountID: bID)
        let first = try MangaBakaCredential(kind: .apiKey, secret: "owned-account-A")
        let second = try MangaBakaCredential(kind: .apiKey, secret: "owned-account-B")
        try a.save(snapshot(81), credential: first); try b.save(snapshot(82), credential: second)
        let reopened = MangaBakaRecommendationCache(directory: directory, accountID: aID)
        XCTAssertEqual(try reopened.load(credential: first)?.payload.records().map(\.id), [81])
        XCTAssertEqual(try reopened.load(credential: first)?.fetchedAt, snapshot(81).fetchedAt)
        XCTAssertThrowsError(try reopened.load(credential: second))
        try a.clear()
        XCTAssertNil(try a.load(credential: first))
        XCTAssertEqual(try b.load(credential: second)?.payload.records().map(\.id), [82])
    }
    private func snapshot(_ id: Int = 81) -> MangaBakaRecommendationSnapshot {
        .init(payload: .init(response: Data("{\"results\":[{\"id\":\(id),\"title\":\"Owned private recommendation\",\"content_rating\":\"safe\"}]}".utf8)),
            fetchedAt: Date(timeIntervalSince1970: 100_000))
    }
    func testEncryptedCacheSurvivesRestartAndRejectsAnotherConnectionAndTampering() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = try MangaBakaCredential(kind: .apiKey, secret: "owned-test-connection-one")
        let second = try MangaBakaCredential(kind: .apiKey, secret: "owned-test-connection-two")
        let cache = MangaBakaRecommendationCache(directory: directory)
        XCTAssertNil(try cache.load(credential: first))
        try cache.save(snapshot(), credential: first)
        let reopened = MangaBakaRecommendationCache(directory: directory)
        let restored = try XCTUnwrap(reopened.load(credential: first))
        XCTAssertEqual(try restored.payload.records().map(\.id), [81])
        XCTAssertEqual(restored.fetchedAt, snapshot().fetchedAt)
        XCTAssertThrowsError(try reopened.load(credential: second))
        let file = directory.appendingPathComponent("recommendations.bin")
        var bytes = try Data(contentsOf: file)
        XCTAssertNil(bytes.range(of: Data("Owned private recommendation".utf8)))
        XCTAssertNil(bytes.range(of: Data(first.secret.utf8)))
        bytes[bytes.count - 1] ^= 1
        try bytes.write(to: file)
        XCTAssertThrowsError(try reopened.load(credential: first))
    }
    func testTokenRotationKeepsOriginalExpiryAndDisconnectRemovesSnapshot() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let old = try MangaBakaCredential(kind: .oauth, secret: "owned-old-access-token")
        let renewed = try MangaBakaCredential(kind: .oauth, secret: "owned-new-access-token")
        let cache = MangaBakaRecommendationCache(directory: directory)
        try cache.save(snapshot(), credential: old)
        let retained = try XCTUnwrap(cache.load(credential: old))
        try cache.save(retained, credential: renewed)
        XCTAssertThrowsError(try cache.load(credential: old))
        let latest = try XCTUnwrap(cache.load(credential: renewed))
        XCTAssertEqual(latest.refreshAt, retained.refreshAt)
        try cache.clear()
        XCTAssertNil(try cache.load(credential: renewed)); try cache.clear()
    }
    func testInvalidReplacementPreservesPreviouslySavedResult() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let credential = try MangaBakaCredential(kind: .apiKey, secret: "owned-test-connection")
        let cache = MangaBakaRecommendationCache(directory: directory)
        try cache.save(snapshot(), credential: credential)
        let invalid = MangaBakaRecommendationSnapshot(payload: .init(response: Data("invalid".utf8)))
        XCTAssertThrowsError(try cache.save(invalid, credential: credential))
        let oversized = MangaBakaRecommendationSnapshot(payload: .init(response: Data(repeating: 32, count: 6_000_001)))
        XCTAssertThrowsError(try cache.save(oversized, credential: credential))
        let restored = try XCTUnwrap(cache.load(credential: credential))
        XCTAssertEqual(try restored.payload.records().map(\.id), [81])
    }
}
#endif
