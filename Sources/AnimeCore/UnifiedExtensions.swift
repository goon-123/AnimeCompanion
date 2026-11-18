import Foundation

/// Retain provider-specific fields (including opaque episode data) across the
/// native UI boundary instead of rebuilding or guessing a provider's URLs.
public enum ExtensionJSON: Codable, Equatable, Sendable {
    case object([String: ExtensionJSON]), array([ExtensionJSON]), string(String), number(Double), bool(Bool), null
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let value = try? c.decode(Bool.self) { self = .bool(value) }
        else if let value = try? c.decode(String.self) { self = .string(value) }
        else if let value = try? c.decode(Double.self) { self = .number(value) }
        else if let value = try? c.decode([String: Self].self) { self = .object(value) }
        else { self = .array(try c.decode([Self].self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
    public subscript(_ key: String) -> ExtensionJSON { if case .object(let values) = self { return values[key] ?? .null }; return .null }
    public var string: String? { if case .string(let value) = self { return value }; return nil }
    public var array: [ExtensionJSON] { if case .array(let value) = self { return value }; return [] }
    public var object: [String: ExtensionJSON] { if case .object(let value) = self { return value }; return [:] }
    public var boolean: Bool { if case .bool(let value) = self { return value }; return false }
    public var foundation: Any {
        switch self {
        case .object(let v): return v.mapValues(\.foundation)
        case .array(let v): return v.map(\.foundation)
        case .string(let v): return v
        case .number(let v): return v
        case .bool(let v): return v
        case .null: return NSNull()
        }
    }
}

public enum ExtensionContentKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case anime, manga, novel
    public var id: String { rawValue }
    public var label: String { switch self { case .anime: return "Anime"; case .manga: return "Manga"; case .novel: return "Novels" } }
}

public struct UnifiedExtensionSource: Codable, Identifiable, Sendable {
    public let sourceID: String
    public let managerId: String
    public let kind: ExtensionContentKind
    public let name: String?
    public let lang: String?
    public let isNsfw: Bool?
    public let iconUrl: String?
    public let baseUrl: String?
    public let version: String?
    public let hasUpdate: Bool?
    public let supportsPopular: Bool?
    public let supportsLatest: Bool?
    public var id: String { [managerId, kind.rawValue, sourceID].joined(separator: ":") }
    public var label: String { name ?? "Source" }
    public func isVisible(includeAdultAnime: Bool, readingContent: MangaBakaContentFilter) -> Bool {
        isNsfw != true || (kind == .anime ? includeAdultAnime : readingContent.allowsMatureSources)
    }
    public var arguments: [String: Any] { ["manager": managerId, "type": kind.rawValue, "source": sourceID] }
    private enum CodingKeys: String, CodingKey {
        case sourceID = "id", managerId, kind, name, lang, isNsfw, iconUrl, baseUrl, version, hasUpdate, supportsPopular, supportsLatest
    }
}
public struct UnifiedExtensionRepository: Decodable, Sendable {
    public let url: String
    public let name: String?
    public let type: ExtensionContentKind
}
public struct UnifiedExtensionManager: Decodable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let types: [ExtensionContentKind]
    public let error: String?
    public let repositories: [UnifiedExtensionRepository]
}
public struct UnifiedExtensionSnapshot: Decodable, Sendable {
    public let managers: [UnifiedExtensionManager]
    public let installed: [UnifiedExtensionSource]
    public let available: [UnifiedExtensionSource]
    public init() { managers = []; installed = []; available = [] }
}

public struct ExtensionMedia: Codable, Identifiable, Sendable {
    public let payload: ExtensionJSON
    public init(payload: ExtensionJSON) { self.payload = payload }
    public init(from decoder: Decoder) throws { payload = try ExtensionJSON(from: decoder) }
    public func encode(to encoder: Encoder) throws { try payload.encode(to: encoder) }
    public var id: String { payload["url"].string ?? title }
    public var title: String { payload["title"].string ?? "Untitled" }
    public var cover: String? { payload["cover"].string }
    public var synopsis: String { payload["description"].string ?? "" }
    public var episodes: [ExtensionEpisode] { payload["episodes"].array.map(ExtensionEpisode.init) }
}
public struct ExtensionEpisode: Codable, Identifiable, Sendable {
    public let payload: ExtensionJSON
    public init(payload: ExtensionJSON) { self.payload = payload }
    public init(from decoder: Decoder) throws { payload = try ExtensionJSON(from: decoder) }
    public func encode(to encoder: Encoder) throws { try payload.encode(to: encoder) }
    public var id: String { payload["url"].string ?? label }
    public var label: String { payload["name"].string ?? payload["episodeNumber"].string.map { "Episode \($0)" } ?? "Chapter" }
}
public struct ExtensionMediaPage: Decodable, Sendable {
    public let list: [ExtensionMedia]
    public let hasNextPage: Bool
}
public struct ExtensionImagePage: Decodable, Sendable {
    public let url: String
    public let headers: [String: String]?
}
public struct ExtensionVideo: Decodable, Sendable {
    public let title: String?
    public let url: String
    public let quality: String
    public let headers: [String: String]?
    public let subtitles: [ExtensionSubtitle]?
    public var arguments: [String: Any] { ["url": url, "headers": headers ?? [:], "title": title ?? quality] }
}
public struct ExtensionSubtitle: Decodable, Sendable {
    public let file: String?
    public let label: String?
}
