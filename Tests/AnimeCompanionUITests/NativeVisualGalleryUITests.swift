import XCTest
import UIKit

final class NativeVisualGalleryUITests: XCTestCase {
    @MainActor func testCompleteNativeGalleryPagesAndImageViewerOnPhoneAndTablet() {
        let app = launch()
        app.appTab("News").tap()
        let visuals = app.buttons["news-open-visuals"]
        XCTAssertTrue(visuals.waitForExistence(timeout: 10)); visuals.tap()
        let title = app.buttons["anime-visual-1"]
        XCTAssertTrue(title.waitForExistence(timeout: 15)); title.tap()
        waitForLabel("8 images", on: app.staticTexts["visuals-image-count"])
        XCTAssertEqual(app.webViews.count, 0)
        for (index, name) in ["Roxy", "Sylphiette", "Rudeus", "Eris"].enumerated() {
            let card = app.buttons["visual-card-liveChart-\(index)"]
            app.revealInContent(card)
            XCTAssertTrue(card.label.contains(name))
        }
        capture("Character-Visuals", app)
        let first = app.buttons["visual-card-liveChart-0"]
        app.revealInContent(first, upward: false); first.tap()
        waitForLabel("1 of 8", on: app.staticTexts["expanded-image-position"])
        XCTAssertEqual(app.staticTexts["expanded-image-caption"].label, "Roxy")
        XCTAssertFalse(app.buttons["expanded-image-previous"].isEnabled)
        app.buttons["expanded-image-next"].tap()
        waitForLabel("2 of 8", on: app.staticTexts["expanded-image-position"])
        XCTAssertEqual(app.staticTexts["expanded-image-caption"].label, "Sylphiette")
        let viewer = app.descendants(matching: .any).matching(identifier: "expanded-anime-image").firstMatch
        viewer.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.45)).press(forDuration: 0.05,
            thenDragTo: viewer.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.45)))
        waitForLabel("3 of 8", on: app.staticTexts["expanded-image-position"])
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCUIDevice.shared.orientation = .landscapeLeft
            waitForLabel("3 of 8", on: app.staticTexts["expanded-image-position"])
        }
        capture("Native-Viewer", app)
        app.buttons["Close enlarged image"].tap()
        XCUIDevice.shared.orientation = .portrait
        let details = app.buttons["visuals-anime-details"]
        app.revealInContent(details, upward: false); details.tap()
        XCTAssertTrue(app.scrollViews["anime-detail-scroll"].waitForExistence(timeout: 10))
    }
    @MainActor func testDeniedGalleryFallsBackInsideTheAppAndCanRefresh() {
        let app = launch(denied: true)
        app.appTab("My Library").tap()
        let title = app.buttons["library-entry-1"]
        app.revealInContent(title); title.tap()
        let visuals = app.buttons["detail-open-visuals"]
        app.revealInContent(visuals); visuals.tap()
        waitForLabel("4 images", on: app.staticTexts["visuals-image-count"])
        XCTAssertTrue(app.staticTexts["visuals-notice"].label.contains("MyAnimeList"))
        let refresh = app.buttons["visuals-refresh"]
        app.revealInContent(refresh); refresh.tap()
        XCTAssertTrue(refresh.waitForExistence(timeout: 10))
        waitForLabel("4 images", on: app.staticTexts["visuals-image-count"])
        let card = app.buttons["visual-card-myAnimeList-0"]
        app.revealInContent(card); card.tap()
        waitForLabel("1 of 4", on: app.staticTexts["expanded-image-position"])
        XCTAssertEqual(app.webViews.count, 0)
        capture("MAL-Fallback", app)
        app.buttons["Close enlarged image"].tap()
    }
    @MainActor private func launch(denied: Bool = false) -> XCUIApplication {
        continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-phase2-preview", "--ui-reset-content-preferences", "--ui-catalog-loading-preview", "--ui-visuals-preview"]
        if denied { app.launchArguments.append("--ui-visuals-denied") }
        app.launch(); XCTAssertTrue(app.buttons["explore-search"].waitForExistence(timeout: 15))
        return app
    }
    @MainActor private func waitForLabel(_ value: String, on element: XCUIElement) {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND label == %@", value), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 15), .completed)
    }
    @MainActor private func capture(_ name: String, _ app: XCUIApplication) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "Gallery-\(UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone")-\(name)"
        image.lifetime = .keepAlways; add(image)
    }
}
