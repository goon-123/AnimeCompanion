import XCTest
@testable import AnimeCore

final class ScreenPresentationTests: XCTestCase {
    func testDefaultsAndOriginalChoice() {
        XCTAssertEqual(ScreenPresentation(preference: nil), .cinematic)
        XCTAssertEqual(ScreenPresentation(preference: "retired-style"), .cinematic)
        XCTAssertEqual(ScreenPresentation(preference: "original"), .original)
        XCTAssertEqual(ScreenPresentation(preference: "cinematic"), .cinematic)
    }

    func testEveryScreenUsesAnIndependentPreference() {
        XCTAssertEqual(Set(ScreenPresentationScope.allCases.map(\.storageKey)).count, 4)
        XCTAssertEqual(ExploreDesign.classic.presentationScope, .classicExplore)
        XCTAssertEqual(ExploreDesign.posterGrid.presentationScope, .mixedExplore)
        XCTAssertEqual(ExploreDesign.discover.presentationScope, .discoveryExplore)
        XCTAssertFalse(ScreenPresentationScope.allCases.map(\.storageKey).contains(ExploreDesign.storageKey))
    }

    func testSpotlightUpgradePreservesExistingWidgetOrderSizesAndVisibility() throws {
        var previous = HomePreferences()
        previous.move(.reading, before: .greeting)
        previous.setSize(.compact, for: .reading)
        previous.setVisible(.news, false)
        let saved = try savedWithoutSpotlight(previous)
        let migrated = HomePreferences(saved: saved)
        XCTAssertEqual(migrated.order.filter { $0 != .cinematicSpotlight }, previous.order.filter { $0 != .cinematicSpotlight })
        XCTAssertEqual(migrated.order.firstIndex(of: .cinematicSpotlight), migrated.order.firstIndex(of: .greeting)! + 1)
        XCTAssertEqual(migrated.size(for: .reading), .compact)
        XCTAssertTrue(migrated.hidden.contains(.news))
        XCTAssertFalse(migrated.hidden.contains(.cinematicSpotlight))
        XCTAssertEqual(HomePreferences(saved: migrated.saved), migrated)
    }

    func testSpotlightUpgradeRespectsAnEmptyHome() throws {
        var previous = HomePreferences()
        previous.setAllVisible(false)
        let migrated = HomePreferences(saved: try savedWithoutSpotlight(previous))
        XCTAssertTrue(migrated.visible.isEmpty)
        XCTAssertTrue(migrated.hidden.contains(.cinematicSpotlight))
    }

    func testMovedAndHiddenSpotlightSurvivesReopening() {
        var preferences = HomePreferences()
        preferences.move(.cinematicSpotlight, after: .reading)
        preferences.setVisible(.cinematicSpotlight, false)
        XCTAssertEqual(HomePreferences(saved: preferences.saved), preferences)
    }

    private func savedWithoutSpotlight(_ value: HomePreferences) throws -> String {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(value.saved.utf8)) as? [String: Any])
        for key in ["order", "hidden"] {
            json[key] = (json[key] as? [String] ?? []).filter { $0 != HomeSection.cinematicSpotlight.rawValue }
        }
        return String(decoding: try JSONSerialization.data(withJSONObject: json), as: UTF8.self)
    }
}
