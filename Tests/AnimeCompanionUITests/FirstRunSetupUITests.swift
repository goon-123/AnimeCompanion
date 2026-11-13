import XCTest

final class FirstRunSetupUITests: XCTestCase {
    @MainActor
    func testPlayerChoiceDuringSetupIsSharedWithSettings() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-onboarding-preview", "--ui-phase2-preview", "--ui-redesign-preview", "--ui-reset-content-preferences"]
        app.launch()
        XCTAssertTrue(app.buttons["setup-continue"].waitForExistence(timeout: 20))
        app.buttons["setup-continue"].tap()
        XCTAssertTrue(app.staticTexts["Bring your libraries."].waitForExistence(timeout: 10))
        app.buttons["setup-continue"].tap()
        XCTAssertTrue(app.staticTexts["Make yourself at home."].waitForExistence(timeout: 10))
        let picker = app.buttons["video-player-picker"]
        app.swipeUp()
        XCTAssertTrue(picker.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(picker.isHittable)
        picker.tap(); app.buttons["Outplayer"].firstMatch.tap()
        XCTAssertTrue(picker.label.contains("Outplayer") || (picker.value as? String) == "Outplayer")
        picker.tap(); app.buttons["Infuse"].firstMatch.tap()
        app.buttons["setup-continue"].tap()
        app.buttons["setup-optional-playback"].tap()
        let settings = app.buttons["settings-player"]
        app.revealInContent(settings); settings.tap()
        XCTAssertTrue(picker.waitForExistence(timeout: 10))
        XCTAssertTrue(picker.label.contains("Infuse") || (picker.value as? String) == "Infuse")
        XCTAssertFalse(app.switches["settings-auto-mark-watched"].exists, "Infuse does not report completion")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Infuse-selected-from-setup-in-player-settings"; attachment.lifetime = .keepAlways; add(attachment)
        picker.tap(); app.buttons["VidHub"].firstMatch.tap()
        XCTAssertTrue(app.switches["settings-auto-mark-watched"].exists)
    }

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
