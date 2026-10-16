import XCTest
@testable import AnimeCore

final class DiscoveryPaginationTests: XCTestCase {
    func testLargePosterGridPrefetchesWhenTheMeasuredBottomApproaches() {
        XCTAssertFalse(DiscoveryPaginationPolicy.isNearEnd(offset: 0, viewport: 800, content: 16_000))
        XCTAssertFalse(DiscoveryPaginationPolicy.isNearEnd(offset: 14_799, viewport: 800, content: 16_000))
        XCTAssertTrue(DiscoveryPaginationPolicy.isNearEnd(offset: 14_800, viewport: 800, content: 16_000))
        XCTAssertTrue(DiscoveryPaginationPolicy.isNearEnd(offset: 15_200, viewport: 800, content: 16_000))
        // Appending results moves the real bottom away, stopping further prefetch.
        XCTAssertFalse(DiscoveryPaginationPolicy.isNearEnd(offset: 15_200, viewport: 800, content: 30_000))
    }
    func testShortPagesAndBottomInsetsUseTheActualViewport() {
        XCTAssertTrue(DiscoveryPaginationPolicy.isNearEnd(offset: 0, viewport: 1_000, content: 600))
        XCTAssertFalse(DiscoveryPaginationPolicy.isNearEnd(offset: 0, viewport: 800, content: 1_000, bottomInset: 500))
        XCTAssertTrue(DiscoveryPaginationPolicy.isNearEnd(offset: 300, viewport: 800, content: 1_000, bottomInset: 500))
    }
    func testUnlaidOutOrInvalidGeometryCannotRequestPages() {
        XCTAssertFalse(DiscoveryPaginationPolicy.isNearEnd(offset: 0, viewport: 0, content: 100))
        XCTAssertFalse(DiscoveryPaginationPolicy.isNearEnd(offset: 0, viewport: 800, content: 0))
        XCTAssertFalse(DiscoveryPaginationPolicy.isNearEnd(offset: .nan, viewport: 800, content: 100))
        XCTAssertFalse(DiscoveryPaginationPolicy.isNearEnd(offset: 0, viewport: .infinity, content: 100))
        XCTAssertFalse(DiscoveryPaginationPolicy.isNearEnd(offset: 0, viewport: 800, content: .infinity))
    }
    func testEmptyAndDuplicateOnlyBatchesPauseButNewMatchesCanContinue() {
        XCTAssertTrue(DiscoveryPaginationPolicy.shouldPause(previousMatches: 0, currentMatches: 0))
        XCTAssertTrue(DiscoveryPaginationPolicy.shouldPause(previousMatches: 24, currentMatches: 24))
        XCTAssertFalse(DiscoveryPaginationPolicy.shouldPause(previousMatches: 24, currentMatches: 48))
    }
}
