import Foundation

public enum MangaSourceSettingValue: Equatable, Sendable, Codable {
    case string(String), boolean(Bool), integer(Int32), long(Int64), decimal(Float), stringSet([String])
    private enum CodingKeys: String, CodingKey { case type, value }
    private enum Kind: String, Codable { case string, boolean, integer, long, decimal, stringSet }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .type) {
        case .string: self = .string(try c.decode(String.self, forKey: .value))
        case .boolean: self = .boolean(try c.decode(Bool.self, forKey: .value))
        case .integer: self = .integer(try c.decode(Int32.self, forKey: .value))
        case .long: self = .long(try c.decode(Int64.self, forKey: .value))
        case .decimal: self = .decimal(try c.decode(Float.self, forKey: .value))
        case .stringSet: self = .stringSet(try c.decode([String].self, forKey: .value))
        }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .string(let value): try c.encode(Kind.string, forKey: .type); try c.encode(value, forKey: .value)
        case .boolean(let value): try c.encode(Kind.boolean, forKey: .type); try c.encode(value, forKey: .value)
        case .integer(let value): try c.encode(Kind.integer, forKey: .type); try c.encode(value, forKey: .value)
        case .long(let value): try c.encode(Kind.long, forKey: .type); try c.encode(value, forKey: .value)
        case .decimal(let value): try c.encode(Kind.decimal, forKey: .type); try c.encode(value, forKey: .value)
        case .stringSet(let value): try c.encode(Kind.stringSet, forKey: .type); try c.encode(value, forKey: .value)
        }
    }
    public var text: String? { if case .string(let value) = self { return value }; return nil }
    public var boolean: Bool? { if case .boolean(let value) = self { return value }; return nil }
    public var strings: [String]? { if case .stringSet(let value) = self { return value }; return nil }
}

public struct MangaSourceSetting: Codable, Equatable, Identifiable, Sendable {
    public enum Control: String, Codable, Sendable { case toggle, choice, multiChoice, text, unsupported }
    public struct Choice: Codable, Equatable, Identifiable, Sendable {
        public var id: String { value }
        public let label: String
        public let value: String
        public init(label: String, value: String) { self.label = label; self.value = value }
    }
    public let id: String
    public let key: String
    public let title: String
    public let summary: String
    public let section: String?
    public let control: Control
    public let enabled: Bool
    public let choices: [Choice]
    public let defaultValue: MangaSourceSettingValue?
    public init(id: String, key: String, title: String, summary: String = "", section: String? = nil,
                control: Control, enabled: Bool = true, choices: [Choice] = [], defaultValue: MangaSourceSettingValue? = nil) {
        self.id = id; self.key = key; self.title = title; self.summary = summary; self.section = section
        self.control = control; self.enabled = enabled; self.choices = choices; self.defaultValue = defaultValue
    }
    public var isSecret: Bool {
        let text = (key + " " + title).lowercased()
        return ["password", "secret", "token", "api_key", "apikey", "api key"].contains { text.contains($0) }
    }
    public func accepts(_ value: MangaSourceSettingValue) -> Bool {
        switch (control, value) {
        case (.toggle, .boolean), (.text, .string): return true
        case (.choice, .string(let item)): return choices.contains { $0.value == item }
        case (.multiChoice, .stringSet(let items)): return Set(items).isSubset(of: Set(choices.map(\.value)))
        default: return false
        }
    }
}

public struct MangaSourceSettingsSchema: Codable, Equatable, Sendable {
    public let sourceID: String
    public let settings: [MangaSourceSetting]
    public init(sourceID: String, settings: [MangaSourceSetting]) { self.sourceID = sourceID; self.settings = settings }
}

/// Settings can contain source credentials; the app persists this envelope in
/// a separate Keychain item rather than its library/history JSON files.
public struct MangaSourceSettings: Codable, Equatable, Sendable {
    public let schema: Int
    public var values: [String: MangaSourceSettingValue]
    public init(values: [String: MangaSourceSettingValue] = [:]) { schema = 1; self.values = values }
    public func encoded() throws -> Data {
        guard schema == 1, values.count <= 128, values.allSatisfy({ key, value in
            guard !key.isEmpty, key.utf8.count <= 256 else { return false }
            switch value {
            case .string(let text): return text.utf8.count <= 16_384
            case .stringSet(let items): return items.count <= 128 && items.allSatisfy { $0.utf8.count <= 4096 }
            case .decimal(let value): return value.isFinite
            default: return true
            }
        }) else { throw MangaExtensionError.invalidSourceSettings }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(self)
        guard data.count <= 65_536 else { throw MangaExtensionError.invalidSourceSettings }
        return data
    }
    public static func decode(_ data: Data) throws -> Self {
        guard data.count <= 65_536 else { throw MangaExtensionError.invalidSourceSettings }
        let settings = try JSONDecoder().decode(Self.self, from: data)
        _ = try settings.encoded()
        return settings
    }
}
