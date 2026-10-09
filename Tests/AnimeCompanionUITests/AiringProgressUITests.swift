import XCTest
import UIKit

final class AiringProgressUITests: XCTestCase {
    @MainActor
    func testAiringCatchUpBadgesShowProgressNextTimeAndBehindFilterInBothLayouts() throws {
        continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-library-preview", "--ui-airing-preview", "--ui-reset-content-preferences"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["My Library"].waitForExistence(timeout: 30)); app.tabBars.buttons["My Library"].tap()
        let behind = app.staticTexts["library-airing-status-990101"]
        XCTAssertTrue(behind.waitForExistence(timeout: 45)); reveal(behind, app: app)
        XCTAssertEqual(behind.label, "2 episodes behind")
        XCTAssertTrue(app.staticTexts["library-airing-progress-990101"].label.contains("Watched Ep 4 · Aired Ep 6"))
        XCTAssertTrue(app.staticTexts["library-airing-next-990101"].label.contains("Next SUB · Ep 7"))
        capture("Airing-Behind-List")
        let caught = app.staticTexts["library-airing-status-990102"]
        reveal(caught, app: app); XCTAssertEqual(caught.label, "Caught up")
        XCTAssertTrue(app.staticTexts["library-airing-next-990102"].label.contains("Next SUB · Ep 7"))
        capture("Airing-Caught-Up-List")
        let finished = app.buttons["library-entry-990103"]
        reveal(finished, app: app); XCTAssertTrue(finished.exists)
        XCTAssertFalse(app.staticTexts["library-airing-status-990103"].exists)
        let filter = app.buttons["library-behind-filter"]
        reveal(filter, app: app, upward: false); filter.tap()
        XCTAssertEqual(filter.value as? String, "Behind only")
        XCTAssertTrue(app.buttons["library-entry-990101"].exists)
        XCTAssertFalse(app.buttons["library-entry-990102"].exists)
        let layout = app.segmentedControls["library-layout"]
        reveal(layout, app: app, upward: false); layout.buttons["Grid"].tap()
        XCTAssertTrue(behind.waitForExistence(timeout: 10)); capture("Airing-Behind-Grid")
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCUIDevice.shared.orientation = .landscapeLeft
            XCTAssertTrue(behind.exists); capture("Airing-Behind-iPad-Landscape")
            XCUIDevice.shared.orientation = .portrait
        }
    }
    @MainActor
    func testLibraryWatchAutosearchesAniListEpisodeInsteadOfStaleResumeAndAllowsOverride() throws {
        continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-library-preview", "--ui-playback-preview", "--ui-playback-stale-resume", "--ui-reset-content-preferences"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["My Library"].waitForExistence(timeout: 30)); app.tabBars.buttons["My Library"].tap()
        let watch = app.buttons["library-watch-1"]
        XCTAssertTrue(watch.waitForExistence(timeout: 45)); reveal(watch, app: app); watch.tap()
        let field = app.textFields["playback-episode-number"]
        XCTAssertTrue(field.waitForExistence(timeout: 15)); XCTAssertEqual(field.value as? String, "9")
        let source = app.buttons["playback-source-0"]
        XCTAssertTrue(source.waitForExistence(timeout: 15)); XCTAssertTrue(source.label.contains("anilist:1:9.json"))
        XCTAssertTrue(app.staticTexts["playback-anilist-progress"].label.contains("8 episodes watched"))
        source.tap(); XCTAssertTrue(app.staticTexts["Preview launch · Episode 9"].waitForExistence(timeout: 10))
        field.tap(); field.typeText(XCUIKeyboardKey.delete.rawValue + "10")
        app.buttons["playback-episode-go"].tap()
        let updated = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "anilist:1:10.json"), object: source)
        XCTAssertEqual(XCTWaiter.wait(for: [updated], timeout: 15), .completed)
        capture("Progress-Aware-VidHub-Search")
        app.buttons["Done"].tap()
    }
    @MainActor private func reveal(_ element: XCUIElement, app: XCUIApplication, upward: Bool = true) {
        for _ in 0..<16 { if element.isHittable { return }; if upward { app.swipeUp() } else { app.swipeDown() } }
        XCTAssertTrue(element.isHittable)
    }
    @MainActor private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "AnimeCompanion-\(UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone")-\(name)"
        attachment.lifetime = .keepAlways; add(attachment)
    }
}
