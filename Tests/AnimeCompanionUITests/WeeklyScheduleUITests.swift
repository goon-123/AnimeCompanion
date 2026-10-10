import XCTest
import UIKit

/// Fixed local dates and release fixtures exercise real scrolling without account writes.
final class WeeklyScheduleUITests: XCTestCase {
    @MainActor
    func testWeeklyOpensAtTodayKeepsAllDaysAndDoesNotSnapBackDuringBrowsing() throws {
        let app = launch(day: "2026-10-07", extra: ["--ui-schedule-delay-preview"])
        let list = app.collectionViews["schedule-weekly-list"].exists
            ? app.collectionViews["schedule-weekly-list"] : app.tables["schedule-weekly-list"]
        let today = day("2026-10-07", in: app)
        XCTAssertTrue(today.waitForExistence(timeout: 15)); XCTAssertTrue(today.isHittable)
        XCTAssertEqual(today.value as? String, "Today")
        XCTAssertTrue(app.buttons["schedule-jump-2026-10-07"].isSelected)
        capture("Weekly-Today-On-Opening")

        // All seven day shortcuts are present; horizontal gestures only move the strip.
        let weekdays = app.scrollViews["schedule-weekdays"]
        XCTAssertEqual(weekdays.buttons.count, 7)
        weekdays.swipeRight()
        app.buttons["schedule-jump-2026-10-04"].tap()
        assertAtTop(day("2026-10-04", in: app), app: app)
        XCTAssertTrue(app.buttons["release-entry-990200-sub-1"].waitForExistence(timeout: 30))
        assertAtTop(day("2026-10-04", in: app), app: app)
        capture("Weekly-Previous-Day-Manual-Browse")
        app.segmentedControls["schedule-release-type"].buttons["Dub"].tap()
        XCTAssertTrue(app.staticTexts["No listed releases for this day."].firstMatch.exists)
        assertAtTop(day("2026-10-04", in: app), app: app)
        app.segmentedControls["schedule-release-type"].buttons["All"].tap()

        app.buttons["schedule-this-week"].tap()
        assertAtTop(today, app: app)
        XCTAssertTrue(app.buttons["release-entry-990203-sub-4"].isHittable)
        // The list remains freely scrollable below and above the automatic target.
        if list.exists { list.swipeUp(); list.swipeDown() }
        else { app.swipeUp(); app.swipeDown() }
        XCTAssertTrue(app.navigationBars["Schedule"].exists)

        app.segmentedControls["schedule-mode"].buttons["Airing Now"].tap()
        app.segmentedControls["schedule-mode"].buttons["Weekly Schedule"].tap()
        assertAtTop(today, app: app)

        app.buttons["Next week"].tap()
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", ", Today")).firstMatch.exists)
        app.buttons["schedule-jump-2026-10-14"].tap()
        assertAtTop(day("2026-10-14", in: app), app: app)
        app.segmentedControls["schedule-mode"].buttons["Airing Now"].tap()
        app.segmentedControls["schedule-mode"].buttons["Weekly Schedule"].tap()
        XCTAssertTrue(app.buttons["schedule-week"].label.contains("Choose schedule date"))
        XCTAssertFalse(app.buttons["schedule-jump-2026-10-07"].exists)
        XCTAssertTrue(app.buttons["schedule-jump-2026-10-14"].exists)
        capture("Weekly-Other-Week-Stays-Selected")
        app.buttons["Previous week"].tap()
        assertAtTop(today, app: app)
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCUIDevice.shared.orientation = .landscapeLeft
            app.buttons["schedule-this-week"].tap(); assertAtTop(today, app: app)
            capture("Weekly-Today-iPad-Landscape")
            XCUIDevice.shared.orientation = .portrait
        }
    }

    @MainActor
    func testFollowingDayAndNewWeekReopenAtTheirOwnTodayIncludingEmptyReleaseDays() throws {
        let app = launch(day: "2026-10-07")
        assertAtTop(day("2026-10-07", in: app), app: app)
        app.terminate()
        app.launchArguments = arguments(day: "2026-10-08"); app.launch(); openWeekly(in: app)
        let tomorrow = day("2026-10-08", in: app)
        assertAtTop(tomorrow, app: app); XCTAssertEqual(tomorrow.value as? String, "Today")
        XCTAssertFalse(app.buttons["schedule-jump-2026-10-07"].isSelected)
        app.segmentedControls["schedule-release-type"].buttons["Dub"].tap()
        XCTAssertTrue(tomorrow.isHittable, "An empty release day must still have a Today target")
        capture("Weekly-Next-Day-Empty-Dub-Releases")
        app.terminate()
        app.launchArguments = arguments(day: "2026-10-11"); app.launch(); openWeekly(in: app)
        let nextWeek = day("2026-10-11", in: app)
        assertAtTop(nextWeek, app: app); XCTAssertEqual(nextWeek.value as? String, "Today")
        capture("Weekly-New-Week-Today")
    }

    private func arguments(day: String) -> [String] {
        ["--ui-schedule-preview", "--ui-schedule-day=\(day)", "--ui-reset-content-preferences"]
    }
    @MainActor private func launch(day: String, extra: [String] = []) -> XCUIApplication {
        continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(); app.launchArguments = arguments(day: day) + extra; app.launch()
        openWeekly(in: app); return app
    }
    @MainActor private func openWeekly(in app: XCUIApplication) {
        XCTAssertTrue(app.tabBars.buttons["Schedule"].waitForExistence(timeout: 20))
        app.tabBars.buttons["Schedule"].tap()
        app.segmentedControls["schedule-mode"].buttons["Weekly Schedule"].tap()
        XCTAssertTrue(app.buttons["schedule-week"].waitForExistence(timeout: 15))
    }
    @MainActor private func day(_ date: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "schedule-day-\(date)").firstMatch
    }
    @MainActor private func assertAtTop(_ target: XCUIElement, app: XCUIApplication) {
        let positioned = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            target.exists && target.isHittable &&
                target.frame.minY >= app.scrollViews["schedule-weekdays"].frame.maxY &&
                target.frame.minY < app.scrollViews["schedule-weekdays"].frame.maxY + 125
        }, object: nil)
        let result = XCTWaiter.wait(for: [positioned], timeout: 15)
        if result != .completed { capture("Weekly-Position-Failure") }
        XCTAssertEqual(result, .completed,
                       "Weekly Schedule must position \(target.identifier) below the fixed controls. Target: \(target.exists ? String(describing: target.frame) : "missing"); strip: \(app.scrollViews["schedule-weekdays"].frame)")
    }
    @MainActor private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "AnimeCompanion-\(UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone")-\(name)"
        attachment.lifetime = .keepAlways; add(attachment)
    }
}
