import Foundation

/// Explicitly scoped preferences. Credentials, callbacks, migration markers and
/// device-specific folder bookmarks must never enter a portable backup.
public enum DeviceSyncPreferences {
    public static let keys: Set<String> = [
        "appearance.scheme.v1", "appearance.theme.v1", "home.sections.v1", "home.ipadArtworkSize.v1", "navigation.tabs.v1",
        "display.ipad.layout", "explore.design", "explore.layout.anime.v1", "explore.layout.reading.v1",
        "explore.layout.discovery.v1", "explore.layout.grid.v1",
        "library.savedViews.v1", "library.layout", "library.sort", "library.reversed", "library.columns",
        "library.anime.defaultStatus", "library.reading.defaultStatus", "library.combined.defaultStatus",
        "library.shared.grid.minimum.v1", "library.airingProgressSource", "library.mediaSection",
        "mangabaka.library.layout", "mangabaka.library.sort", "mangabaka.library.ascending",
        "mangabaka.browseLayout", "mangabaka.contentFilter.v1", "combined.library.sort", "combined.library.ascending", "manga.search.sources.v1", "manga.search.pinnedOnly.v1",
        "discovery.layout", "discovery.columns", "discovery.dub.preferences.v1", "app.mediaSection",
        "content.includeAdult", "tracking.automaticallyComplete", "episodes.defaultFilter.v1",
        "series.appearance.style.v1", "series.more-info.layout.v1", "series.layout.anime.v1",
        "series.layout.manga.v1", "series.layout.reader.v1", "series.artwork.anilist-logo-fallback.v1",
        "series.artwork.anilist-banner-fallback.v1", "series.artwork.anilist-poster-fallback.v1",
        "community.destination.v1", "community.episodeOffsets.v1", "manga.showMatureSources", "manga.chaptersNewestFirst",
        "schedule.releaseType", "schedule.libraryOnly", "schedule.weekly.mode", "schedule.weekly.layout", "schedule.airing.layout",
        "playback.enabled", "playback.autoMarkEpisodes", "playback.completionThreshold", "playback.player",
        "playback.audioFilter", "playback.torrentSort", "torbox.files.sort",
        "news.readingHistory", "news.reader.v1", "news.preferences.v1", "news.compact", "news.unreadOnly", "news.popularPeriod",
        "accounts.selectedProvider", "explore.poster.fillScreen", "explore.poster.balanced",
        "explore.poster.list", "explore.poster.grid", "explore.poster.shelf", "explore.poster.featured",
        "library.poster.list", "library.poster.grid", "library.poster.shelf", "library.poster.featured"
    ]
}

public enum DeviceSyncPreference: Codable, Equatable, Sendable {
    case string(String), bool(Bool), integer(Int), decimal(Double), data(Data)
}

public enum DeviceSyncError: LocalizedError {
    case invalid, newerVersion, tooLarge
    public var errorDescription: String? {
        switch self {
        case .invalid: return "This sync file could not be read. Existing data has been kept."
        case .newerVersion: return "This sync file needs a newer version of the app. Update this device before syncing."
        case .tooLarge: return "This sync file exceeds the supported storage limit. Existing data has been kept."
        }
    }
}

public enum DeviceSyncCoding {
    public static let maximumBytes = 48_000_000
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }
    public static func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        guard data.count <= maximumBytes else { throw DeviceSyncError.tooLarge }
        return try JSONDecoder().decode(type, from: data)
    }
    public static func component(_ value: String) -> String {
        Data(value.utf8).base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    public static func string(_ component: String) throws -> String {
        var raw = component.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        raw += String(repeating: "=", count: (4 - raw.count % 4) % 4)
        guard let data = Data(base64Encoded: raw), let value = String(data: data, encoding: .utf8),
              !value.isEmpty, Self.component(value) == component else { throw DeviceSyncError.invalid }
        return value
    }
}

/// Each field is an independent register. A nil value is a durable deletion,
/// preventing an offline device from resurrecting a removed link or extension.
public struct DeviceSyncEntry: Codable, Equatable, Sendable {
    public let clock: Int64
    public let author: String
    public let value: Data?
    public init(clock: Int64, author: String, value: Data?) { self.clock = clock; self.author = author; self.value = value }
    fileprivate func wins(over other: Self) -> Bool {
        if clock != other.clock { return clock > other.clock }
        if author != other.author { return author > other.author }
        // Also converge when a damaged/cloned journal reuses a stamp.
        return (value?.base64EncodedString() ?? "~") > (other.value?.base64EncodedString() ?? "~")
    }
}

public struct DeviceSyncDocument: Codable, Equatable, Sendable {
    public var format = "AnimeCompanion.DeviceSync"
    public var version = 1
    public var entries: [String: DeviceSyncEntry] = [:]
    public init() {}
    public var values: [String: Data] { entries.compactMapValues(\.value) }
    public mutating func merge(_ other: Self) throws {
        try other.validate()
        for (key, entry) in other.entries {
            if entries[key].map({ entry.wins(over: $0) }) ?? true { entries[key] = entry }
        }
    }
    public func validate() throws {
        guard format == "AnimeCompanion.DeviceSync" else { throw DeviceSyncError.invalid }
        guard version == 1 else { throw DeviceSyncError.newerVersion }
        guard entries.count <= 150_000 else { throw DeviceSyncError.tooLarge }
        for (key, entry) in entries {
            guard entry.clock >= 0, entry.clock < Int64.max - 1_000_000,
                  entry.author.isEmpty || UUID(uuidString: entry.author) != nil else { throw DeviceSyncError.invalid }
            try DeviceSyncPayload.validate(key: key, value: entry.value)
        }
        _ = try DeviceSyncPayload(values: values)
    }
    public static func read(_ data: Data) throws -> Self {
        let value = try DeviceSyncCoding.decode(Self.self, data); try value.validate(); return value
    }
}

/// The journal remembers what was actually applied, separately from desired
/// cloud values. A failed extension download remains pending instead of being
/// echoed back as a deletion on the next pass.
public struct DeviceSyncJournal: Codable, Sendable {
    public let deviceID: String
    public var document = DeviceSyncDocument()
    public private(set) var observed: [String: Data] = [:]
    public private(set) var bootstrapping = true
    public init(deviceID: String = UUID().uuidString) { self.deviceID = deviceID }
    public mutating func observe(_ current: [String: Data], now: Date = Date()) {
        let changed = Set(current.keys).union(observed.keys).filter { current[$0] != observed[$0] }
        let clock = bootstrapping ? 0 : nextClock(now)
        for key in changed { document.entries[key] = DeviceSyncEntry(clock: clock, author: deviceID, value: current[key]) }
        observed = current
    }
    public mutating func finishBootstrap(now: Date = Date()) {
        let clock = nextClock(now)
        for (key, entry) in document.entries where entry.clock == 0 {
            document.entries[key] = DeviceSyncEntry(clock: clock, author: deviceID, value: entry.value)
        }
        bootstrapping = false
    }
    public mutating func acceptApplied(_ actual: [String: Data], baseline: [String: Data], desired: [String: Data], now: Date = Date()) {
        let clock = nextClock(now)
        for key in Set(actual.keys).union(baseline.keys) where actual[key] != baseline[key] && actual[key] != desired[key] {
            document.entries[key] = DeviceSyncEntry(clock: clock, author: deviceID, value: actual[key])
        }
        observed = actual
    }
    public mutating func restore(_ values: [String: Data], now: Date = Date()) throws {
        _ = try DeviceSyncPayload(values: values)
        let clock = nextClock(now)
        for (key, value) in values { document.entries[key] = DeviceSyncEntry(clock: clock, author: deviceID, value: value) }
        bootstrapping = false
    }
    private func nextClock(_ now: Date) -> Int64 {
        let latest = document.entries.values.map(\.clock).max() ?? 0
        return max(latest + 1, Int64(max(1, min(Double(Int64.max / 2), now.timeIntervalSince1970 * 1000))))
    }
}

public struct DeviceSyncMangaTitle: Codable, Sendable {
    public let title: MangaTitleReference
    public let addedAt: Date
}
public struct DeviceSyncReadingHistory: Codable, Sendable {
    public let lastReadAt: Date?
    public let lastChapterURL: String?
}
public struct DeviceSyncMangaExtension: Codable, Sendable {
    public let descriptor: MangaExtensionDescriptor
    public let enabled: Bool
    public init(descriptor: MangaExtensionDescriptor, enabled: Bool) { self.descriptor = descriptor; self.enabled = enabled }
}

/// Split membership, metadata, history and each chapter's progress so edits to
/// two books (or two chapters of the same book) never replace an entire library.
public struct DeviceSyncPayload: Sendable {
    public var preferences: [String: DeviceSyncPreference] = [:]
    public var reading = MangaReadingState()
    public var links = MangaSourceLinkState()
    public var extensions: [String: DeviceSyncMangaExtension] = [:]
    public var repositoryAdded = false
    public var playback: [String: PlaybackProgress] = [:]
    public init() {}

    public static func readingValues(_ state: MangaReadingState) throws -> [String: Data] {
        var values: [String: Data] = ["reader.preferences": try DeviceSyncCoding.encode(state.preferences),
                                     "reader.recent": try DeviceSyncCoding.encode(state.recentSources)]
        for source in state.pinnedSources { values["reader.pin." + DeviceSyncCoding.component(source)] = try DeviceSyncCoding.encode(true) }
        for record in state.records {
            let id = DeviceSyncCoding.component(record.id)
            values["book.title." + id] = try DeviceSyncCoding.encode(DeviceSyncMangaTitle(title: record.title, addedAt: record.addedAt))
            values["book.saved." + id] = try DeviceSyncCoding.encode(record.saved)
            values["book.history." + id] = try DeviceSyncCoding.encode(DeviceSyncReadingHistory(lastReadAt: record.lastReadAt, lastChapterURL: record.lastChapterURL))
            for position in record.positions {
                values["book.position." + id + "." + DeviceSyncCoding.component(position.chapterURL)] = try DeviceSyncCoding.encode(position)
            }
        }
        return values
    }
    public static func linkValues(_ state: MangaSourceLinkState) throws -> [String: Data] {
        try Dictionary(uniqueKeysWithValues: state.links.map { ("link." + DeviceSyncCoding.component($0.key), try DeviceSyncCoding.encode($0.value)) })
    }
    public func encodedValues() throws -> [String: Data] {
        var values = try Self.readingValues(reading)
        values.merge(try Self.linkValues(links)) { _, new in new }
        for (key, value) in preferences { values["preference." + key] = try DeviceSyncCoding.encode(value) }
        values["extensions.repository"] = try DeviceSyncCoding.encode(repositoryAdded)
        for (id, value) in extensions { values["extension." + DeviceSyncCoding.component(id)] = try DeviceSyncCoding.encode(value) }
        for (id, value) in playback { values["playback." + DeviceSyncCoding.component(id)] = try DeviceSyncCoding.encode(value) }
        return values
    }

    /// Only modify fields that have not changed since the sync read started.
    /// This is also used inside the storage actors, after acquiring their turn.
    public static func patch(current: [String: Data], expected: [String: Data], desired: [String: Data]) -> [String: Data] {
        var result = current
        for key in Set(expected.keys).union(desired.keys) where current[key] == expected[key] && expected[key] != desired[key] {
            result[key] = desired[key]
        }
        return result
    }

    public init(values: [String: Data]) throws {
        self.init()
        var titles: [String: DeviceSyncMangaTitle] = [:]
        var saved: [String: Bool] = [:], history: [String: DeviceSyncReadingHistory] = [:]
        var positions: [String: [MangaReadingPosition]] = [:]
        for (key, value) in values {
            try Self.validate(key: key, value: value)
            let parts = key.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
            if key.hasPrefix("preference.") { preferences[String(key.dropFirst(11))] = try DeviceSyncCoding.decode(DeviceSyncPreference.self, value) }
            else if key == "reader.preferences" { reading.preferences = try DeviceSyncCoding.decode(WebtoonPreferences.self, value) }
            else if key == "reader.recent" { reading.recentSources = try DeviceSyncCoding.decode([String].self, value) }
            else if key.hasPrefix("reader.pin.") { if try DeviceSyncCoding.decode(Bool.self, value) { reading.pinnedSources.insert(try DeviceSyncCoding.string(parts[2])) } }
            else if key == "extensions.repository" { repositoryAdded = try DeviceSyncCoding.decode(Bool.self, value) }
            else if key.hasPrefix("extension.") { extensions[try DeviceSyncCoding.string(parts[1])] = try DeviceSyncCoding.decode(DeviceSyncMangaExtension.self, value) }
            else if key.hasPrefix("link.") { links.links[try DeviceSyncCoding.string(parts[1])] = try DeviceSyncCoding.decode(MangaSourceLink.self, value) }
            else if key.hasPrefix("playback.") { playback[try DeviceSyncCoding.string(parts[1])] = try DeviceSyncCoding.decode(PlaybackProgress.self, value) }
            else if parts[0] == "book" {
                let id = try DeviceSyncCoding.string(parts[2])
                switch parts[1] {
                case "title": titles[id] = try DeviceSyncCoding.decode(DeviceSyncMangaTitle.self, value)
                case "saved": saved[id] = try DeviceSyncCoding.decode(Bool.self, value)
                case "history": history[id] = try DeviceSyncCoding.decode(DeviceSyncReadingHistory.self, value)
                case "position": positions[id, default: []].append(try DeviceSyncCoding.decode(MangaReadingPosition.self, value))
                default: throw DeviceSyncError.invalid
                }
            }
        }
        for (id, item) in titles.sorted(by: { $0.key < $1.key }) {
            guard item.title.id == id else { throw DeviceSyncError.invalid }
            var record = MangaReadingRecord(title: item.title, saved: saved[id] ?? false, addedAt: item.addedAt)
            record.lastReadAt = history[id]?.lastReadAt; record.lastChapterURL = history[id]?.lastChapterURL
            record.positions = (positions[id] ?? []).sorted { $0.chapterURL < $1.chapterURL }
            reading.records.append(record)
        }
        guard reading.records.count <= 5000, links.links.count <= 5000, extensions.count <= 64,
              reading.recentSources.count <= 20, reading.pinnedSources.count <= 5000,
              reading.records.allSatisfy({ $0.positions.count <= 10000 }) else { throw DeviceSyncError.tooLarge }
        reading.preferences.normalize()
        // Respect the existing stores' size limits before applying any section.
        guard try DeviceSyncCoding.encode(reading).count <= 16_000_000,
              try DeviceSyncCoding.encode(links).count <= 16_000_000 else { throw DeviceSyncError.tooLarge }
    }

    public static func validate(key: String, value: Data?) throws {
        guard key.count <= 16000 else { throw DeviceSyncError.tooLarge }
        let parts = key.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        let known: Bool
        if key.hasPrefix("preference.") { known = DeviceSyncPreferences.keys.contains(String(key.dropFirst(11))) }
        else if ["reader.preferences", "reader.recent", "extensions.repository"].contains(key) { known = true }
        else if parts.count == 2, ["extension", "link", "playback"].contains(parts[0]) { _ = try DeviceSyncCoding.string(parts[1]); known = true }
        else if parts.count == 3, parts[0] == "reader", parts[1] == "pin" { _ = try DeviceSyncCoding.string(parts[2]); known = true }
        else if parts.count >= 3, parts[0] == "book" {
            _ = try DeviceSyncCoding.string(parts[2])
            if parts.count == 4, parts[1] == "position" { _ = try DeviceSyncCoding.string(parts[3]); known = true }
            else { known = parts.count == 3 && ["title", "saved", "history"].contains(parts[1]) }
        } else { known = false }
        guard known else { throw DeviceSyncError.invalid }
        guard let value else { return }
        guard value.count <= 4_000_000 else { throw DeviceSyncError.tooLarge }
        if key.hasPrefix("preference.") { _ = try DeviceSyncCoding.decode(DeviceSyncPreference.self, value) }
        else if key == "reader.preferences" { _ = try DeviceSyncCoding.decode(WebtoonPreferences.self, value) }
        else if key == "reader.recent" { _ = try DeviceSyncCoding.decode([String].self, value) }
        else if key == "extensions.repository" || key.hasPrefix("reader.pin.") || key.hasPrefix("book.saved.") { _ = try DeviceSyncCoding.decode(Bool.self, value) }
        else if key.hasPrefix("extension.") {
            let item = try DeviceSyncCoding.decode(DeviceSyncMangaExtension.self, value)
            guard item.descriptor.id == (try DeviceSyncCoding.string(parts[1])), item.descriptor.supportsRuntime else { throw DeviceSyncError.invalid }
        } else if key.hasPrefix("link.") {
            let item = try DeviceSyncCoding.decode(MangaSourceLink.self, value)
            guard item.id == (try DeviceSyncCoding.string(parts[1])), !item.library.accountID.isEmpty,
                  item.library.seriesID > 0, !item.title.manga.url.isEmpty,
                  !item.title.source.extensionID.isEmpty, !item.title.source.sourceID.isEmpty else { throw DeviceSyncError.invalid }
        } else if key.hasPrefix("book.title.") {
            let item = try DeviceSyncCoding.decode(DeviceSyncMangaTitle.self, value)
            guard item.title.id == (try DeviceSyncCoding.string(parts[2])), !item.title.manga.url.isEmpty,
                  !item.title.source.extensionID.isEmpty, !item.title.source.sourceID.isEmpty else { throw DeviceSyncError.invalid }
        } else if key.hasPrefix("book.history.") { _ = try DeviceSyncCoding.decode(DeviceSyncReadingHistory.self, value) }
        else if key.hasPrefix("book.position.") {
            let item = try DeviceSyncCoding.decode(MangaReadingPosition.self, value)
            guard item.chapterURL == (try DeviceSyncCoding.string(parts[3])) else { throw DeviceSyncError.invalid }
        } else if key.hasPrefix("playback.") {
            let item = try DeviceSyncCoding.decode(PlaybackProgress.self, value)
            let id = try DeviceSyncCoding.string(parts[1])
            let components = id.split(separator: ":").compactMap { Int($0) }
            guard components.count == 2, components.allSatisfy({ $0 > 0 }),
                  item.position.isFinite, item.position >= 0, item.duration.map({ $0.isFinite && $0 >= 0 }) ?? true else { throw DeviceSyncError.invalid }
        }
    }
}

public struct DeviceSyncBackup: Codable, Sendable {
    public let format: String
    public let version: Int
    public let createdAt: Date
    public let values: [String: Data]
    public init(values: [String: Data], createdAt: Date = Date()) {
        format = "AnimeCompanion.Backup"; version = 1; self.values = values; self.createdAt = createdAt
    }
    public static func read(_ data: Data) throws -> Self {
        let result = try DeviceSyncCoding.decode(Self.self, data)
        guard result.format == "AnimeCompanion.Backup" else { throw DeviceSyncError.invalid }
        guard result.version == 1 else { throw DeviceSyncError.newerVersion }
        _ = try DeviceSyncPayload(values: result.values)
        return result
    }
}
