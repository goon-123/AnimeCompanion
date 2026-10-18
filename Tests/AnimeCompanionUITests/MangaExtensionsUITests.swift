import XCTest

final class MangaExtensionsUITests: XCTestCase {
    @MainActor
    func testPhoneOnlyExtensionSetupIsReachableFromSettings() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-phase2-preview", "--ui-reset-content-preferences", "--ui-manga-extensions"]
        app.launch()
        XCTAssertTrue(app.buttons["explore-search"].waitForExistence(timeout: 15))
        app.appTab("My Library").tap()
        app.buttons["Account and settings"].firstMatch.tap()
        let row = app.buttons["settings-manga-extensions"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        app.revealInContent(row); row.tap()
        XCTAssertTrue(app.staticTexts["Runs on this device"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["manga-add-repository"].exists)
        XCTAssertTrue(app.textFields["manga-repository-link"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Manga-Extensions-Setup"; screenshot.lifetime = .keepAlways; add(screenshot)
    }
}
