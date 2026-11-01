#if canImport(CryptoKit)
import XCTest
@testable import AnimeCore

final class AniListLibraryCacheTests: XCTestCase {
    func testEncryptedLibrarySurvivesRelaunchStaysCredentialScopedAndClearsOnSignOut() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let viewer = try JSONDecoder().decode(Viewer.self, from: Data(#"{"id":77,"name":"Private viewer"}"#.utf8))
        let entries = try JSONDecoder().decode([LibraryEntry].self, from: Data(#"[{"id":4,"mediaId":5,"status":"CURRENT","progress":7,"notes":"private tracking notes","media":{"id":5,"title":{"english":"Saved anime"}}}]"#.utf8))
        let fetchedAt = Date().addingTimeInterval(-3600)
        let cache = AniListLibraryCache(directory: folder)
        let saved = await cache.save(.init(viewer: viewer, entries: entries, fetchedAt: fetchedAt), credential: "owned-anilist-token")
        XCTAssertTrue(saved)
        let restored = await AniListLibraryCache(directory: folder).load(credential: "owned-anilist-token")
        XCTAssertEqual(restored?.viewer.id, 77); XCTAssertEqual(restored?.entries, entries)
        XCTAssertEqual(restored?.fetchedAt, fetchedAt)
        let other = await cache.load(credential: "another-account-token"); XCTAssertNil(other)
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).first)
        var bytes = try Data(contentsOf: file)
        for text in ["Private viewer", "private tracking notes", "owned-anilist-token"] { XCTAssertNil(bytes.range(of: Data(text.utf8))) }
        bytes[bytes.count - 1] ^= 1; try bytes.write(to: file)
        let tampered = await cache.load(credential: "owned-anilist-token"); XCTAssertNil(tampered)
        await cache.save(.init(viewer: viewer, entries: entries), credential: "owned-anilist-token")
        await cache.clear(credential: "owned-anilist-token")
        let removed = await cache.load(credential: "owned-anilist-token"); XCTAssertNil(removed)
    }
    func testExpiredSnapshotIsNotRestoredAndEmptyConfirmedLibraryIsValid() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let viewer = try JSONDecoder().decode(Viewer.self, from: Data(#"{"id":77,"name":"Viewer"}"#.utf8))
        let cache = AniListLibraryCache(directory: folder)
        await cache.save(.init(viewer: viewer, entries: [], savedAt: Date().addingTimeInterval(-31 * 86400)), credential: "token")
        let expired = await cache.load(credential: "token"); XCTAssertNil(expired)
        await cache.save(.init(viewer: viewer, entries: []), credential: "token")
        let empty = await cache.load(credential: "token"); XCTAssertEqual(empty?.entries.count, 0)
    }
    func testCredentialReplacementKeepsNewSnapshotAndOldSignOutCannotClearIt() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = try JSONDecoder().decode(Viewer.self, from: Data(#"{"id":77,"name":"First viewer"}"#.utf8))
        let second = try JSONDecoder().decode(Viewer.self, from: Data(#"{"id":88,"name":"Second viewer"}"#.utf8))
        let cache = AniListLibraryCache(directory: folder)
        await cache.save(.init(viewer: first, entries: []), credential: "first-token")
        await cache.save(.init(viewer: second, entries: []), credential: "second-token")
        await cache.clear(credential: "first-token")
        let restored = await cache.load(credential: "second-token")
        XCTAssertEqual(restored?.viewer.id, 88)
        let old = await cache.load(credential: "first-token"); XCTAssertNil(old)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).count, 1)
    }
}
#endif
