import Foundation

public struct AddonStreamSource: Identifiable, Sendable {
    public struct ID: Hashable, Sendable { public let addonID: UUID; public let index: Int }
    public let id: ID
    public let addonName: String
    public let stream: StremioStream
}
public struct AddonStreamIssue: Identifiable, Sendable {
    public let id: UUID
    public let addonName: String
    public let error: PlaybackError
    public let usingSavedSources: Bool
}

/// Failed providers retain only their own sources from this episode's previous
/// lookup. Successful empty responses replace their old sources with an empty set.
public struct AddonStreamSnapshot: Sendable {
    private let order: [UUID]
    private var entries: [UUID: [AddonStreamSource]]
    private var failures: [UUID: AddonStreamIssue] = [:]
    private var skipped: [UUID: Int] = [:]
    private var completed: Set<UUID> = []
    public var sources: [AddonStreamSource] { order.flatMap { entries[$0] ?? [] } }
    public var issues: [AddonStreamIssue] { order.compactMap { failures[$0] } }
    public var pendingCount: Int { order.count - completed.count }
    public var skippedCount: Int { skipped.values.reduce(0, +) }

    init(installations: [AddonInstallation], previous: [AddonStreamSource]) {
        order = installations.map(\.id)
        let enabled = Set(order)
        entries = Dictionary(grouping: previous.filter { enabled.contains($0.id.addonID) }, by: { $0.id.addonID })
    }
    mutating func accept(_ result: StreamResults, from installation: AddonInstallation) {
        entries[installation.id] = result.streams.enumerated().map {
            AddonStreamSource(id: .init(addonID: installation.id, index: $0.offset), addonName: installation.addon.manifest.name, stream: $0.element)
        }
        skipped[installation.id] = result.skippedCount; completed.insert(installation.id)
    }
    mutating func fail(_ error: PlaybackError, from installation: AddonInstallation) {
        failures[installation.id] = AddonStreamIssue(id: installation.id, addonName: installation.addon.manifest.name,
            error: error, usingSavedSources: !(entries[installation.id] ?? []).isEmpty)
        completed.insert(installation.id)
    }
}

extension StremioClient {
    private struct AddonOutcome: Sendable {
        let installation: AddonInstallation
        let result: Result<StreamResults, PlaybackError>
    }
    /// Publish each provider as it finishes, in stable installed order, with at
    /// most four provider lookups running at once. No manifest URL is surfaced.
    public func streams(installations: [AddonInstallation], anime: Anime, episode: Int,
                        previous: [AddonStreamSource] = [],
                        onUpdate: @escaping @Sendable (AddonStreamSnapshot) async -> Void = { _ in }) async throws -> AddonStreamSnapshot {
        let active = installations.filter(\.enabled)
        var snapshot = AddonStreamSnapshot(installations: active, previous: previous)
        try Task.checkCancellation()
        await onUpdate(snapshot)
        return try await withThrowingTaskGroup(of: AddonOutcome.self) { group in
            var iterator = active.makeIterator()
            func enqueue(_ installation: AddonInstallation) {
                group.addTask {
                    do {
                        let result = try await streams(addon: installation.addon, anime: anime, episode: episode)
                        return AddonOutcome(installation: installation, result: .success(result))
                    } catch is CancellationError { throw CancellationError() }
                    catch let error as PlaybackError { return AddonOutcome(installation: installation, result: .failure(error)) }
                    catch { return AddonOutcome(installation: installation, result: .failure(.unavailable)) }
                }
            }
            for _ in 0..<4 { if let next = iterator.next() { enqueue(next) } }
            for try await outcome in group {
                try Task.checkCancellation()
                switch outcome.result {
                case .success(let result): snapshot.accept(result, from: outcome.installation)
                case .failure(let error): snapshot.fail(error, from: outcome.installation)
                }
                await onUpdate(snapshot)
                try Task.checkCancellation()
                if let next = iterator.next() { enqueue(next) }
            }
            return snapshot
        }
    }
}
