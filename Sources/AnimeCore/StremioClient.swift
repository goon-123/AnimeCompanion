import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum PlaybackError: LocalizedError, Equatable {
    case invalidAddon, invalidManifest, unsupportedAnime, unsupportedResource, configurationRequired, http(Int), unavailable, invalidVideo, needsProxy, invalidCallback
    public var errorDescription: String? {
        switch self {
        case .invalidAddon: return "Paste the add-on’s HTTPS install link or manifest URL."
        case .invalidManifest: return "This link did not return a valid add-on response. Check the manifest link in your add-on’s settings."
        case .unsupportedAnime: return "This add-on does not advertise support for this anime’s AniList or MyAnimeList ID."
        case .unsupportedResource: return "No enabled add-on advertises support for this resource and video ID. Try an installed catalog or check the exact ID."
        case .configurationRequired: return "Configure this add-on first, then use the install link from its configuration page."
        case .http(let status):
            if status == 401 || status == 403 { return "The add-on rejected this connection. Copy a fresh install link from its settings." }
            if status == 429 { return "The add-on is busy. Wait a moment before trying again." }
            return "The add-on returned HTTP \(status). Please try again."
        case .unavailable: return "The add-on could not be reached or timed out. Check your connection and try again."
        case .invalidVideo: return "This source does not provide a direct video URL for VidHub."
        case .needsProxy: return "This source requires special playback headers. Configure a proxy in your add-on before opening it in VidHub."
        case .invalidCallback: return "VidHub returned incomplete playback information. Your saved progress has not changed."
        }
    }
}

/// The full URL can contain account credentials. Keep it in Keychain, never logs or analytics.
public struct AddonEndpoint: Codable, Hashable, Sendable {
    public let manifestURL: URL
    public var displayHost: String { manifestURL.host ?? "Streaming add-on" }
    public init(_ input: String) throws {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains(where: { $0.isWhitespace }), var parts = URLComponents(string: trimmed) else { throw PlaybackError.invalidAddon }
        if parts.scheme?.lowercased() == "stremio" { parts.scheme = "https" }
        guard parts.scheme?.lowercased() == "https", let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.fragment == nil else { throw PlaybackError.invalidAddon }
        var path = parts.percentEncodedPath
        while path.hasSuffix("/") { path.removeLast() }
        if !path.hasSuffix("/manifest.json") { path += "/manifest.json" }
        parts.percentEncodedPath = path
        guard let url = parts.url else { throw PlaybackError.invalidAddon }
        manifestURL = url
    }
    public func streamURL(type: String, id: String) throws -> URL {
        try resourceURL("stream", type: type, id: id)
    }
    public var configurationURL: URL {
        var parts = URLComponents(url: manifestURL, resolvingAgainstBaseURL: false)!
        parts.percentEncodedPath = String(parts.percentEncodedPath.dropLast("manifest.json".count)) + "configure"
        return parts.url!
    }
    public func resourceURL(_ resource: String, type: String, id: String, extra: [String: String] = [:]) throws -> URL {
        guard ["stream", "meta", "catalog", "subtitles", "addon_catalog"].contains(resource),
              var parts = URLComponents(url: manifestURL, resolvingAgainstBaseURL: false) else { throw PlaybackError.invalidAddon }
        let kind = try Self.segment(type), identifier = try Self.segment(id)
        let extras = try extra.sorted { $0.key < $1.key }.map { try Self.segment($0.key) + "=" + Self.segment($0.value, allowEmpty: true, colon: false) }.joined(separator: "&")
        // Edit only the suffix; opaque, percent-encoded configuration and query data stay intact.
        parts.percentEncodedPath = String(parts.percentEncodedPath.dropLast("manifest.json".count)) + "\(resource)/\(kind)/\(identifier)" + (extras.isEmpty ? "" : "/\(extras)") + ".json"
        guard let url = parts.url else { throw PlaybackError.invalidAddon }
        return url
    }
    private static func segment(_ value: String, allowEmpty: Bool = false, colon: Bool = true) throws -> String {
        guard (allowEmpty || !value.isEmpty), value.utf8.count <= 4096,
              !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              !value.split(separator: "/", omittingEmptySubsequences: false).contains(where: { $0 == "." || $0 == ".." }) else { throw PlaybackError.invalidAddon }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~" + (colon ? ":" : ""))
        guard let encoded = value.addingPercentEncoding(withAllowedCharacters: allowed) else { throw PlaybackError.invalidAddon }
        return encoded
    }
}

public struct AddonResource: Codable, Sendable {
    public let name: String
    public let types: [String]?
    public let idPrefixes: [String]?
    public let usesGlobalScope: Bool
    public init(from decoder: Decoder) throws {
        if let name = try? decoder.singleValueContainer().decode(String.self) {
            self.name = name; types = nil; idPrefixes = nil; usesGlobalScope = true
        } else {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            name = try values.decode(String.self, forKey: .name)
            types = try values.decodeIfPresent([String].self, forKey: .types)
            idPrefixes = try values.decodeIfPresent([String].self, forKey: .idPrefixes)
            // Older saved string resources were encoded as {name:...}. Object
            // resources in the protocol declare types and do not inherit prefixes.
            usesGlobalScope = types == nil && idPrefixes == nil
        }
    }
    public func encode(to encoder: Encoder) throws {
        if usesGlobalScope { var value = encoder.singleValueContainer(); try value.encode(name) }
        else {
            var values = encoder.container(keyedBy: CodingKeys.self)
            try values.encode(name, forKey: .name); try values.encodeIfPresent(types, forKey: .types)
            try values.encodeIfPresent(idPrefixes, forKey: .idPrefixes)
        }
    }
    private enum CodingKeys: String, CodingKey { case name, types, idPrefixes }
}

public struct AddonManifest: Codable, Sendable {
    public let id: String
    public let name: String
    public let types: [String]
    public let resources: [AddonResource]
    public let idPrefixes: [String]?
    public let catalogs: [AddonCatalog]?
    public let behaviorHints: AddonManifestBehavior?
    public let description: String?
    public let version: String?
    public func advertises(_ resource: String) -> Bool { resources.contains { $0.name == resource } }
    public func supports(type: String, id: String) -> Bool {
        supports(resource: "stream", type: type, id: id)
    }
    public func supports(resource name: String, type: String, id: String) -> Bool {
        resources.contains { resource in
            guard resource.name == name, (resource.types ?? types).contains(type) else { return false }
            if name == "catalog" || name == "addon_catalog" { return true }
            let prefixes = resource.usesGlobalScope ? idPrefixes : resource.idPrefixes
            return prefixes?.contains(where: { id.hasPrefix($0) }) ?? true
        }
    }
    public var capabilitySummary: String {
        let labels = ["catalog": "Catalogs", "meta": "Metadata", "stream": "Streams", "subtitles": "Subtitles", "addon_catalog": "Add-on directory"]
        var seen = Set<String>()
        return resources.filter { seen.insert($0.name).inserted }.map { labels[$0.name] ?? "Unsupported resource: \($0.name)" }.joined(separator: " · ")
    }
}

public struct InstalledAddon: Codable, Sendable {
    public let endpoint: AddonEndpoint
    public let manifest: AddonManifest
    public init(endpoint: AddonEndpoint, manifest: AddonManifest) { self.endpoint = endpoint; self.manifest = manifest }
}

public struct AnimeStreamRequest: Equatable, Sendable {
    public let type: String
    public let id: String
    public static func candidates(anime: Anime, episode: Int, manifest: AddonManifest) -> [Self] {
        guard anime.id > 0, episode > 0, anime.episodes.map({ $0 <= 0 || episode <= $0 }) ?? true else { return [] }
        let movie = anime.format == "MOVIE"
        let suffix = movie ? "" : ":\(episode)"
        let ids = ["anilist:\(anime.id)\(suffix)"] + (anime.idMal.flatMap { $0 > 0 ? "mal:\($0)\(suffix)" : nil }.map { [$0] } ?? [])
        return ids.compactMap { id in
            // AIOStreams expects movie/series, and identifies anime from the ID itself.
            guard let type = [movie ? "movie" : "series", "anime"].first(where: { manifest.supports(type: $0, id: id) }) else { return nil }
            return Self(type: type, id: id)
        }
    }
}

public struct StreamSubtitle: Codable, Hashable, Sendable {
    public let id: String?
    public let lang: String?
    public let url: String
    public var videoURL: URL? { StremioStream.networkURL(url) }
}
public struct StreamProxyHeaders: Codable, Sendable {
    public let request: [String: String]?
    public let response: [String: String]?
    public var isRequired: Bool { !(request ?? [:]).isEmpty || !(response ?? [:]).isEmpty }
}
public struct StreamBehavior: Codable, Sendable {
    public let filename: String?
    public let proxyHeaders: StreamProxyHeaders?
    public let videoHash: String?
    public let videoSize: Int64?
    private enum CodingKeys: String, CodingKey { case filename, proxyHeaders, videoHash, videoSize }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        filename = try values.decodeIfPresent(String.self, forKey: .filename)
        proxyHeaders = try values.decodeIfPresent(StreamProxyHeaders.self, forKey: .proxyHeaders)
        videoHash = try? values.decodeIfPresent(String.self, forKey: .videoHash)
        let bytes = (try? values.decodeIfPresent(Int64.self, forKey: .videoSize)) ?? (try? values.decodeIfPresent(String.self, forKey: .videoSize)).flatMap(Int64.init)
        videoSize = bytes.flatMap { $0 >= 0 ? $0 : nil }
    }
}
public struct StremioStream: Codable, Sendable {
    public let name: String?
    public let title: String?
    public let description: String?
    public let url: String?
    public let externalUrl: String?
    public let infoHash: String?
    public let behaviorHints: StreamBehavior?
    public let subtitles: [StreamSubtitle]?
    public var displayName: String { PlaybackSourceText.clean(name, maximumLines: 1, maximumCharacters: 80) ?? "Video source" }
    public var details: String {
        [description, title, behaviorHints?.filename].compactMap { PlaybackSourceText.clean($0) }.first ?? "Source details unavailable"
    }
    public var videoURL: URL? { Self.networkURL(url) }
    public var unavailableReason: String? {
        if behaviorHints?.proxyHeaders?.isRequired == true { return "Requires a playback proxy" }
        if videoURL != nil { return nil }
        if infoHash != nil { return "Torrent-only source · needs a streaming service" }
        if externalUrl != nil { return "Webpage link · no direct video URL" }
        return "No supported video URL"
    }
    public static func networkURL(_ value: String?) -> URL? {
        guard let value, let url = URL(string: value), ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              url.host?.isEmpty == false else { return nil }
        return url
    }
}

public struct StreamResults: Sendable {
    public let streams: [StremioStream]
    public let skippedCount: Int
}
public struct StremioClient: Sendable {
    private let transport: any HTTPTransport
    public init(transport: (any HTTPTransport)? = nil) {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.timeoutIntervalForRequest = 90
        config.timeoutIntervalForResource = 100
        self.transport = transport ?? URLSessionTransport(session: URLSession(configuration: config))
    }
    public func install(_ input: String) async throws -> InstalledAddon {
        let endpoint = try AddonEndpoint(input)
        let data = try await fetch(endpoint.manifestURL, timeout: 25)
        guard let manifest = try? JSONDecoder().decode(AddonManifest.self, from: data),
              !manifest.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !manifest.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !manifest.resources.isEmpty, manifest.resources.allSatisfy({ !$0.name.isEmpty }) else {
            throw PlaybackError.invalidManifest
        }
        return InstalledAddon(endpoint: endpoint, manifest: manifest)
    }
    public func streams(addon: InstalledAddon, anime: Anime, episode: Int) async throws -> StreamResults {
        guard addon.manifest.behaviorHints?.configurationRequired != true else { throw PlaybackError.configurationRequired }
        let candidates = AnimeStreamRequest.candidates(anime: anime, episode: episode, manifest: addon.manifest)
        guard !candidates.isEmpty else { throw PlaybackError.unsupportedAnime }
        var lastError: Error?
        var emptyResponse = false
        for candidate in candidates {
            try Task.checkCancellation()
            do {
                let result = try await streams(addon: addon, request: .init(type: candidate.type, id: candidate.id))
                if !result.streams.isEmpty { return result }
                emptyResponse = true
            } catch let error as PlaybackError {
                if case .http(let status) = error, status == 400 || status == 404 { lastError = error; continue }
                throw error
            }
        }
        if emptyResponse { return StreamResults(streams: [], skippedCount: 0) }
        throw lastError ?? PlaybackError.unsupportedAnime
    }
    func fetch(_ url: URL, timeout: TimeInterval) async throws -> Data {
        do {
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await transport.data(for: request)
            try Task.checkCancellation()
            guard (200..<300).contains(response.statusCode) else { throw PlaybackError.http(response.statusCode) }
            guard data.count <= 8_000_000 else { throw PlaybackError.invalidManifest }
            return data
        } catch is CancellationError { throw CancellationError() }
        catch let error as URLError where error.code == .cancelled { throw CancellationError() }
        catch let error as PlaybackError { throw error }
        catch { throw PlaybackError.unavailable } // Never surface URLSession errors containing private URLs.
    }
}
