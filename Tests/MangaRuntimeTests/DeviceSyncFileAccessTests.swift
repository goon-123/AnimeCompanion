import XCTest
import AnimeCore
@testable import AnimeCompanion

final class DeviceSyncFileAccessTests: XCTestCase {
    private func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
    func testWritableFolderCreatesItsSyncDirectoryAndLeavesOtherFilesAlone() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let selected = root.appendingPathComponent("Selected", isDirectory: true)
        try FileManager.default.createDirectory(at: selected, withIntermediateDirectories: true)
        let unrelated = selected.appendingPathComponent("keep.txt")
        try Data("kept".utf8).write(to: unrelated)
        let files = DeviceSyncFiles(journalDirectory: root.appendingPathComponent("Journal"))
        try await files.validateFolder(selected)
        XCTAssertEqual(try String(contentsOf: unrelated), "kept")
        let syncRoot = selected.appendingPathComponent("AnimeCompanion Sync", isDirectory: true)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: syncRoot.path), [])
        let documents = try await files.readFolder(selected)
        XCTAssertTrue(documents.isEmpty)
    }
    func testCapturedFolderBookmarkResolvesForPersistentWrites() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let selected = root.appendingPathComponent("Selected", isDirectory: true)
        try FileManager.default.createDirectory(at: selected, withIntermediateDirectories: true)
        let bookmark = try DeviceSyncFiles.bookmarkSelection(selected)
        let files = DeviceSyncFiles(journalDirectory: root.appendingPathComponent("Journal"))
        let restored = try await files.resolveBookmark(bookmark)
        try await files.validateFolder(restored.url)
        var payload = DeviceSyncPayload(); payload.preferences["appearance.scheme.v1"] = .string("dark")
        var journal = DeviceSyncJournal()
        journal.observe(try payload.encodedValues()); journal.finishBootstrap()
        try await files.writeFolder(restored.url, journal: journal)
        let documents = try await files.readFolder(restored.url)
        XCTAssertEqual(documents.count, 1)
        XCTAssertEqual(documents.first, journal.document)
    }
    func testAFileCannotBeSavedAsTheSyncFolder() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("file.txt")
        try Data("kept".utf8).write(to: file)
        let files = DeviceSyncFiles(journalDirectory: root.appendingPathComponent("Journal"))
        do { try await files.validateFolder(file); XCTFail("A regular file is not a folder") } catch {}
        XCTAssertEqual(try String(contentsOf: file), "kept")
        XCTAssertThrowsError(try DeviceSyncFiles.bookmarkSelection(file))
    }
    func testMissingFolderIsReportedRatherThanTreatedAsAnEmptyCloud() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let missing = root.appendingPathComponent("Missing", isDirectory: true)
        let files = DeviceSyncFiles(journalDirectory: root.appendingPathComponent("Journal"))
        do { _ = try await files.readFolder(missing); XCTFail("Unavailable storage must not bootstrap an empty cloud") } catch {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path))
    }
}
