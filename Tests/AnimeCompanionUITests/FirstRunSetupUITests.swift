import XCTest

final class FirstRunSetupUITests: XCTestCase {
    @MainActor
    func testGuidedSourcesExplainBothRoutesAndReadingBeforeFinish() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-onboarding-preview", "--ui-phase2-preview", "--ui-redesign-preview"]
        app.launch()
        XCTAssertTrue(app.buttons["setup-continue"].waitForExistence(timeout: 20))
        app.buttons["setup-continue"].tap()
        app.buttons["setup-continue"].tap()
        XCTAssertTrue(app.buttons["theme-accent-ocean"].waitForExistence(timeout: 10))
        app.buttons["theme-accent-ocean"].tap()
        app.buttons["setup-continue"].tap()
        XCTAssertTrue(app.staticTexts["Set up video playback."].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["setup-aiostreams"].exists)
        XCTAssertFalse(app.buttons["settings-safari-vidhub"].exists)
        app.segmentedControls["setup-playback-route"].buttons["Seanime + TorBox"].tap()
        XCTAssertTrue(app.buttons["setup-seanime"].exists)
        XCTAssertTrue(app.buttons["setup-torbox"].exists)
        let picker = app.buttons["video-player-picker"]
        app.revealInContent(picker); picker.tap(); app.buttons["Infuse"].firstMatch.tap()
        let confirm = app.switches["setup-player-confirmed"]
        app.revealInContent(confirm); confirm.tap()
        app.buttons["setup-continue"].tap()
        XCTAssertTrue(app.staticTexts["Add your manga sources."].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["setup-keiyoushi"].exists)
        app.buttons["setup-keiyoushi"].tap()
        XCTAssertTrue(app.navigationBars["Manga extensions"].waitForExistence(timeout: 10))
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["setup-continue"].tap()
        XCTAssertTrue(app.staticTexts["Your setup at a glance."].waitForExistence(timeout: 10))
        let incomplete = app.staticTexts["setup-incomplete"]
        app.revealInContent(incomplete); XCTAssertTrue(incomplete.exists)
        app.buttons["setup-start-exploring"].tap()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 15)
            || app.descendants(matching: .any).matching(identifier: "companion-sidebar").firstMatch.exists)
    }

    @MainActor
    func testSkipShowsMissingSourcesBeforeBrowsing() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-onboarding-preview"]; app.launch()
        XCTAssertTrue(app.buttons["setup-skip-all"].waitForExistence(timeout: 15))
        app.buttons["setup-skip-all"].tap()
        XCTAssertTrue(app.staticTexts["Your setup at a glance."].waitForExistence(timeout: 10))
        app.revealInContent(app.staticTexts["setup-incomplete"])
        XCTAssertTrue(app.staticTexts["setup-incomplete"].exists)
        app.buttons["setup-start-exploring"].tap()
        XCTAssertFalse(app.buttons["setup-start-exploring"].exists)
    }
}
