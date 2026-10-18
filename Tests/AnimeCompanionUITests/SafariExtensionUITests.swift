import XCTest

final class SafariExtensionUITests: XCTestCase {
    @MainActor
    func testBundledSafariExtensionSetupIsReachableFromSettings() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-phase2-preview", "--ui-reset-content-preferences"]
        app.launch()
        XCTAssertTrue(app.buttons["explore-search"].waitForExistence(timeout: 15))
        app.appTab("My Library").tap()
        app.buttons["Account and settings"].firstMatch.tap()
        let row = app.buttons["settings-safari-vidhub"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        app.revealInContent(row); row.tap()
        XCTAssertTrue(app.staticTexts["Keep browsing in Safari"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Enable the extension"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Safari-VidHub-Setup"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
