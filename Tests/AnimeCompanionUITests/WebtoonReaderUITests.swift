import XCTest

final class WebtoonReaderUITests: XCTestCase {
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
        app.sliders["webtoon-page-scrubber"].adjust(toNormalizedSliderPosition: 2.0 / 7)
        let retry = app.buttons["webtoon-retry-2"]
        XCTAssertTrue(retry.waitForExistence(timeout: 15)); retry.tap()
        XCTAssertTrue(app.images["webtoon-page-image-2"].waitForExistence(timeout: 20))
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
        app.sliders["webtoon-page-scrubber"].adjust(toNormalizedSliderPosition: 2.0 / 7)
        XCTAssertTrue(app.buttons["webtoon-retry-2"].waitForExistence(timeout: 15))
        showControls(app)
        app.buttons["webtoon-close"].tap()
        let position = app.staticTexts["manga-reading-progress"]
        XCTAssertTrue(position.waitForExistence(timeout: 10))
        XCTAssertTrue(position.label.contains("Page 1 of 8"))
    }
    @MainActor private func launch(failure: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-phase2-preview", "--ui-webtoon-preview", "--ui-webtoon-session", UUID().uuidString]
        if failure { app.launchArguments.append("--ui-webtoon-failed-page") }
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
    @MainActor private func showControls(_ app: XCUIApplication) {
        if !app.buttons["webtoon-close"].exists { app.scrollViews["webtoon-canvas"].tap() }
        XCTAssertTrue(app.buttons["webtoon-close"].waitForExistence(timeout: 5))
    }
    @MainActor private func capture(_ name: String, _ app: XCUIApplication) {
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = "Webtoon-\(name)"; a.lifetime = .keepAlways; add(a)
    }
}
