import XCTest
import UIKit

final class ExperienceRedesignUITests: XCTestCase {
    @MainActor private func launch(dark: Bool = false, largeText: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-reset-content-preferences", "--ui-phase2-preview", "--ui-customization-preview", "--ui-unified-preview", "--ui-redesign-preview"]
        if dark { app.launchArguments.append("--ui-redesign-dark") }
        if largeText { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        XCTAssertTrue(app.buttons["home-customize"].waitForExistence(timeout: 20))
        return app
    }
    @MainActor private func capture(_ title: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = title; attachment.lifetime = .keepAlways; add(attachment)
    }
    @MainActor private func tap(_ element: XCUIElement, in app: XCUIApplication) {
        app.revealInContent(element)
        XCTAssertTrue(element.isHittable); element.tap()
    }
    @MainActor func testHomeAndScopedSearchOpenTheExistingNativeDetails() {
        let app = launch()
        XCTAssertTrue(app.buttons["home-watch-1"].waitForExistence(timeout: 15))
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "companion-sidebar").firstMatch.exists)
        } else {
            XCTAssertTrue(app.tabBars.buttons["Home"].exists)
            XCTAssertFalse(app.tabBars.buttons["Schedule"].exists)
        }
        capture("Redesign-Home-Light")
        app.buttons["home-search"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("harbor\n")
        XCTAssertTrue(app.buttons["explore-story-anilist:1"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["explore-story-mangabaka:73"].waitForExistence(timeout: 15))
        capture("Redesign-Unified-Search")
        tap(app.buttons["search-scope-manga"], in: app)
        XCTAssertTrue(app.buttons["explore-story-mangabaka:73"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["explore-story-anilist:1"].exists)
        tap(app.buttons["search-scope-novels"], in: app)
        let novel = app.buttons["explore-story-mangabaka:74"]
        XCTAssertTrue(novel.waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["explore-story-mangabaka:73"].exists)
        tap(novel, in: app)
        XCTAssertTrue(app.buttons["mangabaka-series-cover"].waitForExistence(timeout: 15))
        capture("Redesign-Novel-Detail")
        XCTAssertTrue(app.buttons["series-information"].exists)
    }
    @MainActor func testHomeSectionsPersistAndHiddenScheduleRemainsReachable() {
        let app = launch(dark: true)
        app.buttons["home-customize"].tap()
        let toggle = app.switches["home-visible-reading"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        let previous = toggle.value as? String
        (toggle.descendants(matching: .switch).allElementsBoundByIndex.last ?? toggle).tap()
        XCTAssertNotEqual(toggle.value as? String, previous)
        app.buttons["Done"].firstMatch.tap()
        app.terminate(); app.launchArguments.removeAll { $0 == "--ui-reset-content-preferences" }; app.launch()
        XCTAssertTrue(app.buttons["home-customize"].waitForExistence(timeout: 15)); app.buttons["home-customize"].tap()
        XCTAssertNotEqual(app.switches["home-visible-reading"].value as? String, previous)
        app.buttons["Restore Home layout"].tap(); app.buttons["Done"].firstMatch.tap()
        capture("Redesign-Home-Dark")
        tap(app.buttons["home-open-schedule"], in: app)
        XCTAssertTrue(app.segmentedControls["schedule-mode"].waitForExistence(timeout: 15))
        app.navigationBars.buttons["Close"].firstMatch.tap()
        tap(app.buttons["home-sources"], in: app)
        XCTAssertTrue(app.buttons["playback-settings"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["seanime-settings"].exists)
        XCTAssertTrue(app.buttons["settings-torbox"].exists)
        capture("Redesign-Sources-Directory")
    }
    @MainActor func testSavedLibraryViewRestoresFiltersAndSurvivesRelaunch() {
        let app = launch()
        app.appTab("My Library").tap()
        XCTAssertTrue(app.buttons["library-saved-views"].waitForExistence(timeout: 15))
        app.buttons["library-saved-views"].tap(); app.buttons["Save current view"].tap()
        let alert = app.alerts["Save library view"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5)); alert.textFields.firstMatch.typeText("Evening queue"); alert.buttons["Save"].tap()
        tap(app.buttons["combined-library-status-planned"], in: app)
        XCTAssertTrue(app.buttons["combined-library-status-planned"].isSelected)
        tap(app.buttons["library-saved-views"], in: app); app.buttons["Evening queue"].firstMatch.tap()
        XCTAssertTrue(app.buttons["combined-library-status-active"].isSelected)
        capture("Redesign-Library-Saved-View")
        app.terminate(); app.launchArguments.removeAll { $0 == "--ui-reset-content-preferences" }; app.launch()
        XCTAssertTrue(app.buttons["home-customize"].waitForExistence(timeout: 15)); app.appTab("My Library").tap()
        XCTAssertTrue(app.buttons["library-saved-views"].waitForExistence(timeout: 15)); app.buttons["library-saved-views"].tap()
        XCTAssertTrue(app.buttons["Evening queue"].firstMatch.exists)
    }
    @MainActor func testLargeTextAndIPadLandscapeKeepPrimaryActionsAvailable() {
        let app = launch(dark: true, largeText: true)
        capture("Redesign-Home-Large-Text")
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCUIDevice.shared.orientation = .landscapeLeft
            let rotated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in app.frame.width > app.frame.height }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [rotated], timeout: 10), .completed)
            capture("Redesign-iPad-Landscape-Large-Text")
        }
        XCTAssertTrue(app.buttons["home-customize"].exists)
        tap(app.buttons["home-search"], in: app)
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 10))
    }
}
