import XCTest
@testable import AnimeCompanion

final class CompanionTabTransitionTests: XCTestCase {
    @MainActor func testContentTransitionIsBriefAndReduceMotionRemovesIt() {
        XCTAssertEqual(CompanionTabTransition(reduceMotion: false).transitionDuration(using: nil), 0.12)
        XCTAssertEqual(CompanionTabTransition(reduceMotion: true).transitionDuration(using: nil), 0)
    }
}
