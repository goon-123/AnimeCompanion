import XCTest
@testable import AnimeCore

final class DeviceSyncTests: XCTestCase {
    private let firstID = "00000000-0000-0000-0000-000000000001"
    private let secondID = "00000000-0000-0000-0000-000000000002"
    private func title(_ url: String = "/story") -> MangaTitleReference {
        .init(source: .init(extensionID: "example.extension", sourceID: "en", name: "Example", language: "en", homeURL: "https://example.com"),
              manga: .init(url: url, title: "Story"))
    }
    private func position(_ chapter: String, page: Int, completed: Bool = false) -> MangaReadingPosition {
        .init(chapterURL: chapter, chapterName: chapter, pageIndex: page, pageCount: 20, fraction: 0.3,
              completed: completed, updatedAt: Date(timeIntervalSince1970: 100))
    }
    private func initialized(_ payload: DeviceSyncPayload, id: String) throws -> DeviceSyncJournal {
        var journal = DeviceSyncJournal(deviceID: id)
        journal.observe(try payload.encodedValues()); journal.finishBootstrap()
        return journal
    }
    func testFirstConnectionUsesExistingCloudSettingsAndKeepsUniqueLocalBooks() throws {
        var a = DeviceSyncPayload(); a.preferences["appearance.scheme.v1"] = .string("dark")
        a.reading.save(title("/a"), saved: true)
        let cloud = try initialized(a, id: firstID)
        var b = DeviceSyncPayload(); b.preferences["appearance.scheme.v1"] = .string("system")
        b.reading.save(title("/b"), saved: true)
        var fresh = DeviceSyncJournal(deviceID: secondID)
        fresh.observe(try b.encodedValues())
        try fresh.document.merge(cloud.document); fresh.finishBootstrap()
        let merged = try DeviceSyncPayload(values: fresh.document.values)
        XCTAssertEqual(merged.preferences["appearance.scheme.v1"], .string("dark"))
        XCTAssertEqual(Set(merged.reading.records.map(\.title.id)), [title("/a").id, title("/b").id])
    }
    func testOfflineChangesToDifferentSettingsAndChaptersConverge() throws {
        var original = DeviceSyncPayload()
        original.preferences["appearance.scheme.v1"] = .string("light")
        original.preferences["library.layout"] = .string("grid")
        original.reading.save(title(), saved: true)
        let base = try initialized(original, id: firstID)
        var a = base, b = DeviceSyncJournal(deviceID: secondID)
        b.document = base.document; b.finishBootstrap(); b.acceptApplied(base.document.values, baseline: [:], desired: base.document.values)
        var one = original; one.preferences["appearance.scheme.v1"] = .string("dark")
        one.reading.record(title(), position: position("/chapter/1", page: 4))
        var two = original; two.preferences["library.layout"] = .string("list")
        two.reading.record(title(), position: position("/chapter/2", page: 8))
        a.observe(try one.encodedValues()); b.observe(try two.encodedValues())
        let aDoc = a.document, bDoc = b.document
        try a.document.merge(bDoc); try b.document.merge(aDoc)
        XCTAssertEqual(a.document, b.document)
        let merged = try DeviceSyncPayload(values: a.document.values)
        XCTAssertEqual(merged.preferences["appearance.scheme.v1"], .string("dark"))
        XCTAssertEqual(merged.preferences["library.layout"], .string("list"))
        XCTAssertEqual(merged.reading.record(title().id)?.position(for: "/chapter/1")?.pageIndex, 4)
        XCTAssertEqual(merged.reading.record(title().id)?.position(for: "/chapter/2")?.pageIndex, 8)
    }
    func testUnsaveUnpinAndUnlinkAreNotResurrectedByAnOfflineSnapshot() throws {
        var payload = DeviceSyncPayload(); payload.reading.save(title(), saved: true)
        payload.reading.pinnedSources.insert(title().source.id)
        let target = MangaSourceLinkTarget(accountID: "owned", seriesID: 1, title: "Story", searchTitles: [])
        payload.links.links[target.id] = MangaSourceLink(library: target, title: title())
        var journal = try initialized(payload, id: firstID)
        let stale = journal.document
        payload.reading.save(title(), saved: false); payload.reading.pinnedSources.removeAll(); payload.links.links.removeAll()
        journal.observe(try payload.encodedValues()); try journal.document.merge(stale)
        let restored = try DeviceSyncPayload(values: journal.document.values)
        XCTAssertFalse(restored.reading.record(title().id)!.saved)
        XCTAssertTrue(restored.reading.pinnedSources.isEmpty); XCTAssertTrue(restored.links.links.isEmpty)
        XCTAssertTrue(journal.document.entries.values.contains { $0.value == nil })
    }
    func testExplicitUnreadAndClearedHistoryPropagate() throws {
        var payload = DeviceSyncPayload(); payload.reading.record(title(), position: position("one", page: 19, completed: true))
        var journal = try initialized(payload, id: firstID)
        payload.reading.mark(title(), chapter: .init(url: "one", name: "One"), read: false)
        payload.reading.clearHistory(); journal.observe(try payload.encodedValues())
        let restored = try DeviceSyncPayload(values: journal.document.values)
        XCTAssertFalse(restored.reading.record(title().id)!.positions[0].completed)
        XCTAssertNil(restored.reading.record(title().id)?.lastReadAt)
    }
    func testLivePatchProtectsAnEditMadeWhileCloudIsDownloading() throws {
        let old = try DeviceSyncCoding.encode(DeviceSyncPreference.string("grid"))
        let cloud = try DeviceSyncCoding.encode(DeviceSyncPreference.string("list"))
        let live = try DeviceSyncCoding.encode(DeviceSyncPreference.string("custom"))
        let key = "preference.library.layout"
        XCTAssertEqual(DeviceSyncPayload.patch(current: [key: live], expected: [key: old], desired: [key: cloud])[key], live)
        XCTAssertEqual(DeviceSyncPayload.patch(current: [key: old], expected: [key: old], desired: [key: cloud])[key], cloud)
    }
    func testFailedExtensionApplicationStaysPendingInsteadOfBecomingADeletion() throws {
        let key = "preference.library.layout"
        let old = try DeviceSyncCoding.encode(DeviceSyncPreference.string("grid"))
        let new = try DeviceSyncCoding.encode(DeviceSyncPreference.string("list"))
        var journal = DeviceSyncJournal(deviceID: firstID)
        journal.observe([key: old]); journal.finishBootstrap()
        try journal.restore([key: new])
        journal.acceptApplied([key: old], baseline: [key: old], desired: [key: new])
        journal.observe([key: old])
        XCTAssertEqual(journal.document.values[key], new)
    }
    func testSameStampConflictIsCommutativeAndIdempotent() throws {
        let key = "preference.library.layout"
        var a = DeviceSyncDocument(), b = DeviceSyncDocument()
        a.entries[key] = .init(clock: 100, author: firstID, value: try DeviceSyncCoding.encode(DeviceSyncPreference.string("grid")))
        b.entries[key] = .init(clock: 100, author: secondID, value: try DeviceSyncCoding.encode(DeviceSyncPreference.string("list")))
        let originalA = a; try a.merge(b); try b.merge(originalA); XCTAssertEqual(a, b)
        try a.merge(a); XCTAssertEqual(a, b)
    }
    func testJournalAndBackupRoundTripWithoutDeviceSecrets() throws {
        var payload = DeviceSyncPayload(); payload.reading.save(title("/日本語?x=1&y=a.b"), saved: true)
        payload.preferences["discovery.dub.preferences.v1"] = .data(Data([0, 1, 2]))
        let journal = try initialized(payload, id: firstID)
        let saved = try DeviceSyncCoding.decode(DeviceSyncJournal.self, DeviceSyncCoding.encode(journal))
        XCTAssertEqual(saved.document, journal.document); XCTAssertEqual(saved.observed, journal.observed)
        let backup = DeviceSyncBackup(values: try payload.encodedValues())
        let data = try DeviceSyncCoding.encode(backup)
        let read = try DeviceSyncBackup.read(data)
        XCTAssertEqual(read.values, backup.values)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains(firstID))
        for secret in ["anilist.clientID", "playback.pending", "preview.addons", "deviceSync.folderBookmark.v1", "setup.lifecycle", "app.reset.inProgress"] {
            XCTAssertFalse(DeviceSyncPreferences.keys.contains(secret))
            XCTAssertThrowsError(try DeviceSyncPayload.validate(key: "preference." + secret, value: nil))
        }
    }
    func testInvalidAndFutureFilesFailBeforeApplying() throws {
        var doc = DeviceSyncDocument(); doc.version = 99
        XCTAssertThrowsError(try DeviceSyncDocument.read(DeviceSyncCoding.encode(doc)))
        doc = DeviceSyncDocument(); doc.entries["preference.library.layout"] = .init(clock: -1, author: firstID, value: Data())
        XCTAssertThrowsError(try doc.validate())
        XCTAssertThrowsError(try DeviceSyncBackup.read(Data("{}".utf8)))
        let wrong = try DeviceSyncCoding.encode(position("one", page: 3))
        XCTAssertThrowsError(try DeviceSyncPayload(values: ["book.position.\(DeviceSyncCoding.component(title().id)).\(DeviceSyncCoding.component("other"))": wrong]))
    }
    func testStorageActorPreservesInterleavedSourceLinks() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = MangaSourceLinkStorage(directory: directory)
        let first = MangaSourceLinkTarget(accountID: "owned", seriesID: 1, title: "First", searchTitles: [])
        let second = MangaSourceLinkTarget(accountID: "owned", seriesID: 2, title: "Second", searchTitles: [])
        let initial = try await storage.setSource(title("/old"), for: first)
        let baseline = try DeviceSyncPayload.linkValues(initial)
        var remote = initial; remote.links[first.id] = MangaSourceLink(library: first, title: title("/remote"))
        _ = try await storage.setSource(title("/during-sync"), for: first)
        _ = try await storage.setSource(title("/unique"), for: second)
        let merged = try await storage.applyDeviceSync(expected: baseline, desired: DeviceSyncPayload.linkValues(remote))
        XCTAssertEqual(merged.links[first.id]?.title.manga.url, "/during-sync")
        XCTAssertEqual(merged.links[second.id]?.title.manga.url, "/unique")
        let reloaded = try await MangaSourceLinkStorage(directory: directory).load()
        XCTAssertEqual(reloaded.links, merged.links)
    }
}
