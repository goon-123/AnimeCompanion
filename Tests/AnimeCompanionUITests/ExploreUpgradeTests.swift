import XCTest
import UIKit

/// Exercises the new poster layout and saved filters on both native device families.
final class ExploreUpgradeTests: XCTestCase {
    @MainActor
    func testFeaturedPosterPagingOpensSeriesDetailsAndKeepsTabletRotation() throws {
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
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "featured-genres-\(id)").firstMatch.exists)
        XCTAssertTrue(app.staticTexts["featured-dub-\(id)"].exists)
        capture("Featured-Poster-Portrait")
        let poster = app.buttons["featured-poster-\(id)"]
        reveal(poster, in: app, upward: false)
        poster.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.22)).tap()
        XCTAssertTrue(app.buttons["expand-anime-cover"].waitForExistence(timeout: 35))
        XCTAssertFalse(app.buttons["Close enlarged image"].exists)
        capture("Featured-Poster-Opens-Series")
        app.returnToBrowsing()
        reveal(app.buttons["featured-details-\(id)"], in: app)
        app.buttons["featured-details-\(id)"].tap()
        XCTAssertTrue(app.buttons["expand-anime-cover"].waitForExistence(timeout: 35))
        app.returnToBrowsing()
        XCTAssertTrue(app.buttons["explore-search"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["featured-page-1"].value as? String, "Selected")
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCUIDevice.shared.orientation = .landscapeLeft
            reveal(app.buttons["featured-details-\(id)"], in: app)
            XCTAssertTrue(app.staticTexts["featured-title-\(id)"].isHittable)
            XCTAssertTrue(app.appTab("My Library").isHittable)
            capture("Featured-Poster-iPad-Landscape-Glass-Bar")
            XCUIDevice.shared.orientation = .portrait
        }
    }
    @MainActor
    func testDubFiltersHideCompletedPersistAndApplyToSearch() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(); app.launchArguments = ["--ui-library-preview"]; app.launch()
        XCTAssertTrue(app.appTab("My Library").waitForExistence(timeout: 20))
        app.appTab("My Library").tap()
        XCTAssertTrue(app.buttons["library-entry-1"].waitForExistence(timeout: 40))
        app.appTab("Explore").tap()
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
        let known = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Dub available"), object: dub)
        XCTAssertEqual(XCTWaiter.wait(for: [known], timeout: 35), .completed)
        XCTAssertTrue(app.buttons["discovery-entry-1"].exists)
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons["discovery-entry-5"])
        XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 15), .completed)
        XCTAssertEqual(app.buttons["explore-dub-filters"].value as? String, "Dub available · 8.0+ ★ · Hide completed")
        capture("Dub-Available-Hide-Completed-Results")
        app.buttons["discovery-layout"].tap(); app.buttons["discovery-layout-option-grid"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "explore-genres-1").firstMatch.exists)
        app.buttons["discovery-entry-1"].tap()
        XCTAssertTrue(app.buttons["expand-anime-cover"].waitForExistence(timeout: 35))
        app.returnToBrowsing()
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
        app.openExploreControl("explore-dub-filter-toolbar")
        XCTAssertTrue(app.navigationBars["Dub filters"].waitForExistence(timeout: 10))
    }
    @MainActor
    private func resetFilters(in app: XCUIApplication) {
        openFilters(in: app)
        reveal(app.buttons["dub-filter-reset"], in: app)
        app.buttons["dub-filter-reset"].tap()
        let reset = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Selected"), object: app.buttons["dub-filter-all"])
        XCTAssertEqual(XCTWaiter.wait(for: [reset], timeout: 10), .completed, "Reset must select All anime before leaving the sheet")
        reveal(app.switches["dub-filter-hide-completed"], in: app)
        XCTAssertEqual(app.switches["dub-filter-hide-completed"].value as? String, "0")
        app.buttons["Done"].tap()
    }
    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, upward: Bool = true) {
        for _ in 0..<15 {
            if element.isHittable { return }
            if upward { app.contentSurface.swipeUp() } else { app.contentSurface.swipeDown() }
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
