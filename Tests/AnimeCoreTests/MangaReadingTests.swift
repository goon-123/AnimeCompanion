import XCTest
@testable import AnimeCore

final class MangaReadingTests: XCTestCase {
    func testChapterMetadataRoundTripsAndOlderSavedChaptersRemainReadable() throws {
        let chapter = SourceMangaChapter(url: "/owned/9000000000002", name: "Alternate", chapterNumber: 2.5, memo: "{\"chapterId\":9000000000002}")
        XCTAssertEqual(try JSONDecoder().decode(SourceMangaChapter.self, from: JSONEncoder().encode(chapter)), chapter)
        let legacy = Data("{\"url\":\"/owned/1\",\"name\":\"One\",\"uploadedAt\":0,\"scanlator\":\"\"}".utf8)
        let restored = try JSONDecoder().decode(SourceMangaChapter.self, from: legacy)
        XCTAssertNil(restored.memo); XCTAssertNil(restored.chapterNumber)
    }
    private func title(source: String = "en", url: String = "/story", package: String = "example") -> MangaTitleReference {
        MangaTitleReference(source: MangaSourceReference(extensionID: package, sourceID: source, name: "Source",
            language: source, homeURL: "https://example.com"), manga: SourceManga(url: url, title: "Story"))
    }
    private func point(_ chapter: String = "/chapter/1", page: Int = 2, completed: Bool = false, at: TimeInterval = 100) -> MangaReadingPosition {
        MangaReadingPosition(chapterURL: chapter, chapterName: "Chapter 1", pageIndex: page, pageCount: 8,
            fraction: 0.42, completed: completed, updatedAt: Date(timeIntervalSince1970: at))
    }
    func testSourcePackageAndURLIdentitiesDoNotShareProgress() {
        var state = MangaReadingState()
        let original = title()
        state.record(original, position: point())
        XCTAssertEqual(state.record(original.id)?.positions.count, 1)
        XCTAssertNil(state.record(title(source: "es").id))
        XCTAssertNil(state.record(title(package: "another").id))
        XCTAssertNil(state.record(title(url: "/another").id))
        XCTAssertNotEqual(title(source: "a.b", url: "/c").id, title(source: "a", url: "b./c").id)
    }
    func testProgressClampsInvalidValuesAndNewPageCountsWithoutLosingStripFraction() throws {
        let p = MangaReadingPosition(chapterURL: "one", chapterName: "One", pageIndex: -3, pageCount: 20, fraction: .nan)
        XCTAssertEqual(p.pageIndex, 0); XCTAssertEqual(p.fraction, 0)
        let restored = point(page: 7).clamped(to: 3)
        XCTAssertEqual(restored.pageIndex, 2); XCTAssertEqual(restored.pageCount, 3); XCTAssertEqual(restored.fraction, 0.42)
        let decoded = try JSONDecoder().decode(MangaReadingPosition.self, from: JSONEncoder().encode(restored))
        XCTAssertEqual(decoded, restored)
    }
    func testLateWritesCannotRewindProgressAndReadFlagRequiresExplicitUnread() {
        let t = title()
        var state = MangaReadingState()
        state.record(t, position: point(page: 6, completed: true, at: 300))
        state.record(t, position: point(page: 1, at: 200))
        XCTAssertEqual(state.record(t.id)?.position(for: "/chapter/1")?.pageIndex, 6)
        state.record(t, position: point(page: 1, at: 400))
        XCTAssertTrue(state.record(t.id)!.positions[0].completed)
        state.mark(t, chapter: SourceMangaChapter(url: "/chapter/1", name: "One"), read: false, now: Date(timeIntervalSince1970: 500))
        XCTAssertFalse(state.record(t.id)!.positions[0].completed)
        XCTAssertEqual(state.record(t.id)?.lastReadAt, Date(timeIntervalSince1970: 400))
    }
    func testEmptyOrFailedChapterDoesNotCreateHistoryAndFavoriteIsExplicit() {
        var state = MangaReadingState()
        let t = title()
        state.record(t, position: MangaReadingPosition(chapterURL: "one", chapterName: "One", pageIndex: 0, pageCount: 0, fraction: 0))
        XCTAssertTrue(state.records.isEmpty)
        state.record(t, position: point())
        XCTAssertFalse(state.record(t.id)!.saved)
        state.save(t, saved: true); state.save(t, saved: false)
        XCTAssertNotNil(state.record(t.id)?.lastReadAt); XCTAssertEqual(state.record(t.id)?.positions.count, 1)
    }
    func testChapterDirectionKeepsSpecialsDuplicatesAndFractionalChaptersInSequence() {
        let newest = [SourceMangaChapter(url: "three", name: "Chapter 3", chapterNumber: 3),
                      SourceMangaChapter(url: "special", name: "A special"),
                      SourceMangaChapter(url: "half", name: "Chapter 2.5", chapterNumber: 2.5),
                      SourceMangaChapter(url: "two", name: "Chapter 2"),
                      SourceMangaChapter(url: "one", name: "Chapter 1"),
                      SourceMangaChapter(url: "one", name: "Duplicate")]
        let ordered = MangaChapterSequence.readingOrder(newest)
        XCTAssertEqual(ordered.map(\.url), ["one", "two", "half", "special", "three"])
        XCTAssertEqual(MangaChapterSequence.readingOrder(ordered), ordered)
        // The host defaults unset native numbers to zero. Explicit chapter
        // names still establish direction, including an ascending source.
        let unnamedNumbers = (0...3).map { SourceMangaChapter(url: "n\($0)", name: "Chapter \($0)", chapterNumber: 0) }
        XCTAssertEqual(MangaChapterSequence.readingOrder(unnamedNumbers), unnamedNumbers)
    }
    func testContinueResumesUnfinishedThenMovesToFollowingUnreadChapter() {
        let chapters = (1...3).map { SourceMangaChapter(url: "/chapter/\($0)", name: "Chapter \($0)", chapterNumber: Double($0)) }
        let t = title()
        var state = MangaReadingState()
        state.record(t, position: point("/chapter/2"))
        XCTAssertEqual(MangaChapterSequence.nextToRead(chapters, record: state.record(t.id))?.url, "/chapter/2")
        state.record(t, position: point("/chapter/2", completed: true, at: 200))
        XCTAssertEqual(MangaChapterSequence.nextToRead(chapters, record: state.record(t.id))?.url, "/chapter/3")
    }
    func testMetadataRefreshPreservesSourceIdentityAndUsefulExistingFields() {
        let original = SourceManga(url: "stable-id", title: "Story", author: "Writer", thumbnailURL: "https://example.com/a.jpg")
        let details = SourceManga(url: "", title: "Updated", description: "Description", status: 2)
        let merged = original.merging(details)
        XCTAssertEqual(merged.url, "stable-id"); XCTAssertEqual(merged.title, "Updated")
        XCTAssertEqual(merged.author, "Writer"); XCTAssertEqual(merged.thumbnailURL, original.thumbnailURL)
    }
    func testPreferencesAndRecentSourcesHaveUsefulBounds() {
        var state = MangaReadingState()
        for i in 0..<30 { state.visitSource(String(i)) }
        state.visitSource("29")
        XCTAssertEqual(state.recentSources.count, 20); XCTAssertEqual(state.recentSources.first, "29")
        XCTAssertEqual(Set(state.recentSources).count, 20)
        var p = WebtoonPreferences(); p.sidePadding = .infinity; p.autoScrollSpeed = -100; p.normalize()
        XCTAssertEqual(p.sidePadding, 0); XCTAssertEqual(p.autoScrollSpeed, 15)
    }
    func testReadingStateSurvivesRestartWithFavoritesPinAndExactStripPosition() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = MangaReadingStorage(directory: root), t = title(), p = point()
        _ = try await storage.update { value in value.save(t, saved: true); value.record(t, position: p); value.pinnedSources.insert(t.source.id) }
        let reloaded = try await MangaReadingStorage(directory: root).load()
        XCTAssertTrue(reloaded.record(t.id)!.saved)
        XCTAssertEqual(reloaded.record(t.id)?.positions.first, p)
        XCTAssertTrue(reloaded.pinnedSources.contains(t.source.id))
    }
    func testCorruptStateAndFailedWritesKeepPreviousData() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let path = root.appendingPathComponent("reading.json")
        let corrupt = Data("unreadable".utf8)
        try corrupt.write(to: path)
        do { _ = try await MangaReadingStorage(directory: root).update { $0.save(self.title(), saved: true) }; XCTFail("Corrupt state overwritten") }
        catch {}
        XCTAssertEqual(try Data(contentsOf: path), corrupt)
        try FileManager.default.removeItem(at: path)
        let storage = MangaReadingStorage(directory: root), t = title()
        _ = try await storage.update { $0.save(t, saved: true) }
        try FileManager.default.removeItem(at: path)
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: false)
        do { _ = try await storage.update { $0.save(t, saved: false) }; XCTFail("Write unexpectedly succeeded") } catch {}
        let retained = try await storage.load()
        XCTAssertTrue(retained.record(t.id)!.saved)
    }
}
