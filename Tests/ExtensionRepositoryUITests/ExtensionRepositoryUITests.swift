import XCTest

final class ExtensionRepositoryUITests: XCTestCase {
    private let repository = "https://jormungandr.ofchaos.com/releases/sora/recommended/Jorm.json"

    @MainActor private func openEditor() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--repository-editor-ui"]
        app.launch()
        let open = app.buttons["Open repository editor"]
        XCTAssertTrue(open.waitForExistence(timeout: 30))
        let ready = NSPredicate(format: "enabled == true")
        expectation(for: ready, evaluatedWith: open)
        waitForExpectations(timeout: 30)
        open.tap()
        XCTAssertTrue(app.textFields["extensions-repository-url"].waitForExistence(timeout: 10))
        return app
    }

    @MainActor func testDedicatedPasteKeepsDraftOpenAndSelectsSora() {
        continueAfterFailure = false
        let app = openEditor()
        app.buttons["extensions-paste-repository"].tap()
        let field = app.textFields["extensions-repository-url"]
        let pasted = NSPredicate(format: "value == %@", repository)
        let inserted = XCTNSPredicateExpectation(predicate: pasted, object: field)
        XCTAssertEqual(XCTWaiter.wait(for: [inserted], timeout: 10), .completed, app.debugDescription)
        let system = app.buttons["extensions-repository-system"]
        XCTAssertTrue(system.label.contains("Sora") || (system.value as? String)?.contains("Sora") == true)
        XCTAssertTrue(app.buttons["extensions-save-repository"].isEnabled)
        app.navigationBars["Add repository"].swipeDown()
        XCTAssertTrue(field.exists, "Pasting or a dismissal gesture must not close the editor.")
        XCTAssertEqual(field.value as? String, repository)
        app.buttons["Cancel"].tap()
        XCTAssertFalse(field.exists)
    }

    @MainActor func testNativePasteMenuAndReturnDoNotSubmitOrDismiss() {
        continueAfterFailure = false
        let app = openEditor()
        let field = app.textFields["extensions-repository-url"]
        field.tap(); field.press(forDuration: 1.2)
        let paste = app.menuItems["Paste"].firstMatch
        if paste.waitForExistence(timeout: 3) { paste.tap() }
        else {
            let button = app.buttons.matching(NSPredicate(format: "label == 'Paste' AND identifier != 'extensions-paste-repository'")).firstMatch
            XCTAssertTrue(button.waitForExistence(timeout: 5)); button.tap()
        }
        expectation(for: NSPredicate(format: "value == %@", repository), evaluatedWith: field)
        waitForExpectations(timeout: 10)
        field.typeText("\n")
        XCTAssertTrue(field.exists)
        XCTAssertEqual(field.value as? String, repository)
        XCTAssertFalse(app.staticTexts["Repository added"].exists)
    }
}
