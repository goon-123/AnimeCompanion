import XCTest
import UIKit

/// Uses the production WebKit worker, bundled TypeScript compiler and TorBox
/// request/client/player builders, with owned scripts and synthetic transports.
/// Never reads/writes production Keychain, starts a real torrent or opens VidHub.
final class SeanimeTorBoxUITests: XCTestCase {
    @MainActor
    func testOnDeviceTypeScriptSearchAndExactTorBoxFileHandoff() {
        let app = launch()
        openSettings(app); saveFixtureKey(app); installFixture(app)
        openSearch(app)
        let result = app.buttons["seanime-torrent-result"].firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 25)); XCTAssertTrue(result.label.contains("English"))
        app.revealInContent(result); result.tap()
        let add = app.buttons["torbox-add-torrent"]
        XCTAssertTrue(add.waitForExistence(timeout: 10)); app.revealInContent(add); add.tap()
        XCTAssertTrue(app.buttons["Confirm add to TorBox"].waitForExistence(timeout: 10))
        app.buttons["Confirm add to TorBox"].tap()
        let file = app.buttons["torbox-file-10"]
        XCTAssertTrue(file.waitForExistence(timeout: 15)); app.revealInContent(file); file.tap()
        let message = app.staticTexts["torbox-player-message"]
        XCTAssertTrue(message.waitForExistence(timeout: 10))
        app.revealInContent(message)
        XCTAssertTrue(message.label.contains("selected-file-10.mkv"))
        XCTAssertFalse(message.label.contains("selected-file-9.mkv"))
        XCTAssertFalse(message.label.contains("synthetic-torbox-key"))
        capture("On-Device-TS-TorBox-Exact-File")
    }
    @MainActor
    func testHTTP400CacheMissExplainsTheCauseAndCanBeRetriedWithUserApproval() {
        let app = launch(["--ui-torbox-cache-miss"])
        openSettings(app); saveFixtureKey(app); installFixture(app); openSearch(app)
        let result = app.buttons["seanime-torrent-result"].firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 25)); app.revealInContent(result); result.tap()
        let add = app.buttons["torbox-add-torrent"]
        XCTAssertTrue(add.waitForExistence(timeout: 10)); app.revealInContent(add); add.tap()
        app.buttons["Confirm add to TorBox"].tap()
        let error = app.staticTexts["torbox-playback-error"]
        XCTAssertTrue(error.waitForExistence(timeout: 15)); app.revealInContent(error)
        XCTAssertTrue(error.label.contains("not cached"))
        XCTAssertFalse(error.label.contains("could not be reached"))
        XCTAssertFalse(error.label.contains("synthetic-torbox-key"))
        XCTAssertFalse(app.buttons["torbox-file-10"].exists)
        let cached = app.switches["torbox-cached-only"]
        app.revealInContent(cached, upward: false)
        XCTAssertEqual(cached.value as? String, "1", "An error must not silently allow uncached account downloads")
        capture("HTTP400-Cache-Miss-Explained")
        cached.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        let uncached = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "0"), object: cached)
        XCTAssertEqual(XCTWaiter.wait(for: [uncached], timeout: 5), .completed)
        app.revealInContent(add); add.tap()
        app.buttons["Confirm add to TorBox"].tap()
        let file = app.buttons["torbox-file-10"]
        XCTAssertTrue(file.waitForExistence(timeout: 15)); app.revealInContent(file); file.tap()
        let message = app.staticTexts["torbox-player-message"]
        XCTAssertTrue(message.waitForExistence(timeout: 10))
        XCTAssertTrue(message.label.contains("selected-file-10.mkv"))
        capture("Explicit-Uncached-Retry-Exact-File")
    }
    @MainActor
    func testUnapprovedHostCannotBecomeSuccessfulEmptySearch() {
        let app = launch(["--ui-seanime-blocked-host"])
        openSettings(app); installFixture(app); openSearch(app)
        let error = app.staticTexts["seanime-search-error"]
        XCTAssertTrue(error.waitForExistence(timeout: 25))
        XCTAssertTrue(error.label.contains("unapproved.example"))
        XCTAssertFalse(app.buttons["seanime-torrent-result"].exists)
        capture("Blocked-Provider-Network")
    }
    @MainActor
    func testInfiniteExtensionWorkerTimesOutWithoutFreezingNativeUI() {
        let app = launch(["--ui-seanime-timeout"])
        openSettings(app); installFixture(app); openSearch(app)
        let error = app.staticTexts["seanime-search-error"]
        XCTAssertTrue(error.waitForExistence(timeout: 15)); XCTAssertTrue(error.label.contains("execution limit"))
        XCTAssertTrue(app.buttons["seanime-run-search"].isEnabled)
        capture("Worker-Deadline-Native-UI-Responsive")
    }
    @MainActor
    func testRunningExtensionCanBeCancelledWithoutAStaleFailureOrAccountAction() {
        let app = launch(["--ui-seanime-spin"])
        openSettings(app); installFixture(app); openSearch(app)
        let cancel = app.buttons["Cancel search"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 10)); cancel.tap()
        XCTAssertTrue(app.buttons["seanime-run-search"].isEnabled)
        XCTAssertFalse(app.staticTexts["seanime-search-error"].exists)
        XCTAssertFalse(app.buttons["seanime-torrent-result"].exists)
        capture("Worker-Explicit-Cancellation")
    }
    @MainActor
    func testWatchCombinesStreamingTorrentSearchAndInlineFileHandoff() {
        let app = launch()
        openSettings(app); saveFixtureKey(app); installFixture(app)
        installFixture(app, suffix: "second")
        app.navigationBars.buttons.firstMatch.tap()
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["Done"].tap()
        let watch = app.buttons["featured-watch-1"]
        app.revealInContent(watch, upward: false); watch.tap()
        XCTAssertTrue(app.navigationBars["Find streams"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.segmentedControls["playback-source-kind"].exists)
        XCTAssertTrue(app.buttons["playback-source-0"].waitForExistence(timeout: 15))
        let result = app.buttons["seanime-torrent-result"].firstMatch
        let combined = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count == 2"), object: app.buttons.matching(identifier: "seanime-torrent-result"))
        XCTAssertEqual(XCTWaiter.wait(for: [combined], timeout: 25), .completed)
        XCTAssertTrue(app.buttons.matching(identifier: "seanime-torrent-result").matching(NSPredicate(format: "label CONTAINS %@", "Another provider")).firstMatch.exists)
        app.revealInContent(result); result.tap()
        let add = app.buttons["torbox-add-torrent"]
        XCTAssertTrue(add.waitForExistence(timeout: 10)); app.revealInContent(add); add.tap()
        app.buttons["Confirm add to TorBox"].tap()
        let file = app.buttons["torbox-file-10"]
        XCTAssertTrue(file.waitForExistence(timeout: 15)); app.revealInContent(file); file.tap()
        XCTAssertTrue(app.navigationBars["Find streams"].exists, "File selection must stay in the Watch screen")
        XCTAssertFalse(app.navigationBars["TorBox playback"].exists)
        let message = app.staticTexts["torbox-player-message"]
        XCTAssertTrue(message.waitForExistence(timeout: 10)); XCTAssertTrue(message.label.contains("Episode 9"))
        XCTAssertTrue(message.label.contains("Anime - 10 JA.mkv")); XCTAssertFalse(message.label.contains("Anime - 09 EN.mkv"))
        XCTAssertTrue(app.staticTexts["playback-anilist-progress"].label.contains("8 episodes watched"))
        capture("Unified-Watch-Streaming-Torrents-Inline-Files")
    }
    @MainActor
    func testQueuedReceiptCanRefreshToFilesWithoutAnotherAdd() {
        let app = launch(["--ui-torbox-queued"])
        openSettings(app); saveFixtureKey(app); installFixture(app); openSearch(app)
        let result = app.buttons["seanime-torrent-result"].firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 25)); app.revealInContent(result); result.tap()
        let add = app.buttons["torbox-add-torrent"]
        XCTAssertTrue(add.waitForExistence(timeout: 10)); app.revealInContent(add); add.tap()
        app.buttons["Confirm add to TorBox"].tap()
        let status = app.staticTexts["torbox-job-status"]
        XCTAssertTrue(status.waitForExistence(timeout: 15)); app.revealInContent(status)
        let queued = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "Queued in TorBox", "41"), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [queued], timeout: 10), .completed)
        XCTAssertFalse(add.exists); XCTAssertFalse(app.staticTexts["torbox-playback-error"].exists)
        let refresh = app.buttons["torbox-refresh-files"]; app.revealInContent(refresh); refresh.tap()
        let file = app.buttons["torbox-file-10"]
        XCTAssertTrue(file.waitForExistence(timeout: 15)); app.revealInContent(file); file.tap()
        XCTAssertTrue(app.staticTexts["torbox-player-message"].waitForExistence(timeout: 10))
        capture("Queued-Receipt-Refresh-To-Exact-Files")
    }
    @MainActor
    func testAcceptedTorrentSurvivesUnreadableFileResponseAndRefreshesWithoutResubmitting() {
        let app = launch(["--ui-torbox-unreadable-files-once"])
        openSettings(app); saveFixtureKey(app); installFixture(app); openSearch(app)
        let result = app.buttons["seanime-torrent-result"].firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 25)); app.revealInContent(result); result.tap()
        let add = app.buttons["torbox-add-torrent"]
        XCTAssertTrue(add.waitForExistence(timeout: 10)); app.revealInContent(add); add.tap()
        app.buttons["Confirm add to TorBox"].tap()
        let error = app.staticTexts["torbox-playback-error"]
        XCTAssertTrue(error.waitForExistence(timeout: 15)); app.revealInContent(error)
        XCTAssertTrue(error.label.contains("release was submitted")); XCTAssertFalse(add.exists)
        let refresh = app.buttons["torbox-refresh-files"]; app.revealInContent(refresh, upward: false); refresh.tap()
        let file = app.buttons["torbox-file-10"]
        XCTAssertTrue(file.waitForExistence(timeout: 15)); XCTAssertFalse(add.exists)
        capture("Accepted-Torrent-Read-Only-Recovery")
    }
    @MainActor
    func testAlreadyAddedReleaseOpensFilesWithoutAnAccountAdd() {
        let app = launch(["--ui-torbox-already-added"])
        openSettings(app); saveFixtureKey(app); installFixture(app); openSearch(app)
        let result = app.buttons["seanime-torrent-result"].firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 25)); app.revealInContent(result); result.tap()
        let file = app.buttons["torbox-file-10"]
        XCTAssertTrue(file.waitForExistence(timeout: 15)); app.revealInContent(file)
        XCTAssertFalse(app.buttons["torbox-add-torrent"].exists)
        XCTAssertTrue(app.navigationBars["Find streams"].exists)
        file.tap(); XCTAssertTrue(app.staticTexts["torbox-player-message"].waitForExistence(timeout: 10))
        capture("Previously-Added-Release-Recovered-By-Hash")
    }
    @MainActor private func launch(_ extra: [String] = []) -> XCUIApplication {
        continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-phase2-preview", "--ui-multiple-addons-preview", "--ui-seanime-preview", "--ui-reset-content-preferences"] + extra
        app.launch(); XCTAssertTrue(app.buttons["explore-search"].waitForExistence(timeout: 15)); return app
    }
    @MainActor private func openSettings(_ app: XCUIApplication) {
        app.openExploreControl("explore-settings")
        let playback = app.buttons["playback-settings"]; app.revealInContent(playback); playback.tap()
        let seanime = app.buttons["seanime-settings"]; XCTAssertTrue(seanime.waitForExistence(timeout: 10)); app.revealInContent(seanime); seanime.tap()
        XCTAssertTrue(app.navigationBars["Seanime & TorBox"].waitForExistence(timeout: 10))
    }
    @MainActor private func saveFixtureKey(_ app: XCUIApplication) {
        let key = app.secureTextFields["torbox-api-key"]; app.revealInContent(key); key.tap(); key.typeText("synthetic-torbox-key\n")
        let save = app.buttons["torbox-save-key"]; app.revealInContent(save); save.tap()
        let verify = app.buttons["torbox-verify"]; app.revealInContent(verify); verify.tap()
        let message = app.staticTexts["seanime-notice"]; app.revealInContent(message)
        XCTAssertTrue(message.waitForExistence(timeout: 10)); XCTAssertTrue(message.label.contains("No torrents were added"))
    }
    @MainActor private func installFixture(_ app: XCUIApplication, suffix: String = "fixture") {
        let field = app.textFields["seanime-manifest-url"]; app.revealInContent(field, upward: false); field.tap(); field.typeText("https://provider.example/\(suffix).json\n")
        let review = app.buttons["seanime-review"]; app.revealInContent(review); review.tap()
        let install = app.buttons["seanime-install-confirm"]
        XCTAssertTrue(install.waitForExistence(timeout: 10)); app.revealInContent(install); install.tap()
        XCTAssertTrue(app.navigationBars["Seanime & TorBox"].waitForExistence(timeout: 10))
    }
    @MainActor private func openSearch(_ app: XCUIApplication) {
        let search = app.buttons["seanime-search"]; app.revealInContent(search); search.tap()
        let field = app.textFields["seanime-query"]; XCTAssertTrue(field.waitForExistence(timeout: 10)); field.tap(); field.typeText("Fixture\n")
    }
    @MainActor private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); attachment.name = "Seanime-\(name)"; attachment.lifetime = .keepAlways; add(attachment)
    }
}
