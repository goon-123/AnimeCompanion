import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum SeanimeError: LocalizedError, Equatable {
    case invalidManifest, unsupportedType, invalidSource, invalidNetwork, networkHost(String), unavailable, runtime, timeout, invalidResults, adultProvider
    public var errorDescription: String? {
        switch self {
        case .invalidManifest: return "This is not a valid Seanime torrent-provider manifest."
        case .unsupportedType: return "Only anime-torrent-provider extensions are supported. UI plugins, manga and online-streaming providers use different APIs."
        case .invalidSource: return "This extension has no supported JavaScript/TypeScript source."
        case .invalidNetwork: return "Extensions can make read-only HTTPS requests to approved public hosts only."
        case .networkHost(let host): return "This extension needs network access to \(host). Add that host in its configuration only if you trust it."
        case .unavailable: return "The extension source or provider could not be reached."
        case .runtime: return "The provider reported an error or used an unsupported runtime API. This is not a successful empty search."
        case .timeout: return "The provider exceeded its execution limit. Its worker was stopped."
        case .invalidResults: return "The provider returned malformed torrent results."
        case .adultProvider: return "This provider advertises adult content. Enable Show adult anime before searching it."
        }
    }
}

public struct SeanimePreference: Codable, Sendable {
    public struct Option: Codable, Sendable { public let value: String; public let label: String? }
    public let name: String
    public let label: String?
    public let type: String
    public let `default`: String?
    public let options: [Option]?
}
public struct SeanimeUserConfig: Codable, Sendable {
    public let requiresConfig: Bool?
    public let fields: [SeanimePreference]?
}
public struct SeanimeManifest: Codable, Sendable {
    public let id: String
    public let name: String
    public let version: String
    public let type: String
    public let language: String
    public let description: String?
    public let author: String?
    public let payloadURI: String?
    public let payload: String?
    public let userConfig: SeanimeUserConfig?
    public let semverConstraint: String?
    public var adultHint: Bool {
        let text = [id, name, description ?? ""].joined(separator: " ").lowercased()
        return ["sukebei", "hentai", "nsfw", "18+"].contains { text.contains($0) }
    }
}
public struct SeanimeInstallation: Codable, Identifiable, Sendable {
    public let id: UUID
    public let manifestURL: URL
    public let manifest: SeanimeManifest
    /// Snapshot reviewed at installation; remote updates never execute silently.
    public let source: String
    public var enabled: Bool
    public var preferences: [String: String]
    public var allowedHosts: [String]
    /// Explicit confirmation is required for providers with unknown ratings.
    public var adult: Bool
    public init(id: UUID = UUID(), manifestURL: URL, manifest: SeanimeManifest, source: String, enabled: Bool = true,
                preferences: [String: String], allowedHosts: [String], adult: Bool) {
        self.id = id; self.manifestURL = manifestURL; self.manifest = manifest; self.source = source
        self.enabled = enabled; self.preferences = preferences; self.allowedHosts = allowedHosts; self.adult = adult
    }
}

public struct SeanimeTorrent: Codable, Identifiable, Sendable {
    public let name: String
    public let infoHash: String?
    public let magnetLink: String?
    public let downloadUrl: String?
    public let link: String?
    public let formattedSize: String?
    public let size: Double?
    public let seeders: Int?
    public let episodeNumber: Double?
    public let isBatch: Bool?
    public var seederSummary: String {
        guard let seeders, seeders >= 0 else { return "Seeders unlisted" }
        return "\(seeders) seeders"
    }
    public var id: String {
        // Stable presentation/job key, not a security hash. Keep configured URLs
        // and magnet query data out of view identities and diagnostics.
        let raw = infoHash?.lowercased() ?? magnetLink ?? downloadUrl ?? link ?? name
        let digest = raw.utf8.reduce(UInt64(14_695_981_039_346_656_037)) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }
        return String(digest, radix: 16)
    }
    public var magnet: String? {
        if let magnetLink, let parts = URLComponents(string: magnetLink), parts.scheme?.lowercased() == "magnet",
           parts.queryItems?.contains(where: { $0.name == "xt" && $0.value?.hasPrefix("urn:btih:") == true }) == true { return magnetLink }
        if let infoHash, infoHash.range(of: "^(?:[a-fA-F0-9]{40}|[a-zA-Z2-7]{32})$", options: .regularExpression) != nil {
            var parts = URLComponents(); parts.scheme = "magnet"
            parts.queryItems = [.init(name: "xt", value: "urn:btih:\(infoHash)"), .init(name: "dn", value: name)]
            return parts.string
        }
        return nil
    }
}

public enum SeanimeNetworkPolicy {
    public static func publicHost(_ raw: String) -> String? {
        let host = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard host.utf8.count <= 253, host.contains("."), !host.hasSuffix("."),
              host.range(of: "^[a-z0-9]+(?:[a-z0-9.-]*[a-z0-9])?$", options: .regularExpression) != nil,
              ![".local", ".localhost", ".internal", ".test", ".invalid"].contains(where: host.hasSuffix),
              host != "localhost", host != "metadata.google.internal",
              labels.allSatisfy({ !$0.isEmpty && $0.count <= 63 && !$0.hasPrefix("-") && !$0.hasSuffix("-") }),
              labels.last.map({ String($0).range(of: "^(?:[a-z]{2,63}|xn--[a-z0-9-]{2,59})$", options: .regularExpression) != nil }) == true else { return nil }
        return host
    }
    public static func httpsURL(_ input: String) throws -> URL {
        guard let parts = URLComponents(string: input.trimmingCharacters(in: .whitespacesAndNewlines)),
              parts.scheme?.lowercased() == "https", let host = parts.host, publicHost(host) != nil,
              parts.user == nil, parts.password == nil, parts.fragment == nil,
              parts.port == nil || parts.port == 443, let url = parts.url else { throw SeanimeError.invalidNetwork }
        return url
    }
    public static func validate(_ input: String, hosts: [String]) throws -> URL {
        let url = try httpsURL(input)
        guard hosts.map({ $0.lowercased() }).contains(url.host!.lowercased()) else { throw SeanimeError.networkHost(url.host!) }
        return url
    }
    public static func suggestedHosts(source: String, preferences: [String: String], urls: [URL]) -> [String] {
        let expression = try! NSRegularExpression(pattern: "https://[a-zA-Z0-9.-]+")
        let text = source + "\n" + preferences.values.joined(separator: "\n")
        var hosts = Set(urls.compactMap(\.host).compactMap(publicHost))
        for match in expression.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            if let range = Range(match.range, in: text), let host = URL(string: String(text[range]))?.host.flatMap(publicHost) { hosts.insert(host) }
        }
        for value in preferences.values { if let host = publicHost(value) { hosts.insert(host) } }
        return hosts.sorted()
    }
}

/// No cookies, ambient credentials, cache or redirects. Requests to a different
/// host must be reviewed instead of forwarding private extension configuration.
public final class ProviderHTTPTransport: NSObject, HTTPTransport, URLSessionTaskDelegate, @unchecked Sendable {
    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.urlCredentialStorage = nil; config.urlCache = nil
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw SeanimeError.unavailable }
        return (data, response)
    }
    public func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                           newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

public struct SeanimeClient: Sendable {
    private let transport: any HTTPTransport
    public init(transport: any HTTPTransport = ProviderHTTPTransport()) { self.transport = transport }
    public func inspect(_ input: String) async throws -> SeanimeInstallation {
        let url = try SeanimeNetworkPolicy.httpsURL(input)
        let data = try await get(url, maximum: 512_000)
        guard let manifest = try? JSONDecoder().decode(SeanimeManifest.self, from: data),
              !manifest.id.isEmpty, manifest.id.utf8.count <= 512, !manifest.name.isEmpty, manifest.name.utf8.count <= 512,
              !manifest.version.isEmpty, manifest.version.utf8.count <= 128,
              (manifest.userConfig?.fields ?? []).count <= 64 else { throw SeanimeError.invalidManifest }
        guard manifest.type == "anime-torrent-provider" else { throw SeanimeError.unsupportedType }
        guard ["typescript", "javascript"].contains(manifest.language.lowercased()) else { throw SeanimeError.invalidSource }
        let source: String
        var urls = [url]
        if let inline = manifest.payload, !inline.isEmpty { source = inline }
        else if let uri = manifest.payloadURI {
            let payload = try SeanimeNetworkPolicy.httpsURL(uri); urls.append(payload)
            guard let value = String(data: try await get(payload, maximum: 1_000_000), encoding: .utf8) else { throw SeanimeError.invalidSource }
            source = value
        } else { throw SeanimeError.invalidSource }
        guard !source.isEmpty, source.utf8.count <= 1_000_000 else { throw SeanimeError.invalidSource }
        let preferences = Dictionary((manifest.userConfig?.fields ?? []).map { ($0.name, $0.default ?? "") }, uniquingKeysWith: { _, last in last })
        return SeanimeInstallation(manifestURL: url, manifest: manifest, source: source, preferences: preferences,
            allowedHosts: SeanimeNetworkPolicy.suggestedHosts(source: source, preferences: preferences, urls: urls), adult: manifest.adultHint)
    }
    public func fetch(_ input: String, hosts: [String]) async throws -> (String, Int) {
        let url = try SeanimeNetworkPolicy.validate(input, hosts: hosts)
        do {
            let (data, response) = try await transport.data(for: URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20))
            try Task.checkCancellation()
            guard data.count <= 4_000_000, !(300..<400).contains(response.statusCode), let text = String(data: data, encoding: .utf8) else { throw SeanimeError.unavailable }
            return (text, response.statusCode)
        } catch is CancellationError { throw CancellationError() }
        catch { throw SeanimeError.unavailable }
    }
    private func get(_ url: URL, maximum: Int) async throws -> Data {
        do {
            let (data, response) = try await transport.data(for: URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 25))
            try Task.checkCancellation()
            guard (200..<300).contains(response.statusCode), data.count <= maximum else { throw SeanimeError.invalidManifest }
            return data
        } catch is CancellationError { throw CancellationError() }
        catch let error as SeanimeError { throw error }
        catch { throw SeanimeError.unavailable }
    }
}
