import Foundation

public struct MangaBakaSourceRating: Hashable, Sendable {
    public let provider: String
    public let score: Double
}

public enum MangaBakaContentRating: String, CaseIterable, Codable, Hashable, Sendable {
    case safe, suggestive, erotica, pornographic
    public var label: String { rawValue.capitalized }
    public var isMature: Bool { self == .erotica || self == .pornographic }
}

public struct MangaBakaGenre: Decodable, Hashable, Identifiable, Sendable {
    public let value: String
    public let label: String
    public var id: String { value }
    public init(value: String, label: String) { self.value = value; self.label = label }
    public init(from decoder: Decoder) throws {
        if let text = try? decoder.singleValueContainer().decode(String.self) {
            value = text; label = text.replacingOccurrences(of: "_", with: " ").capitalized; return
        }
        let c = try decoder.container(keyedBy: MBKey.self)
        value = c.mbString(.value) ?? c.mbString(.name) ?? ""
        label = c.mbString(.label) ?? value.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

public struct MangaBakaPublisher: Decodable, Hashable, Sendable {
    public let name: String
    public init(from decoder: Decoder) throws {
        if let name = try? decoder.singleValueContainer().decode(String.self) { self.name = name; return }
        name = try decoder.container(keyedBy: MBKey.self).mbString(.name) ?? ""
    }
}

public struct MangaBakaCoverImage: Decodable, Hashable, Identifiable, Sendable {
    public let id: Int
    public let seriesID: Int?
    public let type: String
    public let language: String
    public let index: String
    public let note: String?
    public let contentRating: String?
    private let image: MBCover?
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: MBKey.self)
        guard let value = c.mbInt(.id), value > 0 else { throw MangaBakaError.invalidResponse }
        id = value; seriesID = c.mbInt(.seriesID)
        type = c.mbString(.type) ?? "cover"; language = c.mbString(.language) ?? ""
        index = c.mbString(.index) ?? ""; note = c.mbString(.note)
        contentRating = c.mbString(.contentRating)
        image = try c.decodeIfPresent(MBCover.self, forKey: .image)
    }
    public var thumbnailURL: URL? { [image?.x350?.value, image?.x250?.value, image?.x150?.value, image?.raw?.value].compactMap { $0 }.compactMap(MangaBakaSeries.publicURL).first }
    public var fullURL: URL? { [image?.raw?.value, image?.x350?.value, image?.x250?.value].compactMap { $0 }.compactMap(MangaBakaSeries.publicURL).first }
    public var caption: String {
        let title = index.isEmpty ? type.capitalized : type.capitalized + " " + index
        return language.isEmpty ? title : title + " · " + language.uppercased()
    }
    public func isVisible(includeAdult: Bool) -> Bool { includeAdult || ["safe", "suggestive"].contains(contentRating ?? "") }
}

public enum MangaBakaRelatedKind: String, CaseIterable, Hashable, Sendable {
    case relationships, similar, readers = "readers-also-like"
    public var label: String {
        switch self { case .relationships: return "Related series"; case .similar: return "Similar series"; case .readers: return "Readers also like" }
    }
    public var explanation: String {
        switch self {
        case .relationships: return "Sequels, prequels, adaptations and other connected titles."
        case .similar: return "Similar titles from MangaBaka's shared-tag recommendations."
        case .readers: return "Recommendations based on shared library activity."
        }
    }
}

public struct MangaBakaRelatedSeries: Decodable, Hashable, Identifiable, Sendable {
    public let series: MangaBakaSeries
    public let relationship: String?
    public let sharedTags: Int?
    public let sharedReaders: Int?
    public let matchedRelated: Bool
    public var id: Int { series.id }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: MBKey.self)
        series = try c.decode(MangaBakaSeries.self, forKey: .series)
        relationship = c.mbString(.relationship) ?? c.mbString(.relation) ?? c.mbString(.type)
        sharedTags = c.mbInt(.sharedTags); sharedReaders = c.mbInt(.sharedUsers)
        matchedRelated = (try? c.decode(Bool.self, forKey: .matchedRelated)) ?? false
    }
}
