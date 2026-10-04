import XCTest

final class AppSmokeTests: XCTestCase {
    @MainActor
    func testExploreCategoryFilters() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.buttons["explore-category-trending"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.staticTexts["Continue watching"].exists)
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
        capture("Library-Grid-Three-Columns")
        app.terminate(); app.launch()
        app.tabBars.buttons["My Library"].tap()
        XCTAssertTrue(app.buttons["library-entry-1"].waitForExistence(timeout: 35))
        XCTAssertTrue(app.segmentedControls["library-layout"].buttons["Grid"].isSelected)
        XCTAssertTrue(app.buttons["library-columns"].label.contains("3 per row"))
        XCTAssertTrue(app.buttons["library-sort"].label.contains("AniList rating"))
        app.segmentedControls["library-layout"].buttons["List"].tap()
        capture("Library-List-Dub-Counts")
    }

    @MainActor
    func testMatureStoriesSettingAndManhwaDetails() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.buttons["Account and settings"].waitForExistence(timeout: 20))
        app.buttons["Account and settings"].tap()
        let toggle = app.switches["settings-mature-stories"]
        for _ in 0..<4 { if toggle.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(toggle.isHittable)
        if toggle.value as? String != "1" { toggle.tap() }
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["explore-category-matureAnime"].waitForExistence(timeout: 20))
        waitForLoadingToFinish("Finding your season…", in: app)
        XCTAssertFalse(app.buttons["explore-category-trending"].exists)
        capture("Mature-Stories-Explore")
        let manhwa = app.buttons["explore-category-matureManhwa"]
        for _ in 0..<5 { if manhwa.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(manhwa.isHittable); manhwa.tap()
        waitForLoadingToFinish("Loading anime…", in: app)
        let entry = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "discovery-entry-")).firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 35))
        capture("Mature-Manhwa-Category")
        entry.tap()
        XCTAssertTrue(app.buttons["expand-anime-cover"].waitForExistence(timeout: 35))
        XCTAssertTrue(app.navigationBars["Manhwa / Manga"].exists)
        XCTAssertFalse(app.staticTexts["English dub schedule"].exists)
        capture("Manhwa-Details")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Account and settings"].tap()
        let reset = app.switches["settings-mature-stories"]
        for _ in 0..<4 { if reset.isHittable { break }; app.swipeUp() }
        if reset.value as? String == "1" { reset.tap() }
        app.buttons["Done"].tap()
    }

    @MainActor
    func testScheduleNavigationAndSavedDubFilter() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.tabBars.buttons["Schedule"].waitForExistence(timeout: 20))
        app.tabBars.buttons["Schedule"].tap()
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
        capture("Settings")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["My Library"].waitForExistence(timeout: 10))
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
