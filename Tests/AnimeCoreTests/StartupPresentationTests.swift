import XCTest
@testable import AnimeCore

final class StartupPresentationTests: XCTestCase {
    func testFastCachedStartupWaitsOnlyForAShortStableLogoFrame() {
        XCTAssertFalse(StartupPresentation.shouldReveal(elapsed: 0, localReady: true, contentReady: true))
        XCTAssertFalse(StartupPresentation.shouldReveal(elapsed: 0.3, localReady: true, contentReady: true))
        XCTAssertTrue(StartupPresentation.shouldReveal(elapsed: 0.35, localReady: true, contentReady: true))
        XCTAssertFalse(StartupPresentation.shouldReveal(elapsed: 2, localReady: false, contentReady: true))
        XCTAssertFalse(StartupPresentation.shouldReveal(elapsed: 2, localReady: true, contentReady: false))
    }
    func testUnavailableOrOfflineServicesCannotHoldTheLaunchScreen() {
        XCTAssertFalse(StartupPresentation.shouldReveal(elapsed: 5.9, localReady: false, contentReady: false))
        XCTAssertTrue(StartupPresentation.shouldReveal(elapsed: 6, localReady: false, contentReady: false))
        XCTAssertTrue(StartupPresentation.shouldReveal(elapsed: 30, localReady: true, contentReady: false))
    }
}
