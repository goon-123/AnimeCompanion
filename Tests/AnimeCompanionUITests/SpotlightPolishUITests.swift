import XCTest

final class SpotlightPolishUITests: XCTestCase {
    @MainActor func testBothLoopDirectionsShareDecodedLogosAndKeepTheControlsFixed() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-phase2-preview", "--ui-catalog-loading-preview", "--ui-reset-content-preferences", "--ui-redesign-preview", "--ui-redesign-dark", "--ui-spotlight-polish"]
        app.launch()
        let explore = app.buttons["dock-tab-explore"]
        XCTAssertTrue(explore.waitForExistence(timeout: 25)); explore.tap()
        let first = app.buttons["featured-poster-1"]
        XCTAssertTrue(first.waitForExistence(timeout: 25))
        let title = app.descendants(matching: .any).matching(identifier: "featured-title-1").firstMatch
        let logoReady = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Logo"), object: title)
        XCTAssertEqual(XCTWaiter.wait(for: [logoReady], timeout: 20), .completed)
        let watch = app.buttons["featured-watch-1"]
        if !watch.isHittable {
            capture("Spotlight-Control-Visibility", app)
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "Spotlight-Control-Hierarchy"; hierarchy.lifetime = .keepAlways; add(hierarchy)
        }
        XCTAssertTrue(watch.isHittable)
        let baseline = watch.frame
        capture("Spotlight-Larger-Logo-Initial", app)
        // First -> previous must be the last, then last -> next the first.
        first.swipeRight()
        assertPage(4, poster: 5, app: app)
        capture("Spotlight-Backward-Wrap", app)
        app.buttons["featured-poster-5"].swipeLeft()
        assertPage(0, poster: 1, app: app)
        capture("Spotlight-Forward-Wrap", app)
        // Repeat both boundaries without changing the enclosing vertical scroll.
        first.swipeRight()
        assertPage(4, poster: 5, app: app)
        app.buttons["featured-poster-5"].swipeLeft()
        assertPage(0, poster: 1, app: app)
        XCTAssertEqual(watch.frame.minY, baseline.minY, accuracy: 1)
        XCTAssertEqual(watch.frame.width, baseline.width, accuracy: 1)
        XCTAssertEqual(app.buttons.matching(identifier: "featured-poster-1").count, 1)
        XCTAssertTrue(app.buttons["featured-details-1"].isHittable)
        XCTAssertTrue(app.buttons["featured-add-library-1"].isHittable)
        capture("Spotlight-Repeat-Wrap-Stable-Controls", app)
    }
    @MainActor private func assertPage(_ index: Int, poster: Int, app: XCUIApplication) {
        let page = app.buttons["featured-poster-\(poster)"]
        XCTAssertTrue(page.waitForExistence(timeout: 15), "Logical page \(index + 1) must be visible")
        XCTAssertTrue(page.isHittable, "The logical selection must match the physical page")
    }
    @MainActor private func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name
        attachment.lifetime = .keepAlways; add(attachment)
    }
}
