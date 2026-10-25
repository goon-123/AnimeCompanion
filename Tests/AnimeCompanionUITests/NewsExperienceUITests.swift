import XCTest
import UIKit

final class NewsExperienceUITests: XCTestCase {
    @MainActor func testSeriesHeadlinesFindBaseTitleAndArchiveAndPreserveBookmarks() {
        let app = launch(series: true)
        waitForCount(7, app)
        let markRead = app.buttons["news-options-moonlit-season"]
        reveal(markRead, in: app); markRead.tap(); app.buttons["Mark as read"].tap()
        let filters = app.buttons["news-sources"]
        reveal(filters, in: app, upward: false); filters.tap(); app.buttons["news-unread-only"].tap()
        waitForCount(5, app)
        app.appTab("My Library").tap()
        let entry = app.buttons["library-entry-1"]
        app.revealInContent(entry); entry.tap()
        let headlines = app.buttons["detail-open-headlines"]
        app.revealInContent(headlines); headlines.tap()
        XCTAssertTrue(app.navigationBars["Headlines"].waitForExistence(timeout: 10))
        waitForCount(3, app)
        let archive = app.buttons["news-save-relay-archive-0"]
        reveal(archive, in: app); archive.tap()
        let saved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Remove saved story"), object: archive)
        XCTAssertEqual(XCTWaiter.wait(for: [saved], timeout: 5), .completed)
        capture("Series-Season-And-Archive", app)
        app.appTab("News").tap()
        select("Saved", app); waitForCount(1, app)
        XCTAssertTrue(app.buttons["news-story-relay-archive-0"].exists)
    }
    @MainActor func testBookmarksAndPreferencesSurviveRelaunchAndPublisherChanges() {
        var app = launch()
        waitForCount(7, app)
        let save = app.buttons["news-save-harbor-dub"]
        reveal(save, in: app); save.tap()
        // A scaled hero image must not intercept its sibling bookmark button.
        let saved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Remove saved story"), object: save)
        XCTAssertEqual(XCTWaiter.wait(for: [saved], timeout: 5), .completed)
        select("Saved", app)
        waitForCount(1, app)
        XCTAssertTrue(app.buttons["news-story-harbor-dub"].exists)
        capture("Saved", app)

        openPreferences(app)
        let publisher = app.switches["news-enable-animeNewsNetwork"]
        toggle(publisher, to: "0", app)
        let compact = app.switches["news-compact-layout"]
        toggle(compact, to: "1", app)
        app.buttons["news-preferences-done"].tap()
        waitForCount(1, app)
        XCTAssertTrue(app.buttons["news-story-harbor-dub"].exists)
        app.terminate()
        app = launch(keep: true)
        select("Saved", app); waitForCount(1, app)
        let remove = app.buttons["news-save-harbor-dub"]
        reveal(remove, in: app)
        XCTAssertEqual(remove.label, "Remove saved story")
        openPreferences(app)
        let persisted = app.switches["news-compact-layout"]
        reveal(persisted, in: app)
        XCTAssertEqual(persisted.value as? String, "1")
        let disabled = app.switches["news-enable-animeNewsNetwork"]
        reveal(disabled, in: app, upward: false)
        XCTAssertEqual(disabled.value as? String, "0")
        app.buttons["news-preferences-done"].tap()
        reveal(remove, in: app); remove.tap()
        waitForCount(0, app)
        XCTAssertTrue(app.staticTexts["Keep a story for later"].exists)
    }
    @MainActor func testTopicsSearchPersonalizationAndTabletRotation() {
        let app = launch()
        waitForCount(7, app)
        capture("Latest", app)
        select("For You", app)
        waitForCount(2, app)
        let followed = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "In your library")).firstMatch
        reveal(followed, in: app)
        XCTAssertTrue(followed.exists)
        capture("For-You", app)
        select("Latest", app)
        let dubs = app.buttons["news-topic-dubs"]
        reveal(dubs, in: app, upward: false); dubs.tap()
        waitForCount(2, app)
        app.buttons["news-reset-filters"].tap()
        waitForCount(7, app)
        let search = app.searchFields.firstMatch
        if !search.isHittable {
            let searchButton = app.navigationBars.buttons["Search"]
            if searchButton.exists { searchButton.tap() }
            else { app.scrollViews["news-list"].swipeDown() }
        }
        XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("Paper")
        waitForCount(1, app)
        let submit = app.keyboards.buttons.matching(NSPredicate(format: "label ==[c] %@", "search")).firstMatch
        if submit.exists { submit.tap() }
        let result = app.buttons["news-story-lantern-manga"]
        reveal(result, in: app)
        XCTAssertTrue(result.exists)
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCUIDevice.shared.orientation = .landscapeLeft
            waitForCount(1, app)
            let content = app.scrollViews["news-list"]
            XCTAssertGreaterThan(content.frame.width, 900)
            let settleAfter = Date().addingTimeInterval(0.8)
            let fitted = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                guard Date() >= settleAfter else { return false }
                let window = app.frame, story = result.frame
                return window.width > window.height && story.minX >= window.minX - 1 && story.maxX <= window.maxX + 1
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [fitted], timeout: 10), .completed)
            reveal(result, in: app)
            XCTAssertTrue(result.isHittable)
        }
        capture("Search", app)
        XCUIDevice.shared.orientation = .portrait
    }
    @MainActor func testReadFilteringHistoryAndPartialPublisherFailure() {
        let app = launch(partial: true)
        waitForCount(5, app)
        let options = app.buttons["news-options-harbor-dub"]
        reveal(options, in: app); options.tap()
        app.buttons["Mark as read"].tap()
        let filter = app.buttons["news-sources"]
        reveal(filter, in: app, upward: false); filter.tap()
        app.buttons["news-unread-only"].tap()
        waitForCount(3, app) // The owned history fixture is also migrated as read.
        select("History", app)
        waitForCount(1, app)
        XCTAssertTrue(app.buttons["news-story-night-panel"].exists)
        capture("History", app)
        select("Latest", app)
        app.buttons["news-reset-filters"].tap()
        waitForCount(5, app)
        let status = app.descendants(matching: .any).matching(identifier: "news-feed-status").firstMatch
        reveal(status, in: app, upward: false)
        XCTAssertTrue(status.label.contains("Anime Corner") || app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Anime Corner")).count > 0)
        capture("Partial-Feed", app)
    }
    @MainActor private func reveal(_ item: XCUIElement, in app: XCUIApplication, upward: Bool = true) {
        // These journeys only use the News feed and its own preferences form.
        // Target that surface directly instead of scanning unrelated app sheets
        // or requiring a container (rather than its button) to be tappable.
        for _ in 0..<8 {
            if item.exists && item.isHittable { return }
            let preferences = app.navigationBars["Customize News"].exists
            let scroll = preferences ? app.collectionViews.firstMatch : app.scrollViews["news-list"]
            let surface: XCUIElement = scroll.exists ? scroll : app
            let bounds = surface.frame
            let backwards = item.exists && item.frame.height > 0 ? item.frame.midY < bounds.midY : !upward
            let start = surface.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: backwards ? 0.35 : 0.75))
            let end = surface.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: backwards ? 0.70 : 0.40))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.05)
        }
        XCTAssertTrue(item.isHittable, "Could not reveal \(item.identifier)")
    }
    @MainActor private func launch(keep: Bool = false, partial: Bool = false, series: Bool = false) -> XCUIApplication {
        continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-phase2-preview", "--ui-reset-content-preferences", "--ui-catalog-loading-preview", "--ui-news-preview"]
        if keep { app.launchArguments.append("--ui-news-keep-state") }
        if partial { app.launchArguments.append("--ui-news-partial") }
        if series { app.launchArguments.append("--ui-news-series-preview") }
        app.launch()
        XCTAssertTrue(app.buttons["explore-search"].waitForExistence(timeout: 20))
        app.appTab("News").tap()
        XCTAssertTrue(app.segmentedControls["news-collections"].waitForExistence(timeout: 15))
        return app
    }
    @MainActor private func select(_ title: String, _ app: XCUIApplication) {
        let button = app.segmentedControls["news-collections"].buttons[title]
        reveal(button, in: app, upward: false)
        button.tap()
    }
    @MainActor private func openPreferences(_ app: XCUIApplication) {
        let button = app.buttons["news-customize"]
        reveal(button, in: app, upward: false)
        button.tap()
        XCTAssertTrue(app.navigationBars["Customize News"].waitForExistence(timeout: 10))
    }
    @MainActor private func toggle(_ row: XCUIElement, to value: String, _ app: XCUIApplication) {
        reveal(row, in: app)
        let control = row.descendants(matching: .switch).allElementsBoundByIndex.last ?? row
        control.tap()
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: row)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)
    }
    @MainActor private func waitForCount(_ count: Int, _ app: XCUIApplication) {
        let result = app.staticTexts["news-results-count"]
        let expected = "\(count) \(count == 1 ? "story" : "stories")"
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND label BEGINSWITH %@", expected), object: result)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 20), .completed)
    }
    @MainActor private func capture(_ title: String, _ app: XCUIApplication) {
        // Capture the actual display after the window-fit check. Cropped app
        // screenshots can retain portrait coordinates after iPad rotation.
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "News-\(UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone")-\(title)"
        shot.lifetime = .keepAlways; add(shot)
    }
}
