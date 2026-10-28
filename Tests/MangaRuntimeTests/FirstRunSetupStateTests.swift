import XCTest
@testable import AnimeCompanion

final class FirstRunSetupStateTests: XCTestCase {
    @MainActor
    func testFreshInstallStartsWizardAndResumesItsStep() {
        let name = "com.animecompanion.firstRun.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }

        XCTAssertTrue(FirstRunSetupState.prepare(defaults: defaults, arguments: ["AnimeCompanion"]))
        XCTAssertEqual(defaults.string(forKey: FirstRunSetupState.lifecycleKey), "inProgress")
        defaults.set(4, forKey: FirstRunSetupState.stepKey)
        defaults.set(["1": "skipped", "2": "completed"], forKey: FirstRunSetupState.resultsKey)

        XCTAssertTrue(FirstRunSetupState.prepare(defaults: defaults, arguments: ["AnimeCompanion"]))
        XCTAssertEqual(defaults.integer(forKey: FirstRunSetupState.stepKey), 4)
        XCTAssertEqual((defaults.dictionary(forKey: FirstRunSetupState.resultsKey) as? [String: String])?["2"], "completed")
    }

    @MainActor
    func testLegacyInstallationNeverHasOnboardingForcedAfterUpdate() {
        let name = "com.animecompanion.firstRun.legacy.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }

        defaults.set(true, forKey: "explore.poster.immersive-v2")
        XCTAssertFalse(FirstRunSetupState.prepare(defaults: defaults, arguments: ["AnimeCompanion"]))
        XCTAssertEqual(defaults.string(forKey: FirstRunSetupState.lifecycleKey), "finished")
        XCTAssertFalse(FirstRunSetupState.prepare(defaults: defaults, arguments: ["AnimeCompanion"]))
    }

    @MainActor
    func testFinishedSetupDoesNotReappear() {
        let name = "com.animecompanion.firstRun.finished.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }

        defaults.set("finished", forKey: FirstRunSetupState.lifecycleKey)
        XCTAssertFalse(FirstRunSetupState.prepare(defaults: defaults, arguments: ["AnimeCompanion"]))
    }

    @MainActor
    func testOtherUIPreviewsDoNotLaunchWizard() {
        let name = "com.animecompanion.firstRun.preview.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }

        XCTAssertFalse(FirstRunSetupState.prepare(defaults: defaults, arguments: ["AnimeCompanion", "--ui-phase2-preview"]))
        XCTAssertNil(defaults.string(forKey: FirstRunSetupState.lifecycleKey))
    }
}
