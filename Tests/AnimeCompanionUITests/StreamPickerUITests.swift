import XCTest
import UIKit

/// Actual native views, WebKit/TypeScript execution and player URL builders.
/// Owned fixtures only: no production credentials, cloud adds or external apps.
final class StreamPickerUITests: XCTestCase {
    @MainActor
    func testCleanPickerSharesLanguageAndReleaseFiltersAndKeepsOptionsAccessible() {
        let app = openPicker()
        XCTAssertEqual(app.textFields["playback-episode-number"].value as? String, "9")
        XCTAssertTrue(app.staticTexts["stream-picker-title"].exists)
        XCTAssertEqual(app.segmentedControls.matching(identifier: "playback-audio-filter").count, 1)
        XCTAssertFalse(app.segmentedControls["seanime-audio-filter"].exists)
        capture("Clean-Header-And-Streaming-Cards")
        let kind = app.segmentedControls["playback-source-kind"]
        let audio = app.segmentedControls["playback-audio-filter"]
        audio.buttons["English"].tap(); kind.buttons["Streaming"].tap()
        let english = app.buttons["playback-source-1"]
        app.revealInContent(english); XCTAssertTrue(english.label.contains("EN + JA"))
        XCTAssertFalse(app.buttons["playback-source-0"].exists)
        XCTAssertFalse(app.buttons["playback-source-2"].exists)
        let filter = app.textFields["playback-source-search"]
        app.revealInContent(filter, upward: false); filter.tap(); filter.typeText("720p\n")
        let reset = app.buttons["playback-reset-source-filters"]
        app.revealInContent(reset); XCTAssertTrue(reset.exists); reset.tap()
        app.revealInContent(kind, upward: false); kind.buttons["Torrents"].tap()
        app.revealInContent(audio, upward: false); audio.buttons["English"].tap()
        let result = app.buttons["seanime-torrent-result"].firstMatch
        // The production worker has a 60-second cold-start/execution bound.
        XCTAssertTrue(result.waitForExistence(timeout: 65)); app.revealInContent(result)
        XCTAssertTrue(result.label.contains("English")); XCTAssertTrue(audio.buttons["English"].isSelected)
        capture("Shared-English-Filter-Torrent-Card")
        app.buttons["stream-picker-options"].tap(); app.buttons["Sources & options"].tap()
        XCTAssertTrue(app.navigationBars["Source options"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.switches["playback-playable-only"].exists)
        capture("Source-Options-Out-Of-The-Results")
        app.navigationBars["Source options"].buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Find streams"].waitForExistence(timeout: 10))
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCUIDevice.shared.orientation = .landscapeLeft
            app.revealInContent(result)
            XCTAssertGreaterThanOrEqual(result.frame.minX, 0)
            XCTAssertLessThanOrEqual(result.frame.maxX, app.frame.maxX)
            capture("Clean-Picker-iPad-Landscape")
            XCUIDevice.shared.orientation = .portrait
        }
    }
    @MainActor
    func testTorrentSortingKeepsEnglishFirstAndPersistsTheDefault() {
        var app = openPicker(["--ui-torrent-sort-preview"])
        app.segmentedControls["playback-source-kind"].buttons["Torrents"].tap()
        let first = app.buttons["seanime-torrent-result"].firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 65))
        XCTAssertTrue(first.label.contains("Zulu release"), "The English release with 100 seeders must precede Japanese with 5,000")
        let sort = app.buttons["seanime-torrent-sort"]
        app.revealInContent(sort, upward: false)
        XCTAssertTrue((sort.value as? String)?.contains("Highest seeders") == true)
        capture("Default-English-Then-Highest-Seeders")
        sort.tap(); app.buttons["Release name"].tap()
        let alphabetical = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "Alpha release"), object: first)
        XCTAssertEqual(XCTWaiter.wait(for: [alphabetical], timeout: 10), .completed)
        XCTAssertTrue((sort.value as? String)?.contains("Release name") == true)
        capture("Saved-Torrent-Sort")
        app.terminate()
        app = openPicker(["--ui-torrent-sort-preview"], resetPreferences: false)
        app.segmentedControls["playback-source-kind"].buttons["Torrents"].tap()
        let restoredSort = app.buttons["seanime-torrent-sort"]
        app.revealInContent(restoredSort)
        XCTAssertTrue((restoredSort.value as? String)?.contains("Release name") == true)
        let restoredFirst = app.buttons["seanime-torrent-result"].firstMatch
        XCTAssertTrue(restoredFirst.waitForExistence(timeout: 65)); XCTAssertTrue(restoredFirst.label.contains("Alpha release"))
        // Restore the requested default for subsequent scenarios on this simulator.
        app.revealInContent(restoredSort, upward: false); restoredSort.tap(); app.buttons["Highest seeders"].tap()
        let seeders = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "Zulu release"), object: restoredFirst)
        XCTAssertEqual(XCTWaiter.wait(for: [seeders], timeout: 10), .completed)
        capture("Restored-Highest-Seeders")
    }
    @MainActor
    func testUncachedReleaseShowsStableInlineStatusAndPlaysExactFileWithoutExtraDialogs() {
        let app = openPicker(["--ui-torbox-cache-miss", "--ui-torbox-downloading"])
        app.segmentedControls["playback-source-kind"].buttons["Torrents"].tap()
        let result = app.buttons["seanime-torrent-result"].firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 65)); app.revealInContent(result); result.tap()
        let cached = app.buttons["torbox-add-torrent"]
        XCTAssertTrue(cached.waitForExistence(timeout: 15)); app.revealInContent(cached); cached.tap()
        let download = app.buttons["torbox-download-torrent"]
        XCTAssertTrue(download.waitForExistence(timeout: 15)); app.revealInContent(download)
        XCTAssertFalse(app.switches["torbox-cached-only"].exists)
        XCTAssertFalse(app.staticTexts["torbox-playback-error"].exists)
        capture("Compact-Uncached-Download-Action")
        download.tap()
        XCTAssertFalse(app.buttons["Confirm add to TorBox"].exists)
        let status = app.staticTexts["torbox-job-status"]
        XCTAssertTrue(status.waitForExistence(timeout: 15)); app.revealInContent(status)
        XCTAssertTrue(status.label.contains("Downloading") || status.label.contains("Ready to play"))
        XCTAssertFalse(download.exists); XCTAssertFalse(cached.exists)
        capture("Inline-TorBox-Download-Status")
        let file = app.buttons["torbox-file-10"]
        XCTAssertTrue(file.waitForExistence(timeout: 35)); app.revealInContent(file)
        XCTAssertTrue(app.navigationBars["Find streams"].exists)
        capture("Ready-Files-On-The-Same-Screen")
        file.tap()
        let message = app.staticTexts["playback-player-message"]
        app.revealInContent(message, upward: false); XCTAssertTrue(message.waitForExistence(timeout: 10))
        XCTAssertTrue(message.label.contains("TorBox file 10")); XCTAssertTrue(message.label.contains("Episode 9"))
        XCTAssertFalse(message.label.contains("synthetic-torbox-key"))
        let progress = app.staticTexts["playback-anilist-progress"]
        app.revealInContent(progress, upward: false); XCTAssertTrue(progress.label.contains("8 episodes watched"))
        capture("Exact-File-Handoff-Progress-Unchanged")
    }
    @MainActor private func openPicker(_ extra: [String] = [], resetPreferences: Bool = true) -> XCUIApplication {
        continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-library-preview", "--ui-playback-preview", "--ui-playback-languages", "--ui-seanime-preview", "--ui-stream-picker-preview"]
            + (resetPreferences ? ["--ui-reset-content-preferences"] : []) + extra
        app.launch()
        let library = app.appTab("My Library"); XCTAssertTrue(library.waitForExistence(timeout: 20)); library.tap()
        app.watchLibraryEntry(1)
        XCTAssertTrue(app.navigationBars["Find streams"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["playback-english-availability"].waitForExistence(timeout: 15))
        return app
    }
    @MainActor private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "Stream-Picker-\(name)"; attachment.lifetime = .keepAlways; add(attachment)
    }
}
