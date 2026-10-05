import XCTest
import UIKit

/// The same navigation regression runs on iPhone and the 11-inch iPad Pro.
final class DiscoveryNavigationTests: XCTestCase {
    @MainActor
    func testPopularSeasonKeepsVisibleResultsPaginationAndFiltersAfterDetails() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(); app.launch()
        let display = app.buttons["explore-display-options"]
        XCTAssertTrue(display.waitForExistence(timeout: 15)); display.tap()
        XCTAssertTrue(app.navigationBars["Display options"].waitForExistence(timeout: 10))
        reveal(app.buttons["explore-display-reset"], scrolling: app, upward: true)
        app.buttons["explore-display-reset"].tap(); app.buttons["Done"].tap()

        let category = app.buttons["explore-category-seasonal"]
        reveal(category, scrolling: app, upward: true); category.tap()
        let scroll = app.scrollViews["discovery-scroll"]
        XCTAssertTrue(app.textFields["discovery-search"].waitForExistence(timeout: 15))
        waitForTitles(in: app)

        for layout in ["List", "Grid"] {
            reveal(app.buttons["discovery-layout"], scrolling: scroll, upward: false)
            choose(layout, in: app)
            if layout == "Grid" { chooseColumns(2, in: app) }
            for round in 0..<3 {
                if round > 0 { scroll.swipeUp() }
                try openVisibleTitleAndReturn(in: app, swipeBack: round == 2)
            }
            capture("Popular-Season-\(layout)-After-Repeated-Back")
        }

        // A return must retain appended pages, not replace them with page one.
        reveal(app.buttons["discovery-layout"], scrolling: scroll, upward: false)
        chooseColumns(8, in: app)
        let more = app.buttons["discovery-more"]
        if more.exists {
            reveal(more, scrolling: scroll, upward: true)
            let previous = app.staticTexts["discovery-count"].label
            more.tap()
            let appended = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", previous),
                                                     object: app.staticTexts["discovery-count"])
            XCTAssertEqual(XCTWaiter.wait(for: [appended], timeout: 35), .completed)
            try openVisibleTitleAndReturn(in: app)
            capture("Popular-Season-Paginated-Return")
        }

        reveal(app.buttons["discovery-genre"], scrolling: scroll, upward: false)
        app.buttons["discovery-genre"].tap(); app.buttons["Action"].tap()
        waitForTitles(in: app)
        app.buttons["discovery-sort"].tap(); app.buttons["AniList rating"].tap()
        waitForTitles(in: app)
        try openVisibleTitleAndReturn(in: app)
        reveal(app.buttons["discovery-genre"], scrolling: scroll, upward: false)
        XCTAssertEqual(app.buttons["discovery-genre"].label, "Action")
        XCTAssertTrue(app.buttons["discovery-sort"].label.contains("AniList rating"))
        XCTAssertTrue(app.buttons["discovery-layout"].label.contains("Grid"))
        XCTAssertTrue(app.buttons["discovery-columns"].label.contains("8 per row"))
        let genre = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "explore-genres-")).firstMatch
        XCTAssertTrue(genre.exists); XCTAssertTrue(genre.label.contains("Action"))
        capture("Popular-Season-Grid-Genres-And-Saved-Filters")
    }

    @MainActor
    private func openVisibleTitleAndReturn(in app: XCUIApplication, swipeBack: Bool = false) throws {
        let viewport = app.frame
        let entries = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "discovery-entry-"))
        let visible = entries.allElementsBoundByIndex.first {
            $0.isHittable && $0.frame.midY > app.navigationBars.firstMatch.frame.maxY &&
                $0.frame.midY < viewport.maxY - 80
        }
        let selected = try XCTUnwrap(visible, "Returning to the category must leave real titles visible")
        let identifier = selected.identifier
        let count = app.staticTexts["discovery-count"].label
        selected.tap()
        XCTAssertTrue(app.buttons["expand-anime-cover"].waitForExistence(timeout: 35))
        if swipeBack {
            let edge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
            edge.press(forDuration: 0.1, thenDragTo: end)
        } else { app.navigationBars.buttons.firstMatch.tap() }
        XCTAssertTrue(app.navigationBars["Popular this season"].waitForExistence(timeout: 10))
        let retained = app.buttons[identifier]
        let visibleAgain = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: retained)
        XCTAssertEqual(XCTWaiter.wait(for: [visibleAgain], timeout: 10), .completed,
                       "Popping details must preserve the visible title and scroll position")
        XCTAssertEqual(app.staticTexts["discovery-count"].label, count, "Loaded pages must survive back navigation")
        XCTAssertFalse(app.staticTexts["No matching titles"].exists)
    }

    @MainActor
    private func choose(_ layout: String, in app: XCUIApplication) {
        if !app.buttons["discovery-layout"].label.contains(layout) {
            app.buttons["discovery-layout"].tap(); app.buttons[layout].tap()
        }
    }
    @MainActor
    private func chooseColumns(_ columns: Int, in app: XCUIApplication) {
        app.buttons["discovery-columns"].tap(); app.buttons["\(columns) per row"].tap()
    }
    @MainActor
    private func waitForTitles(in app: XCUIApplication) {
        let loaded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "discovery-entry-")).firstMatch.exists &&
                !app.staticTexts["Loading anime…"].exists
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [loaded], timeout: 40), .completed)
    }
    @MainActor
    private func reveal(_ element: XCUIElement, scrolling surface: XCUIElement, upward: Bool) {
        for _ in 0..<25 {
            if element.isHittable { return }
            if upward { surface.swipeUp() } else { surface.swipeDown() }
        }
        XCTAssertTrue(element.isHittable, "Could not reveal \(element.identifier)")
    }
    @MainActor
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "AnimeCompanion-\(UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone")-\(name)"
        attachment.lifetime = .keepAlways; add(attachment)
    }
}
