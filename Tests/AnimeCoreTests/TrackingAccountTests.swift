import XCTest
@testable import AnimeCore

final class TrackingAccountTests: XCTestCase {
    func testSavedChoiceWinsAfterBothSessionsRestore() {
        let both = Set(TrackingAccount.allCases)
        XCTAssertEqual(TrackingAccount.preferred(saved: "mangabaka", librarySection: "all", connected: both), .mangaBaka)
        XCTAssertEqual(TrackingAccount.preferred(saved: "anilist", librarySection: "written", connected: both), .aniList)
    }
    func testRestorationOrderAndDisconnectOnlyAffectTheDisplayedAccount() {
        // A temporarily unavailable connection never rewrites the saved choice.
        let saved = "mangabaka"
        XCTAssertNil(TrackingAccount.preferred(saved: saved, librarySection: "all", connected: []))
        XCTAssertEqual(TrackingAccount.preferred(saved: saved, librarySection: "all", connected: [.aniList]), .aniList)
        XCTAssertEqual(TrackingAccount.preferred(saved: saved, librarySection: "all", connected: Set(TrackingAccount.allCases)), .mangaBaka)
    }
    func testExistingLibraryPreferenceAndInvalidValuesHaveUsableDefaults() {
        let both = Set(TrackingAccount.allCases)
        XCTAssertEqual(TrackingAccount.preferred(saved: nil, librarySection: "written", connected: both), .mangaBaka)
        XCTAssertEqual(TrackingAccount.preferred(saved: "old-value", librarySection: "anime", connected: both), .aniList)
        XCTAssertEqual(TrackingAccount.preferred(saved: nil, librarySection: "all", connected: [.mangaBaka]), .mangaBaka)
        XCTAssertNil(TrackingAccount.preferred(saved: "invalid", librarySection: "invalid", connected: []))
    }
}
