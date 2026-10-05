import XCTest
import UIKit

/// Exercises the new poster layout and saved filters on both native device families.
final class ExploreUpgradeTests: XCTestCase {
    @MainActor
    func testFeaturedPosterPagingExpansionDetailsAndTabletRotation() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(); app.launch()
        resetFilters(in: app)
        let page = app.buttons["featured-page-1"]
        XCTAssertTrue(page.waitForExistence(timeout: 45))
        reveal(page, in: app); page.tap()
        XCTAssertEqual(page.value as? String, "Selected")
        let details = try XCTUnwrap(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "featured-details-")).allElementsBoundByIndex.first { $0.isHittable })
        let id = String(details.identifier.dropFirst("featured-details-".count))
        XCTAssertTrue(app.staticTexts["featured-title-\(id)"].isHittable)
        XCTAssertTrue(app.staticTexts["featured-genres-\(id)"].exists)
        XCTAssertTrue(app.staticTexts["featured-dub-\(id)"].exists)
        capture("Featured-Poster-Portrait")
        reveal(app.buttons["featured-expand-\(id)"], in: app, upward: false)
        app.buttons["featured-expand-\(id)"].tap()
        XCTAssertTrue(app.buttons["Close enlarged image"].waitForExistence(timeout: 15))
        capture("Featured-Expanded-Artwork")
        app.buttons["Close enlarged image"].tap()
        reveal(app.buttons["featured-details-\(id)"], in: app)
        app.buttons["featured-details-\(id)"].tap()
        XCTAssertTrue(app.buttons["expand-anime-cover"].waitForExistence(timeout: 35))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Explore"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["featured-page-1"].value as? String, "Selected")
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCUIDevice.shared.orientation = .landscapeLeft
            reveal(app.buttons["featured-details-\(id)"], in: app)
            XCTAssertTrue(app.staticTexts["featured-title-\(id)"].isHittable)
            XCTAssertTrue(app.tabBars.buttons["My Library"].isHittable)
            capture("Featured-Poster-iPad-Landscape-Glass-Bar")
            XCUIDevice.shared.orientation = .portrait
        }
    }
    @MainActor
    func testDubFiltersHideCompletedPersistAndApplyToSearch() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(); app.launchArguments = ["--ui-library-preview"]; app.launch()
        XCTAssertTrue(app.tabBars.buttons["My Library"].waitForExistence(timeout: 20))
        app.tabBars.buttons["My Library"].tap()
        XCTAssertTrue(app.buttons["library-entry-1"].waitForExistence(timeout: 40))
        app.tabBars.buttons["Explore"].tap()
        resetFilters(in: app)
        app.buttons["explore-search"].tap()
        XCTAssertTrue(app.textFields["discovery-search"].waitForExistence(timeout: 15))
        app.textFields["discovery-search"].tap(); app.textFields["discovery-search"].typeText("Cowboy\n")
        XCTAssertTrue(app.buttons["discovery-entry-1"].waitForExistence(timeout: 40))
        XCTAssertTrue(app.buttons["discovery-entry-5"].waitForExistence(timeout: 15))
        openFilters(in: app)
        app.buttons["dub-filter-available"].tap()
        reveal(app.buttons["dub-filter-rating"], in: app)
        app.buttons["dub-filter-rating"].tap()
        XCTAssertTrue(app.buttons["8.0 or higher"].waitForExistence(timeout: 10))
        app.buttons["8.0 or higher"].tap()
        reveal(app.switches["dub-filter-hide-completed"], in: app)
        let hideCompleted = app.switches["dub-filter-hide-completed"]
        // SwiftUI exposes the whole labelled row as a Switch on iOS 26.
        // Tap its actual trailing thumb and verify the selected state.
        hideCompleted.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "1"), object: hideCompleted)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 10), .completed)
        capture("Saved-Dub-Filters")
        app.buttons["Done"].tap()
        let dub = app.staticTexts["explore-dub-1"]
        XCTAssertTrue(dub.waitForExistence(timeout: 40))
        let known = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "26/26"), object: dub)
        XCTAssertEqual(XCTWaiter.wait(for: [known], timeout: 35), .completed)
        XCTAssertTrue(app.buttons["discovery-entry-1"].exists)
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons["discovery-entry-5"])
        XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 15), .completed)
        XCTAssertEqual(app.buttons["explore-dub-filters"].value as? String, "Dub available · 8.0+ ★ · Hide completed")
        capture("Dub-Available-Hide-Completed-Results")
        app.buttons["discovery-layout"].tap(); app.buttons["discovery-layout-option-grid"].tap()
        XCTAssertTrue(app.staticTexts["explore-genres-1"].exists)
        app.buttons["discovery-entry-1"].tap()
        XCTAssertTrue(app.buttons["expand-anime-cover"].waitForExistence(timeout: 35))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["discovery-entry-1"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["discovery-entry-5"].exists)
        app.terminate(); app.launch()
        openFilters(in: app)
        XCTAssertEqual(app.buttons["dub-filter-available"].value as? String, "Selected")
        reveal(app.switches["dub-filter-hide-completed"], in: app)
        XCTAssertEqual(app.switches["dub-filter-hide-completed"].value as? String, "1")
        app.buttons["Done"].tap()
        resetFilters(in: app)
        app.buttons["explore-search"].tap()
        app.textFields["discovery-search"].tap(); app.textFields["discovery-search"].typeText("Cowboy\n")
        XCTAssertTrue(app.buttons["discovery-entry-5"].waitForExistence(timeout: 40))
    }
    @MainActor
    private func openFilters(in app: XCUIApplication) {
        let button = app.buttons["explore-dub-filter-toolbar"]
        XCTAssertTrue(button.waitForExistence(timeout: 15)); button.tap()
        XCTAssertTrue(app.navigationBars["Dub filters"].waitForExistence(timeout: 10))
    }
    @MainActor
    private func resetFilters(in app: XCUIApplication) {
        openFilters(in: app)
        reveal(app.buttons["dub-filter-reset"], in: app)
        app.buttons["dub-filter-reset"].tap(); app.buttons["Done"].tap()
    }
    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, upward: Bool = true) {
        for _ in 0..<15 {
            if element.isHittable { return }
            if upward { app.swipeUp() } else { app.swipeDown() }
        }
        XCTAssertTrue(element.isHittable, "Could not reveal \(element.identifier)")
    }
    @MainActor
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "AnimeCompanion-\(UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone")-\(name)"
        attachment.lifetime = .keepAlways; add(attachment)
    }
}
