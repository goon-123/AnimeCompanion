import XCTest

final class FirstRunSetupUITests: XCTestCase {
    @MainActor
    func testOptionalFirstLaunchCanBeCompletedWithoutAccounts() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-onboarding-preview"]
        app.launch()

        XCTAssertTrue(app.buttons["setup-continue"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Your stories. Your space."].exists)
        app.buttons["setup-continue"].tap()

        XCTAssertTrue(app.buttons["setup-anilist-connect"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.secureTextFields["mangabaka-api-key"].exists)
        XCTAssertTrue(app.buttons["mangabaka-add-account"].exists)
        XCTAssertFalse(app.textFields["Custom OAuth client ID (optional)"].exists)
        app.buttons["setup-continue"].tap()

        XCTAssertTrue(app.switches["setup-explicit-content"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.switches["setup-explicit-content"].value as? String, "0")
        app.buttons["setup-continue"].tap()

        XCTAssertTrue(app.otherElements["setup-summary"].waitForExistence(timeout: 10)
            || app.staticTexts["Ready when you are."].exists)
        XCTAssertTrue(app.staticTexts["Optional"].firstMatch.exists)
        app.buttons["setup-start-exploring"].tap()

        XCTAssertFalse(app.buttons["setup-start-exploring"].exists)
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 15)
            || app.descendants(matching: .any).matching(identifier: "companion-sidebar").firstMatch.exists)
    }
}
