import XCTest
import UIKit

final class TabletPresentationUITests: XCTestCase {
    @MainActor
    func testDefaultTabsAndAnimeDetailsUseFullWidthAndRetainBrowsing() {
        let app = launch()
        let orientations: [UIDeviceOrientation] = UIDevice.current.userInterfaceIdiom == .pad ? [.portrait, .landscapeLeft] : [.portrait]
        for orientation in orientations {
            rotate(orientation, app: app)
            for (tab, identifier) in [("Explore", "explore-scroll"), ("My Library", "library-scroll"), ("News", "news-list")] {
                app.appTab(tab).tap()
                let surface = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
                XCTAssertTrue(surface.waitForExistence(timeout: 15))
                XCTAssertGreaterThan(surface.frame.width, min(900, app.frame.width * 0.85))
                XCTAssertFalse(app.otherElements["anime-detail-placeholder"].exists)
                capture("Full-Width-\(tab)-\(orientation.isLandscape ? "Landscape" : "Portrait")")
            }
        }
        // Enter text before rotation; the hosted iPad simulator can miss native
        // keyboard focus immediately after its landscape navigation transition.
        if UIDevice.current.userInterfaceIdiom == .pad { rotate(.portrait, app: app) }
        app.appTab("Explore").tap(); app.buttons["explore-search"].tap()
        let search = app.textFields["discovery-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        // Confirm focus after rotation rather than sending keys to an unfocused
        // field; a second direct tap still has to open the real native keyboard.
        for _ in 0..<3 {
            search.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5)).tap()
            if app.keyboards.firstMatch.waitForExistence(timeout: 3) { break }
        }
        XCTAssertTrue(app.keyboards.firstMatch.exists, "Category search must receive keyboard focus")
        search.typeText("Phase\n")
        let entry = app.buttons["discovery-entry-1"]
        XCTAssertTrue(entry.waitForExistence(timeout: 15))
        app.revealInContent(entry); entry.tap()
        let detail = app.scrollViews["anime-detail-scroll"]
        XCTAssertTrue(detail.waitForExistence(timeout: 15))
        XCTAssertGreaterThan(detail.frame.width, app.frame.width * 0.90)
        capture("Full-Width-Anime-Detail")
        if UIDevice.current.userInterfaceIdiom == .pad {
            rotate(.landscapeLeft, app: app)
            waitForWidth(detail, minimum: app.frame.width * 0.90)
            capture("Full-Width-Anime-Detail-Landscape")
            rotate(.portrait, app: app)
        }
        app.returnToBrowsing()
        XCTAssertTrue(search.waitForExistence(timeout: 10)); XCTAssertEqual(search.value as? String, "Phase")
        XCTAssertTrue(entry.exists)
        capture("Full-Width-Return-Preserves-Search")
    }

    @MainActor
    func testIPadCanEnableSplitViewPersistItAndSwitchBackToFullWidth() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("iPad layout preference") }
        let app = launch(); rotate(.landscapeLeft, app: app)
        app.appTab("My Library").tap()
        setSplit(true, app: app)
        let browse = app.scrollViews["library-scroll"]
        XCTAssertTrue(browse.waitForExistence(timeout: 10))
        waitForWidth(browse, minimum: 460, maximum: app.frame.width * 0.80)
        XCTAssertGreaterThanOrEqual(browse.frame.width, 460)
        XCTAssertLessThan(browse.frame.width, app.frame.width * 0.80)
        let entry = app.buttons["library-entry-1"]
        app.revealInContent(entry); entry.tap()
        let detail = app.scrollViews["anime-detail-scroll"]
        XCTAssertTrue(detail.waitForExistence(timeout: 15))
        XCTAssertLessThanOrEqual(browse.frame.maxX, detail.frame.minX + 2)
        capture("Optional-Split-Browse-And-Detail")
        rotate(.portrait, app: app)
        XCTAssertTrue(app.staticTexts["detail-title"].waitForExistence(timeout: 10))
        capture("Optional-Split-Portrait")
        rotate(.landscapeLeft, app: app)
        app.appTab("Explore").tap()
        let hero = app.descendants(matching: .any).matching(identifier: "explore-featured-carousel").firstMatch
        XCTAssertTrue(hero.waitForExistence(timeout: 15))
        let explore = app.scrollViews["explore-scroll"]
        XCTAssertLessThanOrEqual(hero.frame.height, max(400, explore.frame.width * 1.5) + 4)
        capture("Split-Proportioned-Explore-Poster")
        app.appTab("News").tap()
        let news = app.descendants(matching: .any).matching(identifier: "news-list").firstMatch
        XCTAssertTrue(news.waitForExistence(timeout: 15)); XCTAssertGreaterThan(news.frame.width, 900)
        XCTAssertFalse(app.otherElements["anime-detail-placeholder"].exists)
        capture("News-Stays-Full-Width-In-Split-Mode")
        app.terminate(); app.launchArguments += ["--ui-keep-ipad-layout"]; app.launch()
        app.appTab("My Library").tap()
        XCTAssertTrue(browse.waitForExistence(timeout: 15)); waitForWidth(browse, minimum: 460, maximum: app.frame.width * 0.80)
        setSplit(false, app: app)
        XCTAssertTrue(browse.waitForExistence(timeout: 15)); waitForWidth(browse, minimum: app.frame.width * 0.90)
        app.terminate(); app.launch()
        app.appTab("My Library").tap()
        XCTAssertTrue(browse.waitForExistence(timeout: 15)); waitForWidth(browse, minimum: app.frame.width * 0.90)
        capture("Full-Width-Preference-Restored-After-Relaunch")
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor private func launch() -> XCUIApplication {
        continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-phase2-preview", "--ui-reset-content-preferences"]
        app.launch(); XCTAssertTrue(app.buttons["explore-search"].waitForExistence(timeout: 15))
        return app
    }
    @MainActor private func setSplit(_ enabled: Bool, app: XCUIApplication) {
        app.buttons["Account and settings"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
        app.revealSettingsDestination("settings-ipad-layout")
        let row = app.buttons["settings-ipad-layout"]
        app.revealInContent(row); XCTAssertTrue(row.waitForExistence(timeout: 10)); row.tap()
        let toggle = app.switches["settings-ipad-split-view"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10)); XCTAssertEqual(toggle.value as? String, enabled ? "0" : "1")
        // SwiftUI exposes the entire labeled row as a Switch. Its center can
        // be the inert label on iPad; target the actual trailing thumb.
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5)).withOffset(CGVector(dx: -20, dy: 0)).tap()
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", enabled ? "1" : "0"), object: toggle)
        let result = XCTWaiter.wait(for: [changed], timeout: 5)
        capture(enabled ? "Enable-Side-By-Side" : "Disable-Side-By-Side")
        XCTAssertEqual(result, .completed)
        app.navigationBars["iPad layout"].buttons["Appearance & layout"].tap()
        app.navigationBars["Appearance & layout"].buttons["Settings"].tap()
        app.navigationBars["Settings"].buttons["Done"].tap()
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.navigationBars["Settings"])
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 10), .completed)
    }
    @MainActor private func rotate(_ orientation: UIDeviceOrientation, app: XCUIApplication) {
        XCUIDevice.shared.orientation = orientation
        let resized = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            orientation.isLandscape ? app.frame.width > app.frame.height : app.frame.height > app.frame.width
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [resized], timeout: 10), .completed)
    }
    @MainActor private func waitForWidth(_ element: XCUIElement, minimum: CGFloat, maximum: CGFloat = .greatestFiniteMagnitude) {
        let sized = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            element.exists && element.frame.width >= minimum && element.frame.width < maximum
        }, object: nil)
        let result = XCTWaiter.wait(for: [sized], timeout: 10)
        if result != .completed {
            capture("Unexpected-Pane-Width")
            let tree = XCTAttachment(string: XCUIApplication().debugDescription)
            tree.name = "Unexpected-Pane-Width-Hierarchy"; tree.lifetime = .keepAlways; add(tree)
        }
        XCTAssertEqual(result, .completed, "Expected width \(minimum)..<\(maximum); actual frame \(element.frame)")
    }
    @MainActor private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "Tablet-Presentation-\(name.replacingOccurrences(of: " ", with: "-"))"
        attachment.lifetime = .keepAlways; add(attachment)
    }
}
