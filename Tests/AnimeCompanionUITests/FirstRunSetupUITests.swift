import XCTest

final class FirstRunSetupUITests: XCTestCase {
    @MainActor
    func testOptionalFirstLaunchCanBeCompletedWithoutAccounts() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-onboarding-preview"]
        app.launch()

        XCTAssertTrue(app.buttons["setup-continue"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Everything you love, together."].exists)
        app.buttons["setup-continue"].tap()

        XCTAssertTrue(app.buttons["setup-anilist-connect"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["setup-skip-step"].exists)
        app.buttons["setup-skip-step"].tap()

        XCTAssertTrue(app.buttons["setup-mangabaka-connect"].waitForExistence(timeout: 10))
        app.buttons["setup-skip-step"].tap()

        XCTAssertTrue(app.buttons["setup-torrent-install"].waitForExistence(timeout: 10))
        app.buttons["setup-skip-step"].tap()

        XCTAssertTrue(app.buttons["setup-torbox-connect"].waitForExistence(timeout: 10))
        app.buttons["setup-skip-step"].tap()

        XCTAssertTrue(app.buttons["setup-aiostreams-configure"].waitForExistence(timeout: 10))
        app.buttons["setup-skip-step"].tap()

        XCTAssertTrue(app.switches["setup-explicit-content"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.switches["setup-explicit-content"].value as? String, "0")
        app.buttons["setup-continue"].tap()

        XCTAssertTrue(app.otherElements["setup-summary"].waitForExistence(timeout: 10)
            || app.staticTexts["You're ready to explore."].exists)
        XCTAssertTrue(app.staticTexts["Skipped"].firstMatch.exists)
        app.buttons["setup-start-exploring"].tap()

        XCTAssertFalse(app.buttons["setup-start-exploring"].exists)
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 15))
    }
}
