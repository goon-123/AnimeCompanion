import XCTest

/// Only the two reported regressions. The gallery transport uses owned images
/// with LiveChart's current attribute contract; the exact public page is also
/// exercised by the Core captured-page regression.
final class DockAndGalleryFixUITests: XCTestCase {
    @MainActor func testSelectedDockLabelsStayAboveGlassAcrossEveryTab() {
        let app = launch()
        for tab in ["explore", "library", "home", "explore"] {
            let button = app.buttons["dock-tab-" + tab]
            XCTAssertTrue(button.waitForExistence(timeout: 20))
            XCTAssertTrue(button.isHittable)
            button.tap()
            let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: button)
            XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 10), .completed)
            XCTAssertEqual(app.buttons.matching(identifier: "dock-tab-" + tab).count, 1)
            XCTAssertGreaterThan(button.frame.minY, app.frame.height * 0.75)
            capture("Dock-" + tab, app.screenshot())
            capture("Dock-label-" + tab, button.screenshot())
        }
    }
    @MainActor func testCurrentLiveChartMarkupAppearsInNativeGalleryWithClearSelectedDock() {
        let app = launch()
        app.appTab("News").tap()
        let visuals = app.buttons["news-open-visuals"]
        XCTAssertTrue(visuals.waitForExistence(timeout: 20)); visuals.tap()
        let title = app.buttons["anime-visual-1"]
        XCTAssertTrue(title.waitForExistence(timeout: 20)); title.tap()
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND label == %@", "8 images"), object: app.staticTexts["visuals-image-count"])
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 20), .completed)
        let first = app.buttons["visual-card-liveChart-0"]
        app.revealInContent(first)
        XCTAssertTrue(first.exists)
        XCTAssertTrue(first.label.contains("Roxy"))
        XCTAssertFalse(app.staticTexts["visuals-notice"].exists)
        XCTAssertTrue(app.buttons["dock-tab-home"].isHittable)
        capture("Native-current-gallery", app.screenshot())
        capture("Native-gallery-dock-label", app.buttons["dock-tab-home"].screenshot())
    }
    @MainActor private func launch() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-phase2-preview", "--ui-catalog-loading-preview", "--ui-visuals-preview", "--ui-redesign-preview", "--ui-reset-content-preferences"]
        app.launch()
        XCTAssertTrue(app.buttons["dock-tab-home"].waitForExistence(timeout: 25))
        return app
    }
    @MainActor private func capture(_ name: String, _ screenshot: XCUIScreenshot) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
}
