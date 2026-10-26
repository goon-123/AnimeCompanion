import XCTest
import UIKit

final class LibraryCustomizationUITests: XCTestCase {
    @MainActor private func launch(failedPage: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-reset-content-preferences", "--ui-phase2-preview", "--ui-customization-preview",
            "--ui-webtoon-preview", "--ui-webtoon-session", UUID().uuidString]
        if failedPage { app.launchArguments.append("--ui-webtoon-failed-page") }
        app.launch()
        XCTAssertTrue(app.appTab("My Library").waitForExistence(timeout: 20))
        return app
    }
    @MainActor private func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
    @MainActor private func tapWhenVisible(_ item: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<10 {
            if item.exists && item.isHittable { break }
            // Settings is a centered sheet on iPad. Swiping the whole app can
            // miss the sheet entirely, and offscreen Form rows are virtualized.
            if app.collectionViews.count > 0 { app.collectionViews.element(boundBy: app.collectionViews.count - 1).swipeUp() }
            else { app.swipeUp() }
        }
        XCTAssertTrue(item.waitForExistence(timeout: 5)); XCTAssertTrue(item.isHittable)
        if item.elementType == .switch {
            let oldValue = item.value as? String
            // SwiftUI exposes a row-sized accessibility Switch containing the
            // actual UISwitch. A trailing row coordinate can hit the reorder
            // handle instead, so use the innermost native control's bounds.
            let control = item.descendants(matching: .switch).allElementsBoundByIndex.last ?? item
            control.tap()
            if item.value as? String == oldValue {
                capture("Unchanged-Switch-" + item.identifier, app)
                let hierarchy = XCTAttachment(string: app.debugDescription)
                hierarchy.name = "Unchanged switch hierarchy"; hierarchy.lifetime = .keepAlways; add(hierarchy)
            }
        }
        else { item.tap() }
    }
    @MainActor func testCombinedGridCoverLayoutAndSourceSearchWithMangaTabHidden() {
        let app = launch()
        XCTAssertFalse(app.appTab("Manga").exists)
        app.appTab("My Library").tap()
        let picker = app.segmentedControls["library-media-picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 15))
        XCTAssertTrue(picker.buttons["All"].isSelected)
        let search = app.textFields["combined-library-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 15))
        capture("Combined-Library-Grid", app)
        search.tap(); search.typeText("Archivist\n")
        let entry = app.buttons["combined-entry-mangabaka:73"]
        tapWhenVisible(entry, in: app)
        let cover = app.buttons["mangabaka-series-cover"], title = app.staticTexts["mangabaka-series-title"]
        XCTAssertTrue(cover.waitForExistence(timeout: 15)); XCTAssertTrue(title.waitForExistence(timeout: 15))
        XCTAssertGreaterThanOrEqual(cover.frame.width, 180)
        if app.frame.width < 650 {
            XCTAssertEqual(cover.frame.midX, app.frame.midX, accuracy: 8)
            XCTAssertGreaterThanOrEqual(title.frame.minY, cover.frame.maxY)
        } else { XCTAssertGreaterThan(title.frame.minX, cover.frame.maxX) }
        capture("Series-Centered-Cover", app)
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCUIDevice.shared.orientation = .landscapeLeft
            XCTAssertTrue(cover.waitForExistence(timeout: 10)); capture("Series-Wide-Cover", app)
            XCUIDevice.shared.orientation = .portrait
        }
        let source = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Find a reading source")).firstMatch
        tapWhenVisible(source, in: app)
        XCTAssertTrue(app.textFields["manga-search-title"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.appTab("Manga").exists, "A source handoff must keep the Manga tab hidden")
        capture("Reading-Source-Without-Manga-Tab", app)
    }
    @MainActor func testReadingGridListAndTabChangesPersistWithoutDismissingSettingsEarly() {
        let app = launch()
        app.appTab("My Library").tap()
        let media = app.segmentedControls["library-media-picker"]
        XCTAssertTrue(media.waitForExistence(timeout: 15)); media.buttons["Manga & Novels"].tap()
        let layout = app.segmentedControls["reading-library-layout"]
        XCTAssertTrue(layout.waitForExistence(timeout: 15)); layout.buttons.element(boundBy: 0).tap()
        capture("Reading-Library-Grid", app)
        layout.buttons.element(boundBy: 1).tap(); capture("Reading-Library-List", app)
        app.buttons["Account and settings"].tap()
        tapWhenVisible(app.buttons["settings-bottom-tabs"], in: app)
        let manga = app.switches["tab-visible-manga"], library = app.switches["tab-visible-library"]
        XCTAssertTrue(manga.waitForExistence(timeout: 10))
        tapWhenVisible(manga, in: app); XCTAssertEqual(manga.value as? String, "1")
        tapWhenVisible(library, in: app); XCTAssertEqual(library.value as? String, "0")
        XCTAssertTrue(app.navigationBars["Bottom tabs"].exists, "Editing visibility must not tear down the Settings sheet")
        capture("Customize-Bottom-Tabs", app)
        app.navigationBars["Bottom tabs"].buttons["Settings"].tap()
        app.navigationBars["Settings"].buttons["Done"].tap()
        XCTAssertTrue(app.appTab("Manga").waitForExistence(timeout: 15)); XCTAssertFalse(app.appTab("My Library").exists)
        app.terminate()
        app.launchArguments.removeAll { $0 == "--ui-reset-content-preferences" }
        app.launch()
        XCTAssertTrue(app.appTab("Manga").waitForExistence(timeout: 20)); XCTAssertFalse(app.appTab("My Library").exists)
        capture("Saved-Tab-Visibility", app)
    }
    @MainActor private func openReader(_ app: XCUIApplication) -> XCUIElement {
        // Reveal the source hub using the same user-facing setting. Sources and
        // their saved data remain present even when their tab starts hidden.
        app.buttons["account-switcher"].tap()
        tapWhenVisible(app.buttons["account-app-settings"], in: app)
        tapWhenVisible(app.buttons["settings-bottom-tabs"], in: app)
        tapWhenVisible(app.switches["tab-visible-manga"], in: app)
        XCTAssertEqual(app.switches["tab-visible-manga"].value as? String, "1")
        app.navigationBars["Bottom tabs"].buttons["Settings"].tap()
        app.navigationBars["Settings"].buttons["Done"].tap()
        XCTAssertTrue(app.appTab("Manga").waitForExistence(timeout: 15), "Apply the saved tabs after Settings finishes dismissing")
        app.appTab("Manga").tap()
        tapWhenVisible(app.buttons["manga-source-preview-en"], in: app)
        tapWhenVisible(app.buttons["manga-title-0"], in: app)
        tapWhenVisible(app.buttons["manga-read"], in: app)
        XCTAssertTrue(app.images["webtoon-page-image-0"].waitForExistence(timeout: 20))
        return app.scrollViews["webtoon-canvas"]
    }
    @MainActor private func chapter(_ canvas: XCUIElement) -> String { canvas.value as? String ?? "" }
    @MainActor func testReachingChapterEndLoadsNextWithoutTappingAndCanBeDisabled() {
        let app = launch(), canvas = openReader(app)
        XCTAssertTrue(chapter(canvas).hasSuffix("/chapter/1"))
        for _ in 0..<14 {
            if chapter(canvas).hasSuffix("/chapter/2") { break }
            canvas.swipeUp(velocity: .slow)
        }
        let advanced = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in (canvas.value as? String ?? "").hasSuffix("/chapter/2") }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [advanced], timeout: 15), .completed)
        capture("Automatically-Loaded-Chapter-2", app)
        if !app.buttons["webtoon-settings"].exists { canvas.tap() }
        XCTAssertTrue(app.buttons["webtoon-settings"].waitForExistence(timeout: 5))
        app.buttons["webtoon-settings"].tap()
        let automatic = app.switches["webtoon-auto-next"]
        tapWhenVisible(automatic, in: app)
        XCTAssertEqual(automatic.value as? String, "0")
        app.navigationBars["Webtoon reader"].buttons["Done"].tap()
        for _ in 0..<10 { canvas.swipeUp(velocity: .slow) }
        XCTAssertTrue(chapter(canvas).hasSuffix("/chapter/2"), "Turning automatic loading off must leave the next chapter manual")
        capture("Manual-Chapter-Option", app)
    }
    @MainActor func testMissingImagePreventsAutomaticAdvanceUntilRetried() {
        let app = launch(failedPage: true), canvas = openReader(app)
        for _ in 0..<7 { canvas.swipeUp(velocity: .slow) }
        XCTAssertTrue(chapter(canvas).hasSuffix("/chapter/1"))
        for _ in 0..<7 {
            if app.buttons["webtoon-retry-1"].isHittable { break }
            canvas.swipeDown(velocity: .slow)
        }
        tapWhenVisible(app.buttons["webtoon-retry-1"], in: app)
        for _ in 0..<14 {
            if chapter(canvas).hasSuffix("/chapter/2") { break }
            canvas.swipeUp(velocity: .slow)
        }
        let advanced = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in (canvas.value as? String ?? "").hasSuffix("/chapter/2") }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [advanced], timeout: 15), .completed)
        capture("Retry-Then-Automatic-Chapter", app)
    }
}
