import Foundation

/// A stable, opaque identity keeps configured URLs out of row IDs and diagnostics.
public struct AddonInstallation: Codable, Identifiable, Sendable {
    public let id: UUID
    public var addon: InstalledAddon
    public var enabled: Bool
    public init(id: UUID = UUID(), addon: InstalledAddon, enabled: Bool = true) {
        self.id = id; self.addon = addon; self.enabled = enabled
    }
}

public struct AddonCollection: Codable, Sendable {
    public private(set) var installations: [AddonInstallation]
    public var enabled: [AddonInstallation] { installations.filter(\.enabled) }
    public init() { installations = [] }

    /// Reconnecting the same endpoint updates its metadata in place. Two different
    /// configurations of the same manifest ID remain independent installations.
    @discardableResult
    public mutating func install(_ addon: InstalledAddon) -> UUID {
        if let index = installations.firstIndex(where: { $0.addon.endpoint == addon.endpoint }) {
            installations[index].addon = addon; installations[index].enabled = true
            return installations[index].id
        }
        let entry = AddonInstallation(addon: addon)
        installations.append(entry)
        return entry.id
    }
    public mutating func setEnabled(_ enabled: Bool, id: UUID) {
        guard let index = installations.firstIndex(where: { $0.id == id }) else { return }
        installations[index].enabled = enabled
    }
    public mutating func remove(id: UUID) { installations.removeAll { $0.id == id } }

    private enum CodingKeys: String, CodingKey { case installations }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.installations) {
            installations = try container.decode([AddonInstallation].self, forKey: .installations)
            guard Set(installations.map(\.id)).count == installations.count,
                  Set(installations.map { $0.addon.endpoint }).count == installations.count else {
                throw DecodingError.dataCorruptedError(forKey: .installations, in: container, debugDescription: "Duplicate saved add-on identities.")
            }
        } else {
            // The existing Keychain item contained a single InstalledAddon.
            installations = [AddonInstallation(addon: try InstalledAddon(from: decoder))]
        }
    }
}

extension InstalledAddon {
    public var supportsAnime: Bool {
        ["series", "anime"].contains { type in
            ["anilist:1:1", "mal:1:1"].contains { manifest.supports(type: type, id: $0) }
        } || ["anilist:1", "mal:1"].contains { manifest.supports(type: "movie", id: $0) }
    }
}
