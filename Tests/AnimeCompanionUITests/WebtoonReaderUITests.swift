import XCTest

final class WebtoonReaderUITests: XCTestCase {
    @MainActor
    func testSourceSettingsSaveCancelResetAndRelaunch() {
        let app = launch()
        let source = app.buttons["manga-source-preview-en"]
        XCTAssertTrue(source.waitForExistence(timeout: 15)); source.tap()
        openSourceSettings(app)
        app.buttons["source-setting-quality"].tap()
        let high = app.buttons["source-choice-high"]
        XCTAssertTrue(high.waitForExistence(timeout: 10)); high.tap()
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
