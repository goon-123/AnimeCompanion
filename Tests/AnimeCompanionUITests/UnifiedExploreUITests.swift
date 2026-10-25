import XCTest
import UIKit

final class UnifiedExploreUITests: XCTestCase {
    @MainActor private func launch(failedReading: Bool = false) -> XCUIApplication {
        continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-reset-content-preferences", "--ui-phase2-preview", "--ui-customization-preview", "--ui-unified-preview"]
        if failedReading { app.launchArguments.append("--ui-unified-reading-failure") }
        app.launch()
        XCTAssertTrue(app.buttons["unified-explore-search"].waitForExistence(timeout: 20))
        return app
    }
    @MainActor private func capture(_ name: String, _ app: XCUIApplication) {
        let landscape = XCUIDevice.shared.orientation.isLandscape
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            (app.frame.width > app.frame.height) == landscape
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 10), .completed)
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); image.name = name; image.lifetime = .keepAlways; add(image)
    }
    @MainActor private func tap(_ item: XCUIElement, _ app: XCUIApplication) {
        app.revealInContent(item); XCTAssertTrue(item.isEnabled); item.tap()
    }
    @MainActor private func chooseDesign(_ value: String, _ app: XCUIApplication) {
        tap(app.buttons["explore-designs"], app)
        XCTAssertTrue(app.buttons["explore-design-" + value].waitForExistence(timeout: 10))
        app.buttons["explore-design-" + value].tap()
        app.navigationBars["Explore design"].buttons["Done"].tap()
    }
    @MainActor func testCombinedSearchOpensBothProvidersAndPaginatesIndependently() {
        let app = launch()
        XCTAssertFalse(app.buttons["media-section-anime"].exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "unified-spotlight").firstMatch.waitForExistence(timeout: 15))
        capture("Unified-Discovery-Home", app)
        app.buttons["unified-explore-search"].tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10)); field.tap(); field.typeText("harbor\n")
        XCTAssertTrue(app.buttons["explore-story-anilist:1"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["explore-story-mangabaka:73"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.buttons["explore-story-anilist:1"].frame.minY, app.buttons["explore-story-mangabaka:73"].frame.minY, accuracy: 3)
        tap(app.buttons["explore-story-mangabaka:74"], app)
        XCTAssertTrue(app.buttons["mangabaka-series-cover"].waitForExistence(timeout: 15))
        capture("Unified-Novel-Details", app)
        app.returnToBrowsing()
        tap(app.buttons["explore-story-anilist:1"], app)
        XCTAssertTrue(app.scrollViews["anime-detail-scroll"].waitForExistence(timeout: 15))
        app.returnToBrowsing()
        capture("Unified-Search-Both-Catalogs", app)
        tap(app.buttons["unified-search-more-reading"], app)
        XCTAssertTrue(app.buttons["explore-story-mangabaka:75"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["unified-search-more-reading"].exists)
        XCTAssertTrue(app.buttons["unified-search-more-anime"].exists)
        tap(app.buttons["unified-search-more-anime"], app)
        let counts = app.staticTexts["unified-search-counts"]
        let loaded = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "4 anime · 4 manga & novels loaded"), object: counts)
        XCTAssertEqual(XCTWaiter.wait(for: [loaded], timeout: 15), .completed)
        XCTAssertFalse(app.buttons["explore-story-mangabaka:77"].exists)
        capture("Unified-Search-Paginated", app)
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCUIDevice.shared.orientation = .landscapeLeft
            XCTAssertTrue(app.searchFields.firstMatch.exists)
            capture("Unified-Search-Landscape", app)
            XCUIDevice.shared.orientation = .portrait
        }
    }
    @MainActor func testAllDesignsAndAiringGridPersistAcrossRelaunch() {
        let app = launch()
        chooseDesign("posterGrid", app)
        XCTAssertTrue(app.scrollViews["unified-explore-posterGrid"].waitForExistence(timeout: 10))
        capture("Unified-Mixed-Poster-Grid", app)
        app.appTab("Schedule").tap()
        let layout = app.segmentedControls["schedule-airing-layout"]
        XCTAssertTrue(layout.waitForExistence(timeout: 15)); layout.buttons["Grid"].tap()
        let behind = app.staticTexts["library-airing-status-990101"]
        app.revealInContent(behind)
        XCTAssertEqual(behind.label, "2 episodes behind")
        XCTAssertTrue(app.buttons["library-watch-990101"].exists)
        XCTAssertTrue(app.buttons["library-next-990101"].exists)
        capture("Schedule-Airing-Poster-Grid", app)
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCUIDevice.shared.orientation = .landscapeLeft
            app.revealInContent(behind); capture("Schedule-Airing-Grid-Landscape", app)
            XCUIDevice.shared.orientation = .portrait
        }
        app.revealInContent(app.buttons["schedule-behind-filter"], upward: false)
        app.buttons["schedule-behind-filter"].tap()
        XCTAssertFalse(app.staticTexts["library-airing-status-990102"].exists)
        XCTAssertEqual(app.buttons["schedule-behind-filter"].value as? String, "Behind only")
        app.terminate(); app.launchArguments.removeAll { $0 == "--ui-reset-content-preferences" }; app.launch()
        XCTAssertTrue(app.scrollViews["unified-explore-posterGrid"].waitForExistence(timeout: 20))
        app.appTab("Schedule").tap()
        XCTAssertTrue(layout.waitForExistence(timeout: 15)); XCTAssertTrue(layout.buttons["Grid"].isSelected)
        layout.buttons["List"].tap()
        app.revealInContent(behind); XCTAssertEqual(behind.label, "2 episodes behind")
        app.appTab("Explore").tap()
        app.contentSurface.swipeDown()
        chooseDesign("classic", app)
        XCTAssertTrue(app.buttons["media-section-anime"].waitForExistence(timeout: 10))
        app.buttons["media-section-written"].tap()
        XCTAssertTrue(app.buttons["mangabaka-search"].waitForExistence(timeout: 10))
        capture("Classic-Explore-Restored", app)
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["media-section-written"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["media-section-written"].isSelected)
        chooseDesign("discover", app)
        XCTAssertTrue(app.buttons["unified-explore-search"].waitForExistence(timeout: 10))
    }
    @MainActor func testReadingOutageKeepsAnimeHomeAndSearchUsable() {
        let app = launch(failedReading: true)
        app.buttons["unified-explore-search"].tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10)); field.tap(); field.typeText("harbor\n")
        XCTAssertTrue(app.buttons["explore-story-anilist:1"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "unified-search-error-reading").firstMatch.waitForExistence(timeout: 25))
        XCTAssertFalse(app.buttons["explore-story-mangabaka:73"].exists)
        capture("Unified-Partial-Provider-Outage", app)
        tap(app.buttons["explore-story-anilist:1"], app)
        XCTAssertTrue(app.scrollViews["anime-detail-scroll"].waitForExistence(timeout: 15))
    }
    @MainActor func testReplacingASearchRejectsLateResultsFromTheOldQuery() {
        let app = launch()
        app.buttons["unified-explore-search"].tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10)); field.tap(); field.typeText("slow\n")
        XCTAssertTrue(app.staticTexts["Searching catalogs…"].waitForExistence(timeout: 10))
        app.buttons["Clear all-catalog search"].tap()
        field.tap(); field.typeText("harbor\n")
        let result = app.buttons["explore-story-anilist:1"]
        XCTAssertTrue(result.waitForExistence(timeout: 15))
        XCTAssertTrue(result.label.contains("harbor"))
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "slow · anime")).firstMatch.exists)
        tap(app.buttons["explore-story-mangabaka:74"], app)
        XCTAssertTrue(app.buttons["mangabaka-series-cover"].waitForExistence(timeout: 15))
        capture("Unified-Replaced-Search", app)
    }
}
