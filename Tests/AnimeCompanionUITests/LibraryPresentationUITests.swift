import XCTest
import UIKit

/// Owned long-title and unknown-total fixtures; no real sessions or library writes.
final class LibraryPresentationUITests: XCTestCase {
    @MainActor func testListAndGridKeepProgressGenresAndSavedLayoutInBothAppearances() {
        for appearance in ["dark", "light"] {
            let app = launch(extra: ["-appearance.scheme.v1", appearance])
            let entry = app.buttons["library-entry-1"]
            let picker = app.segmentedControls["library-layout"]
            for layout in ["List", "Grid"] {
                app.revealInContent(picker, upward: false); picker.buttons[layout].tap()
                app.revealInContent(entry)
                XCTAssertTrue(entry.label.contains("The Archivist Who Woke Up in Another World"))
                XCTAssertTrue(entry.label.contains("Watched 8/26"))
                XCTAssertTrue(entry.label.contains("Next: Ep 9"))
                XCTAssertFalse(app.buttons["library-watch-1"].exists)
                XCTAssertFalse(app.buttons["library-next-1"].exists)
                assertInsideLibrary(entry, app: app)
                let genres = app.descendants(matching: .any).matching(identifier: "library-genres-1").firstMatch
                app.revealInContent(genres)
                XCTAssertTrue(genres.buttons["genre-1-Action"].isHittable)
                XCTAssertTrue(genres.buttons["genre-1-Sci-Fi"].exists)
                capture("\(appearance)-\(layout)")
            }
            // Opening a card must still navigate to details, without changing progress.
            entry.tap()
            XCTAssertTrue(app.buttons["expand-anime-cover"].waitForExistence(timeout: 15))
            app.returnToBrowsing()
            XCTAssertTrue(entry.waitForExistence(timeout: 10))
            XCTAssertTrue(entry.label.contains("Watched 8/26"))
            app.terminate()
            app.launchArguments.removeAll { $0 == "--ui-reset-content-preferences" }
            app.launch(); app.appTab("My Library").tap()
            XCTAssertTrue(app.segmentedControls["library-layout"].waitForExistence(timeout: 15))
            XCTAssertTrue(app.segmentedControls["library-layout"].buttons["Grid"].isSelected)
            app.terminate()
        }
    }

    @MainActor func testProfileButtonStaysInsideHeaderAndOpensAccountSwitcher() {
        let app = launch()
        let profile = app.buttons["account-switcher"]
        let title = app.navigationBars["My Library"].staticTexts["My Library"]
        XCTAssertTrue(profile.waitForExistence(timeout: 10)); XCTAssertTrue(title.exists)
        XCTAssertGreaterThanOrEqual(profile.frame.width, 44)
        XCTAssertGreaterThanOrEqual(profile.frame.height, 44)
        XCTAssertFalse(profile.frame.intersects(title.frame))
        XCTAssertFalse(profile.frame.intersects(app.buttons["library-display-options"].frame))
        capture("Header-Profile")
        profile.tap()
        XCTAssertTrue(app.navigationBars["Accounts"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["account-switch-anilist"].exists)
        app.navigationBars["Accounts"].buttons["Done"].tap()
        XCTAssertTrue(profile.waitForExistence(timeout: 10))
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCUIDevice.shared.orientation = .landscapeLeft
            XCTAssertTrue(profile.isHittable)
            XCTAssertFalse(profile.frame.intersects(title.frame))
            capture("Header-Profile-Landscape")
            XCUIDevice.shared.orientation = .portrait
        }
    }

    @MainActor func testAccessibilityTextAndUnknownEpisodeTotalsStayWithinLibrary() {
        let app = launch(extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        let entry = app.buttons["library-entry-1"]
        for layout in ["List", "Grid"] {
            let picker = app.segmentedControls["library-layout"]
            app.revealInContent(picker, upward: false); picker.buttons[layout].tap()
            app.revealInContent(entry)
            XCTAssertTrue(entry.label.contains("Watched 8/26"))
            XCTAssertTrue(entry.label.contains("Next: Ep 9"))
            assertInsideLibrary(entry, app: app)
            capture("Accessibility-\(layout)")
        }
        let search = app.textFields["library-search"]
        app.revealInContent(search, upward: false)
        search.tap(); search.typeText("Uncharted\n")
        let unknown = app.buttons["library-entry-990105"]
        XCTAssertTrue(unknown.waitForExistence(timeout: 10)); app.revealInContent(unknown)
        XCTAssertTrue(unknown.label.contains("Watched 2/?"))
        XCTAssertTrue(unknown.label.contains("Next: Ep 3"))
        assertInsideLibrary(unknown, app: app)
        capture("Accessibility-Unknown-Total")
    }

    @MainActor private func launch(extra: [String] = []) -> XCUIApplication {
        continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-phase2-preview", "--ui-library-design-preview", "--ui-reset-content-preferences"] + extra
        app.launch()
        XCTAssertTrue(app.appTab("My Library").waitForExistence(timeout: 25))
        app.appTab("My Library").tap()
        XCTAssertTrue(app.buttons["library-entry-1"].waitForExistence(timeout: 15))
        return app
    }
    @MainActor private func assertInsideLibrary(_ element: XCUIElement, app: XCUIApplication) {
        let pane = app.scrollViews["library-scroll"].frame
        XCTAssertGreaterThanOrEqual(element.frame.minX, pane.minX)
        XCTAssertLessThanOrEqual(element.frame.maxX, pane.maxX)
    }
    @MainActor private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "Library-\(UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone")-\(name)"
        attachment.lifetime = .keepAlways; add(attachment)
    }
}
