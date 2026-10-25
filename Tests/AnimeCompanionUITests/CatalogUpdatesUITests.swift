import XCTest
import UIKit

final class CatalogUpdatesUITests: XCTestCase {
    @MainActor
    func testColdCatalogShowsPlaceholderThenRevealsUsableAnime() {
        let app = launch()
        let skeleton = app.descendants(matching: .any).matching(identifier: "explore-loading").firstMatch
        XCTAssertTrue(skeleton.waitForExistence(timeout: 2))
        capture("Loading-Placeholder", app)
        let title = app.staticTexts["featured-title-1"]
        XCTAssertTrue(title.waitForExistence(timeout: 15))
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: skeleton)
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 10), .completed)
        XCTAssertTrue(app.buttons["featured-details-1"].isHittable)
        capture("Revealed-Catalog", app)
        app.appTab("My Library").tap(); app.appTab("Explore").tap()
        XCTAssertTrue(title.waitForExistence(timeout: 10)); XCTAssertFalse(skeleton.exists)
    }
    @MainActor
    func testNativeScheduleVisualsAndHeadlinesReplaceTheTrackerSwitch() {
        let app = launch()
        app.appTab("My Library").tap()
        let entry = app.buttons["library-entry-1"]
        app.revealInContent(entry); entry.tap()
        XCTAssertTrue(app.scrollViews["anime-detail-scroll"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.segmentedControls["metadata-source-picker"].exists)
        XCTAssertFalse(app.buttons["LiveChart.me"].exists)
        let schedule = app.buttons["detail-open-schedule"]
        app.revealInContent(schedule); schedule.tap()
        XCTAssertTrue(app.navigationBars["Schedule"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["detail-weekly-schedule"].exists)
        capture("Native-Schedule", app)
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["detail-open-visuals"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "visuals-watch-trailer").firstMatch.waitForExistence(timeout: 10))
        capture("Native-Visuals", app)
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["detail-open-headlines"].tap()
        XCTAssertTrue(app.navigationBars["Headlines"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Series news from recent feeds and Anime Corner’s title search, including other seasons."].exists)
        capture("Native-Headlines", app)
    }
    @MainActor
    func testNewsOpensSeasonalVisualsAndLoadsSelectedTitleDetails() {
        let app = launch()
        app.appTab("News").tap()
        let visuals = app.buttons["news-open-visuals"]
        XCTAssertTrue(visuals.waitForExistence(timeout: 10)); visuals.tap()
        let first = app.buttons["anime-visual-1"]
        XCTAssertTrue(first.waitForExistence(timeout: 15))
        // The owned image response deliberately arrives after metadata; capture
        // the settled artwork rather than the middle of its cross-fade.
        let artworkSettled = expectation(description: "Owned artwork cross-fade completes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { artworkSettled.fulfill() }
        wait(for: [artworkSettled], timeout: 3)
        capture("Seasonal-Visuals", app)
        first.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "visuals-watch-trailer").firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["visuals-anime-details"].exists)
        let details = app.buttons["visuals-anime-details"]
        let scroll = app.scrollViews["anime-visuals"]
        for _ in 0..<5 where !details.isHittable { scroll.swipeUp() }
        XCTAssertTrue(details.isHittable); details.tap()
        XCTAssertTrue(app.scrollViews["anime-detail-scroll"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["detail-title"].waitForExistence(timeout: 10))
        let related = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Phase 2 title 5")).firstMatch
        app.revealInContent(related); related.tap()
        let title = app.staticTexts["detail-title"]
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Phase 2 title 5"), object: title)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 10), .completed)
    }
    @MainActor private func launch() -> XCUIApplication {
        continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-phase2-preview", "--ui-reset-content-preferences", "--ui-catalog-loading-preview", "-metadata.source", "livechart"]
        app.launch(); XCTAssertTrue(app.buttons["explore-search"].waitForExistence(timeout: 15))
        return app
    }
    @MainActor private func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Catalog-\(UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone")-\(name)"
        attachment.lifetime = .keepAlways; add(attachment)
    }
}
