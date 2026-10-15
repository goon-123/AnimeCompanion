import XCTest
import UIKit

final class PhaseThreePerformanceUITests: XCTestCase {
    @MainActor
    func testSharedArtworkDecodeCacheColorMemoryAndOrientation() {
        let app = launch()
        let status = app.staticTexts["artwork-check-status"]
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        let finished = NSPredicate(format: "label == %@", "Complete")
        expectation(for: finished, evaluatedWith: status)
        waitForExpectations(timeout: 15)
        let expected = [
            "artwork-shared-downloads": "Shared downloads: 1",
            "artwork-small-bitmap": "Bitmap: 512 × 256",
            "artwork-poster-color": "Poster color: red",
            "artwork-decoded-reuse": "Decoded bitmap: reused",
            "artwork-memory-clear": "Downloads after clear: 2",
            "artwork-refresh": "Downloads after refresh: 3, bypass: true",
            "artwork-orientation": "Oriented bitmap: 256 × 512"
        ]
        for (id, value) in expected { XCTAssertEqual(app.staticTexts[id].label, value, id) }
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Phase 3 shared artwork checks"; screenshot.lifetime = .keepAlways
        add(screenshot)
    }
    @MainActor
    func testMalformedImageCanBeRetriedThroughProductionPhaseView() {
        let app = launch()
        let retry = app.buttons["artwork-preview-retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["artwork-preview-phase"].label, "Artwork unavailable")
        retry.tap()
        let ready = NSPredicate(format: "label == %@", "Artwork ready")
        expectation(for: ready, evaluatedWith: app.staticTexts["artwork-preview-phase"])
        waitForExpectations(timeout: 10)
        XCTAssertFalse(app.buttons["artwork-preview-retry"].exists)
    }
    @MainActor
    private func launch() -> XCUIApplication {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-phase3-artwork-preview"]
        app.launch()
        return app
    }
}
