import XCTest

final class WebtoonReaderUITests: XCTestCase {
    @MainActor
    func testClearingHistoryRequiresConfirmationAndKeepsSavedMangaAndProgress() {
        let app = launch()
        openFirstTitle(app)
        app.buttons["manga-save-title"].tap()
        app.buttons["manga-read"].tap()
        XCTAssertTrue(app.images["webtoon-page-image-0"].waitForExistence(timeout: 20))
        app.scrollViews["webtoon-canvas"].swipeUp()
        showControls(app); app.buttons["webtoon-close"].tap()
        let progress = app.staticTexts["manga-reading-progress"]
        XCTAssertTrue(progress.waitForExistence(timeout: 10))
        let savedProgress = progress.label
        app.terminate(); app.launch(); app.appTab("Manga").tap()
        let sections = app.segmentedControls["manga-hub-sections"]
        XCTAssertTrue(sections.waitForExistence(timeout: 15)); sections.buttons["History"].tap()
        let clear = app.buttons["manga-clear-history"]
        XCTAssertTrue(clear.waitForExistence(timeout: 10)); XCTAssertTrue(clear.isEnabled)
        clear.tap()
        if app.buttons["Cancel"].exists { app.buttons["Cancel"].tap() }
        else {
            // iPad action popovers omit Cancel and dismiss on an outside tap.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.18)).tap()
        }
        XCTAssertTrue(clear.isEnabled, "Cancel must keep history")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "The Glass Harbor")).firstMatch.exists,
                      "Dismissal must keep the history entry")
        clear.tap(); app.buttons["Clear history"].tap()
        XCTAssertTrue(app.staticTexts["No reading history yet"].waitForExistence(timeout: 10))
        XCTAssertFalse(clear.isEnabled)
        capture("Cleared-History", app)
        app.terminate(); app.launch(); app.appTab("Manga").tap()
        XCTAssertTrue(sections.waitForExistence(timeout: 15)); sections.buttons["History"].tap()
        XCTAssertTrue(app.staticTexts["No reading history yet"].waitForExistence(timeout: 10))
        sections.buttons["Library"].tap()
        let saved = app.buttons["manga-saved-title-0"]
        XCTAssertTrue(saved.waitForExistence(timeout: 10)); saved.tap()
        XCTAssertTrue(progress.waitForExistence(timeout: 10)); XCTAssertEqual(progress.label, savedProgress)
        XCTAssertTrue(app.buttons["manga-save-title"].label.contains("In library"))
        capture("Cleared-History-Keeps-Progress", app)
    }
    @MainActor
    func testHoldScrollingStopsOnReleaseAndSpeedCanBeChanged() {
        let app = launch()
        openFirstTitle(app)
        app.buttons["manga-read"].tap()
        let image = app.images["webtoon-page-image-0"]
        XCTAssertTrue(image.waitForExistence(timeout: 20))
        let canvas = app.scrollViews["webtoon-canvas"]
        app.buttons["webtoon-scroll-slower"].tap()
        app.buttons["webtoon-scroll-slower"].tap()
        XCTAssertEqual(app.buttons["webtoon-scroll-speed"].value as? String, "15 points per second")
        let initial = image.frame.minY
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).press(forDuration: 2.4)
        let slowDistance = initial - image.frame.minY
        XCTAssertGreaterThan(slowDistance, 8, "Holding a page must scroll it")
        let released = image.frame.minY
        let stopped = expectation(description: "Releasing the hold stops motion")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            XCTAssertEqual(image.frame.minY, released, accuracy: 3)
            stopped.fulfill()
        }
        wait(for: [stopped], timeout: 3)
        showControls(app)
        for _ in 0..<7 { app.buttons["webtoon-scroll-faster"].tap() }
        XCTAssertEqual(app.buttons["webtoon-scroll-speed"].value as? String, "120 points per second")
        let beforeFast = image.frame.minY
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).press(forDuration: 2.4)
        XCTAssertGreaterThan(beforeFast - image.frame.minY, slowDistance * 2)
        showControls(app)
        app.buttons["webtoon-settings"].tap()
        XCTAssertTrue(app.switches["webtoon-hold-to-scroll"].waitForExistence(timeout: 10))
        if !app.switches["webtoon-hold-to-scroll"].isHittable { app.swipeUp() }
        app.switches["webtoon-hold-to-scroll"].coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        app.navigationBars["Webtoon reader"].buttons["Done"].tap()
        let disabled = image.frame.minY
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).press(forDuration: 1.4)
        XCTAssertEqual(image.frame.minY, disabled, accuracy: 3)
        capture("Hold-Scroll-Controls", app)
    }
    @MainActor
    func testChapterRuntimeErrorIdentifiesSourceAndCanRetry() {
        let app = launch(chapterFailure: true)
        openFirstTitle(app)
        app.buttons["manga-read"].tap()
        let source = app.staticTexts["webtoon-error-source"]
        XCTAssertTrue(source.waitForExistence(timeout: 15))
        XCTAssertEqual(source.label, "Glass House")
        let detail = app.staticTexts["webtoon-error-description"]
        XCTAssertTrue(detail.label.contains("kotlin.text.MatchGroupCollection"))
        XCTAssertTrue(app.buttons["webtoon-source-website"].exists)
        capture("Reader-Runtime-Error", app)
        app.buttons["Try again"].tap()
        XCTAssertTrue(app.images["webtoon-page-image-0"].waitForExistence(timeout: 20))
    }
    @MainActor
    func testSourceSettingsSaveCancelResetAndRelaunch() {
        let app = launch()
        let source = app.buttons["manga-source-preview-en"]
        XCTAssertTrue(source.waitForExistence(timeout: 15)); source.tap()
        openSourceSettings(app)
        app.buttons["source-setting-quality"].tap()
        let high = app.buttons["source-choice-high"]
        XCTAssertTrue(high.waitForExistence(timeout: 10)); high.tap()
        XCTAssertTrue(app.buttons["source-setting-quality"].label.contains("High"))
        let split = app.switches["source-setting-split"]
        XCTAssertTrue(split.waitForExistence(timeout: 10))
        split.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertEqual(split.value as? String, "1")
        capture("Source-Settings", app)
        app.buttons["source-settings-save"].tap()
        XCTAssertTrue(app.buttons["manga-title-0"].waitForExistence(timeout: 15))
        openSourceSettings(app)
        XCTAssertTrue(app.buttons["source-setting-quality"].label.contains("High"))
        XCTAssertEqual(app.switches["source-setting-split"].value as? String, "1")
        resetSourceSettings(app)
        app.buttons["source-settings-cancel"].tap()
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["explore-search"].waitForExistence(timeout: 15))
        app.appTab("Manga").tap()
        XCTAssertTrue(source.waitForExistence(timeout: 15)); source.tap()
        openSourceSettings(app)
        XCTAssertTrue(app.buttons["source-setting-quality"].label.contains("High"))
        XCTAssertEqual(app.switches["source-setting-split"].value as? String, "1")
        resetSourceSettings(app)
        app.buttons["source-settings-save"].tap()
        openSourceSettings(app)
        XCTAssertTrue(app.buttons["source-setting-quality"].label.contains("Standard"))
        XCTAssertEqual(app.switches["source-setting-split"].value as? String, "0")
    }
    @MainActor
    func testCoverLibraryAndLongStripPositionSurviveRelaunch() {
        let app = launch()
        openFirstTitle(app)
        app.buttons["manga-save-title"].tap()
        app.buttons["manga-read"].tap()
        let image = app.images["webtoon-page-image-0"]
        XCTAssertTrue(image.waitForExistence(timeout: 20))
        capture("Reader-Initial", app)
        let original = image.frame.minY
        let canvas = app.scrollViews["webtoon-canvas"]
        canvas.swipeUp()
        let scrolled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in image.frame.minY < original - 100 }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [scrolled], timeout: 10), .completed)
        let expected = image.frame.minY
        showControls(app)
        app.buttons["webtoon-close"].tap()
        XCTAssertTrue(app.staticTexts["manga-reading-progress"].waitForExistence(timeout: 10))
        app.terminate(); app.launch()
        app.appTab("Manga").tap()
        let saved = app.buttons["manga-saved-title-0"]
        XCTAssertTrue(saved.waitForExistence(timeout: 15)); saved.tap()
        XCTAssertTrue(app.buttons["manga-read"].waitForExistence(timeout: 15)); app.buttons["manga-read"].tap()
        XCTAssertTrue(image.waitForExistence(timeout: 20))
        let restored = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            abs(image.frame.minY - expected) < 130 && image.frame.minY < original - 50
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 15), .completed)
        capture("Reader-Restored-Strip-Position", app)
    }
    @MainActor
    func testFailedPageCanRetryAndReaderSettingsAndChapterPickerWork() {
        let app = launch(failure: true)
        openFirstTitle(app)
        app.buttons["manga-read"].tap()
        XCTAssertTrue(app.images["webtoon-page-image-0"].waitForExistence(timeout: 20))
        app.sliders["webtoon-page-scrubber"].adjust(toNormalizedSliderPosition: 5.0 / 7)
        let retry = app.buttons["webtoon-retry-5"]
        XCTAssertTrue(retry.waitForExistence(timeout: 15)); retry.tap()
        XCTAssertTrue(app.images["webtoon-page-image-5"].waitForExistence(timeout: 20))
        let counter = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "6 / 8"),
            object: app.staticTexts["webtoon-page-counter"])
        XCTAssertEqual(XCTWaiter.wait(for: [counter], timeout: 5), .completed)
        showControls(app)
        app.buttons["webtoon-settings"].tap()
        let padding = app.sliders["webtoon-side-padding"]
        XCTAssertTrue(padding.waitForExistence(timeout: 10)); padding.adjust(toNormalizedSliderPosition: 0.4)
        capture("Reader-Settings", app)
        app.navigationBars["Webtoon reader"].buttons["Done"].tap()
        app.buttons["webtoon-chapters"].tap()
        let chapter = app.buttons["webtoon-choose-chapter-1"]
        XCTAssertTrue(chapter.waitForExistence(timeout: 10)); chapter.tap()
        XCTAssertTrue(app.images["webtoon-page-image-0"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["webtoon-chapters"].label.contains("Chapter 2"))
        capture("Reader-Next-Chapter", app)
    }
    @MainActor
    func testFailedTargetDoesNotReplaceLastReadablePosition() {
        let app = launch(failure: true)
        openFirstTitle(app)
        app.buttons["manga-read"].tap()
        XCTAssertTrue(app.images["webtoon-page-image-0"].waitForExistence(timeout: 20))
        app.sliders["webtoon-page-scrubber"].adjust(toNormalizedSliderPosition: 5.0 / 7)
        XCTAssertTrue(app.buttons["webtoon-retry-5"].waitForExistence(timeout: 15))
        showControls(app)
        app.buttons["webtoon-close"].tap()
        let position = app.staticTexts["manga-reading-progress"]
        XCTAssertTrue(position.waitForExistence(timeout: 10))
        XCTAssertTrue(position.label.contains("Page 1 of 8"))
    }
    @MainActor private func launch(failure: Bool = false, chapterFailure: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-phase2-preview", "--ui-webtoon-preview", "--ui-webtoon-session", UUID().uuidString]
        if failure { app.launchArguments.append("--ui-webtoon-failed-page") }
        if chapterFailure { app.launchArguments.append("--ui-webtoon-chapter-runtime-error") }
        app.launch()
        XCTAssertTrue(app.buttons["explore-search"].waitForExistence(timeout: 15))
        app.appTab("Manga").tap()
        return app
    }
    @MainActor private func openFirstTitle(_ app: XCUIApplication) {
        let source = app.buttons["manga-source-preview-en"]
        XCTAssertTrue(source.waitForExistence(timeout: 15)); source.tap()
        let title = app.buttons["manga-title-0"]
        XCTAssertTrue(title.waitForExistence(timeout: 15))
        capture("Cover-Catalog", app); title.tap()
        XCTAssertTrue(app.buttons["manga-read"].waitForExistence(timeout: 15))
        capture("Title-And-Chapters", app)
    }
    @MainActor private func openSourceSettings(_ app: XCUIApplication) {
        let settings = app.buttons["manga-source-settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 15)); settings.tap()
        XCTAssertTrue(app.buttons["source-setting-quality"].waitForExistence(timeout: 15))
    }
    @MainActor private func resetSourceSettings(_ app: XCUIApplication) {
        let reset = app.buttons["source-settings-reset"]
        for _ in 0..<3 where !reset.isHittable { app.swipeUp() }
        XCTAssertTrue(reset.isHittable); reset.tap()
    }
    @MainActor private func showControls(_ app: XCUIApplication) {
        if !app.buttons["webtoon-close"].exists { app.scrollViews["webtoon-canvas"].tap() }
        XCTAssertTrue(app.buttons["webtoon-close"].waitForExistence(timeout: 5))
    }
    @MainActor private func capture(_ name: String, _ app: XCUIApplication) {
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = "Webtoon-\(name)"; a.lifetime = .keepAlways; add(a)
    }
}
