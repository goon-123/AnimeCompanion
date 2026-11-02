import XCTest
@testable import AnimeCore

final class SeriesDetailLayoutTests: XCTestCase {
    func testLegacyOrderMigratesAndMergedDubSectionIsNoLongerSeparate() {
        let layout = SeriesDetailLayout(page: .anime, saved: #"["reviews","dubSchedule","information","watchlist"]"#)
        XCTAssertEqual(Array(layout.order.prefix(3)), [.reviews, .information, .watchlist])
        XCTAssertFalse(layout.order.contains(.dubSchedule))
        XCTAssertTrue(layout.hidden.isEmpty)
        XCTAssertEqual(SeriesDetailLayout(page: .anime, saved: layout.saved), layout)
    }
    func testVisibilitySurvivesRelaunchAndMovingHiddenSectionsKeepsTheirPosition() {
        var layout = SeriesDetailLayout(page: .anime)
        layout.setVisible(.synopsis, false)
        let index = layout.order.firstIndex(of: .synopsis)!
        layout.move(fromOffsets: IndexSet(integer: index), toOffset: 0)
        var restored = SeriesDetailLayout(page: .anime, saved: layout.saved)
        XCTAssertEqual(restored.order.first, .synopsis)
        XCTAssertFalse(restored.visible.contains(.synopsis))
        restored.setVisible(.synopsis, true)
        XCTAssertEqual(restored.visible.first, .synopsis)
    }
    func testHideAllAndShowAllDoNotResetOrderOrOtherPageTypes() {
        var layout = SeriesDetailLayout(page: .reader)
        layout.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        let order = layout.order
        layout.setAllVisible(false)
        let restored = SeriesDetailLayout(page: .reader, saved: layout.saved)
        XCTAssertTrue(restored.visible.isEmpty)
        XCTAssertEqual(restored.order, order)
        layout.setAllVisible(true)
        XCTAssertEqual(layout.visible, order)
        XCTAssertEqual(SeriesDetailLayout(page: .manga).visible, SeriesDetailPage.manga.sections)
    }
    func testVisibilityRejectsForeignAndRemovedSectionsWithoutLosingValidSettings() {
        let saved = #"{"order":["publication","synopsis"],"hidden":["synopsis","dubSchedule","actors","chapters"]}"#
        var layout = SeriesDetailLayout(page: .manga, saved: saved)
        XCTAssertEqual(layout.hidden, [.synopsis])
        XCTAssertEqual(layout.order.first, .publication)
        layout.setVisible(.chapters, false)
        XCTAssertEqual(layout.hidden, [.synopsis])
        let withoutVisibility = SeriesDetailLayout(page: .anime, saved: #"{"order":["reviews","information"]}"#)
        XCTAssertTrue(withoutVisibility.hidden.isEmpty)
        XCTAssertEqual(withoutVisibility.order.first, .reviews)
    }
    func testSavedOrdersSurviveReopeningAndEachPageHasItsOwnKey() {
        var layout = SeriesDetailLayout(page: .anime)
        let synopsis = layout.order.firstIndex(of: .synopsis)!
        layout.move(fromOffsets: IndexSet(integer: synopsis), toOffset: 0)
        let restored = SeriesDetailLayout(page: .anime, saved: layout.saved)
        XCTAssertEqual(restored.order.first, .synopsis)
        XCTAssertEqual(restored, layout)
        XCTAssertEqual(Set(SeriesDetailPage.allCases.map(\.storageKey)).count, 3)
        XCTAssertEqual(SeriesDetailLayout(page: .reader).order.first, .reading)
    }
    func testUnknownDuplicatesAndRemovedSectionsDoNotHideAvailableContent() {
        let saved = #"["reviews","actors","synopsis","reviews","read","chapters","future-section"]"#
        let layout = SeriesDetailLayout(page: .anime, saved: saved)
        XCTAssertEqual(Array(layout.order.prefix(2)), [.reviews, .synopsis])
        XCTAssertEqual(Set(layout.order), Set(SeriesDetailPage.anime.sections))
        XCTAssertEqual(layout.order.count, SeriesDetailPage.anime.sections.count)
        XCTAssertEqual(Array(layout.order.dropFirst(2)), SeriesDetailPage.anime.sections.filter { ![.reviews, .synopsis].contains($0) })
    }
    func testMangaOrderDoesNotImportAnimeOrReaderOnlySections() {
        let layout = SeriesDetailLayout(page: .manga, saved: #"["chapters","publication","broadcast","reading","publication"]"#)
        XCTAssertEqual(Array(layout.order.prefix(2)), [.publication, .reading])
        XCTAssertFalse(layout.order.contains(.broadcast))
        XCTAssertFalse(layout.order.contains(.chapters))
        XCTAssertTrue(layout.order.contains(.coverage))
    }
    func testMovingMultipleRowsAndMovingToTheEndUsesOriginalIndices() {
        var layout = SeriesDetailLayout(page: .reader)
        let original = layout.order
        layout.move(fromOffsets: IndexSet([0, 2]), toOffset: original.count)
        XCTAssertEqual(layout.order, [original[1], original[3], original[4], original[0], original[2]])
        layout.move(fromOffsets: IndexSet(integer: 4), toOffset: 0)
        XCTAssertEqual(layout.order.first, original[2])
        XCTAssertEqual(SeriesDetailLayout(page: .reader, saved: layout.saved).order, layout.order)
    }
    func testMalformedPreferencesAndInvalidMovesPreserveAUsableLayout() {
        for saved in ["", "{bad-json", "[]", String(repeating: "x", count: 16_385)] {
            XCTAssertEqual(SeriesDetailLayout(page: .anime, saved: saved).order, SeriesDetailPage.anime.sections)
        }
        var layout = SeriesDetailLayout(page: .manga)
        let original = layout
        layout.move(fromOffsets: IndexSet(integer: 500), toOffset: 0)
        layout.move(fromOffsets: IndexSet(integer: 0), toOffset: -1)
        layout.move(fromOffsets: [], toOffset: 0)
        XCTAssertEqual(layout, original)
    }
    func testRecommendationArtworkKeepsTabletSizeAndFitsNarrowWindows() {
        XCTAssertEqual(SeriesDetailSizing.posterWidth(availableWidth: 358, isTablet: false), 128)
        XCTAssertEqual(SeriesDetailSizing.posterWidth(availableWidth: 908, isTablet: true), 200)
        let split = SeriesDetailSizing.posterWidth(availableWidth: 300, isTablet: true)
        XCTAssertGreaterThan(split, 100); XCTAssertLessThan(split, 200)
        XCTAssertLessThanOrEqual(SeriesDetailSizing.posterWidth(availableWidth: 60, isTablet: false), 60)
        XCTAssertEqual(SeriesDetailSizing.posterWidth(availableWidth: .nan, isTablet: true), 200)
    }
}
