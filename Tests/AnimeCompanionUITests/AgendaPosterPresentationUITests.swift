import XCTest
import UIKit

/// Offline owned artwork and a long Today exercise the exact reported layouts.
final class AgendaPosterPresentationUITests: XCTestCase {
    @MainActor func testLibraryAndExploreHaveWideFullHeightArtworkAndWorkingTapTargets() {
        let app = launch()
        app.appTab("My Library").tap()
        let library = app.buttons["library-entry-1"]
        XCTAssertTrue(library.waitForExistence(timeout: 15)); app.revealInContent(library)
        assertArtwork("library-poster-art-1", fills: library, app: app)
        let dub = app.staticTexts["library-dub-1"]
        let rating = app.descendants(matching: .any).matching(identifier: "library-rating-1").firstMatch
        XCTAssertTrue(dub.exists); XCTAssertTrue(rating.exists)
        XCTAssertFalse(dub.frame.intersects(rating.frame))
        capture("Library-Wide-Full-Height")
        // Artwork and genres retain their independent navigation targets.
        library.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.8)).tap()
        XCTAssertTrue(app.buttons["detail-actions"].waitForExistence(timeout: 15))
        app.returnToBrowsing()
        app.appTab("Explore").tap(); app.buttons["explore-search"].tap()
        let layout = app.buttons["discovery-layout"]
        XCTAssertTrue(layout.waitForExistence(timeout: 15))
        if layout.label.contains("Grid") { layout.tap(); app.buttons["discovery-layout-option-list"].tap() }
        let explore = app.buttons["discovery-entry-1"]
        app.revealInContent(explore)
        assertArtwork("discovery-poster-art-1", fills: explore, app: app)
        let genres = app.descendants(matching: .any).matching(identifier: "explore-genres-1").firstMatch
        XCTAssertTrue(genres.buttons["genre-1-Action"].exists)
        capture("Explore-Wide-Full-Height")
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCUIDevice.shared.orientation = .landscapeLeft
            let rotated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in app.frame.width > app.frame.height }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [rotated], timeout: 10), .completed)
            app.revealInContent(explore)
            assertArtwork("discovery-poster-art-1", fills: explore, app: app)
            capture("Explore-Landscape-Full-Height")
            XCUIDevice.shared.orientation = .portrait
        }
        app.terminate()
    }

    @MainActor func testTodayHighlightsEveryReleaseAfterHeaderScrollsOffscreenAndWhenEmpty() {
        for appearance in ["dark", "light"] {
            let app = launch(extra: ["-appearance.scheme.v1", appearance])
            app.appTab("Schedule").tap()
            app.segmentedControls["schedule-mode"].buttons["Weekly Schedule"].tap()
            let today = app.descendants(matching: .any).matching(identifier: "schedule-day-2026-10-28").firstMatch
            XCTAssertTrue(today.waitForExistence(timeout: 15))
            let first = app.buttons["release-entry-990203-sub-4"]
            XCTAssertTrue(first.waitForExistence(timeout: 15))
            XCTAssertEqual(today.value as? String, "Today")
            XCTAssertEqual(first.value as? String, "Today")
            capture("Today-Whole-Section-\(appearance)")
            let agenda = app.descendants(matching: .any).matching(identifier: "schedule-weekly-list").firstMatch
            for _ in 0..<2 {
                let start = agenda.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.70))
                let end = agenda.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
                start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.05)
            }
            XCTAssertFalse(today.isHittable)
            let middle = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "release-entry-9903"))
                .allElementsBoundByIndex.filter { $0.isHittable }
            XCTAssertFalse(middle.isEmpty)
            for row in middle { XCTAssertEqual(row.value as? String, "Today") }
            capture("Today-Scrolled-Releases-\(appearance)")
            app.segmentedControls["schedule-release-type"].buttons["Dub"].tap()
            app.buttons["schedule-this-week"].tap()
            let empty = app.staticTexts["schedule-empty-day-2026-10-28"]
            XCTAssertTrue(empty.waitForExistence(timeout: 10))
            XCTAssertEqual(empty.value as? String, "Today")
            capture("Today-Empty-Releases-\(appearance)")
            app.buttons["Next week"].tap()
            XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "schedule-day-2026-10-28").firstMatch.exists)
            app.terminate()
        }
    }

    @MainActor private func launch(extra: [String] = []) -> XCUIApplication {
        continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-phase2-preview", "--ui-library-design-preview", "--ui-schedule-preview",
            "--ui-schedule-day=2026-10-28", "--ui-today-long-preview", "--ui-reset-content-preferences"] + extra
        app.launch()
        XCTAssertTrue(app.appTab("My Library").waitForExistence(timeout: 25))
        return app
    }
    @MainActor private func assertArtwork(_ id: String, fills row: XCUIElement, app: XCUIApplication) {
        let art = app.descendants(matching: .any).matching(identifier: id).firstMatch
        XCTAssertTrue(art.exists)
        XCTAssertGreaterThan(art.frame.width, min(115, row.frame.width * 0.28))
        XCTAssertLessThanOrEqual(art.frame.width, row.frame.width * 0.39)
        XCTAssertEqual(art.frame.minY, row.frame.minY, accuracy: 1)
        XCTAssertEqual(art.frame.maxY, row.frame.maxY, accuracy: 1)
    }
    @MainActor private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "Poster-Today-\(UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone")-\(name)"
        attachment.lifetime = .keepAlways; add(attachment)
    }
}
