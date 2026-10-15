import XCTest
import UIKit

final class SourceAudioUITests: XCTestCase {
    @MainActor
    func testEnglishAudioSurvivesLongBrokenDescriptionsAndFiltersTheActualSource() throws {
        let app = openPlayback(flag: "--ui-playback-languages")
        let summary = app.staticTexts["playback-english-availability"]
        XCTAssertTrue(summary.waitForExistence(timeout: 15))
        XCTAssertEqual(summary.label, "English audio · 1 playable source")
        let english = app.buttons["playback-source-1"]
        reveal(english, in: app)
        XCTAssertTrue(english.label.contains("EN + JA · English & Japanese audio"))
        XCTAssertTrue(english.label.contains("1080p · HEVC · 2.4 GB"))
        XCTAssertFalse(english.label.contains("invalid expression"))
        let languages = app.segmentedControls["playback-audio-filter"]
        reveal(languages, in: app, upward: false); languages.buttons["English"].tap()
        XCTAssertTrue(english.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["playback-source-0"].exists, "Japanese audio with English subtitles must not match English audio")
        XCTAssertFalse(app.buttons["playback-source-2"].exists, "Unspecified multi audio must not be guessed English")
        let field = app.textFields["playback-episode-number"]
        reveal(field, in: app, upward: false)
        field.tap(); field.typeText(XCUIKeyboardKey.delete.rawValue + "10")
        app.buttons["playback-episode-go"].tap()
        let updated = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "anilist:1:10.json"), object: english)
        XCTAssertEqual(XCTWaiter.wait(for: [updated], timeout: 15), .completed)
        XCTAssertTrue(languages.buttons["English"].isSelected)
        reveal(english, in: app); english.tap()
        XCTAssertTrue(app.staticTexts["Preview launch · Episode 10"].waitForExistence(timeout: 10))
        capture("English-Audio-Selected-And-Correct-Episode")
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCUIDevice.shared.orientation = .landscapeLeft
            reveal(english, in: app)
            XCTAssertGreaterThanOrEqual(english.frame.minX, 0)
            XCTAssertLessThanOrEqual(english.frame.maxX, app.frame.maxX)
            capture("Source-Picker-iPad-Landscape")
            XCUIDevice.shared.orientation = .portrait
        }
    }
    @MainActor
    func testJapaneseWithEnglishSubtitlesDoesNotPromiseDubAndEmptyAudioFilterCanReset() throws {
        let app = openPlayback(flag: "--ui-playback-ja-only")
        XCTAssertEqual(app.staticTexts["playback-english-availability"].label, "No playable English source listed")
        let source = app.buttons["playback-source-0"]
        reveal(source, in: app); XCTAssertTrue(source.label.contains("JA · Japanese audio"))
        XCTAssertFalse(source.label.contains("EN · English audio"))
        let languages = app.segmentedControls["playback-audio-filter"]
        reveal(languages, in: app, upward: false); languages.buttons["English"].tap()
        let reset = app.buttons["playback-reset-source-filters"]
        XCTAssertTrue(reset.waitForExistence(timeout: 10)); reveal(reset, in: app)
        XCTAssertFalse(app.staticTexts["playback-empty-results"].exists)
        reset.tap(); XCTAssertTrue(source.waitForExistence(timeout: 10)); reveal(source, in: app)
        XCTAssertTrue(source.label.contains("JA · Japanese audio")); source.tap()
        XCTAssertTrue(app.staticTexts["Preview launch · Episode 9"].waitForExistence(timeout: 10))
        capture("Japanese-Audio-And-English-Filter-Recovery")
    }
    @MainActor private func openPlayback(flag: String) -> XCUIApplication {
        continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-library-preview", "--ui-playback-preview", "--ui-reset-content-preferences", flag]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["My Library"].waitForExistence(timeout: 30)); app.tabBars.buttons["My Library"].tap()
        let watch = app.buttons["library-watch-1"]
        XCTAssertTrue(watch.waitForExistence(timeout: 45)); reveal(watch, in: app); watch.tap()
        XCTAssertTrue(app.staticTexts["playback-english-availability"].waitForExistence(timeout: 15))
        return app
    }
    @MainActor private func reveal(_ element: XCUIElement, in app: XCUIApplication, upward: Bool = true) {
        for _ in 0..<10 where !element.isHittable { if upward { app.swipeUp() } else { app.swipeDown() } }
        XCTAssertTrue(element.isHittable)
    }
    @MainActor private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "Phase-2-\(UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone")-\(name)"
        attachment.lifetime = .keepAlways; add(attachment)
    }
}
