import XCTest
@testable import AnimeCore

final class SetupJourneyTests: XCTestCase {
    func testFreshOrInvalidProgressStartsAtWelcome() {
        XCTAssertEqual(SetupStage.restoring(savedStep: nil, legacyStep: 0), .welcome)
        XCTAssertEqual(SetupStage.restoring(savedStep: 999, legacyStep: 7), .welcome)
        XCTAssertEqual(SetupStage.restoring(savedStep: nil, legacyStep: -1), .welcome)
    }
    func testEachShortFlowStepResumesWithoutUsingLegacyIndex() {
        XCTAssertEqual(SetupStage.allCases.count, 4)
        for stage in SetupStage.allCases {
            XCTAssertEqual(SetupStage.restoring(savedStep: stage.rawValue, legacyStep: 7), stage)
        }
    }
    func testLegacyWizardResumesInEquivalentOptionalStep() {
        for step in 1...2 { XCTAssertEqual(SetupStage.restoring(savedStep: nil, legacyStep: step), .libraries) }
        for step in 3...6 { XCTAssertEqual(SetupStage.restoring(savedStep: nil, legacyStep: step), .preferences) }
        XCTAssertEqual(SetupStage.restoring(savedStep: nil, legacyStep: 7), .ready)
    }
}
