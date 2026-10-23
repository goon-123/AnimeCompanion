import XCTest
@testable import AnimeCore

final class WebtoonScrollMotionTests: XCTestCase {
    func testSlowMotionKeepsItsSpeedAcrossRefreshRatesAndPixelRounding() {
        for refreshRate in [20, 30, 60, 120] {
            for displayScale in [2.0, 3.0] {
                var motion = WebtoonScrollMotion(), displayed = 0.0
                for frame in 0...(refreshRate * 4) {
                    let target = motion.next(timestamp: Double(frame) / Double(refreshRate), offset: displayed, speed: 15, maximum: 5000)
                    displayed = (target * displayScale).rounded() / displayScale
                }
                XCTAssertEqual(displayed, 60, accuracy: 0.5 / displayScale)
            }
        }
    }
    func testSpeedChangesStopsAndExternalJumpsKeepTheCurrentPosition() {
        var motion = WebtoonScrollMotion()
        XCTAssertEqual(motion.next(timestamp: 1, offset: 100, speed: 15, maximum: 1000), 100)
        XCTAssertEqual(motion.next(timestamp: 1.2, offset: 100, speed: 15, maximum: 1000), 103, accuracy: 0.001)
        XCTAssertEqual(motion.next(timestamp: 1.4, offset: 103, speed: 120, maximum: 1000), 127, accuracy: 0.001)
        motion.reset()
        XCTAssertEqual(motion.next(timestamp: 50, offset: 127, speed: 120, maximum: 1000), 127)
        XCTAssertEqual(motion.next(timestamp: 50.2, offset: 600, speed: 120, maximum: 1000), 624, accuracy: 0.001)
        XCTAssertEqual(motion.next(timestamp: 50.4, offset: 990, speed: 120, maximum: 1000), 1000)
    }
    func testFastScrollingKeepsItsRateAndStopsAtChapterEnd() {
        for rate in [30, 60, 120] {
            var motion = WebtoonScrollMotion(), offset = 0.0
            for frame in 0...rate {
                offset = motion.next(timestamp: Double(frame) / Double(rate), offset: offset, speed: 1200, maximum: 5000)
            }
            XCTAssertEqual(offset, 1200, accuracy: 0.001)
            XCTAssertEqual(motion.next(timestamp: 2, offset: 4950, speed: 1200, maximum: 5000), 5000)
            motion.reset()
            XCTAssertEqual(motion.next(timestamp: 20, offset: 5000, speed: 1200, maximum: 5000), 5000)
        }
    }
}
