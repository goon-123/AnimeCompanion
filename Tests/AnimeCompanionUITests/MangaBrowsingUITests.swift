import XCTest

final class MangaBrowsingUITests: XCTestCase {
    @MainActor
    func testDelayedPagesAppendAndRepeatedPagePausesInsteadOfSpinning() {
        let app = launch(["--ui-manga-pagination"])
        openSource(app)
        reveal(app.buttons["manga-title-11"], in: app)
        XCTAssertTrue(app.buttons["manga-title-11"].exists, "Page 2 must actually append new covers")
        let paused = app.staticTexts["manga-catalog-stalled"]
        reveal(paused, in: app)
        XCTAssertFalse(app.progressIndicators["manga-catalog-loading"].exists)
        capture("Pagination-Paused", app)
        app.buttons["manga-catalog-next-page"].tap()
        reveal(app.buttons["manga-title-17"], in: app)
        reveal(app.staticTexts["manga-catalog-end"], in: app)
        XCTAssertFalse(paused.exists)
        XCTAssertFalse(app.buttons["manga-catalog-load-more"].exists)
        capture("Pagination-End", app)
    }
    @MainActor
    func testFailedNextPageKeepsCoversAndCanRetry() {
        let app = launch(["--ui-manga-pagination", "--ui-manga-pagination-error"])
        openSource(app)
        reveal(app.buttons["manga-catalog-retry"], in: app)
        XCTAssertTrue(app.buttons["manga-title-5"].exists)
        app.buttons["manga-catalog-retry"].tap()
        reveal(app.buttons["manga-title-11"], in: app)
        reveal(app.staticTexts["manga-catalog-end"], in: app)
        XCTAssertFalse(app.buttons["manga-catalog-retry"].exists)
    }
    @MainActor
    func testAnimeDetailsFromLibraryAndExploreOpenFreshEditableMangaSearch() {
        let app = launch()
        app.appTab("My Library").tap()
        let entry = app.buttons["library-entry-1"]
        app.revealInContent(entry); entry.tap()
        openMangaShortcut(app, expected: "Phase 2 tracked title")
        let field = app.textFields["manga-search-title"]
        let clear = app.buttons["manga-search-clear"]
        XCTAssertTrue(clear.waitForExistence(timeout: 10)); clear.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10))
        field.typeText("The Glass Harbor\n")
        XCTAssertEqual(field.value as? String, "The Glass Harbor")
        let source = app.buttons["manga-search-source-preview-en"]
        XCTAssertTrue(source.waitForExistence(timeout: 10)); source.tap()
        let result = app.buttons["manga-title-0"]
        XCTAssertTrue(result.waitForExistence(timeout: 15)); result.tap()
        XCTAssertTrue(app.buttons["manga-read"].waitForExistence(timeout: 10))

        // A second shortcut must replace the retained manga detail stack.
        app.appTab("Explore").tap()
        let explore = app.buttons["explore-shelf-entry-2"].firstMatch
        app.revealInContent(explore); explore.tap()
        openMangaShortcut(app, expected: "Phase 2 title 2")
        XCTAssertFalse(app.buttons["manga-read"].exists)
        capture("Anime-To-Manga-Search", app)
    }
    @MainActor
    func testRepositoryIconsAppearInSourcesAndExtensionInstallRows() {
        let app = launch()
        let iconID = "manga-icon-loaded-eu.kanade.tachiyomi.extension.en.webtoonpreview"
        XCTAssertTrue(app.images[iconID].firstMatch.waitForExistence(timeout: 15))
        capture("Source-Icon", app)
        app.buttons["manga-manage-extensions"].tap()
        let icon = app.images[iconID].firstMatch
        for _ in 0..<5 where !icon.isHittable { app.swipeUp() }
        XCTAssertTrue(icon.waitForExistence(timeout: 10))
        capture("Extension-Install-Icon", app)
    }
    @MainActor private func launch(_ extra: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-phase2-preview", "--ui-reset-content-preferences", "--ui-webtoon-preview", "--ui-webtoon-session", UUID().uuidString] + extra
        app.launch()
        XCTAssertTrue(app.buttons["explore-search"].waitForExistence(timeout: 15))
        app.appTab("Manga").tap()
        XCTAssertTrue(app.buttons["manga-source-preview-en"].waitForExistence(timeout: 15))
        return app
    }
    @MainActor private func openSource(_ app: XCUIApplication) {
        app.buttons["manga-source-preview-en"].tap()
        XCTAssertTrue(app.buttons["manga-title-0"].waitForExistence(timeout: 15))
    }
    @MainActor private func openMangaShortcut(_ app: XCUIApplication, expected: String) {
        app.openAnimeActions()
        let action = app.buttons["detail-find-manga"]
        app.revealInContent(action); action.tap()
        let field = app.textFields["manga-search-title"]
        XCTAssertTrue(field.waitForExistence(timeout: 15))
        XCTAssertEqual(field.value as? String, expected)
    }
    @MainActor private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        let catalog = app.scrollViews["manga-source-catalog"]
        for _ in 0..<12 {
            if element.exists && element.isHittable { return }
            catalog.swipeUp()
        }
        XCTAssertTrue(element.waitForExistence(timeout: 10))
        XCTAssertTrue(element.isHittable)
    }
    @MainActor private func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Manga-Browse-\(name)"; attachment.lifetime = .keepAlways; add(attachment)
    }
}
