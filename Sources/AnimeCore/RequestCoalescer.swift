import Foundation

/// Shares work between independent callers. Cancelling one caller releases it immediately;
/// the underlying operation is cancelled only when its last caller leaves.
public actor RequestCoalescer<Key: Hashable & Sendable, Value: Sendable> {
    private struct Flight {
        let id: UUID
        let task: Task<Void, Never>
        var waiters: [UUID: CheckedContinuation<Value, Error>]
    }
    private var flights: [Key: Flight] = [:]
    public init() {}

    public func value(for key: Key, operation: @escaping @Sendable () async throws -> Value) async throws -> Value {
        let waiter = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard !Task.isCancelled else { continuation.resume(throwing: CancellationError()); return }
                if flights[key] != nil {
                    flights[key]?.waiters[waiter] = continuation
                    return
                }
                let id = UUID()
                let task = Task {
                    let result: Result<Value, Error>
                    do { result = .success(try await operation()) }
                    catch { result = .failure(error) }
                    finish(key, id: id, result: result)
                }
                flights[key] = Flight(id: id, task: task, waiters: [waiter: continuation])
            }
        } onCancel: {
            Task { await self.cancel(key, waiter: waiter) }
        }
    }
    private func finish(_ key: Key, id: UUID, result: Result<Value, Error>) {
        // A cancelled operation may finish after another operation has started for this key.
        guard flights[key]?.id == id, let flight = flights.removeValue(forKey: key) else { return }
        for continuation in flight.waiters.values { continuation.resume(with: result) }
    }
    private func cancel(_ key: Key, waiter: UUID) {
        guard let continuation = flights[key]?.waiters.removeValue(forKey: waiter) else { return }
        continuation.resume(throwing: CancellationError())
        if flights[key]?.waiters.isEmpty == true {
            flights.removeValue(forKey: key)?.task.cancel()
        }
    }
    // Internal diagnostics allow deterministic concurrency tests without timing sleeps.
    func waiterCount(for key: Key) -> Int { flights[key]?.waiters.count ?? 0 }
}
