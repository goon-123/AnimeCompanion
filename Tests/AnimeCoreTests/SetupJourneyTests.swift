import XCTest
@testable import AnimeCore

final class SetupJourneyTests: XCTestCase {
    func testFreshOrInvalidProgressStartsAtWelcome() {
        XCTAssertEqual(SetupStage.restoring(savedStep: nil, legacyStep: 0), .welcome)
        XCTAssertEqual(SetupStage.restoring(savedStep: 999, legacyStep: 7), .welcome)
        XCTAssertEqual(SetupStage.restoring(savedStep: nil, legacyStep: -1), .welcome)
    }
    func testEveryGuidedStepResumes() {
        XCTAssertEqual(SetupStage.allCases.count, 6)
        for stage in SetupStage.allCases {
            XCTAssertEqual(SetupStage.restoring(savedStep: stage.rawValue, legacyStep: 7, previousStep: 3), stage)
        }
    }
    func testOldProgressKeepsEquivalentPageAndShowsNewPlaybackGuidance() {
        XCTAssertEqual(SetupStage.restoring(savedStep: nil, legacyStep: 0, previousStep: 2), .preferences)
        XCTAssertEqual(SetupStage.restoring(savedStep: nil, legacyStep: 0, previousStep: 3), .watch)
        for step in 1...2 { XCTAssertEqual(SetupStage.restoring(savedStep: nil, legacyStep: step), .libraries) }
        for step in 3...6 { XCTAssertEqual(SetupStage.restoring(savedStep: nil, legacyStep: step), .preferences) }
        XCTAssertEqual(SetupStage.restoring(savedStep: nil, legacyStep: 7), .watch)
    }
    func testVideoRequiresEitherCompleteRouteAndConfirmedPlayer() {
        func status(addons: Int = 0, torrents: Int = 0, torbox: Bool = false, player: Bool = true) -> SourceSetupStatus {
            SourceSetupStatus(streamAddons: addons, torrentProviders: torrents, torBoxConnected: torbox, playerConfirmed: player, mangaSources: 0)
        }
        XCTAssertFalse(status().videoConfigured)
        XCTAssertFalse(status(torrents: 1).videoConfigured)
        XCTAssertFalse(status(torbox: true).videoConfigured)
        XCTAssertTrue(status(torrents: 1, torbox: true).videoConfigured)
        XCTAssertTrue(status(addons: 1).videoConfigured)
        XCTAssertFalse(status(addons: 1, player: false).videoConfigured)
        XCTAssertFalse(status(torrents: 1, torbox: true, player: false).videoConfigured)
        XCTAssertFalse(status(addons: 1).readingConfigured)
    }
}
