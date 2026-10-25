import XCTest
@testable import AnimeCore

final class LibraryCustomizationTests: XCTestCase {
    func testDefaultHidesMangaAndKeepsOtherTabsInTheirOrder() {
        let value = AppTabPreferences()
        XCTAssertEqual(value.visible, [.explore, .library, .schedule, .news])
        XCTAssertEqual(value.hidden, [.manga]); XCTAssertEqual(value.selection(for: .manga), .explore)
    }
    func testReorderHideAndRelaunchPreserveEveryTabAndSelectedFallback() {
        var value = AppTabPreferences(order: [.news, .manga, .library, .explore, .schedule], hidden: [])
        value.setVisible(.manga, false); value.setVisible(.library, false)
        let reopened = AppTabPreferences(saved: value.saved)
        XCTAssertEqual(reopened, value); XCTAssertEqual(reopened.visible, [.news, .explore, .schedule])
        XCTAssertEqual(reopened.selection(for: .library), .news)
        XCTAssertEqual(reopened.selection(for: .schedule), .schedule)
        value.setVisible(.manga, true)
        XCTAssertEqual(value.visible, [.news, .manga, .explore, .schedule])
    }
    func testLastTabCannotBeHiddenAndDamagedOrOlderPreferencesAreRepaired() {
        var value = AppTabPreferences(order: [.news], hidden: Set(AppTab.allCases.filter { $0 != .news }))
        value.setVisible(.news, false); XCTAssertEqual(value.visible, [.news])
        let old = AppTabPreferences(saved: #"{"order":["news","news","retired-tab"],"hidden":["manga","retired-tab"]}"#)
        XCTAssertEqual(old.order, [.news, .explore, .library, .manga, .schedule])
        XCTAssertEqual(old.hidden, [.manga])
        let hidden = AppTabPreferences(saved: #"{"order":[],"hidden":["explore","library","manga","schedule","news"]}"#)
        XCTAssertEqual(hidden.visible, [.explore])
        XCTAssertEqual(AppTabPreferences(saved: "invalid"), AppTabPreferences())
    }
    func testContinuationRequiresReadingIntentAndLoadedImagesAndOnlyAdvancesOnce() {
        var gate = WebtoonChapterContinuation(); gate.reset(chapter: "one")
        func claim(_ gate: inout WebtoonChapterContinuation, ready: Bool = true) -> Bool {
            gate.claim(chapter: "one", enabled: true, hasNext: true, atEnd: true, imagesComplete: ready, allowed: true, zoomed: false)
        }
        XCTAssertFalse(claim(&gate), "Layout and restored offsets must not auto-skip a short chapter")
        gate.didScroll(); XCTAssertFalse(claim(&gate, ready: false), "Missing/failed image pages must prevent advancing")
        XCTAssertTrue(claim(&gate)); XCTAssertFalse(claim(&gate), "Repeated delegate callbacks must not skip multiple chapters")
        gate.reset(chapter: "two")
        XCTAssertFalse(claim(&gate), "An old chapter callback must not advance the new chapter")
        XCTAssertFalse(gate.claim(chapter: "two", enabled: true, hasNext: true, atEnd: true, imagesComplete: true, allowed: true, zoomed: false))
    }
    func testDisabledLastChapterZoomSheetsAndBackgroundDoNotConsumeContinuation() {
        var gate = WebtoonChapterContinuation(); gate.reset(chapter: "one"); gate.didScroll()
        for values in [(false, true, true, true, false), (true, false, true, true, false),
                       (true, true, false, true, false), (true, true, true, false, false), (true, true, true, true, true)] {
            XCTAssertFalse(gate.claim(chapter: "one", enabled: values.0, hasNext: values.1, atEnd: values.2,
                imagesComplete: true, allowed: values.3, zoomed: values.4))
        }
        XCTAssertTrue(gate.claim(chapter: "one", enabled: true, hasNext: true, atEnd: true, imagesComplete: true, allowed: true, zoomed: false))
    }
    func testAutomaticNextDefaultsOnForOldSavedReaderSettingsAndSavesAnOptOut() throws {
        var old = try JSONDecoder().decode(WebtoonPreferences.self, from: Data(#"{"autoScrollSpeed":120,"holdToScroll":false}"#.utf8))
        XCTAssertTrue(old.autoLoadNextChapter); XCTAssertEqual(old.autoScrollSpeed, 120); XCTAssertFalse(old.holdToScroll)
        old.autoLoadNextChapter = false
        let restored = try JSONDecoder().decode(WebtoonPreferences.self, from: JSONEncoder().encode(old))
        XCTAssertFalse(restored.autoLoadNextChapter); XCTAssertEqual(restored.autoScrollSpeed, 120)
    }
    private func anime(_ id: Int = 73, adult: Bool = false, status: String = "CURRENT") throws -> LibraryEntry {
        try JSONDecoder().decode(LibraryEntry.self, from: Data("{\"id\":\(id),\"mediaId\":\(id),\"status\":\"\(status)\",\"progress\":3,\"media\":{\"id\":\(id),\"title\":{\"english\":\"Harbor Anime\",\"native\":\"Owned native alias\"},\"isAdult\":\(adult)}}".utf8))
    }
    private func book(_ id: Int = 73, rating: String = "safe", state: String = "reading") throws -> MangaBakaLibraryEntry {
        try JSONDecoder().decode(MangaBakaLibraryEntry.self, from: Data("{\"series_id\":\(id),\"state\":\"\(state)\",\"progress_chapter\":4.5,\"series\":{\"id\":\(id),\"title\":\"Harbor Book\",\"content_rating\":\"\(rating)\",\"type\":\"novel\"}}".utf8))
    }
    func testCombinedLibraryKeepsProviderIdentitiesAndOriginalProgressUnits() throws {
        let watchedEntry = try anime(), readEntry = try book()
        let items = CombinedLibraryItem.merge(anime: [watchedEntry, watchedEntry], reading: [readEntry, readEntry], includeAdult: false)
        XCTAssertEqual(Set(items.map(\.id)), ["anilist:73", "mangabaka:73"])
        XCTAssertEqual(items.count, 2, "An adaptation and its original book are independent entries")
        for item in items {
            switch item { case .anime(let value): XCTAssertEqual(value.progressValue, 3)
            case .reading(let value): XCTAssertEqual(value.chapter, 4.5) }
        }
    }
    func testCombinedStatusAndAliasSearchComposeAndMatureContentIsFilteredImmediately() throws {
        let watched = try [anime(), anime(74, status: "PLANNING"), anime(75, adult: true)]
        let books = try [book(), book(74, rating: "erotica"), book(75, state: "paused"), book(76, rating: "unknown")]
        let safe = CombinedLibraryItem.merge(anime: watched, reading: books, includeAdult: false, status: .active)
        XCTAssertEqual(Set(safe.map(\.id)), ["anilist:73", "mangabaka:73"])
        let mature = CombinedLibraryItem.merge(anime: watched, reading: books, includeAdult: true, status: .active)
        XCTAssertEqual(Set(mature.map(\.id)), ["anilist:73", "anilist:75", "mangabaka:73", "mangabaka:74", "mangabaka:76"])
        let alias = CombinedLibraryItem.merge(anime: watched, reading: books, includeAdult: false, query: "native alias", status: .planned)
        XCTAssertEqual(alias.map(\.id), ["anilist:74"])
        let paused = CombinedLibraryItem.merge(anime: watched, reading: books, includeAdult: false, status: .paused)
        XCTAssertEqual(paused.map(\.id), ["mangabaka:75"])
    }
}
