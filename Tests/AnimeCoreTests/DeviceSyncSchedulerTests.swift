import XCTest
@testable import AnimeCore

final class DeviceSyncSchedulerTests: XCTestCase {
    private actor Gate {
        private var open = false
        private var continuation: CheckedContinuation<Void, Never>?
        func wait() async {
            if open { return }
            await withCheckedContinuation { continuation = $0 }
        }
        func release() { open = true; continuation?.resume(); continuation = nil }
    }

    @MainActor
    func testActivationChecksImmediatelyWithoutBlockingTheMainActor() async {
        let began = expectation(description: "foreground check began")
        let responsive = expectation(description: "main actor remains usable")
        let gate = Gate()
        var calls = 0
        let scheduler = DeviceSyncScheduler(interval: .seconds(3600)) {
            calls += 1; began.fulfill(); await gate.wait()
        }
        defer { scheduler.stop() }
        scheduler.activate()
        XCTAssertEqual(calls, 0, "Activation should queue work and return to the UI immediately")
        await fulfillment(of: [began], timeout: 2)
        Task { @MainActor in responsive.fulfill() }
        await fulfillment(of: [responsive], timeout: 2)
        await gate.release(); await scheduler.waitForCurrentSync()
        XCTAssertEqual(calls, 1)
    }

    @MainActor
    func testReturningDuringAnInFlightPassQueuesOneFreshCheckWithoutOverlap() async {
        let began = expectation(description: "first check began")
        let gate = Gate()
        var calls = 0, concurrent = 0, maximumConcurrent = 0
        let scheduler = DeviceSyncScheduler(interval: .seconds(3600)) {
            calls += 1; concurrent += 1; maximumConcurrent = max(maximumConcurrent, concurrent)
            if calls == 1 { began.fulfill(); await gate.wait() }
            concurrent -= 1
        }
        defer { scheduler.stop() }
        scheduler.activate(); await fulfillment(of: [began], timeout: 2)
        scheduler.deactivate(); scheduler.activate()
        scheduler.requestNow(); scheduler.activate()
        await gate.release(); await scheduler.waitForCurrentSync()
        XCTAssertEqual(calls, 2, "Resume checks should coalesce behind the current pass")
        XCTAssertEqual(maximumConcurrent, 1)
    }

    @MainActor
    func testRapidLocalChangesUploadAfterOneDebounce() async {
        let edited = expectation(description: "debounced edit check")
        var calls = 0
        let scheduler = DeviceSyncScheduler(interval: .seconds(3600), editDelay: .milliseconds(20)) {
            calls += 1; if calls == 2 { edited.fulfill() }
        }
        defer { scheduler.stop() }
        scheduler.activate(); await scheduler.waitForCurrentSync()
        XCTAssertEqual(calls, 1)
        for _ in 0..<20 { scheduler.localChange() }
        await fulfillment(of: [edited], timeout: 2)
        await scheduler.waitForCurrentSync()
        XCTAssertEqual(calls, 2)
    }

    @MainActor
    func testPeriodicChecksPauseInTheBackgroundAndResumeImmediately() async {
        let periodic = expectation(description: "automatic periodic checks")
        var calls = 0
        let scheduler = DeviceSyncScheduler(interval: .milliseconds(20), editDelay: .milliseconds(10)) {
            calls += 1; if calls == 3 { periodic.fulfill() }
        }
        defer { scheduler.stop() }
        scheduler.activate(); await fulfillment(of: [periodic], timeout: 2)
        scheduler.deactivate(); await scheduler.waitForCurrentSync()
        let pausedCount = calls
        scheduler.requestNow(); scheduler.localChange()
        await scheduler.waitForCurrentSync()
        XCTAssertEqual(calls, pausedCount)
        scheduler.activate(); await scheduler.waitForCurrentSync()
        XCTAssertEqual(calls, pausedCount + 1)
    }

    @MainActor
    func testResetStopsPendingWorkAndPreventsReactivation() async {
        let began = expectation(description: "check began")
        var calls = 0, completedWrites = 0
        let scheduler = DeviceSyncScheduler(interval: .seconds(3600)) {
            calls += 1; began.fulfill()
            do { try await Task.sleep(for: .seconds(3600)) } catch { return }
            completedWrites += 1
        }
        scheduler.activate(); await fulfillment(of: [began], timeout: 2)
        scheduler.stop(); await scheduler.waitForCurrentSync()
        scheduler.activate(); scheduler.requestNow(); scheduler.localChange()
        await scheduler.waitForCurrentSync()
        XCTAssertEqual(calls, 1); XCTAssertEqual(completedWrites, 0)
    }
}
