import XCTest
import UIKit

final class PhaseOneReliabilityUITests: XCTestCase {
    @MainActor
    func testMalformedSourceTextIsCleanedAndOriginalTextIsAvailableOnDemand() throws {
        let app = openPlayback(extra: ["--ui-playback-malformed-source"])
        let source = app.buttons["playback-source-0"]
        XCTAssertTrue(source.label.contains("1080p · English audio"))
        XCTAssertTrue(source.label.contains("2.4 GB"))
        XCTAssertFalse(source.label.contains("invalid expression"))
        app.buttons["playback-source-info-0"].tap()
        XCTAssertTrue(app.navigationBars["Source information"].waitForExistence(timeout: 10))
        let original = app.descendants(matching: .any).matching(identifier: "playback-original-source-text").firstMatch
        XCTAssertTrue(original.waitForExistence(timeout: 10)); original.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "invalid expression")).firstMatch.waitForExistence(timeout: 10))
        capture("Source-Information")
        app.buttons["Done"].tap()
        XCTAssertTrue(source.waitForExistence(timeout: 10)); source.tap()
        XCTAssertTrue(app.staticTexts["Preview launch · Episode 9"].waitForExistence(timeout: 10))
    }
    @MainActor
    func testFailedSourceRefreshKeepsTheSelectedEpisodeAndPreviouslyLoadedSources() throws {
        let app = openPlayback(extra: ["--ui-playback-refresh-failure"])
        app.buttons["reload-playback-sources"].tap()
        let notice = app.staticTexts["The add-on could not be reached or timed out. Check your connection and try again."]
        XCTAssertTrue(notice.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["playback-source-0"].exists)
        XCTAssertEqual(app.textFields["playback-episode-number"].value as? String, "9")
        XCTAssertFalse(app.staticTexts["playback-empty-results"].exists)
        let source = app.buttons["playback-source-0"]
        for _ in 0..<6 where !source.isHittable { app.swipeUp() }
        XCTAssertTrue(source.isHittable); source.tap()
        XCTAssertTrue(app.staticTexts["Preview launch · Episode 9"].waitForExistence(timeout: 10))
        capture("Sources-Preserved-After-Failed-Refresh")
    }
    @MainActor
    func testVidHubReturnSavesResumeOnlyForTheLaunchedEpisode() throws {
        let app = openPlayback(extra: ["--ui-playback-return-preview"])
        app.buttons["playback-source-0"].tap()
        XCTAssertTrue(app.staticTexts["Resume at 2:05"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["playback-anilist-progress"].label.contains("8 episodes watched"), "A player return must not change AniList progress")
        let episode = app.textFields["playback-episode-number"]
        episode.tap(); episode.typeText(XCUIKeyboardKey.delete.rawValue + "10")
        app.buttons["playback-episode-go"].tap()
        let source = app.buttons["playback-source-0"]
        let updated = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "anilist:1:10.json"), object: source)
        XCTAssertEqual(XCTWaiter.wait(for: [updated], timeout: 15), .completed)
        XCTAssertFalse(app.staticTexts["Resume at 2:05"].exists)
        capture("Callback-Progress-Isolated-By-Episode")
    }
    @MainActor
    func testDubFilterFindsAMatchBeyondTheFirstFourPages() throws {
        let app = openFilteredDiscovery(search: "deep")
        XCTAssertTrue(app.buttons["discovery-entry-990206"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.staticTexts["No matching titles"].exists)
        XCTAssertFalse(app.buttons["discovery-more"].exists)
        capture("Dub-Match-Beyond-Early-Pages")
    }
    @MainActor
    func testPartialFilteredScanExplainsCoverageAndCanContinueToCatalogEnd() throws {
        let app = openFilteredDiscovery(search: "empty")
        // This fixture excludes the only dubbed title from every page of this search.
        XCTAssertTrue(app.staticTexts["No matches yet"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["discovery-partial-results"].exists)
        XCTAssertFalse(app.staticTexts["No matching titles"].exists)
        let more = app.buttons["discovery-more"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: more)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 20), .completed)
        for _ in 0..<5 where !more.isHittable { app.swipeUp() }
        XCTAssertTrue(more.isHittable); more.tap()
        XCTAssertTrue(app.staticTexts["No matching titles"].waitForExistence(timeout: 20))
        XCTAssertFalse(more.exists)
        capture("Filtered-Catalog-Fully-Checked")
    }
    @MainActor
    private func openFilteredDiscovery(search: String) -> XCUIApplication {
        continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-discovery-preview", "--ui-reset-content-preferences"]
        app.launch()
        XCTAssertTrue(app.buttons["explore-dub-filter-toolbar"].waitForExistence(timeout: 20))
        app.buttons["explore-dub-filter-toolbar"].tap()
        XCTAssertTrue(app.buttons["dub-filter-reset"].waitForExistence(timeout: 10)); app.buttons["dub-filter-reset"].tap()
        app.buttons["dub-filter-available"].tap(); app.buttons["Done"].tap()
        app.buttons["explore-search"].tap()
        let field = app.textFields["discovery-search"]
        XCTAssertTrue(field.waitForExistence(timeout: 10)); field.tap(); field.typeText(search + "\n")
        return app
    }
    @MainActor
    private func openPlayback(extra: [String]) -> XCUIApplication {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-library-preview", "--ui-playback-preview", "--ui-reset-content-preferences"] + extra
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["My Library"].waitForExistence(timeout: 30)); app.tabBars.buttons["My Library"].tap()
        let watch = app.buttons["library-watch-1"]
        XCTAssertTrue(watch.waitForExistence(timeout: 45))
        for _ in 0..<10 where !watch.isHittable { app.swipeUp() }
        XCTAssertTrue(watch.isHittable); watch.tap()
        XCTAssertTrue(app.buttons["playback-source-0"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.textFields["playback-episode-number"].value as? String, "9")
        return app
    }
    @MainActor private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "Phase-1-\(UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone")-\(name)"
        attachment.lifetime = .keepAlways; add(attachment)
    }
}
