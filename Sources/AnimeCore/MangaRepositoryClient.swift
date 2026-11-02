import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct MangaRepositoryClient: Sendable {
    public let transport: any HTTPTransport
    private let releases = MangaReleaseCache()
    public init(transport: any HTTPTransport = URLSessionTransport()) { self.transport = transport }

    public func catalog(repository: MangaRepository = .keiyoushi) async throws -> MangaExtensionCatalog {
        // release-assets.json contains version/signature-independent BUILD CONTENT
        // hashes, not APK byte hashes. Resolve the exact release asset at install time.
        try MangaExtensionCatalog.decode(await load(repository.indexURL, limit: 8_000_000))
    }

    /// Always replaces cached catalog hashes, including values saved by older app
    /// versions. Only GitHub's digest for this exact tag, filename and URL is used.
    public func verifiedDescriptor(_ entry: MangaExtensionDescriptor, refresh: Bool = false) async throws -> MangaExtensionDescriptor {
        let location = try MangaReleaseLocation(entry.apkURL)
        let release: MangaRelease
        if !refresh, let cached = await releases.value(for: location.apiURL) { release = cached }
        else {
            let data = try await load(location.apiURL, limit: 8_000_000)
            guard let decoded = try? JSONDecoder().decode(MangaRelease.self, from: data),
                  !decoded.draft, decoded.tagName == location.tag else { throw MangaExtensionError.checksumUnavailable }
            release = decoded
            await releases.save(release, for: location.apiURL)
        }
        let matches = release.assets.filter { $0.name == location.filename && $0.url == entry.apkURL.absoluteString && $0.state == "uploaded" }
        guard matches.count == 1, let digest = matches.first?.digest, digest.hasPrefix("sha256:"),
              let checksum = Self.checksum(String(digest.dropFirst(7))) else { throw MangaExtensionError.checksumUnavailable }
        var verified = entry
        verified.sha256 = checksum
        return verified
    }

    public func package(_ entry: MangaExtensionDescriptor) async throws -> Data {
        guard entry.supportsRuntime else { throw MangaExtensionError.unsupportedAPI }
        _ = try MangaReleaseLocation(entry.apkURL)
        guard let digest = entry.sha256, Self.checksum(digest) != nil else { throw MangaExtensionError.checksumUnavailable }
        return try await load(entry.apkURL, limit: 32 * 1024 * 1024)
    }

    private func load(_ url: URL, limit: Int) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData); request.timeoutInterval = 45
        request.setValue("AnimeCompanion/0.45.1 (manga extensions)", forHTTPHeaderField: "User-Agent")
        if url.host == "api.github.com" { request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept") }
        let (data, response) = try await transport.data(for: request)
        try HTTPValidation.check(response)
        guard !data.isEmpty, data.count <= limit else { throw MangaExtensionError.oversized }
        return data
    }
    private static func checksum(_ raw: String) -> String? {
        guard raw.range(of: "^[a-fA-F0-9]{64}$", options: .regularExpression) != nil else { return nil }
        return raw.lowercased()
    }
}

private struct MangaReleaseLocation {
    let tag: String
    let filename: String
    let apiURL: URL
    init(_ url: URL) throws {
        guard let p = URLComponents(url: url, resolvingAgainstBaseURL: false),
              p.scheme == "https", p.host == "github.com", p.user == nil, p.password == nil,
              p.port == nil, p.query == nil, p.fragment == nil else { throw MangaExtensionError.invalidRepository }
        let parts = p.path.split(separator: "/").map(String.init)
        guard parts.count == 6, Array(parts.prefix(4)) == ["keiyoushi", "extensions", "releases", "download"],
              parts[4].range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil,
              parts[5].range(of: "^[A-Za-z0-9_.-]+\\.apk$", options: .regularExpression) != nil else { throw MangaExtensionError.invalidRepository }
        tag = parts[4]; filename = parts[5]
        apiURL = URL(string: "https://api.github.com/repos/keiyoushi/extensions/releases/tags/\(tag)")!
    }
}

private struct MangaRelease: Decodable, Sendable {
    let tagName: String
    let draft: Bool
    let assets: [Asset]
    enum CodingKeys: String, CodingKey { case tagName = "tag_name", draft, assets }
    struct Asset: Decodable, Sendable {
        let name: String
        let url: String
        let digest: String?
        let state: String
        enum CodingKeys: String, CodingKey { case name, url = "browser_download_url", digest, state }
    }
}

/// A batch often installs several extensions from the same release. Reuse its
/// metadata briefly to avoid spending an unauthenticated API request per APK.
private actor MangaReleaseCache {
    private var entries: [URL: (MangaRelease, Date)] = [:]
    func value(for url: URL) -> MangaRelease? {
        guard let (value, date) = entries[url], Date().timeIntervalSince(date) < 300 else { return nil }
        return value
    }
    func save(_ value: MangaRelease, for url: URL) { entries[url] = (value, Date()) }
}
