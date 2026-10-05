import XCTest
import UIKit

final class IPadLayoutTests: XCTestCase {
    @MainActor
    func testLibraryPosterGrowthComingUpGridDensityAndPersistence() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-library-preview", "--ui-layout-preview"]
        XCUIDevice.shared.orientation = .portrait; app.launch()
        selectTab("My Library", in: app)
        XCTAssertTrue(app.buttons["library-entry-1"].waitForExistence(timeout: 40))
        openDisplay("library", in: app)
        reveal(app.buttons["library-display-reset"], in: app)
        app.buttons["library-display-reset"].tap(); app.buttons["Done"].tap()
        app.segmentedControls["library-layout"].buttons["List"].tap()
        let initialHeight = app.buttons["library-entry-1"].frame.height

        openDisplay("library", in: app)
        let listSize = app.sliders["library-list-size"]
        XCTAssertTrue(listSize.isHittable)
        listSize.adjust(toNormalizedSliderPosition: 0.9)
        let savedList = listSize.value as? String
        let comingSize = app.sliders["library-coming-size"]
        reveal(comingSize, in: app); comingSize.adjust(toNormalizedSliderPosition: 0.9)
        let savedComing = comingSize.value as? String
        capture("Library-Display-Options")
        app.buttons["Done"].tap()
        XCTAssertGreaterThan(app.buttons["library-entry-1"].frame.height, initialHeight + 50,
                             "Increasing list poster width must visibly grow the actual row")
        capture("Library-Large-List-Portrait")
        app.buttons["library-coming-up"].tap()
        let release = app.buttons["release-entry-1-sub-9"]
        XCTAssertTrue(release.waitForExistence(timeout: 10))
        XCTAssertGreaterThan(release.frame.height, 240, "Coming-up artwork must use its own larger saved size")
        capture("Library-Large-Coming-Up-Portrait")
        app.buttons["library-coming-up"].tap()

        app.segmentedControls["library-layout"].buttons["Grid"].tap()
        chooseRows(3, button: "library-columns", in: app)
        let entries = [1, 199, 205].map { app.buttons["library-entry-\($0)"] }
        XCTAssertTrue(entries.allSatisfy { $0.exists })
        for entry in entries { XCTAssertEqual(entry.frame.minY, entries[0].frame.minY, accuracy: 3) }
        XCTAssertTrue(app.staticTexts["library-genres-1"].exists)
        XCTAssertTrue(app.staticTexts["library-genres-1"].label.contains("Sci-Fi"))
        let ordered = entries.sorted { $0.frame.minX < $1.frame.minX }
        XCTAssertGreaterThan(ordered[1].frame.minX, ordered[0].frame.minX)
        XCTAssertGreaterThan(ordered[2].frame.minX, ordered[1].frame.minX)
        capture("Library-Three-Columns-Portrait")
        rotate(.landscapeLeft, in: app)
        for entry in entries {
            XCTAssertGreaterThanOrEqual(entry.frame.minX, 0)
            XCTAssertLessThanOrEqual(entry.frame.maxX, app.frame.width)
        }
        capture("Library-Three-Columns-Landscape")
        app.terminate(); app.launch()
        selectTab("My Library", in: app)
        XCTAssertTrue(app.buttons["library-entry-1"].waitForExistence(timeout: 40))
        XCTAssertTrue(app.segmentedControls["library-layout"].buttons["Grid"].isSelected)
        XCTAssertTrue(app.buttons["library-columns"].label.contains("3 per row"))
        openDisplay("library", in: app)
        XCTAssertEqual(app.sliders["library-list-size"].value as? String, savedList)
        reveal(app.sliders["library-coming-size"], in: app)
        XCTAssertEqual(app.sliders["library-coming-size"].value as? String, savedComing)
        app.buttons["Done"].tap()
        app.segmentedControls["library-layout"].buttons["List"].tap()
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor
    func testExploreShelfListAndGridSizesRotateAndRemainIndependent() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--ui-library-preview"]
        XCUIDevice.shared.orientation = .portrait; app.launch()
        selectTab("My Library", in: app)
        XCTAssertTrue(app.buttons["library-entry-1"].waitForExistence(timeout: 40))
        openDisplay("library", in: app)
        let originalLibrarySize = app.sliders["library-list-size"].value as? String
        app.buttons["Done"].tap(); selectTab("Explore", in: app)
        waitForLoading("Finding your season…", in: app)
        let shelf = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "explore-shelf-entry-")).firstMatch
        XCTAssertTrue(shelf.waitForExistence(timeout: 35))
        openDisplay("explore", in: app)
        reveal(app.buttons["explore-display-reset"], in: app)
        app.buttons["explore-display-reset"].tap(); app.buttons["Done"].tap()
        let originalShelfWidth = shelf.frame.width
        openDisplay("explore", in: app)
        let shelfSize = app.sliders["explore-shelf-size"]
        reveal(shelfSize, in: app); shelfSize.adjust(toNormalizedSliderPosition: 0.9)
        let savedShelf = shelfSize.value as? String
        app.buttons["Done"].tap()
        XCTAssertGreaterThan(shelf.frame.width, originalShelfWidth + 70)
        capture("Explore-Large-Shelves-Portrait")

        app.buttons["explore-category-trending"].tap()
        XCTAssertTrue(app.textFields["discovery-search"].waitForExistence(timeout: 15))
        if app.buttons["discovery-layout"].label.contains("Grid") {
            app.buttons["discovery-layout"].tap(); app.buttons["List"].tap()
        }
        waitForLoading("Loading anime…", in: app)
        let entry = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "discovery-entry-")).firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 35))
        let initialListHeight = entry.frame.height
        openDisplay("explore", in: app)
        app.sliders["explore-list-size"].adjust(toNormalizedSliderPosition: 1)
        app.buttons["Done"].tap()
        XCTAssertGreaterThan(entry.frame.height, initialListHeight + 60)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "explore-dub-")).firstMatch.exists)
        capture("Explore-Large-List-Portrait")

        app.buttons["discovery-layout"].tap(); app.buttons["Grid"].tap()
        chooseRows(2, button: "discovery-columns", in: app)
        let initialGridWidth = entry.frame.width
        openDisplay("explore", in: app)
        app.sliders["explore-grid-size"].adjust(toNormalizedSliderPosition: 0.25)
        app.buttons["Done"].tap()
        XCTAssertLessThan(entry.frame.width, initialGridWidth - 70,
                          "Maximum grid poster size must change the artwork even with the same row count")
        openDisplay("explore", in: app)
        app.sliders["explore-grid-size"].adjust(toNormalizedSliderPosition: 1)
        app.buttons["Done"].tap()
        let twoColumnWidth = entry.frame.width
        chooseRows(3, button: "discovery-columns", in: app)
        XCTAssertGreaterThan(twoColumnWidth, entry.frame.width + 70)
        capture("Explore-Three-Columns-Portrait")
        rotate(.landscapeLeft, in: app)
        capture("Explore-Three-Columns-Landscape")
        chooseRows(8, button: "discovery-columns", in: app)
        capture("Explore-Eight-Columns-Landscape")
        let genres = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "explore-genres-")).firstMatch
        XCTAssertTrue(genres.exists)
        XCTAssertTrue(genres.label.hasPrefix("Genres: "))
        let firstRow = Array(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "discovery-entry-")).allElementsBoundByIndex.prefix(8))
        XCTAssertEqual(firstRow.count, 8)
        for tile in firstRow {
            XCTAssertEqual(tile.frame.minY, firstRow[0].frame.minY, accuracy: 3)
            XCTAssertGreaterThanOrEqual(tile.frame.minX, 0)
            XCTAssertLessThanOrEqual(tile.frame.maxX, app.frame.width)
        }
        chooseRows(3, button: "discovery-columns", in: app)
        app.terminate(); app.launch()
        openDisplay("explore", in: app)
        reveal(app.sliders["explore-shelf-size"], in: app)
        XCTAssertEqual(app.sliders["explore-shelf-size"].value as? String, savedShelf)
        app.buttons["Done"].tap(); selectTab("My Library", in: app)
        openDisplay("library", in: app)
        XCTAssertEqual(app.sliders["library-list-size"].value as? String, originalLibrarySize)
        app.buttons["Done"].tap()
        selectTab("Explore", in: app)
        app.buttons["explore-category-trending"].tap()
        XCTAssertTrue(app.textFields["discovery-search"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["discovery-layout"].label.contains("Grid"))
        XCTAssertTrue(app.buttons["discovery-columns"].label.contains("3 per row"))
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor
    func testAllTabsDetailAndFullScreenArtworkInBothOrientations() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--ui-library-preview"]
        XCUIDevice.shared.orientation = .portrait; app.launch()
        rotate(.landscapeLeft, in: app)
        for title in ["Explore", "Schedule", "News", "My Library"] {
            selectTab(title, in: app)
            XCTAssertTrue(app.navigationBars[title == "News" ? "Anime News" : title].waitForExistence(timeout: 15))
            if title == "Explore" { waitForLoading("Finding your season…", in: app) }
            if title == "Schedule" { waitForLoading("Loading releases…", in: app) }
            if title == "News" { waitForLoading("Loading headlines…", in: app) }
            capture("\(title)-Landscape")
        }
        XCTAssertTrue(app.buttons["library-entry-1"].waitForExistence(timeout: 40))
        app.textFields["library-search"].tap(); app.textFields["library-search"].typeText("Cowboy\n")
        app.buttons["library-entry-1"].tap()
        XCTAssertTrue(app.buttons["expand-anime-cover"].waitForExistence(timeout: 35))
        capture("Detail-Landscape")
        app.buttons["expand-anime-cover"].tap()
        XCTAssertTrue(app.buttons["Close enlarged image"].waitForExistence(timeout: 15))
        capture("Expanded-Artwork-Landscape")
        rotate(.portrait, in: app)
        XCTAssertTrue(app.buttons["Close enlarged image"].isHittable)
        capture("Expanded-Artwork-Portrait")
        app.buttons["Close enlarged image"].tap()
        XCTAssertTrue(app.buttons["expand-anime-cover"].isHittable)
        capture("Detail-Portrait")
        for _ in 0..<6 {
            if app.staticTexts["English dub schedule"].isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(app.staticTexts["English dub schedule"].isHittable)
        capture("Detail-Dub-Schedule-Portrait")
    }

    @MainActor
    private func selectTab(_ title: String, in app: XCUIApplication) {
        // iPadOS can put the native tab bar at the top instead of the bottom.
        let tab = app.tabBars.buttons[title].firstMatch
        if tab.waitForExistence(timeout: 10) { tab.tap() }
        else {
            let button = app.buttons.matching(NSPredicate(format: "label == %@", title)).firstMatch
            XCTAssertTrue(button.waitForExistence(timeout: 10)); button.tap()
        }
    }
    @MainActor
    private func openDisplay(_ scope: String, in app: XCUIApplication) {
        let button = app.buttons["\(scope)-display-options"].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 15)); button.tap()
        XCTAssertTrue(app.navigationBars["Display options"].waitForExistence(timeout: 10))
    }
    @MainActor
    private func chooseRows(_ count: Int, button: String, in app: XCUIApplication) {
        app.buttons[button].tap()
        let scope = button == "library-columns" ? "library" : "discovery"
        let option = app.buttons["\(scope)-column-option-\(count)"]
        XCTAssertTrue(option.waitForExistence(timeout: 10)); option.tap()
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: option)
        XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 10), .completed)
        XCTAssertTrue(app.buttons[button].label.contains("\(count) per row"))
    }
    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<6 {
            if element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }
    @MainActor
    private func rotate(_ orientation: UIDeviceOrientation, in app: XCUIApplication) {
        XCUIDevice.shared.orientation = orientation
        let predicate = NSPredicate { _, _ in
            orientation.isLandscape ? app.frame.width > app.frame.height : app.frame.height > app.frame.width
        }
        let resized = XCTNSPredicateExpectation(predicate: predicate, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [resized], timeout: 15), .completed, "iPad must rotate natively, not stay in an iPhone-size window")
    }
    @MainActor
    private func waitForLoading(_ label: String, in app: XCUIApplication) {
        let indicator = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
        let finished = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: indicator)
        XCTAssertEqual(XCTWaiter.wait(for: [finished], timeout: 45), .completed)
    }
    @MainActor
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "AnimeCompanion-iPad-\(name.replacingOccurrences(of: " ", with: "-"))"
        attachment.lifetime = .keepAlways; add(attachment)
    }
}
