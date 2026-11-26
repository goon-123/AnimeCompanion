import XCTest
@testable import AnimeCore

final class AppThemeTests: XCTestCase {
    func testDefaultAndCorruptPreferences() {
        XCTAssertEqual(AppThemePreferences(saved: nil), AppThemePreferences())
        XCTAssertEqual(AppThemePreferences(saved: "bad"), AppThemePreferences())
        XCTAssertNil(ThemeRGB(hex: "red"))
        XCTAssertNil(ThemeRGB(hex: "FFFFFFF"))
        XCTAssertEqual(ThemeRGB(hex: " #ab23cd ")?.hex, "AB23CD")
    }
    func testThemeRoundTripAndInvalidCustomColor() {
        var value = AppThemePreferences(); value.accent = .ocean; value.canvas = .midnight; value.customAccent = "FF4400"
        XCTAssertEqual(AppThemePreferences(saved: value.saved), value)
        value.customAccent = "invalid"
        XCTAssertNil(AppThemePreferences(saved: value.saved).customAccent)
        XCTAssertTrue(DeviceSyncPreferences.keys.contains(AppThemePreferences.storageKey))
    }
    func testSavedThemeIdentityIsStableAcrossReadsAndRoundTrips() {
        var value = AppThemePreferences(); value.accent = .ocean; value.canvas = .midnight; value.customAccent = "AA44FF"
        let expected = value.saved
        for _ in 0..<100 {
            XCTAssertEqual(value.saved, expected)
            XCTAssertEqual(AppThemePreferences(saved: expected).saved, expected)
        }
    }
    func testAllPresetsAndCustomAccentsStayReadableOnEveryCanvas() {
        for dark in [false, true] {
            for canvas in AppCanvas.allCases {
                for accent in AppAccent.allCases {
                    for custom in [nil, "000000", "FFFFFF", "777777", "00FF00", "FF0000"] as [String?] {
                        var value = AppThemePreferences(); value.canvas = canvas; value.accent = accent; value.customAccent = custom
                        let color = value.accentColor(dark: dark)
                        XCTAssertGreaterThanOrEqual(color.contrast(with: ThemeRGB(hex: canvas.background(dark: dark))!), 4.5)
                        XCTAssertGreaterThanOrEqual(color.contrast(with: ThemeRGB(hex: canvas.surface(dark: dark))!), 4.5)
                    }
                }
            }
        }
    }
}
