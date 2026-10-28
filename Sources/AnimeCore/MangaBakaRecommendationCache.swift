#if canImport(CryptoKit)
import Foundation
import CryptoKit

/// A single connection's bounded, encrypted snapshot, separate from public
/// catalog data. The credential stays in Keychain; it is never written here.
public struct MangaBakaRecommendationCache {
    private let file: URL
    private static let context = Data("com.animecompanion.mangabaka.recommendations.v1".utf8)
    private static let maximumBytes = 16_100_000

    public init(directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        .appendingPathComponent("MangaBakaPrivate", isDirectory: true), accountID: UUID? = nil) {
        file = directory.appendingPathComponent(accountID.map { $0.uuidString.lowercased() + ".bin" } ?? "recommendations.bin")
    }
    private func key(_ credential: MangaBakaCredential) -> SymmetricKey {
        SymmetricKey(data: SHA256.hash(data: Data(credential.secret.utf8)))
    }
    public func load(credential: MangaBakaCredential) throws -> MangaBakaRecommendationSnapshot? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
        guard size <= Self.maximumBytes else { throw MangaBakaError.invalidResponse }
        let sealed = try AES.GCM.SealedBox(combined: Data(contentsOf: file))
        let bytes = try AES.GCM.open(sealed, using: key(credential), authenticating: Self.context)
        let snapshot = try JSONDecoder().decode(MangaBakaRecommendationSnapshot.self, from: bytes)
        _ = try snapshot.payload.records()
        return snapshot
    }
    public func save(_ snapshot: MangaBakaRecommendationSnapshot, credential: MangaBakaCredential) throws {
        _ = try snapshot.payload.records()
        let bytes = try JSONEncoder().encode(snapshot)
        guard bytes.count <= Self.maximumBytes - 64 else { throw MangaBakaError.invalidResponse }
        let sealed = try AES.GCM.seal(bytes, using: key(credential), authenticating: Self.context)
        guard let encrypted = sealed.combined else { throw MangaBakaError.invalidResponse }
        let directory = file.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var excluded = directory
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try excluded.setResourceValues(values)
        #if os(iOS)
        try encrypted.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try encrypted.write(to: file, options: .atomic)
        #endif
    }
    public func clear() throws {
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
    }
}
#endif
