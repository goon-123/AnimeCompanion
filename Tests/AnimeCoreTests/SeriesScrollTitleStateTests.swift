import XCTest
@testable import AnimeCore

final class SeriesScrollTitleStateTests: XCTestCase {
    func testFirstDownwardMovementHidesAndUpwardMovementReveals() {
        var state = SeriesScrollTitleState()
        state.update(offset: 0, userScrolling: false)
        state.update(offset: 4, userScrolling: true)
        XCTAssertFalse(state.isVisible)
        state.update(offset: 140, userScrolling: true)
        XCTAssertFalse(state.isVisible)
        state.update(offset: 136, userScrolling: true)
        XCTAssertTrue(state.isVisible)
    }
    func testSmallMovementsAccumulateAndDirectionChangesDoNotFlicker() {
        var state = SeriesScrollTitleState()
        state.update(offset: 20, userScrolling: false)
        state.update(offset: 21, userScrolling: true)
        state.update(offset: 22, userScrolling: true)
        XCTAssertTrue(state.isVisible)
        state.update(offset: 23, userScrolling: true)
        XCTAssertFalse(state.isVisible)
        state.update(offset: 22.5, userScrolling: true)
        state.update(offset: 23, userScrolling: true)
        XCTAssertFalse(state.isVisible)
        state.update(offset: 19, userScrolling: true)
        XCTAssertTrue(state.isVisible)
    }
    func testLayoutChangesEstablishBaselineWithoutHidingTitle() {
        var state = SeriesScrollTitleState()
        state.update(offset: 0, userScrolling: false)
        state.update(offset: 500, userScrolling: false)
        XCTAssertTrue(state.isVisible)
        state.update(offset: 504, userScrolling: true)
        XCTAssertFalse(state.isVisible)
        state.update(offset: 100, userScrolling: false)
        XCTAssertFalse(state.isVisible)
        state.update(offset: 96, userScrolling: true)
        XCTAssertTrue(state.isVisible)
    }
    func testClampedBounceAndNonFiniteSamplesDoNotReverseDirection() {
        var state = SeriesScrollTitleState()
        state.update(offset: 0, userScrolling: false)
        state.update(offset: 100, userScrolling: true)
        state.update(offset: 100, userScrolling: true)
        state.update(offset: .nan, userScrolling: true)
        state.update(offset: .infinity, userScrolling: true)
        XCTAssertFalse(state.isVisible)
        state.update(offset: -10, userScrolling: true)
        XCTAssertTrue(state.isVisible)
        state.update(offset: 0, userScrolling: true)
        XCTAssertTrue(state.isVisible)
    }
}
