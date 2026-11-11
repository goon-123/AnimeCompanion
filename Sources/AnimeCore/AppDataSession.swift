import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A reset invalidates writers before erasing files. A late network response or
/// suspended reader save from the old session cannot recreate erased data.
public final class AppDataEpoch: @unchecked Sendable {
    public static let shared = AppDataEpoch()
    private let lock = NSRecursiveLock()
    private var generation: UInt64 = 0
    private var resetting = false
    public init() {}
    fileprivate func capture() -> UInt64? { lock.lock(); defer { lock.unlock() }; return resetting ? nil : generation }
    fileprivate func perform<T>(_ generation: UInt64, _ operation: () throws -> T) throws -> T {
        lock.lock(); defer { lock.unlock() }
        guard !resetting, generation == self.generation else { throw CancellationError() }
        return try operation()
    }
    public func beginReset() {
        lock.lock(); defer { lock.unlock() }
        generation &+= 1; resetting = true
    }
    public func finishReset() { lock.lock(); resetting = false; lock.unlock() }
}

public struct AppDataSession: Sendable {
    private let epoch: AppDataEpoch
    private let generation: UInt64?
    public init(epoch: AppDataEpoch = .shared) { self.epoch = epoch; generation = epoch.capture() }
    public var isCurrent: Bool { do { try check(); return true } catch { return false } }
    public func check() throws { try perform {} }
    public func perform<T>(_ operation: () throws -> T) throws -> T {
        guard let generation else { throw CancellationError() }
        return try epoch.perform(generation, operation)
    }
    public func write(_ data: Data, to url: URL, options: Data.WritingOptions = .atomic) throws {
        try perform { try data.write(to: url, options: options) }
    }
}

/// Restrict erasure to explicitly supplied subdirectories of this app's sandbox.
/// Validate the whole plan first, including symlinks, before deleting anything.
public enum AppLocalDataReset {
    public static func eraseContents(of directories: [URL], inside container: URL, fileManager: FileManager = .default) throws {
        let base = container.standardizedFileURL.resolvingSymlinksInPath().path + "/"
        for directory in directories {
            let path = directory.standardizedFileURL.resolvingSymlinksInPath().path
            guard path.hasPrefix(base), path != String(base.dropLast()) else {
                throw ServiceError.message("The reset storage location is outside this app.")
            }
        }
        for directory in directories where fileManager.fileExists(atPath: directory.path) {
            for item in try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
                try fileManager.removeItem(at: item)
            }
        }
    }
}

/// Sessions remain usable by new stores after reset, while outstanding work and
/// each session's HTTP cache are cleared. This also covers ephemeral clients.
public final class AppNetworkSessions: @unchecked Sendable {
    public static let shared = AppNetworkSessions()
    private final class WeakSession { weak var value: URLSession?; init(_ value: URLSession) { self.value = value } }
    private let lock = NSLock()
    private var sessions: [ObjectIdentifier: WeakSession] = [:]
    private init() {}
    public func register(_ session: URLSession) {
        lock.lock(); defer { lock.unlock() }
        sessions = sessions.filter { $0.value.value != nil }
        sessions[ObjectIdentifier(session)] = WeakSession(session)
    }
    private func snapshot() -> [URLSession] {
        lock.lock(); defer { lock.unlock() }; return sessions.values.compactMap(\.value)
    }
    public func cancelAndClear() async {
        for session in snapshot() {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                session.getAllTasks { tasks in
                    tasks.forEach { $0.cancel() }
                    session.configuration.urlCache?.removeAllCachedResponses()
                    continuation.resume()
                }
            }
        }
    }
}
