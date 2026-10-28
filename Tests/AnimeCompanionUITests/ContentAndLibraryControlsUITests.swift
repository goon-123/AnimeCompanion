import XCTest

final class ContentAndLibraryControlsUITests: XCTestCase {
    @MainActor private func launch() -> XCUIApplication {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-reset-content-preferences", "--ui-phase2-preview", "--ui-customization-preview", "--ui-library-controls-preview"]
        app.launch()
        XCTAssertTrue(app.appTab("My Library").waitForExistence(timeout: 20))
        app.appTab("My Library").tap()
        XCTAssertTrue(app.segmentedControls["library-media-picker"].waitForExistence(timeout: 15))
        return app
    }
    @MainActor private func showReading(_ app: XCUIApplication) {
        app.segmentedControls["library-media-picker"].buttons["Manga & Novels"].tap()
        XCTAssertTrue(app.buttons["mangabaka-library-status-reading"].waitForExistence(timeout: 10))
    }
    @MainActor private func tapSwitch(_ value: XCUIElement) {
        XCTAssertTrue(value.waitForExistence(timeout: 10))
        (value.descendants(matching: .switch).allElementsBoundByIndex.last ?? value).tap()
    }
    @MainActor private func capture(_ name: String, _ app: XCUIApplication) {
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = name; image.lifetime = .keepAlways; add(image)
    }
    @MainActor private func reopen(_ app: XCUIApplication) {
        app.terminate(); app.launchArguments.removeAll { $0 == "--ui-reset-content-preferences" }; app.launch()
        XCTAssertTrue(app.appTab("My Library").waitForExistence(timeout: 20)); app.appTab("My Library").tap()
    }
    @MainActor func testActiveDefaultsAndCompletePagingBeforeFinalSort() {
        let app = launch()
        XCTAssertTrue(app.buttons["combined-library-status-active"].isSelected)
        XCTAssertFalse(app.buttons["combined-entry-mangabaka:806"].exists)
        showReading(app)
        XCTAssertTrue(app.buttons["mangabaka-library-status-reading"].isSelected)
        let finalPage = app.descendants(matching: .any).matching(identifier: "reading-library-title-807").firstMatch
        XCTAssertTrue(finalPage.waitForExistence(timeout: 15), "The second page must load automatically")
        XCTAssertTrue(app.buttons["reading-library-sort"].label.contains("Last updated"))
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "reading-library-title-806").firstMatch.exists)
        capture("Reading-Active-Complete-Sort", app)
        app.segmentedControls["library-media-picker"].buttons["Anime"].tap()
        XCTAssertTrue(app.buttons["library-status-CURRENT"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["library-status-CURRENT"].isSelected)
        app.buttons["library-status-all"].tap(); XCTAssertTrue(app.buttons["library-status-all"].isSelected)
    }
    @MainActor func testIndependentRatingsFilterImmediatelyAndSurviveRelaunch() {
        let app = launch(); showReading(app)
        app.buttons["mangabaka-content-settings"].tap()
        XCTAssertEqual(app.switches["mangabaka-rating-safe"].value as? String, "1")
        XCTAssertEqual(app.switches["mangabaka-rating-suggestive"].value as? String, "1")
        XCTAssertEqual(app.switches["mangabaka-rating-erotica"].value as? String, "0")
        tapSwitch(app.switches["mangabaka-rating-erotica"])
        tapSwitch(app.switches["mangabaka-rating-suggestive"])
        XCTAssertEqual(app.switches["mangabaka-rating-pornographic"].value as? String, "0")
        capture("Independent-MangaBaka-Ratings", app)
        app.navigationBars["MangaBaka content"].buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["Cedar Letters"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Beacon Letters"].exists); XCTAssertFalse(app.staticTexts["Dawn Letters"].exists)
        reopen(app); showReading(app)
        app.buttons["mangabaka-content-settings"].tap()
        XCTAssertEqual(app.switches["mangabaka-rating-erotica"].value as? String, "1")
        XCTAssertEqual(app.switches["mangabaka-rating-suggestive"].value as? String, "0")
        XCTAssertEqual(app.switches["mangabaka-rating-pornographic"].value as? String, "0")
    }
    @MainActor func testIndependentSortsAndDirectionSurviveRelaunch() {
        let app = launch(); showReading(app)
        app.buttons["reading-library-sort"].tap(); app.buttons["Title"].tap()
        app.buttons["reading-library-sort"].tap(); app.buttons["Z–A"].tap()
        XCTAssertTrue((app.buttons["reading-library-sort"].value as? String ?? "").contains("Z–A"))
        app.segmentedControls["library-media-picker"].buttons["All"].tap()
        app.buttons["combined-library-sort"].tap(); app.buttons["Completion"].tap()
        XCTAssertTrue(app.buttons["combined-library-sort"].label.contains("Completion"))
        capture("Combined-Sort-Options", app)
        reopen(app)
        app.segmentedControls["library-media-picker"].buttons["All"].tap()
        XCTAssertTrue(app.buttons["combined-library-sort"].label.contains("Completion"))
        showReading(app)
        XCTAssertTrue(app.buttons["reading-library-sort"].label.contains("Title"))
        XCTAssertTrue((app.buttons["reading-library-sort"].value as? String ?? "").contains("Z–A"))
    }
    @MainActor func testCustomOpeningStatusPersistsAndDoesNotChangeOtherLibraries() {
        let app = launch(); showReading(app)
        app.buttons["reading-library-sort"].tap()
        app.buttons["library-default-reading"].tap()
        app.buttons["Completed"].tap()
        XCTAssertTrue(app.buttons["mangabaka-library-status-completed"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["mangabaka-library-status-completed"].isSelected)
        XCTAssertTrue(app.staticTexts["Finished Letters"].waitForExistence(timeout: 10))
        reopen(app); showReading(app)
        XCTAssertTrue(app.buttons["mangabaka-library-status-completed"].isSelected)
        app.segmentedControls["library-media-picker"].buttons["All"].tap()
        XCTAssertTrue(app.buttons["combined-library-status-active"].isSelected)
        capture("Saved-Custom-Library-Default", app)
    }
}
