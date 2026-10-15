import Foundation

public struct AddonManifestBehavior: Codable, Sendable {
    public let configurable: Bool?
    public let configurationRequired: Bool?
    public let adult: Bool?
    public let p2p: Bool?
}

public struct AddonCatalogExtra: Codable, Sendable {
    public let name: String
    public let isRequired: Bool?
    public let options: [String]?
    public let optionsLimit: Int?
}

public struct AddonCatalog: Codable, Sendable, Identifiable {
    public let type: String
    public let id: String
    public let name: String?
    public let extra: [AddonCatalogExtra]?
    public let extraSupported: [String]?
    public let extraRequired: [String]?
    public var displayName: String { PlaybackSourceText.clean(name, maximumLines: 1) ?? id }
    public var extras: [AddonCatalogExtra] {
        extra ?? (extraSupported ?? []).map { AddonCatalogExtra(name: $0, isRequired: extraRequired?.contains($0), options: nil, optionsLimit: nil) }
    }
    public func accepts(_ extra: String) -> Bool { extras.contains { $0.name == extra } }
}

/// A provider's exact type/video ID. Never inferred from an AniList season number.
public struct StremioVideoRequest: Hashable, Sendable {
    public let type: String
    public let id: String
    public init(type: String, id: String) { self.type = type; self.id = id }
}

public struct StremioVideo: Decodable, Identifiable, Sendable {
    public let id: String
    public let title: String?
    public let season: Int?
    public let episode: Int?
    public let streams: [StremioStream]?
    public var displayTitle: String {
        PlaybackSourceText.clean(title, maximumLines: 1) ?? (episode.map { "Episode \($0)" } ?? id)
    }
}

public struct StremioMeta: Decodable, Identifiable, Sendable {
    public let id: String
    public let type: String
    public let name: String
    public let poster: String?
    public let description: String?
    public let genres: [String]?
    public let videos: [StremioVideo]?
    public var displayName: String { PlaybackSourceText.clean(name, maximumLines: 2) ?? "Untitled" }
}

public struct CatalogResults: Sendable {
    public let metas: [StremioMeta]
    /// Includes malformed entries so pagination never repeats the preceding page.
    public let receivedCount: Int
    public var skippedCount: Int { receivedCount - metas.count }
}

private struct LossyResource<T: Decodable & Sendable>: Decodable, Sendable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}
private struct CatalogEnvelope: Decodable { let metas: [LossyResource<StremioMeta>] }
private struct MetaEnvelope: Decodable {
    let meta: StremioMeta?
    private enum CodingKeys: String, CodingKey { case meta }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard values.contains(.meta) else { throw PlaybackError.invalidManifest }
        meta = try values.decodeIfPresent(StremioMeta.self, forKey: .meta)
    }
}
private struct SubtitleEnvelope: Decodable { let subtitles: [LossyResource<StreamSubtitle>] }
private struct ExactStreamEnvelope: Decodable { let streams: [LossyResource<StremioStream>] }

extension StremioClient {
    public func catalog(addon: InstalledAddon, catalog: AddonCatalog, extra: [String: String] = [:]) async throws -> CatalogResults {
        guard addon.manifest.behaviorHints?.configurationRequired != true else { throw PlaybackError.configurationRequired }
        guard addon.manifest.supports(resource: "catalog", type: catalog.type, id: catalog.id),
              (addon.manifest.catalogs ?? []).contains(where: { $0.id == catalog.id && $0.type == catalog.type }),
              catalog.extras.filter({ $0.isRequired == true }).allSatisfy({ extra[$0.name]?.isEmpty == false }) else { throw PlaybackError.unsupportedResource }
        let url = try addon.endpoint.resourceURL("catalog", type: catalog.type, id: catalog.id, extra: extra)
        let data = try await fetch(url, timeout: 30)
        guard let envelope = try? JSONDecoder().decode(CatalogEnvelope.self, from: data) else { throw PlaybackError.invalidManifest }
        let metas = envelope.metas.compactMap(\.value).filter { !$0.id.isEmpty && !$0.name.isEmpty && !$0.type.isEmpty }
        if metas.isEmpty && !envelope.metas.isEmpty { throw PlaybackError.invalidManifest }
        return CatalogResults(metas: metas, receivedCount: envelope.metas.count)
    }
    public func meta(addon: InstalledAddon, request: StremioVideoRequest) async throws -> StremioMeta? {
        try check(addon, resource: "meta", request: request)
        let data = try await fetch(addon.endpoint.resourceURL("meta", type: request.type, id: request.id), timeout: 30)
        guard let envelope = try? JSONDecoder().decode(MetaEnvelope.self, from: data) else { throw PlaybackError.invalidManifest }
        if let meta = envelope.meta {
            guard meta.id == request.id, meta.type == request.type else { throw PlaybackError.invalidManifest }
        }
        return envelope.meta
    }
    public func streams(addon: InstalledAddon, request: StremioVideoRequest) async throws -> StreamResults {
        try check(addon, resource: "stream", request: request)
        let data = try await fetch(addon.endpoint.streamURL(type: request.type, id: request.id), timeout: 90)
        guard let envelope = try? JSONDecoder().decode(ExactStreamEnvelope.self, from: data) else { throw PlaybackError.invalidManifest }
        let streams = envelope.streams.compactMap(\.value)
        if streams.isEmpty && !envelope.streams.isEmpty { throw PlaybackError.invalidManifest }
        return StreamResults(streams: streams, skippedCount: envelope.streams.count - streams.count)
    }
    public func subtitles(addon: InstalledAddon, request: StremioVideoRequest, stream: StremioStream) async throws -> [StreamSubtitle] {
        try check(addon, resource: "subtitles", request: request)
        var extra: [String: String] = [:]
        if let value = stream.behaviorHints?.videoHash { extra["videoHash"] = value }
        if let value = stream.behaviorHints?.videoSize { extra["videoSize"] = String(value) }
        if let value = stream.behaviorHints?.filename { extra["filename"] = value }
        let data = try await fetch(addon.endpoint.resourceURL("subtitles", type: request.type, id: request.id, extra: extra), timeout: 30)
        guard let envelope = try? JSONDecoder().decode(SubtitleEnvelope.self, from: data) else { throw PlaybackError.invalidManifest }
        let subtitles = envelope.subtitles.compactMap(\.value)
        if subtitles.isEmpty && !envelope.subtitles.isEmpty { throw PlaybackError.invalidManifest }
        return subtitles.filter { $0.videoURL != nil }
    }
    private func check(_ addon: InstalledAddon, resource: String, request: StremioVideoRequest) throws {
        guard addon.manifest.behaviorHints?.configurationRequired != true else { throw PlaybackError.configurationRequired }
        guard addon.manifest.supports(resource: resource, type: request.type, id: request.id) else { throw PlaybackError.unsupportedResource }
    }
}

/// Only intercept install links in a top-level navigation initiated in the browser.
/// Ordinary configuration pages stay on the provider's real website.
public enum AddonBrowserLink {
    public static let directoryURL = URL(string: "https://stremio-addons.net/addons?categories=anime&sort=popular")!
    public static func installEndpoint(_ url: URL) -> AddonEndpoint? {
        if let direct = directEndpoint(url) { return direct }
        // The directory also offers this official Stremio Web install handoff.
        // It embeds a raw URL today; other clients percent-encode the whole URL.
        // Decode only an encoded wrapper, never an opaque configured URL twice.
        guard permitsPage(url), url.host?.lowercased() == "web.stremio.com", url.port == nil,
              url.path.isEmpty || url.path == "/", let fragment = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedFragment,
              fragment.hasPrefix("/addons?addon=") else { return nil }
        let raw = String(fragment.dropFirst("/addons?addon=".count))
        let input = raw.hasPrefix("https://") || raw.hasPrefix("stremio://") ? raw : raw.removingPercentEncoding
        guard let input, let nested = URL(string: input) else { return nil }
        return directEndpoint(nested)
    }
    private static func directEndpoint(_ url: URL) -> AddonEndpoint? {
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard ["https", "stremio"].contains(url.scheme?.lowercased() ?? ""),
              path == "manifest.json" || path.hasSuffix("/manifest.json") else { return nil }
        return try? AddonEndpoint(url.absoluteString)
    }
    public static func permitsPage(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.host?.isEmpty == false && url.user == nil && url.password == nil
    }
}
