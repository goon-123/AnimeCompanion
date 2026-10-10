import XCTest
import UIKit

/// Uses public metadata and local preview progress, never account writes.
final class ExplorePresentationUITests: XCTestCase {
    @MainActor
    func testFeaturedAndShelfCardsAreCompactWithoutEpisodeSchedules() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = launchPreview()
        let featuredDub = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "featured-dub-")).firstMatch
        XCTAssertTrue(featuredDub.waitForExistence(timeout: 40))
        reveal(featuredDub, in: app)
        let id = String(featuredDub.identifier.dropFirst("featured-dub-".count))
        XCTAssertTrue(app.staticTexts["featured-title-\(id)"].exists)
        XCTAssertTrue(app.staticTexts["featured-library-\(id)"].exists)
        XCTAssertTrue(app.staticTexts["featured-genres-\(id)"].exists)
        assertNoEpisodeSchedules(in: app)
        capture("Explore-Simple-Featured")

        let shelfDub = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "explore-dub-")).firstMatch
        reveal(shelfDub, in: app)
        let shelfID = String(shelfDub.identifier.dropFirst("explore-dub-".count))
        XCTAssertTrue(app.staticTexts["explore-library-\(shelfID)"].exists)
        XCTAssertTrue(app.staticTexts["explore-genres-\(shelfID)"].exists)
        XCTAssertFalse(shelfDub.label.contains("episodes not listed"))
        XCTAssertFalse(shelfDub.label.contains(" released"))
        assertNoEpisodeSchedules(in: app)
        capture("Explore-Simple-Shelves")
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCUIDevice.shared.orientation = .landscapeLeft
            reveal(shelfDub, in: app)
            XCTAssertTrue(app.tabBars.buttons["Explore"].isHittable)
            assertNoEpisodeSchedules(in: app)
            capture("Explore-Simple-Shelves-iPad-Landscape")
            XCUIDevice.shared.orientation = .portrait
        }
    }

    @MainActor
    func testListAndGridRetainStatusDubGenresAndOnlyMarkAiringTitles() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = launchPreview()
        app.buttons["explore-search"].tap()
        let search = app.textFields["discovery-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 15))
        selectList(in: app)
        search.tap(); search.typeText("Cowboy\n")
        XCTAssertTrue(app.buttons["discovery-entry-1"].waitForExistence(timeout: 40))
        let dub = app.staticTexts["explore-dub-1"]
        let available = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Dub available"), object: dub)
        XCTAssertEqual(XCTWaiter.wait(for: [available], timeout: 35), .completed)
        XCTAssertEqual(app.staticTexts["explore-library-1"].label, "Watching")
        XCTAssertEqual(app.staticTexts["explore-library-5"].label, "Completed")
        XCTAssertFalse(app.descendants(matching: .any)["explore-airing-1"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["explore-airing-5"].exists)
        XCTAssertTrue(app.staticTexts["explore-genres-1"].label.contains("Sci-Fi"))
        assertNoEpisodeSchedules(in: app)
        capture("Explore-Simple-Tracked-List")

        app.buttons["discovery-entry-1"].tap()
        let detailedDub = app.staticTexts["detail-dub-count"]
        reveal(detailedDub, in: app)
        XCTAssertTrue(detailedDub.waitForExistence(timeout: 35))
        XCTAssertTrue(detailedDub.label.contains("26/26"), "Details must retain the full dub count")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(search.waitForExistence(timeout: 15))
        app.buttons["Clear category search"].tap()
        app.buttons["discovery-status"].tap()
        app.buttons["Releasing"].tap()
        let dot = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "explore-airing-")).firstMatch
        XCTAssertTrue(dot.waitForExistence(timeout: 40))
        reveal(dot, in: app)
        let id = String(dot.identifier.dropFirst("explore-airing-".count))
        XCTAssertEqual(dot.label, "Currently airing")
        XCTAssertEqual(app.staticTexts["explore-library-\(id)"].label, "Not on list")
        XCTAssertTrue(app.staticTexts["explore-dub-\(id)"].exists)
        assertNoEpisodeSchedules(in: app)
        capture("Explore-Simple-Airing-List")

        reveal(app.buttons["discovery-layout"], in: app, upward: false)
        app.buttons["discovery-layout"].tap(); app.buttons["discovery-layout-option-grid"].tap()
        app.buttons["discovery-columns"].tap(); app.buttons["discovery-column-option-2"].tap()
        let gridDot = app.descendants(matching: .any)["explore-airing-\(id)"]
        XCTAssertTrue(gridDot.waitForExistence(timeout: 15))
        reveal(app.staticTexts["explore-dub-\(id)"], in: app)
        XCTAssertEqual(gridDot.label, "Currently airing")
        XCTAssertTrue(app.staticTexts["explore-library-\(id)"].exists)
        XCTAssertTrue(app.staticTexts["explore-genres-\(id)"].exists)
        assertNoEpisodeSchedules(in: app)
        capture("Explore-Simple-Airing-Grid")
        reveal(app.buttons["discovery-layout"], in: app, upward: false)
        selectList(in: app)
    }

    @MainActor private func launchPreview() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-library-preview", "--ui-reset-content-preferences"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["My Library"].waitForExistence(timeout: 20))
        app.tabBars.buttons["My Library"].tap()
        XCTAssertTrue(app.buttons["library-entry-1"].waitForExistence(timeout: 40))
        app.tabBars.buttons["Explore"].tap()
        app.buttons["explore-dub-filter-toolbar"].tap()
        XCTAssertTrue(app.buttons["dub-filter-reset"].waitForExistence(timeout: 10))
        app.buttons["dub-filter-reset"].tap()
        let reset = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Selected"), object: app.buttons["dub-filter-all"])
        XCTAssertEqual(XCTWaiter.wait(for: [reset], timeout: 10), .completed)
        app.buttons["Done"].tap()
        return app
    }
    @MainActor private func selectList(in app: XCUIApplication) {
        if app.buttons["discovery-layout"].label.contains("Grid") {
            app.buttons["discovery-layout"].tap(); app.buttons["discovery-layout-option-list"].tap()
        }
    }
    @MainActor private func assertNoEpisodeSchedules(in app: XCUIApplication) {
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "explore-next-")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "(?i)(Next sub|Next dub|Dub estimate|Dub delayed) ·.*")).firstMatch.exists)
    }
    @MainActor private func reveal(_ element: XCUIElement, in app: XCUIApplication, upward: Bool = true) {
        for _ in 0..<16 {
            if element.isHittable { return }
            if upward { app.swipeUp() } else { app.swipeDown() }
        }
        XCTAssertTrue(element.isHittable, "Could not reveal \(element.identifier)")
    }
    @MainActor private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "AnimeCompanion-\(UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone")-\(name)"
        attachment.lifetime = .keepAlways; add(attachment)
    }
}
