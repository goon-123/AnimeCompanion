import XCTest
@testable import AnimeCore

final class ExperiencePreferencesTests: XCTestCase {
    func testHomeSectionsIntroduceWeekWithoutLosingExistingOrderOrHiddenChoices() {
        let repaired = HomePreferences(saved: #"{"order":["reading","reading","unknown"],"hidden":["watching","reading","airing","shortcuts","unknown"]}"#)
        XCTAssertEqual(repaired.order, [.weekly, .reading, .watching, .airing, .shortcuts])
        XCTAssertEqual(repaired.visible, [.weekly])
        XCTAssertEqual(HomePreferences(saved: repaired.saved), repaired)
        XCTAssertEqual(HomePreferences(saved: "broken"), HomePreferences())
        var single = repaired
        single.setVisible(.weekly, false)
        XCTAssertEqual(single.visible, [.weekly])
        single.setVisible(.reading, true)
        XCTAssertEqual(single.visible, [.weekly, .reading])
        let allHidden = HomePreferences(hidden: Set(HomeSection.allCases))
        XCTAssertEqual(allHidden.visible, [.shortcuts])
        var customized = HomePreferences(order: [.reading, .weekly], hidden: [.weekly])
        customized.setVisible(.weekly, false)
        XCTAssertEqual(HomePreferences(saved: customized.saved), customized)
        XCTAssertFalse(HomePreferences(saved: customized.saved).visible.contains(.weekly))
    }
    func testExistingTabCustomizationPreservesVisibleOrderAndHidesNewHome() {
        let saved = #"{"order":["news","library","explore","manga","schedule"],"hidden":["manga","schedule"]}"#
        let value = AppTabPreferences(saved: saved)
        XCTAssertEqual(value.visible, [.news, .library, .explore])
        XCTAssertTrue(value.hidden.contains(.home))
        XCTAssertEqual(AppTabPreferences(saved: value.saved), value)
        XCTAssertEqual(AppTabPreferences().visible, [.home, .explore, .library])
    }
    func testSavedViewsRoundTripAndRetainIndependentFilters() {
        var values = LibraryViewPresets()
        let first = LibraryViewPreset(name: "  Weekend  ", query: "space", status: "planned", sort: ReadingLibrarySort.rating.rawValue, ascending: false, layout: "list")
        XCTAssertTrue(values.add(first))
        XCTAssertEqual(values.items.first?.name, "Weekend")
        let reopened = LibraryViewPresets(saved: values.saved)
        XCTAssertEqual(reopened, values)
        XCTAssertEqual(reopened.items.first?.query, "space")
        XCTAssertEqual(reopened.items.first?.status, "planned")
        XCTAssertEqual(reopened.items.first?.layout, "list")
        XCTAssertEqual(reopened.items.first?.ascending, false)
        values.remove(first.id); XCTAssertTrue(values.items.isEmpty)
    }
    func testSavedViewsBoundNamesCountAndInvalidValues() throws {
        var values = LibraryViewPresets()
        XCTAssertFalse(values.add(.init(name: "   ", query: "", status: "all", sort: "", ascending: true, layout: "grid")))
        for index in 0..<LibraryViewPresets.limit {
            XCTAssertTrue(values.add(.init(name: String(repeating: "a", count: 100) + "\(index)", query: "", status: "unknown", sort: "unknown", ascending: true, layout: "unknown")))
        }
        XCTAssertFalse(values.add(.init(name: "Overflow", query: "", status: "all", sort: "", ascending: true, layout: "grid")))
        XCTAssertTrue(values.items.allSatisfy { $0.name.count == 40 && $0.status == "active" && $0.sort == "Title" && $0.layout == "grid" })
        let duplicate = try JSONEncoder().encode([values.items[0], values.items[0]])
        XCTAssertEqual(LibraryViewPresets(saved: String(decoding: duplicate, as: UTF8.self)).items.count, 1)
        XCTAssertTrue(LibraryViewPresets(saved: "broken").items.isEmpty)
    }
    func testScopesRequestOnlyTheNeededCatalogs() {
        XCTAssertTrue(StorySearchScope.all.needsAnime && StorySearchScope.all.needsReading)
        XCTAssertTrue(StorySearchScope.anime.needsAnime); XCTAssertFalse(StorySearchScope.anime.needsReading)
        XCTAssertFalse(StorySearchScope.manga.needsAnime); XCTAssertTrue(StorySearchScope.manga.needsReading)
        XCTAssertFalse(StorySearchScope.novels.needsAnime); XCTAssertTrue(StorySearchScope.novels.needsReading)
    }
    func testArtworkSizingSharesVariantsNeverUndersamplesAndBoundsAllocation() {
        XCTAssertEqual(ArtworkDecodeSize.pixels(for: 401), ArtworkDecodeSize.pixels(for: 477))
        XCTAssertEqual(ArtworkDecodeSize.pixels(for: Int.min), 128)
        XCTAssertEqual(ArtworkDecodeSize.pixels(for: Int.max), 3200)
        for size in stride(from: 128, through: 3200, by: 7) {
            XCTAssertGreaterThanOrEqual(ArtworkDecodeSize.pixels(for: size), size)
            XCTAssertLessThanOrEqual(ArtworkDecodeSize.pixels(for: size), 3200)
        }
    }
}
