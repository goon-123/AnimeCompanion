import XCTest

extension XCUIApplication {
    /// iPad's adaptive tabs may be represented as a top bar or sidebar rather
    /// than the phone's bottom tab bar. Keep feature assertions in both modes.
    @MainActor func appTab(_ title: String) -> XCUIElement {
        let tab = tabBars.buttons[title].firstMatch
        if tab.exists { return tab }
        return buttons.matching(NSPredicate(format: "label == %@", title)).firstMatch
    }

    @MainActor var browseSurface: XCUIElement {
        for id in ["discovery-scroll", "library-scroll", "explore-scroll", "schedule-airing-scroll"] {
            let scroll = scrollViews[id]
            if scroll.exists { return scroll }
        }
        return self
    }

    @MainActor var contentSurface: XCUIElement {
        // A sheet sits over the browse/detail panes; drag its form, not the
        // retained view underneath. The screen center is inside these sheets.
        if ["Display options", "Dub filters", "Settings", "Watch in VidHub", "Edit AniList tracking"].contains(where: { navigationBars[$0].exists }) {
            return self
        }
        let detail = scrollViews["anime-detail-scroll"]
        return detail.exists ? detail : browseSurface
    }

    @MainActor func returnToBrowsing() {
        let back = buttons["back-to-browsing"]
        if back.exists { back.tap() } else { navigationBars.buttons.firstMatch.tap() }
    }
}
