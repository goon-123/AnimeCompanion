import XCTest
@testable import AnimeCore

final class AppDataResetTests: XCTestCase {
    private func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }
    func testOldWriterCannotResurrectFilesAfterResetAndNewSessionCanSave() throws {
        let root = try temporaryRoot(), file = root.appendingPathComponent("reading.json")
        let epoch = AppDataEpoch(), old = AppDataSession(epoch: epoch)
        try old.write(Data("saved position".utf8), to: file)
        epoch.beginReset()
        let duringReset = AppDataSession(epoch: epoch)
        XCTAssertThrowsError(try old.write(Data("stale".utf8), to: file))
        XCTAssertThrowsError(try duringReset.write(Data("too early".utf8), to: file))
        try FileManager.default.removeItem(at: file)
        epoch.finishReset()
        XCTAssertThrowsError(try old.write(Data("late network callback".utf8), to: file))
        XCTAssertThrowsError(try duringReset.write(Data("late initializer".utf8), to: file))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        let fresh = AppDataSession(epoch: epoch)
        try fresh.write(Data("new session".utf8), to: file)
        XCTAssertEqual(try Data(contentsOf: file), Data("new session".utf8))
    }
    func testSecureWriterClosureCannotRunFromOldSession() throws {
        let epoch = AppDataEpoch(), old = AppDataSession(epoch: epoch)
        var secret = "before reset"
        epoch.beginReset(); secret = ""; epoch.finishReset()
        XCTAssertThrowsError(try old.perform { secret = "restored old token" })
        XCTAssertEqual(secret, "")
        try AppDataSession(epoch: epoch).perform { secret = "new login" }
        XCTAssertEqual(secret, "new login")
    }
    func testResetClearsHiddenFilesNestedExtensionsAndHistoryButKeepsOtherDirectories() throws {
        let root = try temporaryRoot()
        let data = root.appendingPathComponent("Application Support", isDirectory: true)
        let outside = root.appendingPathComponent("Untouched", isDirectory: true)
        try FileManager.default.createDirectory(at: data.appendingPathComponent("extensions"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        for name in [".private-cache", "reading.json", "extensions/source.apk"] { try Data("owned".utf8).write(to: data.appendingPathComponent(name)) }
        try Data("keep".utf8).write(to: outside.appendingPathComponent("keep"))
        try AppLocalDataReset.eraseContents(of: [data], inside: root)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: data.path), [])
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.appendingPathComponent("keep").path))
    }
    func testEntirePlanIsValidatedBeforeDeletingAnything() throws {
        let root = try temporaryRoot(), outside = try temporaryRoot()
        let data = root.appendingPathComponent("data", isDirectory: true)
        try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
        let file = data.appendingPathComponent("keep.json")
        try Data().write(to: file)
        XCTAssertThrowsError(try AppLocalDataReset.eraseContents(of: [data, outside], inside: root))
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        XCTAssertThrowsError(try AppLocalDataReset.eraseContents(of: [root], inside: root))
    }
    func testSymbolicLinkCannotEscapeTheContainer() throws {
        let root = try temporaryRoot(), outside = try temporaryRoot()
        let link = root.appendingPathComponent("linked")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        let file = outside.appendingPathComponent("keep")
        try Data().write(to: file)
        XCTAssertThrowsError(try AppLocalDataReset.eraseContents(of: [link], inside: root))
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }
    func testResetOfMissingStorageIsIdempotent() throws {
        let root = try temporaryRoot(), missing = root.appendingPathComponent("nothing")
        try AppLocalDataReset.eraseContents(of: [missing], inside: root)
        try AppLocalDataReset.eraseContents(of: [missing], inside: root)
    }
}
