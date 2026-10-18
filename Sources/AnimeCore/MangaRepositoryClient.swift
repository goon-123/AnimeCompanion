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
        let assets = try JSONDecoder().decode([String: ReleaseAssets].self, from: await checksums)
        for i in catalog.extensions.indices {
            let entry = catalog.extensions[i]
            if let asset = assets[entry.packageName]?.apk, asset.name == entry.apkURL.lastPathComponent,
               asset.sha256.range(of: "^[a-fA-F0-9]{64}$", options: .regularExpression) != nil {
                catalog.extensions[i].sha256 = asset.sha256.lowercased()
            }
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
    private struct ReleaseAssets: Decodable {
        let apk: Asset?
        struct Asset: Decodable { let name: String; let sha256: String }
    }
}
