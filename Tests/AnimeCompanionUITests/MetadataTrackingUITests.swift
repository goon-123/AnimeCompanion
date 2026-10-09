import XCTest
import UIKit

final class MetadataTrackingUITests: XCTestCase {
    @MainActor
    func testAdultSettingPersistsAndHidesExistingLibraryEntries() throws {
        let app = launchPreview()
        defer { reset(app) }
        app.tabBars.buttons["My Library"].tap()
        XCTAssertTrue(app.buttons["library-entry-1"].waitForExistence(timeout: 45))
        XCTAssertFalse(app.buttons["library-entry-990001"].exists)
        setAdult(true, app: app)
        XCTAssertTrue(app.buttons["library-entry-990001"].waitForExistence(timeout: 15))
        app.terminate(); app.launchArguments.removeAll { $0 == "--ui-reset-content-preferences" }; app.launch()
        app.tabBars.buttons["My Library"].tap()
        XCTAssertTrue(app.buttons["library-entry-990001"].waitForExistence(timeout: 45))
        setAdult(false, app: app)
        XCTAssertFalse(app.buttons["library-entry-990001"].exists)
        XCTAssertTrue(app.buttons["library-entry-1"].exists)
    }
    @MainActor
    func testLiveChartSourceSwitchKeepsAniListProgressAndNativeEditor() throws {
        let app = launchPreview()
        defer { reset(app) }
        openCowboy(app)
        let picker = app.segmentedControls["metadata-source-picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 15))
        picker.buttons["LiveChart.me"].tap()
        XCTAssertTrue(app.buttons["livechart-track-edit"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "8/26")).firstMatch.exists)
        capture("LiveChart-AniList-Tracking")
        app.buttons["livechart-track-edit"].tap()
        XCTAssertTrue(app.textFields["tracking-episode-input"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.textFields["tracking-episode-input"].value as? String, "8")
        if UIDevice.current.userInterfaceIdiom == .pad { XCUIDevice.shared.orientation = .landscapeLeft }
        capture("Tracking-Editor")
        app.buttons["Cancel"].tap()
        picker.buttons["AniList"].tap()
        XCTAssertTrue(app.buttons["tracking-set-episode"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["tracking-set-episode"].label.contains("8 / 26"))
    }
    @MainActor
    func testInvalidEpisodeIsRejectedWithoutChangingConfirmedProgress() throws {
        let app = launchPreview()
        defer { reset(app) }
        openCowboy(app)
        let edit = app.buttons["tracking-edit"]
        reveal(edit, app: app); edit.tap()
        let input = app.textFields["tracking-episode-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 15)); input.tap()
        input.typeText(XCUIKeyboardKey.delete.rawValue + "999")
        app.buttons["tracking-save"].tap()
        XCTAssertTrue(app.staticTexts["Enter an episode number within this anime’s AniList episode total."].waitForExistence(timeout: 10))
        capture("Invalid-Episode-Preserves-Progress")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["tracking-set-episode"].label.contains("8 / 26"))
    }
    @MainActor private func launchPreview() -> XCUIApplication {
        continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-library-preview", "--ui-content-preview", "--ui-livechart-preview", "--ui-reset-content-preferences"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["My Library"].waitForExistence(timeout: 30))
        return app
    }
    @MainActor private func openCowboy(_ app: XCUIApplication) {
        app.tabBars.buttons["My Library"].tap()
        let entry = app.buttons["library-entry-1"]
        XCTAssertTrue(entry.waitForExistence(timeout: 45)); reveal(entry, app: app); entry.tap()
        XCTAssertTrue(app.buttons["expand-anime-cover"].waitForExistence(timeout: 45))
    }
    @MainActor private func setAdult(_ enabled: Bool, app: XCUIApplication) {
        app.buttons["Account and settings"].tap()
        let toggle = app.switches["settings-adult-content"]
        reveal(toggle, app: app)
        if (toggle.value as? String == "1") != enabled {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
        }
        capture(enabled ? "Adult-Setting-Enabled" : "Adult-Setting-Disabled")
        app.buttons["Done"].tap()
    }
    @MainActor private func reveal(_ element: XCUIElement, app: XCUIApplication) {
        for _ in 0..<12 { if element.isHittable { return }; app.swipeUp() }
        XCTAssertTrue(element.isHittable)
    }
    @MainActor private func reset(_ app: XCUIApplication) {
        app.terminate(); app.launchArguments = ["--ui-reset-content-preferences"]; app.launch(); app.terminate()
        XCUIDevice.shared.orientation = .portrait
    }
    @MainActor private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "Metadata-\(UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone")-\(name)"
        attachment.lifetime = .keepAlways; add(attachment)
    }
}
