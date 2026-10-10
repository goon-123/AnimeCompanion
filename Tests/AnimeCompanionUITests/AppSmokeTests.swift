import XCTest

final class AppSmokeTests: XCTestCase {
    @MainActor
    func testDisplayOptionsAndExploreDensityOnPhone() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        app.buttons["explore-display-options"].tap()
        XCTAssertTrue(app.navigationBars["Display options"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.sliders["explore-list-size"].isHittable)
        app.sliders["explore-list-size"].adjust(toNormalizedSliderPosition: 0.6)
        let saved = app.sliders["explore-list-size"].value as? String
        app.buttons["Done"].tap()
        app.terminate(); app.launch()
        app.buttons["explore-display-options"].tap()
        XCTAssertTrue(app.navigationBars["Display options"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.sliders["explore-list-size"].value as? String, saved)
        app.buttons["Done"].tap()
        revealExplore(app.buttons["explore-category-trending"], in: app)
        app.buttons["explore-category-trending"].tap()
        XCTAssertTrue(app.textFields["discovery-search"].waitForExistence(timeout: 15))
        waitForLoadingToFinish("Loading anime…", in: app)
        if !app.buttons["discovery-layout"].label.contains("Grid") {
            app.buttons["discovery-layout"].tap(); app.buttons["Grid"].tap()
        }
        app.buttons["discovery-columns"].tap()
        app.buttons["3 per row"].tap()
        XCTAssertTrue(app.buttons["discovery-columns"].label.contains("3 per row"))
        capture("Phone-Custom-Explore-Grid")
        app.buttons["discovery-layout"].tap(); app.buttons["List"].tap()
    }

    @MainActor
    func testExploreCategoryFilters() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.buttons["explore-category-trending"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.staticTexts["Continue watching"].exists)
        waitForLoadingToFinish("Finding your season…", in: app)
        revealExplore(app.buttons["explore-category-trending"], in: app)
        app.buttons["explore-category-trending"].tap()
        XCTAssertTrue(app.textFields["discovery-search"].waitForExistence(timeout: 15))
        waitForLoadingToFinish("Loading anime…", in: app)
        let entry = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "discovery-entry-")).firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 35))
        XCTAssertTrue(app.buttons["discovery-genre"].exists)
        XCTAssertTrue(app.buttons["discovery-year"].exists)
        XCTAssertTrue(app.buttons["discovery-season"].exists)
        capture("Expanded-Trending")
        app.buttons["discovery-format"].tap()
        XCTAssertTrue(app.buttons["Movie"].waitForExistence(timeout: 10))
        app.buttons["Movie"].tap()
        waitForLoadingToFinish("Loading anime…", in: app)
        XCTAssertTrue(entry.waitForExistence(timeout: 35))
        capture("Filtered-Category")
    }

    @MainActor
    func testLibraryLayoutsDubCountsAndRating() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--ui-library-preview"]; app.launch()
        XCTAssertTrue(app.tabBars.buttons["My Library"].waitForExistence(timeout: 20))
        app.tabBars.buttons["My Library"].tap()
        XCTAssertTrue(app.buttons["library-entry-1"].waitForExistence(timeout: 35))
        XCTAssertFalse(app.staticTexts["Continue watching"].exists)
        let layouts = app.segmentedControls["library-layout"]
        XCTAssertTrue(layouts.exists)
        layouts.buttons["Grid"].tap()
        XCTAssertTrue(app.buttons["library-columns"].waitForExistence(timeout: 10))
        app.buttons["library-columns"].tap()
        XCTAssertTrue(app.buttons["3 per row"].waitForExistence(timeout: 10))
        app.buttons["3 per row"].tap()
        app.buttons["library-sort"].tap()
        XCTAssertTrue(app.buttons["AniList rating"].waitForExistence(timeout: 10))
        app.buttons["AniList rating"].tap()
        let dub = app.staticTexts["library-dub-1"]
        XCTAssertTrue(dub.waitForExistence(timeout: 15))
        let known = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "26/26"), object: dub)
        XCTAssertEqual(XCTWaiter.wait(for: [known], timeout: 35), .completed)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "library-genres-1").firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "library-genres-1").firstMatch.label.contains("Action"))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "library-genres-1").firstMatch.label.contains("Sci-Fi"))
        capture("Library-Grid-Three-Columns")
        app.terminate(); app.launch()
        app.tabBars.buttons["My Library"].tap()
        XCTAssertTrue(app.buttons["library-entry-1"].waitForExistence(timeout: 35))
        XCTAssertTrue(app.segmentedControls["library-layout"].buttons["Grid"].isSelected)
        XCTAssertTrue(app.buttons["library-columns"].label.contains("3 per row"))
        XCTAssertTrue(app.buttons["library-sort"].label.contains("AniList rating"))
        app.segmentedControls["library-layout"].buttons["List"].tap()
        let selectedList = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"),
            object: app.segmentedControls["library-layout"].buttons["List"])
        XCTAssertEqual(XCTWaiter.wait(for: [selectedList], timeout: 10), .completed)
        XCTAssertFalse(app.buttons["library-columns"].exists)
        capture("Library-List-Dub-Counts")
    }

    @MainActor
    func testExploreAtAGlanceLibraryDubAndAiringIndicators() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--ui-library-preview"]; app.launch()
        XCTAssertTrue(app.tabBars.buttons["My Library"].waitForExistence(timeout: 20))
        app.tabBars.buttons["My Library"].tap()
        XCTAssertTrue(app.buttons["library-entry-1"].waitForExistence(timeout: 35))
        app.tabBars.buttons["Explore"].tap()
        waitForLoadingToFinish("Finding your season…", in: app)
        let shelfDub = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "explore-dub-")).firstMatch
        XCTAssertTrue(shelfDub.waitForExistence(timeout: 20))
        revealExplore(shelfDub, in: app)
        let shelfStatus = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "explore-library-")).firstMatch
        XCTAssertTrue(shelfStatus.exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "explore-next-")).firstMatch.exists)
        capture("Explore-Glance-Shelves")

        app.buttons["explore-search"].tap()
        let search = app.textFields["discovery-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 15))
        if app.buttons["discovery-layout"].label.contains("Grid") {
            app.buttons["discovery-layout"].tap()
            app.buttons["List"].tap()
        }
        search.tap(); search.typeText("Cowboy\n")
        XCTAssertTrue(app.buttons["discovery-entry-1"].waitForExistence(timeout: 35))
        let dub = app.staticTexts["explore-dub-1"]
        XCTAssertTrue(dub.exists)
        let known = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Dub available"), object: dub)
        XCTAssertEqual(XCTWaiter.wait(for: [known], timeout: 35), .completed)
        XCTAssertEqual(app.staticTexts["explore-library-1"].label, "Watching")
        XCTAssertTrue(app.staticTexts["explore-library-5"].waitForExistence(timeout: 20))
        XCTAssertEqual(app.staticTexts["explore-library-5"].label, "Completed")
        XCTAssertFalse(app.descendants(matching: .any)["explore-airing-1"].exists)
        XCTAssertFalse(app.staticTexts["explore-next-sub-1"].exists)
        capture("Explore-Glance-List")

        app.buttons["discovery-layout"].tap()
        app.buttons["Grid"].tap()
        XCTAssertTrue(app.staticTexts["explore-dub-1"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["explore-dub-1"].label, "Dub available")
        XCTAssertEqual(app.staticTexts["explore-library-5"].label, "Completed")
        XCTAssertFalse(app.descendants(matching: .any)["explore-airing-5"].exists)
        XCTAssertFalse(app.staticTexts["explore-next-sub-5"].exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "explore-genres-1").firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "explore-genres-1").firstMatch.label.contains("Action"))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "explore-genres-1").firstMatch.label.contains("Sci-Fi"))
        capture("Explore-Glance-Grid")
        app.buttons["discovery-layout"].tap()
        app.buttons["List"].tap()
    }

    @MainActor
    func testScheduleNavigationAndSavedDubFilter() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.tabBars.buttons["Schedule"].waitForExistence(timeout: 20))
        app.tabBars.buttons["Schedule"].tap()
        XCTAssertTrue(app.segmentedControls["schedule-mode"].buttons["Airing Now"].isSelected)
        app.segmentedControls["schedule-mode"].buttons["Weekly Schedule"].tap()
        let week = app.buttons["schedule-week"]
        XCTAssertTrue(week.waitForExistence(timeout: 15))
        let initial = week.value as? String
        XCTAssertNotNil(initial)
        app.buttons["Next week"].tap()
        XCTAssertNotEqual(week.value as? String, initial)
        app.buttons["Previous week"].tap()
        XCTAssertEqual(week.value as? String, initial)
        week.tap()
        XCTAssertTrue(app.navigationBars["Choose a date"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.datePickers.firstMatch.exists)
        capture("Schedule-Date-Picker")
        app.buttons["Done"].tap()
        app.segmentedControls["schedule-release-type"].buttons["Dub"].tap()
        waitForLoadingToFinish("Loading releases…", in: app)
        capture("Schedule-Dub-Filter")
        app.terminate(); app.launch()
        app.tabBars.buttons["Schedule"].tap()
        XCTAssertTrue(app.segmentedControls["schedule-mode"].buttons["Airing Now"].isSelected)
        app.segmentedControls["schedule-mode"].buttons["Weekly Schedule"].tap()
        XCTAssertTrue(app.segmentedControls["schedule-release-type"].buttons["Dub"].isSelected)
        app.segmentedControls["schedule-release-type"].buttons["All"].tap()
    }

    @MainActor
    func testLibrarySearchDetailCoverAndDubSchedule() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-library-preview"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["My Library"].waitForExistence(timeout: 20))
        app.tabBars.buttons["My Library"].tap()
        XCTAssertTrue(app.buttons["library-entry-1"].waitForExistence(timeout: 35))
        XCTAssertTrue(app.textFields["library-search"].exists)
        XCTAssertTrue(app.buttons["library-status-CURRENT"].exists)
        capture("My-Library-Reference")

        app.textFields["library-search"].tap()
        app.textFields["library-search"].typeText("Cowboy\n")
        XCTAssertTrue(app.buttons["library-entry-1"].exists)
        XCTAssertFalse(app.buttons["library-entry-205"].exists)
        app.buttons["library-entry-1"].tap()
        XCTAssertTrue(app.buttons["expand-anime-cover"].waitForExistence(timeout: 35))
        capture("Anime-detail")
        app.buttons["expand-anime-cover"].tap()
        XCTAssertTrue(app.buttons["Close enlarged image"].waitForExistence(timeout: 15))
        capture("Expanded-cover")
        app.buttons["Close enlarged image"].tap()
        XCTAssertTrue(app.buttons["expand-anime-cover"].waitForExistence(timeout: 15))
        for _ in 0..<6 {
            if app.staticTexts["English dub schedule"].isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(app.staticTexts["English dub schedule"].isHittable)
        XCTAssertTrue(app.staticTexts["Upcoming releases"].exists)
        capture("Anime-dub-schedule")
    }

    @MainActor
    func testFourTabsAndAccountSettings() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()

        for title in ["Explore", "Schedule", "My Library", "News"] {
            let tab = app.tabBars.buttons[title]
            XCTAssertTrue(tab.waitForExistence(timeout: 15), "Missing tab: \(title)")
            tab.tap()
            let navigationTitle = title == "News" ? "Anime News" : title
            XCTAssertTrue(app.navigationBars[navigationTitle].waitForExistence(timeout: 10))
            if title == "Explore" { waitForLoadingToFinish("Finding your season…", in: app) }
            if title == "Schedule" { waitForLoadingToFinish("Loading releases…", in: app) }
            if title == "News" { waitForLoadingToFinish("Loading headlines…", in: app) }
            XCTAssertFalse(app.staticTexts["Unable to read the saved AniList connection."].exists,
                           "The signed simulator app must be able to read its Keychain.")
            capture(title)
        }

        app.tabBars.buttons["My Library"].tap()
        app.buttons["Account and settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.textFields["AniList app ID"].exists)
        XCTAssertTrue(app.buttons["Connect AniList"].exists)
        XCTAssertFalse(app.switches["settings-mature-stories"].exists)
        capture("Settings")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["My Library"].waitForExistence(timeout: 10))
    }

    @MainActor
    private func revealExplore(_ element: XCUIElement, in app: XCUIApplication) {
        let scroll = app.scrollViews["explore-scroll"]
        for _ in 0..<12 { if element.isHittable { return }; scroll.swipeUp() }
        XCTAssertTrue(element.isHittable)
    }

    @MainActor
    private func waitForLoadingToFinish(_ label: String, in app: XCUIApplication) {
        let indicator = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
        let finished = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: indicator)
        XCTAssertEqual(XCTWaiter.wait(for: [finished], timeout: 45), .completed,
                       "Loading did not finish: \(label)")
    }

    @MainActor
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "AnimeCompanion-\(name.replacingOccurrences(of: " ", with: "-"))"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
