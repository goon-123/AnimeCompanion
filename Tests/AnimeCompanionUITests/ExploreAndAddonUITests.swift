import XCTest
import UIKit

final class ExploreAndAddonUITests: XCTestCase {
    @MainActor
    func testMultipleManifestInstallsPersistAndCanBeDisabledOrRemovedIndependently() {
        let app = launch()
        openAddons(app)
        install("alpha", name: "Alpha sources", in: app)
        install("beta", name: "Beta sources", in: app)
        XCTAssertTrue(app.staticTexts["UI preview"].exists)
        let alpha = app.switches["Enable Alpha sources"]
        app.revealInContent(alpha, upward: false); alpha.tap()
        XCTAssertEqual(alpha.value as? String, "0")
        app.terminate(); app.launchArguments += ["--ui-keep-addon-preview"]; app.launch()
        openAddons(app)
        XCTAssertTrue(app.staticTexts["Alpha sources"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Beta sources"].exists)
        XCTAssertEqual(app.switches["Enable Alpha sources"].value as? String, "0")
        let remove = app.buttons["Remove Alpha sources"]
        app.revealInContent(remove); remove.tap()
        XCTAssertFalse(app.staticTexts["Alpha sources"].exists)
        XCTAssertTrue(app.staticTexts["UI preview"].exists)
        XCTAssertTrue(app.staticTexts["Beta sources"].exists)
        capture("Multiple-Manifests-Persist-And-Remove")
    }
    @MainActor
    func testCombinedSourcesKeepEnglishFirstAndLaunchTheSelectedProvider() {
        let app = launch()
        openAddons(app)
        install("alpha", name: "Alpha sources", in: app)
        install("beta", name: "Beta sources", in: app)
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["Done"].tap()
        let watch = app.buttons["featured-watch-1"]
        app.revealInContent(watch); watch.tap()
        let beta = app.buttons["playback-source-2"]
        XCTAssertTrue(beta.waitForExistence(timeout: 15))
        XCTAssertTrue(beta.label.contains("From Beta sources"))
        XCTAssertTrue(app.buttons["playback-source-1"].label.contains("From Alpha sources"))
        let audio = app.segmentedControls["playback-audio-filter"]
        app.revealInContent(audio, upward: false); audio.buttons["English"].tap()
        XCTAssertFalse(app.buttons["playback-source-1"].exists, "Japanese audio with English subtitles must not match English audio")
        XCTAssertTrue(beta.exists)
        XCTAssertEqual(app.textFields["playback-episode-number"].value as? String, "9")
        app.revealInContent(beta); beta.tap()
        let launch = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@", "Preview launch · Episode 9", "Beta sources")).firstMatch
        XCTAssertTrue(launch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["playback-anilist-progress"].label.contains("8 episodes watched"))
        capture("Combined-English-Sources-Provider-Identity")
    }
    @MainActor
    func testBrowseLoadsNextPageByScrollingAndRetainsItAfterDetails() {
        let app = launch()
        app.buttons["explore-search"].tap()
        XCTAssertTrue(app.buttons["discovery-entry-1"].waitForExistence(timeout: 10))
        app.buttons["discovery-layout"].tap(); app.buttons["discovery-layout-option-grid"].tap()
        app.buttons["discovery-columns"].tap(); app.buttons["discovery-column-option-8"].tap()
        let next = app.buttons["discovery-entry-25"]
        for _ in 0..<18 where !next.isHittable { app.browseSurface.swipeUp() }
        XCTAssertTrue(next.waitForExistence(timeout: 15)); XCTAssertTrue(next.isHittable)
        XCTAssertFalse(app.buttons["discovery-more"].exists)
        let count = app.staticTexts["discovery-count"].label
        XCTAssertTrue(count.contains("48"))
        next.tap()
        XCTAssertTrue(app.staticTexts["detail-title"].waitForExistence(timeout: 10))
        app.returnToBrowsing()
        XCTAssertEqual(app.staticTexts["discovery-count"].label, count)
        XCTAssertTrue(next.isHittable)
        capture("Automatic-Pagination-And-Back")
    }
    @MainActor private func launch() -> XCUIApplication {
        continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-phase2-preview", "--ui-multiple-addons-preview", "--ui-reset-content-preferences"]
        app.launch()
        XCTAssertTrue(app.buttons["explore-search"].waitForExistence(timeout: 15))
        return app
    }
    @MainActor private func openAddons(_ app: XCUIApplication) {
        app.openExploreControl("explore-settings")
        let setup = app.buttons["playback-settings"]
        app.revealInContent(setup); setup.tap()
        XCTAssertTrue(app.navigationBars["Add-ons & playback"].waitForExistence(timeout: 10))
        app.revealInContent(app.textFields["addon-install-url"])
    }
    @MainActor private func install(_ path: String, name: String, in app: XCUIApplication) {
        let field = app.textFields["addon-install-url"]
        app.revealInContent(field); field.tap(); field.typeText("https://addon.example/\(path)/manifest.json\n")
        let add = app.buttons["connect-streaming-addon"]
        app.revealInContent(add); add.tap()
        let saved = app.staticTexts[name]
        app.revealInContent(saved, upward: false)
        XCTAssertTrue(saved.waitForExistence(timeout: 10))
    }
    @MainActor private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "Explore-Addons-\(name)"; attachment.lifetime = .keepAlways
        add(attachment)
    }
}
