import XCTest
import UIKit

final class MangaBakaSavedAccountsUITests: XCTestCase {
    @MainActor private func launch() -> XCUIApplication {
        continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-reset-content-preferences", "--ui-phase2-preview", "--ui-customization-preview",
            "--ui-unified-preview", "--ui-account-switcher-preview", "--ui-mangabaka-accounts-preview"]
        app.launch(); XCTAssertTrue(app.buttons["account-switcher"].waitForExistence(timeout: 20))
        return app
    }
    @MainActor private func tapVisible(_ element: XCUIElement, _ app: XCUIApplication, towardTop: Bool = false) {
        for _ in 0..<8 {
            if element.exists && element.isHittable { break }
            if towardTop { app.collectionViews.allElementsBoundByIndex.last?.swipeDown() }
            else { app.collectionViews.allElementsBoundByIndex.last?.swipeUp() }
        }
        XCTAssertTrue(element.waitForExistence(timeout: 10)); XCTAssertTrue(element.isHittable); element.tap()
    }
    @MainActor private func settings(_ app: XCUIApplication) {
        app.buttons["account-switcher"].tap()
        tapVisible(app.buttons["account-manage-mangabaka"], app)
        XCTAssertTrue(app.navigationBars["MangaBaka account"].waitForExistence(timeout: 10))
    }
    @MainActor private func capture(_ name: String, _ app: XCUIApplication) {
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = name; image.lifetime = .keepAlways; add(image)
    }
    @MainActor func testOneTapSwitchKeepsBothLoginsAndRestoresTheSelectedLibraryAfterRestart() {
        let app = launch(); settings(app)
        let a = app.buttons["mangabaka-saved-account-owned-reader"], b = app.buttons["mangabaka-saved-account-owned-reader-two"]
        XCTAssertTrue(a.waitForExistence(timeout: 10)); XCTAssertTrue(b.exists)
        XCTAssertEqual(a.value as? String, "Active")
        tapVisible(b, app)
        XCTAssertEqual(b.value as? String, "Active"); XCTAssertEqual(a.value as? String, "Saved")
        XCTAssertTrue(app.staticTexts["mangabaka-active-name"].label.contains("HarborReader"))
        capture("MangaBaka-Two-Saved-Accounts", app)
        tapVisible(app.buttons["account-use-mangabaka"], app, towardTop: true)
        XCTAssertTrue(app.segmentedControls["library-media-picker"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["HarborReader"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["A Lantern Across the Sea"].waitForExistence(timeout: 10))
        app.terminate(); app.launchArguments.removeAll { $0 == "--ui-reset-content-preferences" }; app.launch()
        XCTAssertTrue(app.buttons["account-switcher"].waitForExistence(timeout: 20))
        app.appTab("My Library").tap()
        XCTAssertTrue(app.staticTexts["HarborReader"].waitForExistence(timeout: 10))
        settings(app)
        XCTAssertTrue(a.waitForExistence(timeout: 10)); XCTAssertTrue(b.exists)
        XCTAssertEqual(b.value as? String, "Active")
        capture("MangaBaka-Saved-Selection-Relaunch", app)
    }
    @MainActor func testAccountActionIsReadableInsideThePageAndNotABottomOverlay() {
        let app = launch(); settings(app)
        let action = app.buttons["account-use-mangabaka"]
        XCTAssertTrue(action.waitForExistence(timeout: 10))
        XCTAssertTrue(action.label.contains("Open MangaBaka library"))
        XCTAssertLessThan(action.frame.midY, app.frame.height * 0.6)
        XCTAssertTrue(app.buttons["mangabaka-add-account"].exists)
        capture("MangaBaka-No-Blank-Bottom-Bar", app)
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCUIDevice.shared.orientation = .landscapeLeft
            XCTAssertTrue(action.waitForExistence(timeout: 10)); capture("MangaBaka-Accounts-Landscape", app)
        }
    }
    @MainActor func testRemovingSelectedSavedAccountRetainsTheOtherLogin() {
        let app = launch(); settings(app)
        tapVisible(app.buttons["mangabaka-saved-account-owned-reader-two"], app)
        tapVisible(app.buttons["mangabaka-remove-selected"], app)
        app.alerts.buttons["Remove"].tap()
        let first = app.buttons["mangabaka-saved-account-owned-reader"]
        tapVisible(first, app, towardTop: true)
        XCTAssertTrue(first.waitForExistence(timeout: 10)); XCTAssertEqual(first.value as? String, "Active")
        XCTAssertFalse(app.buttons["mangabaka-saved-account-owned-reader-two"].exists)
        capture("MangaBaka-Remove-One-Keep-Other", app)
    }
}
