import XCTest
import UIKit

/// Short offline checks for Explore controls and the cinematic series destinations.
final class ExploreWidgetFixUITests: XCTestCase {
    @MainActor func testSeriesOpensEpisodesFirstAndCommentsHaveTwoDestinations() {
        let app = launch()
        app.buttons["featured-poster-1"].tap()
        let comments = app.buttons["detail-floating-comments"]
        XCTAssertTrue(comments.waitForExistence(timeout: 15))
        capture("Series-Cinematic-Header")
        let moreInfo = app.buttons["More Info"]
        for _ in 0..<8 {
            if moreInfo.exists && moreInfo.isHittable { break }
            app.scrollViews["anime-detail-scroll"].swipeUp()
        }
        XCTAssertTrue(moreInfo.isHittable)
        XCTAssertTrue(app.buttons["Episodes"].isSelected, "Episodes must be the initial tab")
        moreInfo.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "series-info-tab").firstMatch.waitForExistence(timeout: 10))
        capture("Series-More-Info")
        comments.tap()
        let tabs = app.segmentedControls["series-community-tabs"]
        XCTAssertTrue(tabs.waitForExistence(timeout: 10))
        XCTAssertTrue(tabs.buttons["Series Reviews"].exists)
        XCTAssertTrue(tabs.buttons["Episode Comments"].exists)
        capture("Series-Reviews-And-Comments")
    }
    @MainActor func testAddWidgetAndShortcutNavigationStayEnabledWhileReordering() {
        let app = launch()
        openCustomizer(app)
        let add = app.buttons["explore-add-widgets"]
        XCTAssertTrue(add.isEnabled, "Reorder mode must not disable adding widgets")
        XCTAssertTrue(add.isHittable); add.tap()
        XCTAssertTrue(app.navigationBars["Add widgets"].waitForExistence(timeout: 10))
        let quickAccess = app.buttons["explore-add-featureLinks"]
        XCTAssertTrue(quickAccess.waitForExistence(timeout: 10)); XCTAssertTrue(quickAccess.isEnabled)
        quickAccess.tap()
        XCTAssertFalse(quickAccess.exists, "The added widget should become a checkmark")
        app.navigationBars["Add widgets"].buttons.firstMatch.tap()
        let shortcuts = app.buttons["explore-widget-shortcuts"]
        revealInEditor(shortcuts, app)
        XCTAssertTrue(shortcuts.isEnabled); shortcuts.tap()
        XCTAssertTrue(app.navigationBars["Customize shortcuts"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "home-shortcut-slot-0").firstMatch.exists)
        capture("Explore-Shortcut-Picker-Enabled")
        app.navigationBars["Customize shortcuts"].buttons.firstMatch.tap()
        app.navigationBars["Customize Explore"].buttons["Done"].tap()

        app.terminate()
        app.launchArguments.removeAll { $0 == "--ui-reset-content-preferences" }
        app.launch()
        XCTAssertTrue(app.buttons["explore-customize"].waitForExistence(timeout: 20))
        openCustomizer(app)
        let toggle = app.switches["explore-visible-widget.featureLinks"]
        revealInEditor(toggle, app)
        XCTAssertEqual(toggle.value as? String, "1", "The added widget must survive relaunch")
        capture("Explore-Added-Widget-Persisted")
    }

    @MainActor func testSpotlightHasNoTopGapAndHiddenSpotlightKeepsRowsBelowTheHeader() {
        let app = launch()
        assertNoSpotlightGap(app)
        capture("Explore-Spotlight-No-Top-Gap")
        openCustomizer(app)
        let spotlight = app.switches["explore-visible-catalog.spotlight"]
        XCTAssertTrue(spotlight.waitForExistence(timeout: 10)); spotlight.tap()
        app.navigationBars["Customize Explore"].buttons["Done"].tap()
        let trending = app.buttons["explore-category-trending"]
        XCTAssertTrue(trending.waitForExistence(timeout: 10)); XCTAssertTrue(trending.isHittable)
        let header = app.buttons["media-section-anime"]
        XCTAssertGreaterThanOrEqual(trending.frame.minY, header.frame.maxY - 1,
            "A normal first row must stay below the fixed format controls")
        capture("Explore-Hidden-Spotlight-Safe-Header")
        openCustomizer(app)
        XCTAssertTrue(spotlight.waitForExistence(timeout: 10)); spotlight.tap()
        app.navigationBars["Customize Explore"].buttons["Done"].tap()
        assertNoSpotlightGap(app)
    }

    @MainActor private func launch() -> XCUIApplication {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-phase2-preview", "--ui-catalog-loading-preview", "--ui-reset-content-preferences"]
        app.launch()
        XCTAssertTrue(app.buttons["explore-customize"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["featured-poster-1"].waitForExistence(timeout: 20))
        return app
    }
    @MainActor private func openCustomizer(_ app: XCUIApplication) {
        app.buttons["explore-customize"].tap()
        let action = app.buttons["Customize rows & widgets"]
        XCTAssertTrue(action.waitForExistence(timeout: 10)); action.tap()
        XCTAssertTrue(app.navigationBars["Customize Explore"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["explore-add-widgets"].exists)
    }
    @MainActor private func assertNoSpotlightGap(_ app: XCUIApplication) {
        let poster = app.buttons["featured-poster-1"]
        XCTAssertTrue(poster.waitForExistence(timeout: 15))
        let header = app.buttons["media-section-anime"]
        XCTAssertGreaterThan(poster.frame.height, 300)
        XCTAssertLessThanOrEqual(poster.frame.minY, header.frame.maxY + 1,
            "Spotlight must touch or extend behind the fixed format controls")
    }
    @MainActor private func revealInEditor(_ item: XCUIElement, _ app: XCUIApplication) {
        for _ in 0..<8 {
            if item.exists && item.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(item.exists); XCTAssertTrue(item.isHittable)
    }
    @MainActor private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
