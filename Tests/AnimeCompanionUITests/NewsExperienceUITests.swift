import XCTest
import UIKit

final class NewsExperienceUITests: XCTestCase {
    @MainActor func testBookmarksAndPreferencesSurviveRelaunchAndPublisherChanges() {
        var app = launch()
        waitForCount(7, app)
        let save = app.buttons["news-save-harbor-dub"]
        app.revealInContent(save); save.tap()
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
        app.revealInContent(remove)
        XCTAssertEqual(remove.label, "Remove saved story")
        openPreferences(app)
        let persisted = app.switches["news-compact-layout"]
        app.revealInContent(persisted)
        XCTAssertEqual(persisted.value as? String, "1")
        let disabled = app.switches["news-enable-animeNewsNetwork"]
        app.revealInContent(disabled, upward: false)
        XCTAssertEqual(disabled.value as? String, "0")
        app.buttons["news-preferences-done"].tap()
        app.revealInContent(remove); remove.tap()
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
        app.revealInContent(followed)
        XCTAssertTrue(followed.exists)
        capture("For-You", app)
        select("Latest", app)
        let dubs = app.buttons["news-topic-dubs"]
        app.revealInContent(dubs, upward: false); dubs.tap()
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
        app.revealInContent(result)
        XCTAssertTrue(result.exists)
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCUIDevice.shared.orientation = .landscapeLeft
            waitForCount(1, app)
            let content = app.scrollViews["news-list"]
            XCTAssertGreaterThan(content.frame.width, 900)
        }
        capture("Search", app)
        XCUIDevice.shared.orientation = .portrait
    }
    @MainActor func testReadFilteringHistoryAndPartialPublisherFailure() {
        let app = launch(partial: true)
        waitForCount(5, app)
        let options = app.buttons["news-options-harbor-dub"]
        app.revealInContent(options); options.tap()
        app.buttons["Mark as read"].tap()
        let filter = app.buttons["news-sources"]
        app.revealInContent(filter, upward: false); filter.tap()
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
        app.revealInContent(status, upward: false)
        XCTAssertTrue(status.label.contains("Anime Corner") || app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Anime Corner")).count > 0)
        capture("Partial-Feed", app)
    }
    @MainActor private func launch(keep: Bool = false, partial: Bool = false) -> XCUIApplication {
        continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-phase2-preview", "--ui-reset-content-preferences", "--ui-catalog-loading-preview", "--ui-news-preview"]
        if keep { app.launchArguments.append("--ui-news-keep-state") }
        if partial { app.launchArguments.append("--ui-news-partial") }
        app.launch()
        XCTAssertTrue(app.buttons["explore-search"].waitForExistence(timeout: 20))
        app.appTab("News").tap()
        XCTAssertTrue(app.segmentedControls["news-collections"].waitForExistence(timeout: 15))
        return app
    }
    @MainActor private func select(_ title: String, _ app: XCUIApplication) {
        let control = app.segmentedControls["news-collections"]
        app.revealInContent(control, upward: false)
        control.buttons[title].tap()
    }
    @MainActor private func openPreferences(_ app: XCUIApplication) {
        let button = app.buttons["news-customize"]
        app.revealInContent(button, upward: false)
        button.tap()
        XCTAssertTrue(app.navigationBars["Customize News"].waitForExistence(timeout: 10))
    }
    @MainActor private func toggle(_ row: XCUIElement, to value: String, _ app: XCUIApplication) {
        app.revealInContent(row)
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
        // A frame-width assertion can finish while UIKit is still rotating its
        // screenshot surface. Require the captured pixels to match the window.
        let landscape = app.frame.width > app.frame.height
        let deadline = Date().addingTimeInterval(5)
        var screenshot = app.screenshot()
        while (screenshot.image.size.width > screenshot.image.size.height) != landscape && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            screenshot = app.screenshot()
        }
        XCTAssertEqual(screenshot.image.size.width > screenshot.image.size.height, landscape)
        let shot = XCTAttachment(screenshot: screenshot)
        shot.name = "News-\(UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone")-\(title)"
        shot.lifetime = .keepAlways; add(shot)
    }
}
