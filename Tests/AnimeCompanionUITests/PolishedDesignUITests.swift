import XCTest
import UIKit

/// Native taps and screenshots for both iPhone and iPad, with synthetic progress and no account writes.
final class PolishedDesignUITests: XCTestCase {
    @MainActor
    func testLibraryGenreScrollOpensExploreWithFreshGenreFilterAndRetainsLibrary() throws {
        let app = launchPreview()
        let tags = app.descendants(matching: .any).matching(identifier: "library-genres-1").firstMatch
        reveal(tags, in: app)
        XCTAssertTrue(tags.buttons["genre-1-Action"].exists)
        let sciFi = tags.buttons["genre-1-Sci-Fi"]
        for _ in 0..<4 where !sciFi.isHittable { tags.swipeLeft() }
        XCTAssertTrue(sciFi.isHittable)
        XCTAssertLessThan(tags.frame.height, 65, "Genres must stay in one compact row")
        capture("Library-Scrollable-Genres")
        sciFi.tap()
        assertGenre("Sci-Fi", in: app)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "discovery-entry-")).firstMatch.waitForExistence(timeout: 45))
        capture("Genre-Filtered-Explore")
        app.tabBars.buttons["My Library"].tap()
        XCTAssertTrue(app.buttons["library-entry-1"].exists)
        XCTAssertTrue(app.buttons["library-watch-1"].label.contains("episode 9"))
        app.buttons["library-entry-1"].tap()
        let detailTags = app.descendants(matching: .any).matching(identifier: "detail-genres-1").firstMatch
        XCTAssertTrue(detailTags.waitForExistence(timeout: 45)); reveal(detailTags, in: app)
        detailTags.buttons["genre-1-Action"].tap()
        assertGenre("Action", in: app)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "discovery-entry-")).firstMatch.waitForExistence(timeout: 45))
        capture("Detail-Genre-Shortcut")
    }

    @MainActor
    func testExploreGenreShortcutReplacesStaleSearchAndSurvivesDetailBackNavigation() throws {
        let app = launchPreview()
        app.tabBars.buttons["Explore"].tap(); app.buttons["explore-search"].tap()
        let search = app.textFields["discovery-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 15))
        if app.buttons["discovery-layout"].label.contains("Grid") {
            app.buttons["discovery-layout"].tap(); app.buttons["discovery-layout-option-list"].tap()
        }
        search.tap(); search.typeText("Cowboy\n")
        XCTAssertTrue(app.buttons["discovery-entry-1"].waitForExistence(timeout: 45))
        let tags = app.descendants(matching: .any).matching(identifier: "explore-genres-1").firstMatch
        reveal(tags, in: app); tags.buttons["genre-1-Action"].tap()
        assertGenre("Action", in: app)
        let entry = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "discovery-entry-")).firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 45)); reveal(entry, in: app)
        let identifier = entry.identifier
        entry.tap(); XCTAssertTrue(app.buttons["expand-anime-cover"].waitForExistence(timeout: 45))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Action"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons[identifier].isHittable)
        reveal(search, in: app, upward: false); search.tap(); search.typeText("Cowboy\n")
        XCTAssertTrue(app.buttons["discovery-entry-1"].waitForExistence(timeout: 45))
        reveal(tags, in: app); tags.buttons["genre-1-Action"].tap()
        assertGenre("Action", in: app)
        capture("Explore-Genre-Replaces-Stale-Search")
    }

    @MainActor
    func testCinematicDetailsKeepDubCountTrackingArtworkAndCorrectResumeEpisode() throws {
        let app = launchPreview()
        app.buttons["library-entry-1"].tap()
        let cover = app.buttons["expand-anime-cover"]
        XCTAssertTrue(cover.waitForExistence(timeout: 45))
        XCTAssertTrue(app.buttons["expand-anime-banner"].exists)
        XCTAssertTrue(app.staticTexts["detail-title"].label.contains("Cowboy"))
        XCTAssertEqual(app.staticTexts["detail-release-status"].label, "Finished")
        let watch = app.buttons["watch-in-vidhub"]
        reveal(watch, in: app)
        XCTAssertTrue(watch.label.contains("Resume episode 9"))
        capture("Cinematic-Details-Header")
        watch.tap()
        XCTAssertTrue(app.textFields["playback-episode-number"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.textFields["playback-episode-number"].value as? String, "9")
        let source = app.buttons["playback-source-0"]
        XCTAssertTrue(source.waitForExistence(timeout: 15)); source.tap()
        XCTAssertTrue(app.staticTexts["Preview launch · Episode 9"].waitForExistence(timeout: 10))
        app.buttons["Done"].tap()
        let progress = app.buttons["tracking-set-episode"]
        reveal(progress, in: app); XCTAssertTrue(progress.label.contains("8 / 26"))
        let expand = app.buttons["expand-synopsis"]
        reveal(expand, in: app); expand.tap(); XCTAssertEqual(expand.label, "Show less"); expand.tap()
        let dub = app.staticTexts["detail-dub-count"]
        reveal(dub, in: app)
        let count = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "26/26"), object: dub)
        XCTAssertEqual(XCTWaiter.wait(for: [count], timeout: 35), .completed)
        capture("Details-Dub-Counts-And-Schedule")
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCUIDevice.shared.orientation = .landscapeLeft
            reveal(watch, in: app, upward: false)
            XCTAssertGreaterThanOrEqual(watch.frame.minX, 0)
            XCTAssertLessThanOrEqual(watch.frame.maxX, app.frame.width)
            capture("Cinematic-Details-iPad-Landscape")
            XCUIDevice.shared.orientation = .portrait
        }
        reveal(cover, in: app, upward: false); cover.tap()
        XCTAssertTrue(app.buttons["Close enlarged image"].waitForExistence(timeout: 10)); app.buttons["Close enlarged image"].tap()
    }

    @MainActor
    func testAiringDetailsCountdownAndCaughtUpProgressRemainReadable() throws {
        let app = launchPreview(extra: ["--ui-detail-airing-preview"])
        app.buttons["library-entry-1"].tap()
        XCTAssertTrue(app.buttons["expand-anime-cover"].waitForExistence(timeout: 45))
        XCTAssertEqual(app.staticTexts["detail-release-status"].label, "Airing now")
        let countdown = app.descendants(matching: .any)["detail-countdown"]
        reveal(countdown, in: app)
        XCTAssertTrue(countdown.label.contains("Days"))
        XCTAssertTrue(countdown.label.contains("Seconds"))
        XCTAssertLessThanOrEqual(countdown.frame.maxX, app.frame.width)
        XCTAssertEqual(app.staticTexts["library-airing-status-1"].label, "Caught up")
        XCTAssertTrue(app.staticTexts["library-airing-progress-1"].label.contains("Watched Ep 8 · Aired Ep 8"))
        capture("Details-Airing-Countdown-And-Progress")
        app.tabBars.buttons["Schedule"].tap()
        XCTAssertTrue(app.staticTexts["schedule-airing-title"].isHittable)
        let entry = app.buttons["library-entry-1"]
        reveal(entry, in: app); entry.tap()
        XCTAssertTrue(app.buttons["expand-anime-cover"].waitForExistence(timeout: 45))
        let tags = app.descendants(matching: .any).matching(identifier: "detail-genres-1").firstMatch
        reveal(tags, in: app); tags.buttons["genre-1-Action"].tap()
        assertGenre("Action", in: app)
        app.tabBars.buttons["Schedule"].tap()
        XCTAssertTrue(app.staticTexts["schedule-airing-title"].isHittable, "Returning to Schedule must open the glanceable watchlist")
        XCTAssertTrue(app.segmentedControls["schedule-mode"].buttons["Airing Now"].isSelected)
    }

    @MainActor private func launchPreview(extra: [String] = []) -> XCUIApplication {
        continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-library-preview", "--ui-playback-preview", "--ui-reset-content-preferences"] + extra
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["My Library"].waitForExistence(timeout: 30))
        app.buttons["explore-dub-filter-toolbar"].tap()
        XCTAssertTrue(app.buttons["dub-filter-reset"].waitForExistence(timeout: 15))
        app.buttons["dub-filter-reset"].tap(); app.buttons["Done"].tap()
        app.tabBars.buttons["My Library"].tap()
        XCTAssertTrue(app.buttons["library-entry-1"].waitForExistence(timeout: 45))
        app.segmentedControls["library-layout"].buttons["List"].tap()
        return app
    }
    @MainActor private func assertGenre(_ name: String, in app: XCUIApplication) {
        XCTAssertTrue(app.navigationBars[name].waitForExistence(timeout: 15))
        XCTAssertTrue(app.tabBars.buttons["Explore"].isSelected)
        XCTAssertEqual(app.buttons["discovery-genre"].label, name)
        XCTAssertEqual(app.buttons["discovery-year"].label, "Year")
        XCTAssertEqual(app.buttons["discovery-season"].label, "Season")
        let search = app.textFields["discovery-search"]
        XCTAssertEqual(search.value as? String, search.placeholderValue)
    }
    @MainActor private func reveal(_ element: XCUIElement, in app: XCUIApplication, upward: Bool = true) {
        let scroll = app.scrollViews["anime-detail-scroll"].exists ? app.scrollViews["anime-detail-scroll"] : app
        for _ in 0..<16 { if element.isHittable { return }; if upward { scroll.swipeUp() } else { scroll.swipeDown() } }
        XCTAssertTrue(element.isHittable, "Could not reveal \(element.identifier)")
    }
    @MainActor private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "Design-\(UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone")-\(name)"
        attachment.lifetime = .keepAlways; add(attachment)
    }
}
