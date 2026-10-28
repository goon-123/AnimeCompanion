import XCTest

extension XCUIApplication {
    @MainActor func openLibraryActions(_ mediaID: Int) {
        let entry = buttons["library-entry-\(mediaID)"]
        XCTAssertTrue(entry.waitForExistence(timeout: 45)); revealInContent(entry)
        entry.press(forDuration: 1.1)
        XCTAssertTrue(buttons["library-watch-\(mediaID)"].waitForExistence(timeout: 10))
    }
    @MainActor func watchLibraryEntry(_ mediaID: Int) {
        openLibraryActions(mediaID)
        buttons["library-watch-\(mediaID)"].tap()
    }
    @MainActor func chooseAiringLayout(_ title: String) {
        let options = buttons["schedule-airing-layout"]
        XCTAssertTrue(options.waitForExistence(timeout: 15)); revealInContent(options, upward: false)
        options.tap(); buttons[title].firstMatch.tap()
    }
    /// Explore keeps only a floating search control; advanced options live in
    /// its native context menu. Browse pages retain their normal toolbar actions.
    @MainActor func openExploreControl(_ id: String) {
        if buttons[id].exists && buttons[id].isHittable { buttons[id].tap(); return }
        let search = buttons["explore-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 15)); XCTAssertTrue(search.isHittable)
        search.press(forDuration: 1.1)
        let labels = ["explore-display-options": "Display options", "explore-dub-filter-toolbar": "Dub filters", "explore-settings": "Account and settings", "explore-season": "Browse seasons"]
        let action = buttons[id].exists ? buttons[id].firstMatch : buttons[labels[id] ?? id].firstMatch
        XCTAssertTrue(action.waitForExistence(timeout: 10)); action.tap()
    }
    @MainActor func revealSettingsDestination(_ id: String) {
        let sources = ["playback-settings", "seanime-settings", "settings-torbox", "settings-player", "settings-safari-vidhub", "settings-manga-extensions"]
        let appearance = ["settings-bottom-tabs", "settings-explore-design", "settings-ipad-layout", "settings-home-sections"]
        let parent = sources.contains(id) ? "settings-sources" : appearance.contains(id) ? "settings-personalization" : nil
        if buttons[id].exists { return }
        for title in ["Sources & playback", "Appearance & layout"] where navigationBars[title].exists {
            let back = navigationBars[title].buttons["Settings"]
            if back.exists { back.tap() }
        }
        if let parent {
            let row = buttons[parent]; revealInContent(row)
            XCTAssertTrue(row.waitForExistence(timeout: 10)); row.tap()
        }
    }
    /// iPad's adaptive tabs may be represented as a top bar or sidebar rather
    /// than the phone's bottom tab bar. Keep feature assertions in both modes.
    @MainActor func appTab(_ title: String) -> XCUIElement {
        let ids = ["Home": "home", "Explore": "explore", "My Library": "library", "Manga": "manga", "Schedule": "schedule", "News": "news"]
        if let id = ids[title] {
            let sidebar = descendants(matching: .any).matching(identifier: "sidebar-tab-" + id).firstMatch
            if sidebar.exists && sidebar.isHittable { return sidebar }
        }
        let tab = tabBars.buttons[title].firstMatch
        if tab.exists && tab.isHittable { return tab }
        let button = buttons.matching(NSPredicate(format: "label == %@", title)).firstMatch
        return button.exists ? button : staticTexts[title].firstMatch
    }

    @MainActor var browseSurface: XCUIElement {
        for id in ["home-dashboard", "combined-library", "unified-search", "unified-explore-discover", "unified-explore-posterGrid", "discovery-scroll", "library-scroll", "explore-scroll", "schedule-airing-scroll", "news-list"] {
            let scroll = scrollViews[id]
            if scroll.exists { return scroll }
        }
        return self
    }

    @MainActor var contentSurface: XCUIElement {
        if navigationBars["Customize News"].exists { return self }
        let news = scrollViews["news-list"]
        if news.exists && news.isHittable { return news }
        let picker = scrollViews["stream-picker-scroll"].firstMatch
        if picker.exists && picker.isHittable { return picker }
        if descendants(matching: .any).matching(identifier: "torbox-webdav-list").firstMatch.exists { return self }
        // A sheet sits over the browse/detail panes; drag its form, not the
        // retained view underneath. The screen center is inside these sheets.
        if ["Sources & playback", "Appearance & layout", "Customize Home", "Saved views", "Accounts", "MangaBaka account", "Customize News", "Display options", "Dub filters", "Settings", "Watch in VidHub", "Find streams", "Source options", "Playback help", "Release information", "Edit AniList tracking", "Stremio add-ons", "Browse add-ons", "Review add-on", "Installed catalogs", "Exact video ID", "Add-on sources", "Subtitles", "Seanime extensions", "TorBox", "AniList account", "Browsing & content", "Watch tracking", "Video player", "About & data sources", "Compatibility & privacy", "Review Seanime extension", "Seanime sources", "TorBox playback", "Configure provider"].contains(where: { navigationBars[$0].exists }) {
            return self
        }
        if navigationBars["iPad layout"].exists { return self }
        let detail = scrollViews["anime-detail-scroll"]
        return detail.exists ? detail : browseSurface
    }

    @MainActor func returnToBrowsing() {
        let back = buttons["back-to-browsing"]
        if back.exists { back.tap() } else { navigationBars.buttons.firstMatch.tap() }
    }

    @MainActor func enterPlaybackEpisode(_ number: Int) {
        let field = textFields["playback-episode-number"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        let expected = String(number)
        for _ in 0..<2 {
            field.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
            // Cold simulator keyboards can drop the last key if clearing and
            // typing share one event. Keep both operations observable.
            let count = (field.value as? String)?.count ?? 0
            if count > 0 { field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: count)) }
            field.typeText(expected)
            let typed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", expected), object: field)
            if XCTWaiter.wait(for: [typed], timeout: 5) == .completed { break }
        }
        XCTAssertEqual(field.value as? String, expected)
    }

    @MainActor func revealInContent(_ element: XCUIElement, upward: Bool = true) {
        for _ in 0..<24 {
            let surface = contentSurface
            let bounds = surface.frame
            if element.isHittable, element.frame.midY > bounds.minY + 12,
               element.frame.midY < bounds.maxY - 35 { return }
            let backwards = element.exists && element.frame.height > 0 ? element.frame.midY < bounds.midY : !upward
            let start = surface.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: backwards ? 0.35 : 0.75))
            let end = surface.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: backwards ? 0.70 : 0.40))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.05)
        }
        XCTAssertTrue(element.isHittable, "Could not reveal \(element.identifier)")
    }
}
