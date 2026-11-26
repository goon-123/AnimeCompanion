import Foundation

/// Foreground sync is asynchronous work owned by the app session, rather than
/// by a screen's task. Returning while a pass is still running queues one fresh
/// check. Timers and edits coalesce without running overlapping file transfers.
@MainActor
public final class DeviceSyncScheduler {
    private let interval: Duration
    private let editDelay: Duration
    private let operation: @MainActor @Sendable () async -> Void
    private var active = false
    private var stopped = false
    private var requestedAgain = false
    private var running: Task<Void, Never>?
    private var timer: Task<Void, Never>?
    private var edit: Task<Void, Never>?

    public init(interval: Duration = .seconds(30), editDelay: Duration = .seconds(2),
                operation: @escaping @MainActor @Sendable () async -> Void) {
        self.interval = interval; self.editDelay = editDelay; self.operation = operation
    }
    public func activate() {
        guard !stopped else { return }
        active = true
        requestNow()
        guard timer == nil else { return }
        let interval = interval
        timer = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: interval) } catch { return }
                guard let self, self.active, !self.stopped else { return }
                self.requestNow()
            }
        }
    }
    public func deactivate() {
        active = false; requestedAgain = false
        timer?.cancel(); timer = nil; edit?.cancel(); edit = nil
        // Let an in-flight pass finish its journal safely. iOS may suspend the
        // process; its next activation resumes from the durable local journal.
    }
    public func localChange() {
        guard active, !stopped else { return }
        edit?.cancel()
        let delay = editDelay
        edit = Task { [weak self] in
            do { try await Task.sleep(for: delay) } catch { return }
            guard let self else { return }
            self.edit = nil; self.requestNow()
        }
    }
    public func requestNow() {
        guard active, !stopped else { return }
        edit?.cancel(); edit = nil
        guard running == nil else { requestedAgain = true; return }
        running = Task { [weak self] in
            guard let self else { return }
            repeat {
                self.requestedAgain = false
                await self.operation()
            } while self.active && !self.stopped && self.requestedAgain && !Task.isCancelled
            self.running = nil
        }
    }
    public func waitForCurrentSync() async { await running?.value }
    public func stop() {
        stopped = true; deactivate(); running?.cancel()
    }
}
