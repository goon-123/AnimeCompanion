import Foundation

/// A catalog title in one stable MangaBaka account, independent of source names.
public struct MangaSourceLinkTarget: Codable, Hashable, Identifiable, Sendable {
    public let accountID: String
    public let seriesID: Int
    public let title: String
    public let searchTitles: [String]
    public var id: String { MangaSourceReference.key(["mangabaka", accountID, String(seriesID)]) }
    public init(accountID: String, seriesID: Int, title: String, searchTitles: [String]) {
        self.accountID = accountID; self.seriesID = seriesID; self.title = title; self.searchTitles = searchTitles
    }
}

public struct MangaSourceLink: Codable, Equatable, Identifiable, Sendable {
    public let library: MangaSourceLinkTarget
    public let title: MangaTitleReference
    public let updatedAt: Date
    public var id: String { library.id }
    public init(library: MangaSourceLinkTarget, title: MangaTitleReference, updatedAt: Date = Date()) {
        self.library = library; self.title = title; self.updatedAt = updatedAt
    }
}

public struct MangaSourceLinkState: Codable, Sendable {
    public var schemaVersion = 1
    public var revision: UInt64 = 0
    public var links: [String: MangaSourceLink] = [:]
    public init() {}
}

public enum MangaSourceLinkError: LocalizedError {
    case unreadable, tooLarge, invalidLink
    public var errorDescription: String? {
        switch self {
        case .unreadable: return "Saved reading-source links could not be opened. Existing links have been kept."
        case .tooLarge: return "Saved reading-source links exceed this device's storage limit."
        case .invalidLink: return "This title or reading source cannot be linked. Choose it again."
        }
    }
}

/// Separate from frequently updated page progress so linking never rewrites or
/// migrates reading history. Failed reads and writes leave existing data intact.
public actor MangaSourceLinkStorage {
    private let directory: URL
    private var cached: MangaSourceLinkState?
    public init(directory: URL) { self.directory = directory }
    public func load() throws -> MangaSourceLinkState {
        if let cached { return cached }
        let file = directory.appendingPathComponent("source-links.json")
        guard FileManager.default.fileExists(atPath: file.path) else {
            let empty = MangaSourceLinkState(); cached = empty; return empty
        }
        do {
            let data = try Data(contentsOf: file)
            guard data.count <= 16_000_000 else { throw MangaSourceLinkError.tooLarge }
            let value = try JSONDecoder().decode(MangaSourceLinkState.self, from: data)
            guard value.schemaVersion == 1, value.links.count <= 5000,
                  value.links.allSatisfy({ $0.key == $0.value.id && Self.valid($0.value) }) else {
                throw MangaSourceLinkError.unreadable
            }
            cached = value; return value
        } catch { throw MangaSourceLinkError.unreadable }
    }
    @discardableResult
    public func setSource(_ title: MangaTitleReference?, for target: MangaSourceLinkTarget) throws -> MangaSourceLinkState {
        var value = try load()
        if let title {
            let link = MangaSourceLink(library: target, title: title)
            guard Self.valid(link) else { throw MangaSourceLinkError.invalidLink }
            value.links[target.id] = link
        } else { value.links.removeValue(forKey: target.id) }
        guard value.links.count <= 5000, value.revision < UInt64.max else { throw MangaSourceLinkError.tooLarge }
        value.revision += 1
        let data = try JSONEncoder().encode(value)
        guard data.count <= 16_000_000 else { throw MangaSourceLinkError.tooLarge }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent("source-links.json"), options: .atomic)
        cached = value; return value
    }
    private static func valid(_ link: MangaSourceLink) -> Bool {
        !link.library.accountID.isEmpty && link.library.seriesID > 0 &&
        !link.title.source.extensionID.isEmpty && !link.title.source.sourceID.isEmpty &&
        !link.title.manga.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
