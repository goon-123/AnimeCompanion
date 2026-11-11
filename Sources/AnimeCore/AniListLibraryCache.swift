import Foundation

public struct AniListLibrarySnapshot: Codable, Sendable {
    public let viewer: Viewer
    public let entries: [LibraryEntry]
    public let savedAt: Date
    public let fetchedAt: Date
    private let version: Int
    public init(viewer: Viewer, entries: [LibraryEntry], savedAt: Date = Date(), fetchedAt: Date? = nil) {
        self.viewer = viewer; self.entries = entries; self.savedAt = savedAt; self.fetchedAt = fetchedAt ?? savedAt; version = 1
    }
    public func isUsable(at now: Date = Date()) -> Bool {
        version == 1 && viewer.id > 0 && now.timeIntervalSince(savedAt) >= -300 && now.timeIntervalSince(savedAt) < 30 * 86400
    }
}

#if canImport(CryptoKit)
import CryptoKit

/// Scoped to the Keychain credential. Tokens and unencrypted tracking data never enter the file.
public actor AniListLibraryCache {
    private let persistence = AppDataSession()
    private let directory: URL
    private let context = Data("com.animecompanion.anilist.library.v1".utf8)
    public init(directory: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        .appendingPathComponent("AnimeCompanion-AniListPrivate", isDirectory: true)) { self.directory = directory }
    private func digest(_ credential: String) -> SHA256.Digest { SHA256.hash(data: Data(credential.utf8)) }
    private func file(_ credential: String) -> URL {
        directory.appendingPathComponent(digest(credential).map { String(format: "%02x", $0) }.joined() + ".bin")
    }
    public func load(credential: String, now: Date = Date()) -> AniListLibrarySnapshot? {
        guard !credential.isEmpty else { return nil }
        let file = file(credential)
        guard let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 16_000_000,
              let data = try? Data(contentsOf: file), let box = try? AES.GCM.SealedBox(combined: data),
              let bytes = try? AES.GCM.open(box, using: SymmetricKey(data: digest(credential)), authenticating: context),
              let snapshot = try? JSONDecoder().decode(AniListLibrarySnapshot.self, from: bytes), snapshot.isUsable(at: now) else { return nil }
        return snapshot
    }
    @discardableResult public func save(_ snapshot: AniListLibrarySnapshot, credential: String) -> Bool {
        guard !credential.isEmpty, let bytes = try? JSONEncoder().encode(snapshot), bytes.count <= 15_900_000,
              let encrypted = try? AES.GCM.seal(bytes, using: SymmetricKey(data: digest(credential)), authenticating: context).combined else { return false }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            #if os(iOS)
            try persistence.write(encrypted, to: file(credential), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            #else
            try persistence.write(encrypted, to: file(credential), options: .atomic)
            #endif
            // AniList has one active account; keep this private snapshot bounded.
            // Directory enumeration may return relative/base URLs on Apple platforms.
            // Compare sibling filenames so URL representation cannot delete the file just written.
            let currentName = file(credential).lastPathComponent
            for old in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                where old.pathExtension == "bin" && old.lastPathComponent != currentName { try? FileManager.default.removeItem(at: old) }
            return true
        } catch { return false }
    }
    public func clear(credential: String) { try? FileManager.default.removeItem(at: file(credential)) }
}
#endif
