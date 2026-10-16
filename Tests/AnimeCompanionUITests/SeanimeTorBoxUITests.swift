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
        let file = app.buttons["torbox-file-10"]
        XCTAssertTrue(file.waitForExistence(timeout: 15)); app.revealInContent(file); file.tap()
        let message = app.staticTexts["torbox-player-message"]
        XCTAssertTrue(message.waitForExistence(timeout: 10))
        app.revealInContent(message)
        XCTAssertTrue(message.label.contains("TorBox file 10"))
        XCTAssertFalse(message.label.contains("TorBox file 9"))
        XCTAssertFalse(message.label.contains("synthetic-torbox-key"))
        capture("On-Device-TS-TorBox-Exact-File")
    }
    @MainActor
    func testHTTP400CacheMissExplainsTheCauseAndCanBeRetriedWithUserApproval() {
        let app = launch(["--ui-torbox-cache-miss", "--ui-torbox-downloading"])
        openSettings(app); saveFixtureKey(app); installFixture(app); openSearch(app)
        let result = app.buttons["seanime-torrent-result"].firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 25)); app.revealInContent(result); result.tap()
        let add = app.buttons["torbox-add-torrent"]
        app.revealInContent(add); XCTAssertTrue(add.waitForExistence(timeout: 10)); add.tap()
        let cacheMiss = app.staticTexts["torbox-cache-miss"]
        XCTAssertTrue(cacheMiss.waitForExistence(timeout: 15)); app.revealInContent(cacheMiss)
        XCTAssertTrue(cacheMiss.label.contains("Not cached"))
        XCTAssertFalse(app.staticTexts["torbox-playback-error"].exists)
        XCTAssertFalse(app.buttons["torbox-file-10"].exists)
        XCTAssertFalse(app.switches["torbox-cached-only"].exists)
        capture("Cache-Miss-Single-Download-Action")
        let download = app.buttons["torbox-download-torrent"]
        app.revealInContent(download); download.tap()
        XCTAssertFalse(app.buttons["Confirm add to TorBox"].exists, "The clearly labeled download tap is the account authorization")
        let status = app.descendants(matching: .any).matching(identifier: "torbox-job-status").firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 10)); app.revealInContent(status)
        XCTAssertTrue(status.label.contains("Downloading") || status.label.contains("Ready to play"))
        XCTAssertFalse(download.exists); XCTAssertFalse(add.exists, "An accepted release must not offer a second submission")
        capture("Uncached-Download-Progress")
        // Status checks are automatic GETs: no extra confirmation or refresh.
        let file = app.buttons["torbox-file-10"]
        XCTAssertTrue(file.waitForExistence(timeout: 35)); app.revealInContent(file); file.tap()
        let message = app.staticTexts["torbox-player-message"]
        app.revealInContent(message); XCTAssertTrue(message.waitForExistence(timeout: 10))
        XCTAssertTrue(message.label.contains("TorBox file 10"))
        XCTAssertFalse(message.label.contains("synthetic-torbox-key"))
        capture("Uncached-Auto-Ready-Exact-File")
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
        app.buttons["Done"].tap()
        let watch = app.buttons["featured-watch-1"]
        app.revealInContent(watch, upward: false); watch.tap()
        XCTAssertTrue(app.navigationBars["Find streams"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.segmentedControls["playback-source-kind"].exists)
        XCTAssertTrue(app.buttons["playback-source-0"].waitForExistence(timeout: 15))
        let query = app.textFields["seanime-query"]
        app.revealInContent(query)
        let count = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "2 releases")).firstMatch
        app.revealInContent(count); XCTAssertTrue(count.exists)
        let first = app.buttons.matching(identifier: "seanime-torrent-result").matching(NSPredicate(format: "label CONTAINS %@", "On-device fixture")).firstMatch
        app.revealInContent(first); XCTAssertTrue(first.label.contains("English"))
        let result = app.buttons.matching(identifier: "seanime-torrent-result").matching(NSPredicate(format: "label CONTAINS %@", "Another provider")).firstMatch
        app.revealInContent(result); XCTAssertTrue(result.label.contains("English")); result.tap()
        let add = app.buttons["torbox-add-torrent"]
        app.revealInContent(add); XCTAssertTrue(add.waitForExistence(timeout: 10)); add.tap()
        let file = app.buttons["torbox-file-10"]
        XCTAssertTrue(file.waitForExistence(timeout: 15)); app.revealInContent(file); file.tap()
        XCTAssertTrue(app.navigationBars["Find streams"].exists, "File selection must stay in the Watch screen")
        XCTAssertFalse(app.navigationBars["TorBox playback"].exists)
        let message = app.staticTexts["torbox-player-message"]
        app.revealInContent(message)
        XCTAssertTrue(message.waitForExistence(timeout: 10)); XCTAssertTrue(message.label.contains("Episode 9"))
        XCTAssertTrue(message.label.contains("Anime - 10 JA.mkv")); XCTAssertFalse(message.label.contains("Anime - 09 EN.mkv"))
        XCTAssertTrue(message.label.contains("TorBox file 10")); XCTAssertFalse(message.label.contains("synthetic-torbox-key"))
        capture("Unified-Watch-Streaming-Torrents-Inline-Files")
        let progress = app.staticTexts["playback-anilist-progress"]
        app.revealInContent(progress, upward: false); XCTAssertTrue(progress.label.contains("8 episodes watched"))
    }
    @MainActor
    func testQueuedReceiptCanRefreshToFilesWithoutAnotherAdd() {
        let app = launch(["--ui-torbox-queued"])
        openSettings(app); saveFixtureKey(app); installFixture(app); openSearch(app)
        let result = app.buttons["seanime-torrent-result"].firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 25)); app.revealInContent(result); result.tap()
        let add = app.buttons["torbox-add-torrent"]
        XCTAssertTrue(add.waitForExistence(timeout: 10)); app.revealInContent(add); add.tap()
        let status = app.descendants(matching: .any).matching(identifier: "torbox-job-status").firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 15)); app.revealInContent(status)
        XCTAssertTrue(status.label.contains("Queued in TorBox") || status.label.contains("Ready to play"))
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
        let app = launch(["--ui-torbox-already-added", "--ui-torbox-single-file"])
        openSettings(app); saveFixtureKey(app); installFixture(app); openSearch(app)
        let result = app.buttons["seanime-torrent-result"].firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 25)); app.revealInContent(result); result.tap()
        let file = app.buttons["torbox-file-0"]
        XCTAssertTrue(file.waitForExistence(timeout: 15)); app.revealInContent(file)
        XCTAssertFalse(app.buttons["torbox-add-torrent"].exists)
        XCTAssertTrue(app.navigationBars["Find streams"].exists)
        file.tap()
        let message = app.staticTexts["torbox-player-message"]; app.revealInContent(message)
        XCTAssertTrue(message.waitForExistence(timeout: 10))
        XCTAssertTrue(message.label.contains("TorBox file 0"))
        XCTAssertFalse(message.label.contains("synthetic-torbox-key"))
        capture("Single-File-Private-Permalink-Recovered-By-Hash")
    }
    @MainActor
    func testWebDAVBrowserNavigatesSearchesRefreshesAndOpensExactFile() {
        let app = launch(["--ui-webdav-refresh-404"])
        let tab = app.appTab("My Library"); XCTAssertTrue(tab.waitForExistence(timeout:10)); tab.tap()
        let browse = app.buttons["library-torbox-files"]
        XCTAssertTrue(browse.waitForExistence(timeout:10)); browse.tap()
        XCTAssertTrue(app.navigationBars["TorBox files"].waitForExistence(timeout:10))
        let key = app.secureTextFields["webdav-torbox-key"]
        XCTAssertTrue(key.waitForExistence(timeout:10)); key.tap(); key.typeText("synthetic-torbox-key")
        let connect = app.buttons["webdav-connect-torbox"]; app.revealInContent(connect); connect.tap()
        let loose = app.buttons["torbox-webdav-video-Loose Episode.mkv"]
        XCTAssertTrue(loose.waitForExistence(timeout:15)); app.revealInContent(loose)
        XCTAssertTrue(app.staticTexts["torbox-webdav-sort-label"].label.contains("Newest first"))
        let older = app.buttons["torbox-webdav-folder-Fixture batch"]
        XCTAssertLessThan(loose.frame.minY, older.frame.minY, "Dates, not folder/name order, determine newest first")
        loose.tap()
        let message = app.staticTexts["torbox-webdav-player-message"]
        app.revealInContent(message)
        XCTAssertTrue(message.label.contains("WebDAV · Loose Episode.mkv")); XCTAssertFalse(message.label.contains("synthetic-torbox-key"))
        capture("WebDAV-Root-Video-Private-Handoff")
        let batch = app.buttons["torbox-webdav-folder-Fixture batch"]
        app.revealInContent(batch,upward:false); batch.tap()
        let extras = app.buttons["torbox-webdav-folder-Extras"]
        XCTAssertTrue(extras.waitForExistence(timeout:10)); extras.tap()
        XCTAssertTrue(app.buttons["torbox-webdav-video-Sample.mkv"].waitForExistence(timeout:10))
        app.navigationBars.buttons.firstMatch.tap()
        let search = app.searchFields.firstMatch
        app.revealInContent(search,upward:false); search.tap(); search.typeText("02\n")
        let episode = app.buttons["torbox-webdav-video-Episode 02 JA & Friends.mkv"]
        XCTAssertTrue(episode.waitForExistence(timeout:10)); app.revealInContent(episode)
        XCTAssertFalse(app.buttons["torbox-webdav-video-Episode 01 EN.mkv"].exists)
        episode.tap(); app.revealInContent(message)
        XCTAssertTrue(message.label.contains("WebDAV · Episode 02 JA & Friends.mkv"))
        XCTAssertFalse(message.label.contains("synthetic-torbox-key"))
        capture("WebDAV-Search-Exact-Batch-File")
        if app.buttons["Cancel"].exists { app.buttons["Cancel"].tap() }
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["TorBox files"].waitForExistence(timeout:10))
        let refresh = app.buttons["torbox-webdav-refresh"]; refresh.tap()
        let fresh = app.buttons["torbox-webdav-video-Fresh Episode.mkv"]
        app.revealInContent(fresh); XCTAssertTrue(fresh.waitForExistence(timeout:15))
        XCTAssertFalse(app.staticTexts["torbox-webdav-error"].exists, "Optional index HTTP 404 must not block folder browsing")
        let notice = app.staticTexts["torbox-webdav-refresh-notice"]
        app.revealInContent(notice, upward: false)
        XCTAssertTrue(notice.label.contains("Folder reloaded"))
        XCTAssertFalse(notice.label.contains("synthetic-torbox-key"))
        app.revealInContent(fresh); XCTAssertLessThan(fresh.frame.minY, loose.frame.minY)
        capture("WebDAV-Refresh-404-Recovered-Newest-First")
    }
    @MainActor
    func testSettingsCategoriesKeepConnectionAndPreferencesEasyToFind() {
        let app = launch()
        app.openExploreControl("explore-settings")
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout:10))
        XCTAssertTrue(app.buttons["settings-torbox"].exists)
        XCTAssertTrue(app.buttons["playback-settings"].exists)
        XCTAssertTrue(app.buttons["seanime-settings"].exists)
        capture("Settings-Clean-Categories")
        for (id, title, control) in [
            ("settings-torbox", "TorBox", "torbox-api-key"),
            ("settings-player", "Video player", ""),
            ("settings-browsing", "Browsing & content", "settings-adult-content"),
            ("settings-tracking", "Watch tracking", "settings-auto-complete")
        ] {
            let row = app.buttons[id]; app.revealInContent(row); row.tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout:10))
            if !control.isEmpty { XCTAssertTrue(app.descendants(matching:.any).matching(identifier:control).firstMatch.exists) }
            capture("Settings-\(title.replacingOccurrences(of:" ",with:"-"))")
            app.navigationBars.buttons.firstMatch.tap()
        }
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["explore-search"].waitForExistence(timeout:10))
    }
    @MainActor private func launch(_ extra: [String] = []) -> XCUIApplication {
        continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-phase2-preview", "--ui-multiple-addons-preview", "--ui-seanime-preview", "--ui-reset-content-preferences"] + extra
        app.launch(); XCTAssertTrue(app.buttons["explore-search"].waitForExistence(timeout: 15)); return app
    }
    @MainActor private func openSettings(_ app: XCUIApplication) {
        app.openExploreControl("explore-settings")
        let seanime = app.buttons["seanime-settings"]; XCTAssertTrue(seanime.waitForExistence(timeout: 10)); app.revealInContent(seanime); seanime.tap()
        XCTAssertTrue(app.navigationBars["Seanime extensions"].waitForExistence(timeout: 10))
    }
    @MainActor private func saveFixtureKey(_ app: XCUIApplication) {
        let connection = app.buttons["seanime-torbox-settings"]; app.revealInContent(connection); connection.tap()
        XCTAssertTrue(app.navigationBars["TorBox"].waitForExistence(timeout: 10))
        let key = app.secureTextFields["torbox-api-key"]; app.revealInContent(key); key.tap(); key.typeText("synthetic-torbox-key\n")
        let save = app.buttons["torbox-save-key"]; app.revealInContent(save); save.tap()
        let verify = app.buttons["torbox-verify"]; app.revealInContent(verify); verify.tap()
        let message = app.staticTexts["seanime-notice"]; app.revealInContent(message)
        XCTAssertTrue(message.waitForExistence(timeout: 10)); XCTAssertTrue(message.label.contains("No torrents were added"))
        capture("TorBox-Connection-Settings")
        app.navigationBars.buttons.firstMatch.tap()
    }
    @MainActor private func installFixture(_ app: XCUIApplication, suffix: String = "fixture") {
        let field = app.textFields["seanime-manifest-url"]; app.revealInContent(field, upward: false); field.tap(); field.typeText("https://provider.example/\(suffix).json\n")
        let review = app.buttons["seanime-review"]; app.revealInContent(review); review.tap()
        let install = app.buttons["seanime-install-confirm"]
        XCTAssertTrue(install.waitForExistence(timeout: 10)); app.revealInContent(install); install.tap()
        XCTAssertTrue(app.navigationBars["Seanime extensions"].waitForExistence(timeout: 10))
    }
    @MainActor private func openSearch(_ app: XCUIApplication) {
        let search = app.buttons["seanime-search"]; app.revealInContent(search); search.tap()
        let field = app.textFields["seanime-query"]; XCTAssertTrue(field.waitForExistence(timeout: 10)); field.tap(); field.typeText("Fixture\n")
    }
    @MainActor private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); attachment.name = "Seanime-\(name)"; attachment.lifetime = .keepAlways; add(attachment)
    }
}
