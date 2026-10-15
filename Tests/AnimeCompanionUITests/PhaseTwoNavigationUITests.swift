import XCTest
import UIKit

/// Offline Phase 2 regressions on both families. Playback uses the local preview
/// transport; opening details/episodes must not mutate AniList progress.
final class PhaseTwoNavigationUITests: XCTestCase {
    @MainActor
    func testTabsExposeBrowsingBeforeAnyDetailSelectionInBothOrientations() throws {
        let app = launch()
        let orientations: [UIDeviceOrientation] = UIDevice.current.userInterfaceIdiom == .pad ? [.portrait, .landscapeLeft, .portrait] : [.portrait]
        for orientation in orientations {
            XCUIDevice.shared.orientation = orientation
            if UIDevice.current.userInterfaceIdiom == .pad {
                let rotated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                    orientation.isLandscape ? app.frame.width > app.frame.height : app.frame.height > app.frame.width
                }, object: nil)
                XCTAssertEqual(XCTWaiter.wait(for: [rotated], timeout: 10), .completed)
            }
            app.appTab("Schedule").tap()
            let mode = app.segmentedControls["schedule-mode"]
            XCTAssertTrue(mode.waitForExistence(timeout: 10)); XCTAssertTrue(mode.isHittable)
            app.appTab("My Library").tap()
            XCTAssertTrue(app.textFields["library-search"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.textFields["library-search"].isHittable)
            XCTAssertFalse(app.buttons["continue-watch-1"].exists)
            XCTAssertFalse(app.buttons["library-coming-up"].exists)
            app.appTab("Explore").tap()
            XCTAssertTrue(app.buttons["explore-search"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.buttons["explore-search"].isHittable)
            XCTAssertFalse(app.buttons["explore-display-options"].isHittable)
        }
        capture("Initial-Tab-Browsing-Visibility")
    }

    @MainActor
    func testLibraryOmitsRemovedShelvesAndWatchStillUsesAniListEpisode() throws {
        let app = launch()
        app.appTab("My Library").tap()
        XCTAssertTrue(app.textFields["library-search"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["Continue Watching"].exists)
        XCTAssertFalse(app.buttons["library-coming-up"].exists)
        let entry = app.buttons["library-entry-1"]
        reveal(entry, in: app); entry.tap()
        let watch = app.buttons["watch-in-vidhub"]
        reveal(watch, in: app)
        watch.tap()
        XCTAssertTrue(app.textFields["playback-episode-number"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.textFields["playback-episode-number"].value as? String, "9")
        XCTAssertFalse(app.staticTexts["playback-resume-position"].exists, "Episode 1's local record must not resume episode 9")
        XCTAssertTrue(app.buttons["playback-source-0"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["playback-source-0"].label.contains("anilist:1:9.json"))
        app.buttons["Done"].tap()
        app.returnToBrowsing()
        reveal(app.buttons["library-entry-1"], in: app)
        XCTAssertTrue(app.buttons["library-entry-1"].label.contains("Watched 8/26"))
        capture("Watch-First-Library")
    }

    @MainActor
    func testAiringGroupsSeparateReadyCaughtUpUpcomingAndUnknown() throws {
        let app = launch()
        app.appTab("Schedule").tap()
        for group in ["ready", "caughtUp", "upcoming", "unverified"] {
            let header = app.descendants(matching: .any)["schedule-group-\(group)"].firstMatch
            reveal(header, in: app)
            XCTAssertTrue(header.exists)
        }
        reveal(app.staticTexts["library-airing-status-990105"], in: app)
        XCTAssertEqual(app.staticTexts["library-airing-status-990105"].label, "Airing · count unavailable")
        XCTAssertFalse(app.staticTexts["library-next-episode-990101"].exists, "The Schedule card must not duplicate the generic Library next-episode block")
        reveal(app.buttons["schedule-behind-filter"], in: app, upward: false)
        app.buttons["schedule-behind-filter"].tap()
        XCTAssertTrue(app.buttons["library-entry-990101"].exists)
        XCTAssertFalse(app.buttons["library-entry-990102"].exists)
        XCTAssertFalse(app.buttons["library-entry-990105"].exists)
        capture("Grouped-Airing-Now")
    }

    @MainActor
    func testDetailsDisclosuresPreserveDubCountAndExplicitEpisodeChoice() throws {
        let app = launch()
        app.appTab("My Library").tap()
        let entry = app.buttons["library-entry-1"]
        reveal(entry, in: app); entry.tap()
        let dub = app.staticTexts["detail-dub-count"]
        reveal(dub, in: app)
        XCTAssertTrue(dub.label.contains("26/26"))
        XCTAssertFalse(app.staticTexts["Upcoming releases"].exists)
        app.buttons["detail-dub-disclosure"].tap()
        XCTAssertTrue(app.staticTexts["Upcoming releases"].exists)
        app.buttons["detail-dub-disclosure"].tap()
        let episodes = app.buttons["detail-episodes-disclosure"]
        reveal(episodes, in: app)
        XCTAssertFalse(app.buttons["detail-episode-2"].exists)
        episodes.tap()
        reveal(app.buttons["detail-episode-2"], in: app)
        app.buttons["detail-episode-2"].tap()
        XCTAssertTrue(app.textFields["playback-episode-number"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.textFields["playback-episode-number"].value as? String, "2")
        XCTAssertTrue(app.buttons["playback-source-0"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["playback-source-0"].label.contains("anilist:1:2.json"))
        XCTAssertTrue(app.staticTexts["playback-anilist-progress"].label.contains("8 episodes watched"))
        app.buttons["Done"].tap()
        reveal(episodes, in: app, upward: false); episodes.tap()
        let more = app.buttons["detail-more-information"]
        reveal(more, in: app)
        XCTAssertFalse(app.staticTexts["Fixture studio"].exists)
        more.tap()
        reveal(app.staticTexts["Fixture studio"], in: app)
        XCTAssertTrue(app.staticTexts["Fixture studio"].exists)
        capture("Organized-Details-And-Episodes")
    }

    @MainActor
    func testBrowseDetailRotationRetainsQueryResultsAndGenreNavigation() throws {
        let app = launch()
        app.buttons["explore-search"].tap()
        let search = app.textFields["discovery-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap(); search.typeText("Phase\n")
        let entry = app.buttons["discovery-entry-1"]
        reveal(entry, in: app)
        let count = app.staticTexts["discovery-count"].label
        entry.tap()
        XCTAssertTrue(app.staticTexts["detail-title"].waitForExistence(timeout: 10))
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCTAssertTrue(search.exists)
            XCUIDevice.shared.orientation = .landscapeLeft
            let landscape = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in app.frame.width > app.frame.height }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [landscape], timeout: 10), .completed)
            XCTAssertLessThanOrEqual(search.frame.maxX, app.scrollViews["anime-detail-scroll"].frame.minX + 2)
            XCTAssertEqual(search.value as? String, "Phase")
            XCTAssertEqual(app.staticTexts["discovery-count"].label, count)
            XCTAssertTrue(app.staticTexts["detail-title"].exists)
            capture("iPad-Browse-And-Detail")
            XCUIDevice.shared.orientation = .portrait
        }
        app.returnToBrowsing()
        XCTAssertEqual(search.value as? String, "Phase")
        XCTAssertEqual(app.staticTexts["discovery-count"].label, count)
        XCTAssertTrue(entry.isHittable)
        entry.tap()
        let genre = app.descendants(matching: .any)["detail-genres-1"].buttons["genre-1-Action"]
        reveal(genre, in: app)
        genre.tap()
        XCTAssertTrue(app.navigationBars["Action"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["discovery-genre"].label, "Action")
        XCTAssertEqual(search.value as? String, search.placeholderValue)
    }

    @MainActor
    func testImmersiveHeroLibraryActionAndSavedDisplayOptions() throws {
        let app = launch()
        let carousel = app.descendants(matching: .any)["explore-featured-carousel"].firstMatch
        XCTAssertTrue(carousel.waitForExistence(timeout: 15))
        let pane = app.scrollViews["explore-scroll"]
        XCTAssertEqual(carousel.frame.width, pane.frame.width, accuracy: 2)
        XCTAssertGreaterThan(carousel.frame.height, pane.frame.height * 0.9)
        XCTAssertTrue(app.buttons["explore-search"].isHittable)
        XCTAssertFalse(app.buttons["explore-dub-filter-toolbar"].isHittable)
        XCTAssertFalse(app.navigationBars["Explore"].isHittable)
        let add = app.buttons["featured-add-library-1"]
        reveal(add, in: app); add.tap()
        XCTAssertTrue(app.navigationBars["Edit AniList tracking"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.textFields["tracking-episode-input"].value as? String, "8")
        app.buttons["Cancel"].tap()
        app.openExploreControl("explore-display-options")
        let balanced = app.switches["explore-featured-balanced"]
        reveal(balanced, in: app)
        XCTAssertEqual(balanced.value as? String, "0")
        balanced.tap(); app.buttons["Done"].tap()
        let smaller = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in carousel.frame.height < pane.frame.height * 0.8 }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [smaller], timeout: 10), .completed)
        app.terminate()
        app.launchArguments += ["--ui-phase2-keep-display"]
        app.launch()
        app.openExploreControl("explore-display-options")
        reveal(balanced, in: app)
        XCTAssertEqual(balanced.value as? String, "1")
        balanced.tap(); app.buttons["Done"].tap()
        capture("Balanced-Explore")
    }

    @MainActor private func launch() -> XCUIApplication {
        continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-phase2-preview", "--ui-playback-preview", "--ui-playback-stale-resume", "--ui-reset-content-preferences"]
        app.launch()
        XCTAssertTrue(app.buttons["explore-search"].waitForExistence(timeout: 15))
        return app
    }
    @MainActor private func reveal(_ element: XCUIElement, in app: XCUIApplication, upward: Bool = true) {
        app.revealInContent(element, upward: upward)
    }
    @MainActor private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "Phase2-\(UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone")-\(name)"
        attachment.lifetime = .keepAlways; add(attachment)
    }
}
