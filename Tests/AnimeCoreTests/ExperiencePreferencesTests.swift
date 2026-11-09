import XCTest
@testable import AnimeCore

final class ExperiencePreferencesTests: XCTestCase {
    func testLegacyHomeMigrationKeepsOrderAndHiddenChoicesAndAddsOptionalWidgetsHidden() {
        let repaired = HomePreferences(saved: #"{"order":["reading","reading","unknown"],"hidden":["watching","reading","airing","shortcuts","unknown"]}"#)
        let chrome: [HomeSection] = [.greeting, .cinematicSpotlight, .search, .featureLinks, .welcome, .syncStatus]
        XCTAssertEqual(Array(repaired.order.prefix(13)), chrome + [.weekly, .news, .community, .reading, .watching, .airing, .shortcuts])
        XCTAssertEqual(repaired.visible, chrome + [.weekly, .news, .community])
        XCTAssertTrue(HomeSection.optionalWidgets.isSubset(of: repaired.hidden))
        XCTAssertEqual(HomePreferences(saved: repaired.saved), repaired)
        XCTAssertEqual(HomePreferences(saved: "broken"), HomePreferences())
        var customized = HomePreferences(order: [.reading, .weekly], hidden: [.weekly])
        customized.setVisible(.weekly, false)
        XCTAssertEqual(HomePreferences(saved: customized.saved), customized)
        XCTAssertFalse(HomePreferences(saved: customized.saved).visible.contains(.weekly))
    }
    func testEveryWidgetCanBeHiddenAndRestoredWithoutLosingLayoutOrSizes() {
        var value = HomePreferences()
        value.move(.reading, before: .greeting)
        value.setSize(.compact, for: .reading)
        let order = value.order
        for section in HomeSection.allCases { value.setVisible(section, false) }
        XCTAssertTrue(value.visible.isEmpty)
        let reopened = HomePreferences(saved: value.saved)
        XCTAssertTrue(reopened.visible.isEmpty)
        XCTAssertEqual(reopened.order, order)
        XCTAssertEqual(reopened.size(for: .reading), .compact)
        value.setVisible(.search, true)
        XCTAssertEqual(value.visible, [.search])
        value.setAllVisible(true)
        XCTAssertEqual(value.visible, order)
        value.setAllVisible(false)
        XCTAssertTrue(HomePreferences(saved: value.saved).visible.isEmpty)
        XCTAssertTrue(HomePreferences(hidden: Set(HomeSection.allCases)).visible.isEmpty)
    }
    func testRelativeMovesKeepHiddenSlotsAndSupportBothDirections() {
        var value = HomePreferences()
        value.setVisible(.search, false)
        value.move(.watching, before: .greeting)
        XCTAssertEqual(value.order.first, .watching)
        value.move(.greeting, after: .shortcuts)
        XCTAssertTrue(value.order.firstIndex(of: .greeting)! > value.order.firstIndex(of: .shortcuts)!)
        let unchanged = value
        value.move(.reading, before: .reading)
        value.move(.reading, after: .reading)
        XCTAssertEqual(value, unchanged)
        XCTAssertTrue(value.hidden.contains(.search))
        XCTAssertEqual(Set(value.order).count, HomeSection.allCases.count)
        XCTAssertEqual(HomePreferences(saved: value.saved), value)
    }
    func testUnknownWidgetSizesAndDuplicateIDsRepairWithoutUnhidingAnything() {
        let value = HomePreferences(saved: #"{"version":2,"order":["search","search","retired"],"hidden":["search","retired"],"sizes":{"reading":"compact","planned":"enormous","retired":"expanded","greeting":"expanded"}}"#)
        XCTAssertEqual(value.order.first, .search)
        XCTAssertTrue(value.hidden.contains(.search))
        XCTAssertEqual(value.size(for: .reading).itemLimit, 3)
        XCTAssertEqual(value.size(for: .planned).itemLimit, 6)
        XCTAssertEqual(value.size(for: .greeting), .standard)
        XCTAssertEqual(HomePreferences(saved: value.saved), value)
    }
    func testShortcutSlotsSwapHideAndRoundTripWithoutChangingLayout() {
        var value = HomePreferences()
        let order = value.order
        value.setShortcut(.community, at: 1)
        XCTAssertEqual(value.shortcuts, [.calendar, .community, .news])
        value.setShortcut(.news, at: 0)
        XCTAssertEqual(value.shortcuts, [.news, .community, .calendar])
        value.setShortcut(nil, at: 2)
        value.setVisible(.featureLinks, false)
        let reopened = HomePreferences(saved: value.saved)
        XCTAssertEqual(reopened.shortcuts, [.news, .community, nil])
        XCTAssertEqual(reopened.order, order)
        XCTAssertTrue(reopened.hidden.contains(.featureLinks))
        XCTAssertEqual(reopened, value)
        value.setShortcut(.reading, at: 99)
        XCTAssertEqual(value, reopened)
        for index in 0..<3 { value.setShortcut(nil, at: index) }
        XCTAssertEqual(HomePreferences(saved: value.saved).shortcuts, [nil, nil, nil])
    }
    func testShortcutMigrationPreservesOldLayoutAndNewBannersStartHidden() {
        let value = HomePreferences(saved: #"{"version":2,"order":["reading","featureLinks"],"hidden":["reading"],"sizes":{"reading":"compact"}}"#)
        XCTAssertEqual(value.shortcuts, [.calendar, .airing, .news])
        XCTAssertEqual(Array(value.order.prefix(2)), [.reading, .featureLinks])
        XCTAssertTrue(value.hidden.isSuperset(of: [.seasonSpotlight, .nextEpisode, .watchlistBanners]))
        XCTAssertEqual(value.size(for: .reading), .compact)
        let unknown = HomePreferences(saved: #"{"version":3,"order":[],"hidden":[],"shortcuts":["community","community","retired","library"]}"#)
        XCTAssertEqual(unknown.shortcuts, [.community, nil, nil])
        XCTAssertEqual(HomePreferences(saved: unknown.saved), unknown)
    }
    func testExistingTabCustomizationMovesScheduleAndNewsIntoVisibleHome() {
        let saved = #"{"order":["news","library","explore","manga","schedule"],"hidden":["manga","schedule"]}"#
        let value = AppTabPreferences(saved: saved)
        XCTAssertEqual(value.visible, [.home, .library, .explore])
        XCTAssertFalse(value.hidden.contains(.home))
        XCTAssertFalse(value.order.contains(.news)); XCTAssertFalse(value.order.contains(.schedule))
        XCTAssertEqual(AppTabPreferences(saved: value.saved), value)
        XCTAssertEqual(AppTabPreferences().visible, [.home, .explore, .library])
    }
    func testPreviouslyHiddenHomeAndAllTabsVisibleUpgradeToOneHub() {
        let legacy = AppTabPreferences(saved: #"{"order":["explore","schedule","news","home","library","manga"],"hidden":["home"]}"#)
        XCTAssertEqual(legacy.visible, [.explore, .home, .library, .manga])
        XCTAssertFalse(legacy.saved.contains("schedule")); XCTAssertFalse(legacy.saved.contains("news"))
        let upgraded = HomePreferences(saved: #"{"order":["watching","reading","weekly","airing","shortcuts"],"hidden":["reading","weekly"]}"#)
        XCTAssertEqual(Array(upgraded.order.prefix(13)), [.greeting, .cinematicSpotlight, .search, .featureLinks, .welcome, .syncStatus, .watching, .reading, .weekly, .news, .community, .airing, .shortcuts])
        XCTAssertTrue(upgraded.hidden.contains(.reading)); XCTAssertTrue(upgraded.hidden.contains(.weekly))
        var hiddenNews = upgraded; hiddenNews.setVisible(.news, false)
        XCTAssertFalse(HomePreferences(saved: hiddenNews.saved).visible.contains(.news))
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
