import XCTest
import UIKit

final class LibraryDetailImprovementsUITests: XCTestCase {
    @MainActor func testBothLayoutsKeepCountdownAndBroadcastCatchUpWithDubPreference() {
        let app = launch(extra: ["--ui-library-detail-dub-preference"])
        for layout in ["List", "Grid"] {
            let picker = app.segmentedControls["library-layout"]
            app.revealInContent(picker, upward: false); picker.buttons[layout].tap()
            for (id, state) in [(1, "Behind original broadcast"), (990101, "Caught up with original broadcast")] {
                let entry = app.buttons["library-entry-\(id)"]
                app.revealInContent(entry)
                let next = app.staticTexts["library-next-episode-\(id)"]
                XCTAssertTrue(next.label.contains("Airs in"))
                XCTAssertEqual(next.value as? String, state)
                let dub = app.staticTexts["library-dub-\(id)"]
                let rating = app.descendants(matching: .any).matching(identifier: "library-rating-\(id)").firstMatch
                XCTAssertTrue(dub.exists); XCTAssertTrue(rating.exists)
                XCTAssertFalse(dub.frame.intersects(rating.frame))
                XCTAssertTrue(entry.frame.contains(dub.frame)); XCTAssertTrue(entry.frame.contains(rating.frame))
                XCTAssertFalse(entry.label.contains("15/17 released"))
                capture("\(layout)-\(id == 1 ? "Behind" : "Caught-Up")")
            }
        }
    }

    @MainActor func testDetailOverviewFloatingMenuEditingPlaybackDismissalAndSwipeBack() {
        let app = launch()
        let entry = app.buttons["library-entry-1"]
        app.revealInContent(entry); entry.tap()
        let actions = app.buttons["detail-actions"]
        XCTAssertTrue(actions.waitForExistence(timeout: 15))
        XCTAssertFalse(app.tabBars.firstMatch.isHittable)
        XCTAssertFalse(app.buttons["detail-episodes-disclosure"].exists)
        let aired = app.descendants(matching: .any).matching(identifier: "detail-episodes-aired").firstMatch
        app.revealInContent(aired)
        XCTAssertEqual(aired.label, "Aired: 17/26")
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "detail-episodes-dubbed").firstMatch.label, "Dubbed: 15")
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "detail-episodes-watched").firstMatch.label, "Watched: 16")
        let initialFrame = actions.frame
        app.revealInContent(app.staticTexts["Fixture studio"])
        XCTAssertFalse(app.buttons["detail-more-information"].exists)
        XCTAssertTrue(actions.isHittable)
        XCTAssertEqual(actions.frame.minY, initialFrame.minY, accuracy: 2)
        capture("Detail-Overview-And-Visible-Information")
        app.openAnimeActions()
        XCTAssertTrue(app.buttons["detail-edit-entry"].exists)
        XCTAssertTrue(app.buttons["detail-find-manga"].exists)
        capture("Detail-Actions-Expanded")
        app.buttons["detail-actions-dismiss"].coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.15)).tap()
        XCTAssertEqual(actions.value as? String, "Collapsed")
        app.openAnimeActions(); app.buttons["detail-edit-entry"].tap()
        XCTAssertTrue(app.textFields["tracking-episode-input"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.textFields["tracking-episode-input"].value as? String, "16")
        app.buttons["Cancel"].tap()
        app.openAnimeActions(); app.buttons["watch-in-vidhub"].tap()
        XCTAssertTrue(app.textFields["playback-episode-number"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.textFields["playback-episode-number"].value as? String, "17")
        // The existing player still permits explicit episode selection after
        // removing the redundant episode list from the detail page.
        app.enterPlaybackEpisode(2); app.buttons["playback-episode-go"].tap()
        XCTAssertEqual(app.textFields["playback-episode-number"].value as? String, "2")
        app.buttons["Done"].tap()
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCUIDevice.shared.orientation = .landscapeLeft
            XCTAssertTrue(actions.isHittable)
            XCTAssertLessThanOrEqual(actions.frame.maxX, app.frame.maxX)
            capture("Detail-Landscape-Actions")
            XCUIDevice.shared.orientation = .portrait
            app.returnToBrowsing()
        } else {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.90, dy: 0.5))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTAssertTrue(app.segmentedControls["library-layout"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.appTab("My Library").isHittable)
        app.revealInContent(entry)
        XCTAssertTrue(entry.label.contains("Watched 16/26"))
    }

    @MainActor func testFindMangaActionOpensExistingSourceSearchAndRetainsAnimeProgress() {
        let app = launch(extra: ["--ui-webtoon-preview", "--ui-webtoon-session", UUID().uuidString])
        let entry = app.buttons["library-entry-1"]
        app.revealInContent(entry); entry.tap()
        app.openAnimeActions(); app.buttons["detail-find-manga"].tap()
        let search = app.textFields["manga-search-title"]
        XCTAssertTrue(search.waitForExistence(timeout: 15))
        XCTAssertTrue((search.value as? String)?.contains("The Archivist") == true)
        XCTAssertTrue(app.buttons["manga-search-source-preview-en"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.appTab("My Library").isHittable)
        capture("Detail-To-Manga-Source-Search")
        app.appTab("My Library").tap()
        XCTAssertTrue(app.buttons["detail-actions"].waitForExistence(timeout: 10))
        app.returnToBrowsing(); app.revealInContent(entry)
        XCTAssertTrue(entry.label.contains("Watched 16/26"))
    }

    @MainActor private func launch(extra: [String] = []) -> XCUIApplication {
        continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-phase2-preview", "--ui-library-design-preview", "--ui-library-detail-preview",
            "--ui-playback-preview", "--ui-reset-content-preferences"] + extra
        app.launch()
        XCTAssertTrue(app.appTab("My Library").waitForExistence(timeout: 25)); app.appTab("My Library").tap()
        XCTAssertTrue(app.buttons["library-entry-1"].waitForExistence(timeout: 15))
        return app
    }
    @MainActor private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "Library-Detail-\(UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone")-\(name)"
        attachment.lifetime = .keepAlways; add(attachment)
    }
}
