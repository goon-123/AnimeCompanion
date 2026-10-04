import XCTest

final class AppSmokeTests: XCTestCase {
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
