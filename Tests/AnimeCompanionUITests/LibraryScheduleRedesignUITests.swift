import XCTest
import UIKit

/// Real native navigation with offline data: these checks never write to an account.
final class LibraryScheduleRedesignUITests: XCTestCase {
    @MainActor func testLibraryArtworkStaysClearAndContextActionsPreserveEpisodeSelection() {
        let app = launch()
        app.appTab("My Library").tap()
        let entry = app.buttons["library-entry-1"]
        XCTAssertTrue(entry.waitForExistence(timeout: 30))
        for layout in ["List", "Grid"] {
            let picker = app.segmentedControls["library-layout"]
            app.revealInContent(picker, upward: false); picker.buttons[layout].tap()
            app.revealInContent(entry)
            XCTAssertTrue(entry.label.contains("Watched 8/26"))
            XCTAssertFalse(app.buttons["library-watch-1"].exists)
            XCTAssertFalse(app.buttons["library-next-1"].exists)
            capture("Clean-Library-\(layout)")
        }
        app.openLibraryActions(1)
        XCTAssertTrue(app.buttons["library-watch-1"].label.contains("episode 9"))
        XCTAssertTrue(app.buttons["library-next-1"].exists)
        app.buttons["library-edit-1"].tap()
        XCTAssertTrue(app.textFields["tracking-episode-input"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.textFields["tracking-episode-input"].value as? String, "8")
        app.buttons["Cancel"].tap()
        app.watchLibraryEntry(1)
        XCTAssertTrue(app.textFields["playback-episode-number"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.textFields["playback-episode-number"].value as? String, "9")
        app.buttons["Done"].tap()
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        XCTAssertTrue(entry.label.contains("Watched 8/26"), "Opening actions and playback must not mark an episode watched")
    }

    @MainActor func testAiringNowKeepsCatchUpAndNextReleaseWithoutActionStacks() {
        let app = launch()
        app.appTab("Schedule").tap()
        let behind = app.staticTexts["library-airing-status-990101"]
        XCTAssertTrue(behind.waitForExistence(timeout: 15))
        app.revealInContent(behind)
        XCTAssertEqual(behind.label, "2 episodes behind")
        XCTAssertTrue(app.staticTexts["library-airing-next-990101"].label.contains("Next SUB · Ep 7"))
        XCTAssertFalse(app.buttons["library-watch-990101"].exists)
        XCTAssertFalse(app.buttons["library-next-990101"].exists)
        capture("Compact-Airing-Now")
        app.chooseAiringLayout("Grid")
        app.revealInContent(behind)
        XCTAssertEqual(behind.label, "2 episodes behind")
        XCTAssertFalse(app.buttons["library-watch-990101"].exists)
        capture("Clean-Airing-Grid")
        app.terminate()
        app.launchArguments.removeAll { $0 == "--ui-reset-content-preferences" }
        app.launch(); app.appTab("Schedule").tap()
        XCTAssertTrue(app.buttons["schedule-airing-layout"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.buttons["schedule-airing-layout"].value as? String, "Grid")
    }

    @MainActor func testCalendarDateSelectionAndReleaseTypesInBothAppearances() {
        for appearance in ["dark", "light"] {
            let app = launch(extra: ["-appearance.scheme.v1", appearance])
            app.appTab("Schedule").tap()
            app.segmentedControls["schedule-mode"].buttons["Weekly Schedule"].tap()
            let today = app.buttons["schedule-jump-2026-10-28"]
            XCTAssertTrue(today.waitForExistence(timeout: 15))
            XCTAssertTrue(today.isSelected)
            XCTAssertEqual(app.scrollViews["schedule-weekdays"].buttons.count, 7)
            XCTAssertTrue(app.buttons["release-entry-990203-sub-4"].waitForExistence(timeout: 20))
            capture("Calendar-\(appearance)")
            app.buttons["schedule-jump-2026-10-26"].tap()
            XCTAssertTrue(app.buttons["schedule-jump-2026-10-26"].isSelected)
            XCTAssertFalse(today.isSelected)
            app.segmentedControls["schedule-release-type"].buttons["Dub"].tap()
            XCTAssertTrue(app.staticTexts["No listed releases for this day."].firstMatch.waitForExistence(timeout: 10))
            app.buttons["schedule-this-week"].tap()
            XCTAssertTrue(today.isSelected)
            app.segmentedControls["schedule-release-type"].buttons["All"].tap()
            if UIDevice.current.userInterfaceIdiom == .pad {
                XCUIDevice.shared.orientation = .landscapeLeft
                XCTAssertTrue(today.isHittable)
                capture("Calendar-\(appearance)-Landscape")
                XCUIDevice.shared.orientation = .portrait
            }
            app.terminate()
        }
    }

    @MainActor private func launch(extra: [String] = []) -> XCUIApplication {
        continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-phase2-preview", "--ui-playback-preview", "--ui-reset-content-preferences",
            "--ui-schedule-preview", "--ui-schedule-day=2026-10-28"] + extra
        app.launch()
        XCTAssertTrue(app.appTab("My Library").waitForExistence(timeout: 30))
        return app
    }
    @MainActor private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "Library-Schedule-\(UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone")-\(name)"
        attachment.lifetime = .keepAlways; add(attachment)
    }
}
