import XCTest

/// Exercises setup without ever installing or publishing a personal add-on URL.
final class PlaybackUITests: XCTestCase {
    @MainActor
    func testPlaybackSetupRejectsInvalidURLAndKeepsAccountSettingsAccessible() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        let settings = app.buttons["Account and settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 20)); settings.tap()
        let playback = app.buttons["playback-settings"]
        for _ in 0..<6 where !playback.isHittable { app.swipeUp() }
        XCTAssertTrue(playback.waitForExistence(timeout: 10)); playback.tap()
        let field = app.secureTextFields["addon-install-url"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap(); field.typeText("https://")
        app.buttons["connect-streaming-addon"].tap()
        XCTAssertTrue(app.staticTexts["Paste the add-on’s HTTPS install link or manifest URL."].waitForExistence(timeout: 10))
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "VidHub-Addon-Setup"; screenshot.lifetime = .keepAlways; add(screenshot)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.tabBars.buttons["Explore"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testWatchEpisodeDefaultsToNextAniListEpisodeAndAllowsSetup() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--ui-library-preview"]; app.launch()
        XCTAssertTrue(app.tabBars.buttons["My Library"].waitForExistence(timeout: 20)); app.tabBars.buttons["My Library"].tap()
        let entry = app.buttons["library-entry-1"]
        XCTAssertTrue(entry.waitForExistence(timeout: 45)); entry.tap()
        let watch = app.buttons["watch-in-vidhub"]
        XCTAssertTrue(watch.waitForExistence(timeout: 35))
        for _ in 0..<8 where !watch.isHittable { app.swipeUp() }
        XCTAssertTrue(watch.isHittable); watch.tap()
        let episode = app.textFields["playback-episode-number"]
        XCTAssertTrue(episode.waitForExistence(timeout: 10)); XCTAssertEqual(episode.value as? String, "9")
        XCTAssertTrue(app.buttons["Set up add-on & VidHub"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "VidHub-Episode-Picker"; screenshot.lifetime = .keepAlways; add(screenshot)
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["watch-in-vidhub"].waitForExistence(timeout: 10))
    }
}
