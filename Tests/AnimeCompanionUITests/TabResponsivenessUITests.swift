import XCTest

final class TabResponsivenessUITests: XCTestCase {
    @MainActor func testWarmDockSwitchesRetainCatalogsScrollPositionAndClearHeaders() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-phase2-preview", "--ui-catalog-loading-preview", "--ui-reset-content-preferences", "--ui-redesign-preview", "--ui-redesign-dark", "--ui-unified-preview", "--ui-tab-performance"]
        app.launch()
        XCTAssertTrue(app.buttons["dock-tab-home"].waitForExistence(timeout: 25))
        var measurements: [[String: Double]] = []
        for tab in ["explore", "library", "home", "explore", "library", "explore"] {
            let button = app.buttons["dock-tab-" + tab]
            XCTAssertTrue(button.isHittable); button.tap()
            let value = try XCTUnwrap(app.tabBars["companion-dock"].value as? String)
            let metric = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(value.utf8)) as? [String: Double])
            measurements.append(metric)
            XCTAssertEqual(metric["rootReassignments"], 0, "A switch must reuse its native hosting roots")
            XCTAssertLessThan(try XCTUnwrap(metric["milliseconds"]), 2000, "Dock selection must not wait for the five-second catalog fixture")
        }
        let metrics = XCTAttachment(string: String(decoding: try JSONSerialization.data(withJSONObject: measurements, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
        metrics.name = "Owned-native-tab-timings-and-frame-gaps"; metrics.lifetime = .keepAlways; add(metrics)
        let firstAnime = app.buttons["featured-poster-1"]
        XCTAssertTrue(firstAnime.waitForExistence(timeout: 20))
        let switcher = app.buttons["explore-media-switch"]
        switcher.tap()
        let spotlight = app.descendants(matching: .any).matching(identifier: "reading-spotlight").firstMatch
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Ready"), object: spotlight)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 20), .completed)
        let firstFrame = spotlight.frame
        capture("Reading-Spotlight-Ready", app)
        switcher.tap()
        XCTAssertTrue(firstAnime.isHittable, "Returning to Anime must not recreate an empty catalog")
        switcher.tap()
        XCTAssertEqual(spotlight.value as? String, "Ready")
        XCTAssertEqual(spotlight.frame.minY, firstFrame.minY, accuracy: 1)
        XCTAssertEqual(spotlight.frame.height, firstFrame.height, accuracy: 1)
        capture("Reading-Spotlight-Retained", app)
        app.swipeUp()
        XCTAssertTrue(app.buttons["account-switcher"].isHittable)
        XCTAssertTrue(app.buttons["explore-customize"].isHittable)
        capture("Reading-Clear-Glass-Header-Scrolled", app)
        app.buttons["dock-tab-home"].tap()
        app.swipeUp()
        XCTAssertTrue(app.buttons["home-actions"].isHittable)
        capture("Home-Clear-Native-Header-Scrolled", app)
        app.buttons["dock-tab-library"].tap()
        let entry = app.buttons["library-entry-990104"]
        app.revealInContent(entry)
        XCTAssertTrue(entry.isHittable)
        let position = entry.frame.minY
        capture("Library-Clear-Native-Header-Scrolled", app)
        app.buttons["dock-tab-explore"].tap()
        app.buttons["dock-tab-library"].tap()
        XCTAssertEqual(entry.frame.minY, position, accuracy: 2, "Library scroll position must survive tab switches")
        XCTAssertEqual(app.tabBars.count, 1)
    }
    @MainActor private func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
