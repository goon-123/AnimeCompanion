import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum SourceDates {
    public static func parse(_ value: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: value) { return date }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: value)
    }
}
public struct SourceTimestamp: Codable, Hashable, Sendable {
    public let date: Date?
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let seconds = try? c.decode(Double.self) {
            date = Date(timeIntervalSince1970: seconds > 100_000_000_000 ? seconds / 1000 : seconds)
        } else if let string = try? c.decode(String.self) {
            date = SourceDates.parse(string)
        } else { date = nil }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        if let date { try c.encode(ISO8601DateFormatter().string(from: date)) } else { try c.encodeNil() }
    }
}
public struct SourceAiringNode: Codable, Hashable, Sendable { public let episode: Int?; public let airingAt: SourceTimestamp? }
public struct SourceAiringConnection: Codable, Hashable, Sendable { public let nodes: [SourceAiringNode]? }
public struct DubMediaEnvelope: Decodable, Sendable { public let media: Anime? }
public struct RawDubItem: Decodable, Sendable {
    public let title: String?
    public let route: String?
    public let episodeDate: SourceTimestamp?
    public let episodeNumber: Int?
    public let delayedText: String?
    public let delayedIndefinitely: Bool?
    public let delayedUntil: SourceTimestamp?
    public let verified: Bool?
    public let media: DubMediaEnvelope?
}
public struct RawDubFeedItem: Decodable, Sendable {
    public let id: Int
    public let idMal: Int?
    public let episode: RawDubFeedEpisode
}
public struct RawDubFeedEpisode: Decodable, Sendable { public let aired: Int; public let airedAt: SourceTimestamp? }

public enum DubProvider: String, Sendable, Hashable {
    case current, legacy
    public var repositoryURL: URL {
        URL(string: "https://github.com/\(self == .current ? "RockinChaos" : "Bas1874")/AniSchedule")!
    }
    public var label: String { self == .current ? "AniSchedule · RockinChaos" : "AniSchedule · older mirror" }
    public func url(for file: String) -> URL {
        URL(string: "https://raw.githubusercontent.com/\(self == .current ? "RockinChaos" : "Bas1874")/AniSchedule/refs/heads/master/raw/\(file)")!
    }
}

public struct DubSnapshot: Sendable {
    public let upcoming: [RawDubItem]
    public let history: [RawDubFeedItem]
    public let fetchedAt: Date
    public let scheduleProvider: DubProvider?
    public let historyProvider: DubProvider?
    public let scheduleUpdatedAt: Date?
    public let historyUpdatedAt: Date?
    public init(upcoming: [RawDubItem], history: [RawDubFeedItem], fetchedAt: Date = Date(),
                scheduleProvider: DubProvider? = .current, historyProvider: DubProvider? = .current,
                scheduleUpdatedAt: Date? = nil, historyUpdatedAt: Date? = nil) {
        self.upcoming = upcoming; self.history = history; self.fetchedAt = fetchedAt
        self.scheduleProvider = scheduleProvider; self.historyProvider = historyProvider
        self.scheduleUpdatedAt = scheduleUpdatedAt; self.historyUpdatedAt = historyUpdatedAt
    }
    public func warnings(now: Date = Date()) -> [String] {
        var messages: [String] = []
        if scheduleProvider == nil { messages.append("Upcoming dub dates could not be loaded.") }
        if historyProvider == nil { messages.append("Dub episode history could not be loaded. Counts may be estimated.") }
        if scheduleProvider == .legacy || historyProvider == .legacy {
            messages.append("Using an older dub source as a fallback; recent releases may be missing.")
        }
        if let updated = historyUpdatedAt, now.timeIntervalSince(updated) > 3 * 86400 {
            messages.append("The dub release feed has not updated for over three days. Counts may be behind.")
        }
        if let updated = scheduleUpdatedAt, now.timeIntervalSince(updated) > 3 * 86400 {
            messages.append("The dub schedule has not updated for over three days. Dates may be out of date.")
        }
        return messages
    }
    // Exact AniList IDs remain primary. A matching MAL ID can resolve changed/missing mappings,
    // but a contradictory MAL ID must never attach another season's episode to this anime.
    public func releases(for anime: Anime, now: Date = Date()) -> [RawDubFeedItem] {
        history.filter { item in
            let matches = item.id == anime.id
                ? (item.idMal == nil || anime.idMal == nil || item.idMal == anime.idMal)
                : (anime.idMal != nil && item.idMal == anime.idMal)
            return matches && item.episode.aired > 0
                && (anime.episodes.map { $0 <= 0 || item.episode.aired <= $0 } ?? true)
                && (item.episode.airedAt?.date.map { $0 <= now } ?? false)
        }
    }
    public func schedules(for anime: Anime) -> [RawDubItem] {
        upcoming.filter { item in
            guard let media = item.media?.media else { return false }
            if media.id == anime.id { return media.idMal == nil || anime.idMal == nil || media.idMal == anime.idMal }
            return anime.idMal != nil && media.idMal == anime.idMal
        }
    }
    public func schedulePage(for anime: Anime) -> URL? {
        guard let route = schedules(for: anime).compactMap(\.route).first,
              route.range(of: "^[a-z0-9][a-z0-9-]*$", options: .regularExpression) != nil else { return nil }
        return URL(string: "https://animeschedule.net/anime/\(route)")
    }
    public func events(knownMedia: [Int: Anime] = [:], now: Date = Date()) -> [ReleaseEvent] {
        var media = knownMedia
        for item in upcoming { if let anime = item.media?.media, media[anime.id] == nil { media[anime.id] = anime } }
        var byMAL: [Int: Anime] = [:]
        for anime in media.values { if let id = anime.idMal { byMAL[id] = anime } }
        for anime in knownMedia.values { if let id = anime.idMal { byMAL[id] = anime } }
        var byEpisode: [String: ReleaseEvent] = [:]
        // A recorded release overrides a schedule estimate for the same exact AniList ID and episode.
        for item in history {
            guard item.episode.aired > 0, let date = item.episode.airedAt?.date, date <= now else { continue }
            let anime = media[item.id] ?? item.idMal.flatMap { byMAL[$0] } ?? Anime(id: item.id, title: "Anime #\(item.id)")
            guard item.idMal == nil || anime.idMal == nil || item.idMal == anime.idMal,
                  anime.isAdult != true,
                  anime.episodes.map({ $0 <= 0 || item.episode.aired <= $0 }) ?? true else { continue }
            let event = ReleaseEvent(anime: anime, episode: item.episode.aired, kind: .dub, date: date, certainty: .recorded)
            if byEpisode[event.id] == nil { byEpisode[event.id] = event }
        }
        for item in upcoming {
            guard let source = item.media?.media else { continue }
            let anime = knownMedia[source.id] ?? source.idMal.flatMap { byMAL[$0] } ?? source
            guard anime.isAdult != true, source.idMal == nil || anime.idMal == nil || source.idMal == anime.idMal else { continue }
            let nodes = source.airingSchedule?.nodes ?? []
            let expanded: [(Int, Date?)]
            if !nodes.isEmpty { expanded = nodes.compactMap { node in node.episode.map { ($0, node.airingAt?.date) } } }
            else if let number = item.episodeNumber { expanded = [(number, item.episodeDate?.date)] }
            else { expanded = [] }
            let indefinite = item.delayedIndefinitely == true
            let postponed = item.delayedUntil?.date.map { $0 > now } ?? false
            for (episode, date) in expanded where episode > 0 {
                let certainty: ScheduleCertainty = indefinite || postponed ? .delayed : (item.verified == true ? .verified : .unverified)
                let releaseDate = postponed && episode == item.episodeNumber ? item.delayedUntil?.date : date
                let event = ReleaseEvent(anime: anime, episode: episode, kind: .dub, date: indefinite ? nil : releaseDate,
                    certainty: certainty, note: indefinite ? (item.delayedText ?? "Delayed; no confirmed date") : item.delayedText)
                if byEpisode[event.id] == nil { byEpisode[event.id] = event }
            }
        }
        return byEpisode.values.sorted {
            let a = $0.date ?? .distantFuture, b = $1.date ?? .distantFuture
            return a == b ? $0.id < $1.id : a < b
        }
    }
}

public struct DubIndex: Decodable, Sendable {
    public let dubbed: Set<Int>
    public let partial: Set<Int>
    public let sourceCounts: [Int: Int]
    private enum CodingKeys: String, CodingKey { case dubbed, partial, sourceCounts }
    public init(dubbed: Set<Int>, partial: Set<Int>, sourceCounts: [Int: Int] = [:]) {
        self.dubbed = dubbed; self.partial = partial; self.sourceCounts = sourceCounts
    }
    public init(from decoder: Decoder) throws {
        if let list = try? decoder.singleValueContainer().decode([Int].self) {
            dubbed = Set(list); partial = []; sourceCounts = [:]
        } else {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            // A changed/missing schema is an error, never evidence that every anime lacks a dub.
            dubbed = Set(try c.decode([Int].self, forKey: .dubbed))
            partial = Set(try c.decodeIfPresent([Int].self, forKey: .partial) ?? [])
            sourceCounts = try c.decodeIfPresent([Int: Int].self, forKey: .sourceCounts) ?? [:]
        }
    }
    public func availability(malId: Int?) -> DubAvailability {
        guard let malId else { return .unknown }
        if partial.contains(malId) { return .partial }
        if !dubbed.contains(malId), (sourceCounts[malId] ?? 0) > 0 { return .unknown }
        return dubbed.contains(malId) ? .dubbed : .notReported
    }
    public func agreeingSources(malId: Int?) -> Int? { malId.flatMap { sourceCounts[$0] } }
}

public actor DubClient {
    public static let scheduleURL = DubProvider.current.url(for: "dub-schedule.json")
    public static let feedURL = DubProvider.current.url(for: "dub-episode-feed.json")
    public static let manifestURL = DubProvider.current.url(for: "last-updated.json")
    public static let indexURL = URL(string: "https://raw.githubusercontent.com/Joelis57/MyDubList/refs/heads/main/dubs/confidence/normal/dubbed_english.json")!
    public static let countsURL = URL(string: "https://raw.githubusercontent.com/Joelis57/MyDubList/refs/heads/main/dubs/counts/dubbed_english.json")!
    private let transport: any HTTPTransport
    private var cachedSnapshot: DubSnapshot?
    private var cachedIndex: (Date, DubIndex)?
    private var snapshotTask: Task<DubSnapshot, Error>?
    private var indexTask: Task<DubIndex, Error>?
    public init(transport: any HTTPTransport = URLSessionTransport()) { self.transport = transport }
    private func load<T: Decodable>(_ type: T.Type, from url: URL) async throws -> T {
        var request = URLRequest(url: url); request.timeoutInterval = 20
        let (data, response) = try await transport.data(for: request)
        try HTTPValidation.check(response)
        return try JSONDecoder().decode(type, from: data)
    }
    public func snapshot(refresh: Bool = false) async throws -> DubSnapshot {
        if !refresh, let cachedSnapshot, Date().timeIntervalSince(cachedSnapshot.fetchedAt) < 600 { return cachedSnapshot }
        if let snapshotTask { return try await snapshotTask.value }
        let work = Task { try await self.fetchSnapshot() }
        snapshotTask = work
        defer { snapshotTask = nil }
        let result = try await work.value
        cachedSnapshot = result
        return result
    }
    private func endpoint<T: Decodable & Sendable>(_ type: T.Type, file: String) async throws -> DubEndpoint<T> {
        do {
            let value = try await load(type, from: DubProvider.current.url(for: file))
            return DubEndpoint(value: value, provider: .current)
        }
        catch {
            try Task.checkCancellation()
            let value = try await load(type, from: DubProvider.legacy.url(for: file))
            return DubEndpoint(value: value, provider: .legacy)
        }
    }
    private func fetchSnapshot() async throws -> DubSnapshot {
        // An outage of one endpoint must not discard the other endpoint's useful data.
        async let dates = try? endpoint([RawDubItem].self, file: "dub-schedule.json")
        async let episodes = try? endpoint([RawDubFeedItem].self, file: "dub-episode-feed.json")
        async let manifest = try? load(DubUpdateManifest.self, from: Self.manifestURL)
        let (schedule, history, updates) = await (dates, episodes, manifest)
        try Task.checkCancellation()
        guard schedule != nil || history != nil else { throw ServiceError.message("Dub release sources are temporarily unavailable.") }
        let legacyUpdates: DubUpdateManifest?
        if schedule?.provider == .legacy || history?.provider == .legacy {
            legacyUpdates = try? await load(DubUpdateManifest.self, from: DubProvider.legacy.url(for: "last-updated.json"))
        } else { legacyUpdates = nil }
        return DubSnapshot(upcoming: schedule?.value ?? [], history: history?.value ?? [],
            scheduleProvider: schedule?.provider, historyProvider: history?.provider,
            scheduleUpdatedAt: (schedule?.provider == .legacy ? legacyUpdates : updates)?.dubbed.schedule?.date,
            historyUpdatedAt: (history?.provider == .legacy ? legacyUpdates : updates)?.dubbed.episodes?.date)
    }
    public func index(refresh: Bool = false) async throws -> DubIndex {
        if !refresh, let (date, index) = cachedIndex, Date().timeIntervalSince(date) < 86400 { return index }
        if let indexTask { return try await indexTask.value }
        let work = Task { try await self.fetchIndex() }
        indexTask = work
        defer { indexTask = nil }
        let result = try await work.value
        cachedIndex = (Date(), result)
        return result
    }
    private func fetchIndex() async throws -> DubIndex {
        async let complete = try? load(DubIndex.self, from: Self.indexURL)
        // These numbers count sources that report a dub, NEVER available episodes.
        // Partial dubs are intentionally excluded from MyDubList's confidence tiers.
        async let supplemental = try? load(DubSourceCounts.self, from: Self.countsURL)
        let (base, counts) = await (complete, supplemental)
        try Task.checkCancellation()
        guard base != nil || counts != nil else { throw ServiceError.message("Dub availability sources are temporarily unavailable.") }
        let corroborated = Set(counts?.sources.filter { $0.value >= 2 }.map(\.key) ?? [])
        return DubIndex(dubbed: base?.dubbed ?? corroborated,
                        partial: (base?.partial ?? []).union(counts?.partial ?? []), sourceCounts: counts?.sources ?? [:])
    }
    public func availability(malId: Int?) async throws -> DubAvailability {
        guard malId != nil else { return .unknown }
        return try await index().availability(malId: malId)
    }
}

private struct DubEndpoint<Value: Sendable>: Sendable { let value: Value; let provider: DubProvider }
private struct DubUpdateManifest: Decodable, Sendable {
    struct Updates: Decodable, Sendable { let schedule: SourceTimestamp?; let episodes: SourceTimestamp? }
    let dubbed: Updates
}

public struct DubSourceCounts: Decodable, Sendable {
    public let sources: [Int: Int]
    public let partial: Set<Int>
    private struct Key: CodingKey {
        let stringValue: String
        var intValue: Int? { Int(stringValue) }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { stringValue = String(intValue) }
    }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        partial = Set(try container.decodeIfPresent([Int].self, forKey: Key(stringValue: "partial")!) ?? [])
        var result: [Int: Int] = [:]
        for key in container.allKeys {
            guard let id = Int(key.stringValue), id > 0 else { continue }
            let count = try container.decode(Int.self, forKey: key)
            if count > 0 { result[id] = count }
        }
        guard !result.isEmpty || container.contains(Key(stringValue: "partial")!) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Missing dub source-count schema"))
        }
        sources = result
    }
}

public enum DubCountConfidence: Sendable, Equatable { case reported, estimated, unknown }
public enum DubStatusTone: Sendable, Equatable { case available, estimated, announced, neutral }

public struct LibraryDubProgress: Sendable, Equatable {
    public let released: Int?
    public let availability: DubAvailability
    public let announced: Bool
    public let completeListing: Bool
    public let confidence: DubCountConfidence
    public let agreeingSources: Int?
    public let lastReleaseAt: Date?
    public init(anime: Anime, snapshot: DubSnapshot?, index: DubIndex?, now: Date = Date()) {
        availability = index?.availability(malId: anime.idMal) ?? .unknown
        agreeingSources = index?.agreeingSources(malId: anime.idMal)
        let planned = snapshot?.schedules(for: anime) ?? []
        announced = !planned.isEmpty
        let releases = snapshot?.releases(for: anime, now: now) ?? []
        let recorded = releases.map { $0.episode.aired }.max()
        lastReleaseAt = releases.filter { $0.episode.aired == recorded }.compactMap { $0.episode.airedAt?.date }.max()
        // A completed non-partial listing supplies the count for older titles outside the recent feed.
        // FINISHED refers to the original broadcast, so it must not override a dub still in progress.
        completeListing = recorded == nil && !announced && availability == .dubbed
            && anime.status == "FINISHED" && (anime.episodes ?? 0) > 0
        if let recorded {
            released = recorded; confidence = .reported
        } else if completeListing {
            released = anime.episodes; confidence = .estimated
        } else {
            let delayed = planned.contains { $0.delayedIndefinitely == true || ($0.delayedUntil?.date.map { $0 > now } ?? false) }
            let next = DubSnapshot(upcoming: planned, history: []).events(knownMedia: [anime.id: anime], now: now).first {
                $0.anime.id == anime.id && ($0.certainty == .verified || $0.certainty == .unverified)
                    && ($0.date.map { $0 > now && $0 <= now.addingTimeInterval(14 * 86400) } ?? false)
            }
            if !delayed, anime.status != "NOT_YET_RELEASED", let next, next.episode > 1,
               (anime.episodes.map { $0 <= 0 || next.episode <= $0 } ?? true) {
                let count = min(next.episode - 1, anime.releasedEpisodeCount(at: now) ?? next.episode - 1)
                released = count > 0 ? count : nil; confidence = count > 0 ? .estimated : .unknown
            } else { released = nil; confidence = .unknown }
        }
    }
    public var tone: DubStatusTone {
        if confidence == .estimated { return .estimated }
        if released != nil { return .available }
        if announced { return .announced }
        if availability == .dubbed || availability == .partial { return .available }
        if (agreeingSources ?? 0) > 0 { return .estimated }
        return .neutral
    }
    public var explanation: String {
        switch confidence {
        case .reported: return "Reported released through episode \(released ?? 0) in the dub episode feed. This is separate from the original broadcast."
        case .estimated:
            return completeListing
                ? "Estimated from a completed title’s dub listing and its episode total; an episode-by-episode count is not supplied."
                : "Estimated from the next listed dub episode. Earlier episodes may be available; the streaming catalog has not been verified."
        case .unknown:
            if availability == .unknown, (agreeingSources ?? 0) > 0 {
                return "A source reports an English dub, but the availability index has not corroborated it. No episode count is supplied."
            }
            return announced ? "A dub is scheduled, but no released-episode count is supplied yet."
                : "Availability listings report whether a dub exists. They do not always include episode totals or a release schedule."
        }
    }
    public func label(for anime: Anime, now: Date = Date()) -> String {
        if let released {
            let prefix = confidence == .estimated ? "Dub ~\(released)" : "Dub \(released)"
            let suffix = confidence == .estimated ? " · estimated" : " released"
            if let aired = anime.releasedEpisodeCount(at: now), aired >= released {
                return "\(prefix)/\(aired)\(suffix)"
            }
            return prefix + suffix
        }
        if announced { return "Dub announced · episodes not listed" }
        switch availability {
        case .notReported: return "No dub reported yet"
        case .partial: return "Partial dub · episodes not listed"
        case .dubbed: return "Dub available · episodes not listed"
        case .unknown: return (agreeingSources ?? 0) > 0 ? "Dub reported · unconfirmed" : "Dub status unknown"
        }
    }
}

