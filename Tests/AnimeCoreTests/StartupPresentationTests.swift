import XCTest
@testable import AnimeCore

final class StartupPresentationTests: XCTestCase {
    func testFastCachedStartupWaitsOnlyForAShortStableLogoFrame() {
        XCTAssertFalse(StartupPresentation.shouldReveal(elapsed: 0, localReady: true, contentReady: true))
        XCTAssertFalse(StartupPresentation.shouldReveal(elapsed: 0.1, localReady: true, contentReady: true))
        XCTAssertFalse(StartupPresentation.shouldReveal(elapsed: 0.2, localReady: true, contentReady: true))
        XCTAssertTrue(StartupPresentation.shouldReveal(elapsed: 0.45, localReady: true, contentReady: true))
        XCTAssertFalse(StartupPresentation.shouldReveal(elapsed: 0.5, localReady: false, contentReady: true))
        XCTAssertFalse(StartupPresentation.shouldReveal(elapsed: 0.5, localReady: true, contentReady: false))
    }
    func testUnavailableOrOfflineServicesCannotHoldTheLaunchScreen() {
        XCTAssertFalse(StartupPresentation.shouldReveal(elapsed: 1.69, localReady: false, contentReady: false))
        XCTAssertTrue(StartupPresentation.shouldReveal(elapsed: 1.7, localReady: false, contentReady: false))
        XCTAssertTrue(StartupPresentation.shouldReveal(elapsed: 2, localReady: false, contentReady: false))
        XCTAssertTrue(StartupPresentation.shouldReveal(elapsed: 30, localReady: true, contentReady: false))
    }
}
