import XCTest

/// Focused dock and detail regression checks. The gallery transport uses owned images
/// with LiveChart's current attribute contract; the exact public page is also
/// exercised by the Core captured-page regression.
final class DockAndGalleryFixUITests: XCTestCase {
    @MainActor func testSelectedDockLabelsStayAboveGlassAcrossEveryTab() {
        let app = launch()
        for tab in ["explore", "library", "home", "explore"] {
            let button = app.buttons["dock-tab-" + tab]
            XCTAssertTrue(button.waitForExistence(timeout: 20))
            XCTAssertTrue(button.isHittable)
            XCTAssertEqual(app.tabBars.count, 1, "Use one native Liquid Glass bar")
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
        // HomeWidgetFrame supplies the widget identifier to its descendants.
        // Use the actual native shortcut label rather than an overridden ID.
        let news = app.buttons.matching(NSPredicate(format: "label == %@", "News, Your briefing")).firstMatch
        XCTAssertTrue(news.waitForExistence(timeout: 20)); news.tap()
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
    @MainActor func testDetailUsesKnownTitleAndNativeDockReturnsOnceAfterBack() {
        let app = launch(extra: ["--ui-detail-title-delay"])
        app.buttons["dock-tab-library"].tap()
        let entry = app.buttons["library-entry-1"]
        XCTAssertTrue(entry.waitForExistence(timeout: 20)); app.revealInContent(entry); entry.tap()
        XCTAssertTrue(app.scrollViews["anime-detail-scroll"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.navigationBars["Anime"].exists, "The generic loading title must never flash")
        XCTAssertTrue(app.navigationBars["Phase 2 tracked title"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["dock-tab-library"].isHittable)
        capture("Detail-known-title-native-dock-hidden", app.screenshot())
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["dock-tab-library"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["dock-tab-library"].isHittable)
        XCTAssertEqual(app.tabBars.count, 1)
        XCTAssertEqual(app.buttons.matching(identifier: "dock-tab-library").count, 1)
        capture("Native-dock-restored-after-back", app.screenshot())
    }
    @MainActor private func launch(extra: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-phase2-preview", "--ui-catalog-loading-preview", "--ui-visuals-preview", "--ui-redesign-preview", "--ui-redesign-dark", "--ui-reset-content-preferences"]
        app.launchArguments += extra
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
