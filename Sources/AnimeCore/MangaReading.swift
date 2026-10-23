import Foundation

public struct MangaSourceReference: Codable, Hashable, Identifiable, Sendable {
    public let extensionID: String
    public let sourceID: String
    public let name: String
    public let language: String
    public let homeURL: String
    public let adult: Bool
    public var id: String { Self.key([extensionID, sourceID]) }
    public init(extensionID: String, sourceID: String, name: String, language: String, homeURL: String, adult: Bool = false) {
        self.extensionID = extensionID; self.sourceID = sourceID; self.name = name
        self.language = language; self.homeURL = homeURL; self.adult = adult
    }
    public init(installation: InstalledMangaExtension, source: MangaRuntimeSource) {
        self.init(extensionID: installation.id, sourceID: source.id, name: source.name,
                  language: source.language, homeURL: source.homeURL, adult: installation.descriptor.adult)
    }
    static func key(_ components: [String]) -> String {
        components.map { Data($0.utf8).base64EncodedString() }.joined(separator: ".")
    }
}

public struct MangaTitleReference: Codable, Equatable, Identifiable, Sendable {
    public let source: MangaSourceReference
    public let manga: SourceManga
    public var id: String { MangaSourceReference.key([source.extensionID, source.sourceID, manga.url]) }
    public init(source: MangaSourceReference, manga: SourceManga) { self.source = source; self.manga = manga }
}

public struct MangaBook: Codable, Sendable {
    public let manga: SourceManga
    public let chapters: [SourceMangaChapter]
    public init(manga: SourceManga, chapters: [SourceMangaChapter]) { self.manga = manga; self.chapters = chapters }
}

public struct MangaReadingPosition: Codable, Equatable, Sendable {
    public let chapterURL: String
    public let chapterName: String
    public let pageIndex: Int
    public let pageCount: Int
    /// Position of the viewport's top edge within this source image, including tall strips.
    public let fraction: Double
    public let completed: Bool
    public let updatedAt: Date
    public init(chapterURL: String, chapterName: String, pageIndex: Int, pageCount: Int,
                fraction: Double, completed: Bool = false, updatedAt: Date = Date()) {
        self.chapterURL = chapterURL; self.chapterName = chapterName
        self.pageCount = min(5000, max(0, pageCount))
        self.pageIndex = min(max(0, pageIndex), max(0, self.pageCount - 1))
        self.fraction = fraction.isFinite ? min(1, max(0, fraction)) : 0
        self.completed = completed; self.updatedAt = updatedAt
    }
    public func clamped(to count: Int) -> MangaReadingPosition {
        MangaReadingPosition(chapterURL: chapterURL, chapterName: chapterName, pageIndex: pageIndex,
                             pageCount: count, fraction: fraction, completed: completed, updatedAt: updatedAt)
    }
    private enum CodingKeys: String, CodingKey { case chapterURL, chapterName, pageIndex, pageCount, fraction, completed, updatedAt }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(chapterURL: try c.decode(String.self, forKey: .chapterURL), chapterName: try c.decode(String.self, forKey: .chapterName),
                  pageIndex: try c.decode(Int.self, forKey: .pageIndex), pageCount: try c.decode(Int.self, forKey: .pageCount),
                  fraction: try c.decode(Double.self, forKey: .fraction), completed: try c.decode(Bool.self, forKey: .completed),
                  updatedAt: try c.decode(Date.self, forKey: .updatedAt))
    }
}

public struct MangaReadingRecord: Codable, Identifiable, Sendable {
    public var title: MangaTitleReference
    public var saved: Bool
    public let addedAt: Date
    public var lastReadAt: Date?
    public var lastChapterURL: String?
    public var positions: [MangaReadingPosition]
    public var id: String { title.id }
    public init(title: MangaTitleReference, saved: Bool = false, addedAt: Date = Date()) {
        self.title = title; self.saved = saved; self.addedAt = addedAt; positions = []
    }
    public func position(for chapter: String) -> MangaReadingPosition? { positions.first { $0.chapterURL == chapter } }
}

public struct WebtoonPreferences: Codable, Equatable, Sendable {
    public enum Background: String, Codable, CaseIterable, Sendable { case black, charcoal, paper }
    public static let scrollSpeedRange = 15.0...240.0
    public var background = Background.black
    public var sidePadding = 0.0
    public var autoScrollSpeed = 45.0
    public var holdToScroll = true
    public var keepAwake = true
    public init() {}
    public mutating func normalize() {
        sidePadding = sidePadding.isFinite ? min(0.12, max(0, sidePadding)) : 0
        autoScrollSpeed = autoScrollSpeed.isFinite ? min(Self.scrollSpeedRange.upperBound, max(Self.scrollSpeedRange.lowerBound, autoScrollSpeed)) : 45
    }
    private enum CodingKeys: String, CodingKey { case background, sidePadding, autoScrollSpeed, holdToScroll, keepAwake }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        background = try c.decodeIfPresent(Background.self, forKey: .background) ?? .black
        sidePadding = try c.decodeIfPresent(Double.self, forKey: .sidePadding) ?? 0
        autoScrollSpeed = try c.decodeIfPresent(Double.self, forKey: .autoScrollSpeed) ?? 45
        holdToScroll = try c.decodeIfPresent(Bool.self, forKey: .holdToScroll) ?? true
        keepAwake = try c.decodeIfPresent(Bool.self, forKey: .keepAwake) ?? true
        normalize()
    }
}

public struct MangaReadingState: Codable, Sendable {
    public var schemaVersion = 1
    public var revision: UInt64 = 0
    public var records: [MangaReadingRecord] = []
    public var pinnedSources: Set<String> = []
    public var recentSources: [String] = []
    public var preferences = WebtoonPreferences()
    public init() {}
    public func record(_ id: String) -> MangaReadingRecord? { records.first { $0.id == id } }
    public mutating func save(_ title: MangaTitleReference, saved: Bool) {
        let index = ensure(title)
        records[index].saved = saved
    }
    public mutating func updateMetadata(_ title: MangaTitleReference) {
        guard let i = records.firstIndex(where: { $0.id == title.id }) else { return }
        records[i].title = title
    }
    public mutating func record(_ title: MangaTitleReference, position: MangaReadingPosition) {
        guard !position.chapterURL.isEmpty, position.pageCount > 0 else { return }
        let i = ensure(title)
        let previous = records[i].position(for: position.chapterURL)
        guard previous == nil || previous!.updatedAt <= position.updatedAt else { return }
        let normalized = MangaReadingPosition(chapterURL: position.chapterURL, chapterName: position.chapterName,
            pageIndex: position.pageIndex, pageCount: position.pageCount, fraction: position.fraction,
            completed: position.completed || previous?.completed == true, updatedAt: position.updatedAt)
        records[i].positions.removeAll { $0.chapterURL == normalized.chapterURL }
        records[i].positions.append(normalized)
        if records[i].lastReadAt == nil || records[i].lastReadAt! <= normalized.updatedAt {
            records[i].lastReadAt = normalized.updatedAt; records[i].lastChapterURL = normalized.chapterURL
        }
    }
    public mutating func mark(_ title: MangaTitleReference, chapter: SourceMangaChapter, read: Bool, now: Date = Date()) {
        let i = ensure(title)
        let previous = records[i].position(for: chapter.url)
        records[i].positions.removeAll { $0.chapterURL == chapter.url }
        records[i].positions.append(MangaReadingPosition(chapterURL: chapter.url, chapterName: chapter.name,
            pageIndex: read ? max(0, (previous?.pageCount ?? 1) - 1) : 0, pageCount: previous?.pageCount ?? 0,
            fraction: read ? 1 : 0, completed: read, updatedAt: now))
    }
    public mutating func visitSource(_ id: String) {
        recentSources.removeAll { $0 == id }; recentSources.insert(id, at: 0)
        recentSources = Array(recentSources.prefix(20))
    }
    private mutating func ensure(_ title: MangaTitleReference) -> Int {
        if let index = records.firstIndex(where: { $0.id == title.id }) {
            records[index].title = title; return index
        }
        records.append(MangaReadingRecord(title: title)); return records.count - 1
    }
}

public enum MangaChapterSequence {
    /// Preserve source adjacency and specials; reverse a descending feed as a whole.
    /// Actual extension chapter numbers take precedence over name/date hints.
    public static func readingOrder(_ chapters: [SourceMangaChapter]) -> [SourceMangaChapter] {
        var seen = Set<String>()
        let unique = chapters.filter { !$0.url.isEmpty && seen.insert($0.url).inserted }
        let numbers = unique.compactMap { number($0) }
        if let first = numbers.first, let last = numbers.last, first != last {
            return first > last ? Array(unique.reversed()) : unique
        }
        let dates = unique.map(\.uploadedAt).filter { $0 > 0 }
        if let first = dates.first, let last = dates.last, first != last {
            return first > last ? Array(unique.reversed()) : unique
        }
        // The source chapter-list convention is newest first.
        return Array(unique.reversed())
    }
    public static func nextToRead(_ chapters: [SourceMangaChapter], record: MangaReadingRecord?) -> SourceMangaChapter? {
        guard !chapters.isEmpty else { return nil }
        if let url = record?.lastChapterURL, let index = chapters.firstIndex(where: { $0.url == url }) {
            if record?.position(for: url)?.completed != true { return chapters[index] }
            if let next = chapters.dropFirst(index + 1).first(where: { record?.position(for: $0.url)?.completed != true }) { return next }
        }
        return chapters.first(where: { record?.position(for: $0.url)?.completed != true }) ?? chapters.first
    }
    private static func number(_ chapter: SourceMangaChapter) -> Double? {
        if let n = chapter.chapterNumber, n.isFinite, n > 0 { return n }
        let name = chapter.name
        let patterns = [#"(?i)(?:chapter|chap|ch\.?|episode|ep\.?)\s*#?\s*(\d+(?:\.\d+)?)"#, #"^\s*(\d+(?:\.\d+)?)(?:\s|$|:)"#]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
                  let range = Range(match.range(at: 1), in: name), let value = Double(name[range]) else { continue }
            return value
        }
        return chapter.chapterNumber == 0 ? 0 : nil
    }
}

public enum MangaReadingStorageError: LocalizedError {
    case unreadable, tooLarge
    public var errorDescription: String? {
        switch self {
        case .unreadable: return "Saved manga reading data could not be opened. Existing data has been kept."
        case .tooLarge: return "Reading data exceeds this device’s storage limit."
        }
    }
}

public actor MangaReadingStorage {
    private let directory: URL
    private var state: MangaReadingState?
    public init(directory: URL) { self.directory = directory }
    public func load() throws -> MangaReadingState {
        if let state { return state }
        let path = directory.appendingPathComponent("reading.json")
        guard FileManager.default.fileExists(atPath: path.path) else {
            let empty = MangaReadingState(); state = empty; return empty
        }
        do {
            let data = try Data(contentsOf: path)
            guard data.count <= 16_000_000 else { throw MangaReadingStorageError.tooLarge }
            var value = try JSONDecoder().decode(MangaReadingState.self, from: data)
            guard value.schemaVersion == 1, value.records.count <= 5000,
                  Set(value.records.map(\.id)).count == value.records.count,
                  value.records.allSatisfy({ $0.positions.count <= 10000 &&
                      Set($0.positions.map(\.chapterURL)).count == $0.positions.count }) else { throw MangaReadingStorageError.unreadable }
            value.preferences.normalize(); state = value; return value
        } catch { throw MangaReadingStorageError.unreadable }
    }
    @discardableResult
    public func update(_ mutation: @Sendable (inout MangaReadingState) -> Void) throws -> MangaReadingState {
        var value = try load()
        mutation(&value); value.preferences.normalize()
        guard value.revision < UInt64.max, value.records.count <= 5000,
              value.records.allSatisfy({ $0.positions.count <= 10000 }) else { throw MangaReadingStorageError.tooLarge }
        value.revision += 1
        let data = try JSONEncoder().encode(value)
        guard data.count <= 16_000_000 else { throw MangaReadingStorageError.tooLarge }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent("reading.json"), options: .atomic)
        state = value; return value
    }
}
