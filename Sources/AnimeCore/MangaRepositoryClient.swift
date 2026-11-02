import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct MangaRepositoryClient: Sendable {
    public let transport: any HTTPTransport
    public init(transport: any HTTPTransport = URLSessionTransport()) { self.transport = transport }
    public func catalog(repository: MangaRepository = .keiyoushi) async throws -> MangaExtensionCatalog {
        async let index = load(repository.indexURL, limit: 8_000_000)
        async let checksums = load(repository.checksumsURL, limit: 4_000_000)
        var catalog = try MangaExtensionCatalog.decode(await index)
        let inventory = try await checksums
        guard let assets = try? JSONSerialization.jsonObject(with: inventory) as? [String: Any], assets.count <= 10_000,
              assets.values.contains(where: { Self.checksum($0) != nil }) else { throw MangaExtensionError.invalidChecksums }
        for i in catalog.extensions.indices {
            let entry = catalog.extensions[i]
            catalog.extensions[i].sha256 = Self.checksum(assets[entry.packageName], filename: entry.apkURL.lastPathComponent)
        }
        return catalog
    }
    public func package(_ entry: MangaExtensionDescriptor) async throws -> Data {
        guard entry.supportsRuntime else { throw MangaExtensionError.unsupportedAPI }
        guard entry.sha256 != nil else { throw MangaExtensionError.checksumUnavailable }
        return try await load(entry.apkURL, limit: 32 * 1024 * 1024)
    }
    private func load(_ url: URL, limit: Int) async throws -> Data {
        var request = URLRequest(url: url); request.timeoutInterval = 45
        request.setValue("AnimeCompanion/0.18 (manga extensions)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await transport.data(for: request)
        try HTTPValidation.check(response)
        guard !data.isEmpty, data.count <= limit else { throw MangaExtensionError.oversized }
        return data
    }
    private static func checksum(_ value: Any?, filename: String? = nil) -> String? {
        let raw: String?
        if let digest = value as? String { raw = digest }
        else if let entry = value as? [String: Any], let apk = entry["apk"] as? [String: Any],
                let name = apk["name"] as? String, !name.isEmpty, filename == nil || name == filename {
            raw = apk["sha256"] as? String
        } else { raw = nil }
        guard let raw, raw.range(of: "^[a-fA-F0-9]{64}$", options: .regularExpression) != nil else { return nil }
        return raw.lowercased()
    }
}
