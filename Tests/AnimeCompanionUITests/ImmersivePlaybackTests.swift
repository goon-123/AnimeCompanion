import XCTest
import UIKit

final class ImmersivePlaybackTests: XCTestCase {
    @MainActor
    func testExploreFeaturedArtworkIsFullBleedAndPages() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(); app.launch()
        let carousel = app.descendants(matching: .any).matching(identifier: "explore-featured-carousel").firstMatch
        XCTAssertTrue(carousel.waitForExistence(timeout: 60))
        XCTAssertEqual(carousel.frame.minX, app.frame.minX, accuracy: 2)
        XCTAssertEqual(carousel.frame.width, app.frame.width, accuracy: 2)
        XCTAssertGreaterThan(carousel.frame.height, app.frame.height * 0.6)
        XCTAssertLessThanOrEqual(carousel.frame.minY, app.navigationBars["Explore"].frame.minY)
        capture("Full-Bleed-Explore-First")
        let page = app.buttons["featured-page-1"]
        for _ in 0..<4 where !page.isHittable { app.swipeUp() }
        XCTAssertTrue(page.isHittable); page.tap()
        XCTAssertEqual(page.value as? String, "Selected")
        // Return to the top to inspect the complete poster and its tinted page.
        app.swipeDown()
        capture("Full-Bleed-Explore-Second")
        app.swipeUp()
        capture("Poster-Tinted-Explore-Shelves")
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCUIDevice.shared.orientation = .landscapeLeft
            app.swipeDown()
            XCTAssertEqual(carousel.frame.width, app.frame.width, accuracy: 2)
            capture("Full-Bleed-Explore-Landscape")
            XCUIDevice.shared.orientation = .portrait
        }
    }

    @MainActor
    func testSourcesAutoloadAndOneTapLaunchesWithoutConfirmation() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-library-preview", "--ui-playback-preview"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["My Library"].waitForExistence(timeout: 20))
        app.tabBars.buttons["My Library"].tap()
        let entry = app.buttons["library-entry-1"]
        XCTAssertTrue(entry.waitForExistence(timeout: 60)); entry.tap()
        let watch = app.buttons["watch-in-vidhub"]
        XCTAssertTrue(watch.waitForExistence(timeout: 45))
        for _ in 0..<8 where !watch.isHittable { app.swipeUp() }
        XCTAssertTrue(watch.isHittable); watch.tap()
        let source = app.buttons["playback-source-0"]
        XCTAssertTrue(source.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["find-playback-sources"].exists)
        XCTAssertEqual(app.textFields["playback-episode-number"].value as? String, "9")
        capture("Autoloaded-Sources")
        source.tap()
        XCTAssertTrue(app.staticTexts["Preview launch · Episode 9"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.navigationBars["Selected source"].exists)
        XCTAssertFalse(app.buttons["launch-vidhub"].exists)
        let field = app.textFields["playback-episode-number"]
        field.tap(); field.typeText(XCUIKeyboardKey.delete.rawValue + "10")
        app.buttons["Go"].tap()
        let updated = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "anilist:1:10.json"), object: source)
        XCTAssertEqual(XCTWaiter.wait(for: [updated], timeout: 10), .completed)
        source.tap()
        XCTAssertTrue(app.staticTexts["Preview launch · Episode 10"].waitForExistence(timeout: 10))
        capture("One-Tap-Player-Launch")
    }

    @MainActor
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "AnimeCompanion-\(UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone")-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
