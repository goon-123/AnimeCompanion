import XCTest
import UIKit

/// Real WKNavigationDelegate handoffs against local HTML and fixture JSON only.
/// No directory account, personal token, Keychain or external player is used.
final class AddonDirectoryUITests: XCTestCase {
    @MainActor
    func testManifestEntryIsReadableAndCatalogOnlyManifestInstalls() {
        let app = launch(); openSettings(app)
        let field = app.textFields["addon-install-url"]
        app.revealInContent(field); field.tap()
        field.typeText("https://addon.example/catalog/manifest.json")
        XCTAssertEqual(field.value as? String, "https://addon.example/catalog/manifest.json")
        XCTAssertFalse(app.secureTextFields["addon-install-url"].exists)
        field.typeText("\n")
        let install = app.buttons["connect-streaming-addon"]
        app.revealInContent(install); install.tap()
        app.revealInContent(app.staticTexts["Fixture catalog"], upward: false)
        XCTAssertTrue(app.staticTexts["Fixture catalog"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["UI preview"].exists, "Installing a catalog must preserve an existing streaming add-on")
        capture("Readable-Manifest-Catalog-Install")
    }

    @MainActor
    func testDirectoryInstallNeedsConfirmationAndCancelSavesNothing() {
        let app = launch(); openSettings(app); openBrowser(app)
        app.webViews.links["Install catalog"].tap()
        XCTAssertTrue(app.navigationBars["Review add-on"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["addon-review-capabilities"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["addon-review-capabilities"].label.contains("Catalogs"))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Browse add-ons"].waitForExistence(timeout: 10))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertFalse(app.staticTexts["Fixture catalog"].exists)
        XCTAssertTrue(app.staticTexts["UI preview"].exists)
        openBrowser(app); installLink("Install catalog", app: app)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Fixture catalog"].waitForExistence(timeout: 10))
        capture("Directory-Reviewed-Install")
    }

    @MainActor
    func testRequiredConfigurationKeepsOpaqueInstallPathAndCanBeManaged() {
        let app = launch(); openSettings(app); openBrowser(app)
        app.webViews.links["Configure provider"].tap()
        let install = app.buttons["addon-review-install"]
        XCTAssertTrue(install.waitForExistence(timeout: 10))
        app.revealInContent(install)
        XCTAssertFalse(install.isEnabled)
        let configure = app.buttons["addon-review-configure"]
        app.revealInContent(configure); configure.tap()
        let configuredLink = app.webViews.links["Install configured provider"]
        XCTAssertTrue(configuredLink.waitForExistence(timeout: 10)); configuredLink.tap()
        XCTAssertTrue(app.staticTexts["addon-review-url"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["addon-review-url"].label.contains("opaque%2Btoken/manifest.json"))
        let confirm = app.buttons["addon-review-install"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10)); app.revealInContent(confirm); confirm.tap()
        XCTAssertTrue(app.staticTexts["browser-addon-saved"].waitForExistence(timeout: 10))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Configured sources"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Needs setup"].exists)
        let toggle = app.switches["Enable Configured sources"]
        app.revealInContent(toggle); toggle.tap(); XCTAssertEqual(toggle.value as? String, "0")
        let remove = app.buttons["Remove Configured sources"]
        app.revealInContent(remove); remove.tap()
        XCTAssertFalse(app.staticTexts["Configured sources"].exists)
        XCTAssertTrue(app.staticTexts["UI preview"].exists)
        capture("Configured-Install-Disable-Remove")
    }

    @MainActor
    func testTargetBlankInstallAndCatalogExactIDPlaybackWithSubtitleAddon() {
        let app = launch(); openSettings(app); openBrowser(app)
        installLink("Install IMDb sources", app: app)
        installLink("Install catalog", app: app)
        installLink("Install subtitles", app: app)
        app.navigationBars.buttons.firstMatch.tap()
        let catalogs = app.buttons["browse-installed-catalogs"]
        app.revealInContent(catalogs, upward: false); catalogs.tap()
        let catalog = app.buttons["installed-addon-catalog-fixture"]
        XCTAssertTrue(catalog.waitForExistence(timeout: 10)); catalog.tap()
        let movie = app.buttons["addon-catalog-title-tt100"]
        XCTAssertTrue(movie.waitForExistence(timeout: 10)); app.revealInContent(movie); movie.tap()
        let find = app.buttons["addon-meta-find-sources"]
        XCTAssertTrue(find.waitForExistence(timeout: 10)); find.tap()
        let source = app.buttons["playback-source-0"]
        XCTAssertTrue(source.waitForExistence(timeout: 10))
        XCTAssertTrue(source.label.contains("IMDb sources")); XCTAssertTrue(source.label.contains("English"))
        let information = app.buttons["playback-source-info-0"]
        app.revealInContent(information); information.tap()
        XCTAssertTrue(app.navigationBars["Source information"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "playback-original-source-text").firstMatch.exists)
        app.buttons["close-source-information"].tap()
        XCTAssertTrue(source.waitForExistence(timeout: 10))
        app.revealInContent(source); source.press(forDuration: 1.1)
        app.buttons["Choose subtitles"].tap()
        let subtitles = app.buttons["Play with en subtitles"]
        XCTAssertTrue(subtitles.waitForExistence(timeout: 10)); subtitles.tap()
        let message = app.staticTexts["addon-video-player-message"]
        XCTAssertTrue(message.waitForExistence(timeout: 10)); XCTAssertTrue(message.label.contains("Preview catalog launch"))
        XCTAssertTrue(message.label.contains("Catalog movie")); XCTAssertTrue(message.label.contains("IMDb sources"))
        capture("Catalog-Exact-ID-EN-Subtitle-Handoff")
    }

    @MainActor private func launch() -> XCUIApplication {
        continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-phase2-preview", "--ui-multiple-addons-preview", "--ui-addon-browser-preview", "--ui-reset-content-preferences"]
        app.launch()
        XCTAssertTrue(app.buttons["explore-search"].waitForExistence(timeout: 15))
        return app
    }
    @MainActor private func openSettings(_ app: XCUIApplication) {
        app.openExploreControl("explore-settings")
        let setup = app.buttons["playback-settings"]
        app.revealInContent(setup); setup.tap()
        XCTAssertTrue(app.navigationBars["Add-ons & playback"].waitForExistence(timeout: 10))
    }
    @MainActor private func openBrowser(_ app: XCUIApplication) {
        let browser = app.buttons["browse-addon-directory"]
        app.revealInContent(browser, upward: false); browser.tap()
        XCTAssertTrue(app.webViews.links["Install catalog"].waitForExistence(timeout: 10))
    }
    @MainActor private func installLink(_ label: String, app: XCUIApplication) {
        let link = app.webViews.links[label]
        XCTAssertTrue(link.waitForExistence(timeout: 10)); link.tap()
        let install = app.buttons["addon-review-install"]
        XCTAssertTrue(install.waitForExistence(timeout: 10)); app.revealInContent(install); install.tap()
        XCTAssertTrue(app.staticTexts["browser-addon-saved"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.navigationBars["Browse add-ons"].waitForExistence(timeout: 10))
    }
    @MainActor private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "Addons-\(name)"; attachment.lifetime = .keepAlways; add(attachment)
    }
}
