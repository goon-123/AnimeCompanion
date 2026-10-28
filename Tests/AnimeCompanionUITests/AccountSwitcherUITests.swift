import XCTest
import UIKit

final class AccountSwitcherUITests: XCTestCase {
    @MainActor private func launch(extra: [String] = []) -> XCUIApplication {
        continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-reset-content-preferences", "--ui-phase2-preview", "--ui-customization-preview",
            "--ui-unified-preview", "--ui-account-switcher-preview"] + extra
        app.launch()
        XCTAssertTrue(app.buttons["account-switcher"].waitForExistence(timeout: 20))
        return app
    }
    @MainActor private func openAccounts(_ app: XCUIApplication) {
        app.buttons["account-switcher"].tap()
        XCTAssertTrue(app.navigationBars["Accounts"].waitForExistence(timeout: 10))
    }
    @MainActor private func assertBothConnected(_ app: XCUIApplication, active: String) {
        XCTAssertTrue(app.buttons["account-switch-anilist"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["account-switch-mangabaka"].exists)
        XCTAssertTrue((app.buttons["account-switch-anilist"].value as? String ?? "").contains("HarborWatcher"))
        XCTAssertTrue((app.buttons["account-switch-mangabaka"].value as? String ?? "").contains("LanternReader"))
        XCTAssertTrue((app.buttons["account-switch-" + active].value as? String ?? "").contains("Active"))
    }
    @MainActor func testSwitchesBothLibrariesAndKeepsBothAccountsConnected() {
        let app = launch()
        openAccounts(app); assertBothConnected(app, active: "anilist")
        capture("Accounts-Both-Connected")
        app.buttons["account-switch-mangabaka"].tap()
        let picker = app.segmentedControls["library-media-picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10)); XCTAssertTrue(picker.buttons["Manga & Novels"].isSelected)
        XCTAssertTrue(app.staticTexts["LanternReader"].waitForExistence(timeout: 10))
        openAccounts(app); assertBothConnected(app, active: "mangabaka")
        app.buttons["account-switch-anilist"].tap()
        XCTAssertTrue(picker.waitForExistence(timeout: 10)); XCTAssertTrue(picker.buttons["Anime"].isSelected)
        XCTAssertTrue(app.scrollViews["library-scroll"].waitForExistence(timeout: 10))
        openAccounts(app); assertBothConnected(app, active: "anilist")
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCUIDevice.shared.orientation = .landscapeLeft
            assertBothConnected(app, active: "anilist"); capture("Accounts-iPad-Landscape")
        }
    }
    @MainActor func testSelectedAccountAndLibrarySurviveRelaunch() {
        let app = launch()
        openAccounts(app); app.buttons["account-switch-mangabaka"].tap()
        XCTAssertTrue(app.segmentedControls["library-media-picker"].waitForExistence(timeout: 10))
        app.terminate(); app.launchArguments.removeAll { $0 == "--ui-reset-content-preferences" }; app.launch()
        XCTAssertTrue(app.buttons["account-switcher"].waitForExistence(timeout: 20))
        openAccounts(app); assertBothConnected(app, active: "mangabaka")
        app.navigationBars["Accounts"].buttons["Done"].tap()
        app.appTab("My Library").tap()
        XCTAssertTrue(app.segmentedControls["library-media-picker"].buttons["Manga & Novels"].isSelected)
        capture("Accounts-Saved-Library")
    }
    @MainActor func testSecondAccountSignInAndSettingsStayReachable() {
        let app = launch(extra: ["--ui-account-mangabaka-disconnected"])
        openAccounts(app)
        XCTAssertTrue(app.buttons["account-switch-anilist"].waitForExistence(timeout: 10))
        app.buttons["account-signin-mangabaka"].tap()
        XCTAssertTrue(app.buttons["Sign in with MangaBaka"].waitForExistence(timeout: 10))
        app.navigationBars["MangaBaka account"].buttons["Accounts"].tap()
        app.buttons["account-app-settings"].tap()
        XCTAssertTrue(app.buttons["settings-account"].waitForExistence(timeout: 10))
        app.buttons["settings-account-switcher"].tap()
        XCTAssertTrue(app.buttons["account-switch-anilist"].waitForExistence(timeout: 10))
        app.buttons["account-switch-anilist"].tap()
        XCTAssertTrue(app.scrollViews["library-scroll"].waitForExistence(timeout: 10))
        openAccounts(app); app.buttons["account-manage-anilist"].tap()
        XCTAssertTrue(app.buttons["Disconnect"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["account-use-anilist"].exists)
        app.buttons["account-use-anilist"].tap()
        XCTAssertTrue(app.scrollViews["library-scroll"].waitForExistence(timeout: 10))
    }
    @MainActor func testAniListSignInDoesNotReplaceMangaBakaAndHiddenLibraryOpens() {
        let app = launch(extra: ["--ui-account-anilist-disconnected", "--ui-account-hidden-library"])
        XCTAssertFalse(app.appTab("My Library").exists)
        openAccounts(app)
        app.buttons["account-signin-anilist"].tap()
        XCTAssertTrue(app.textFields["AniList app ID"].waitForExistence(timeout: 10))
        app.navigationBars["AniList account"].buttons["Accounts"].tap()
        XCTAssertTrue(app.buttons["account-switch-mangabaka"].exists)
        app.buttons["account-switch-mangabaka"].tap()
        XCTAssertTrue(app.segmentedControls["library-media-picker"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["LanternReader"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.appTab("My Library").exists)
        capture("Accounts-Hidden-Library")
        app.navigationBars["My Library"].buttons["Close"].tap()
        XCTAssertTrue(app.buttons["unified-explore-search"].waitForExistence(timeout: 10))
    }
    @MainActor private func capture(_ name: String) {
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = name; image.lifetime = .keepAlways; add(image)
    }
}
