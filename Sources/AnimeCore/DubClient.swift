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
    public let episode: RawDubFeedEpisode
}
public struct RawDubFeedEpisode: Decodable, Sendable { public let aired: Int; public let airedAt: SourceTimestamp? }
public struct DubSnapshot: Sendable {
    public let upcoming: [RawDubItem]
    public let history: [RawDubFeedItem]
    public let fetchedAt: Date
    public init(upcoming: [RawDubItem], history: [RawDubFeedItem], fetchedAt: Date = Date()) {
        self.upcoming = upcoming; self.history = history; self.fetchedAt = fetchedAt
    }
    public func events(knownMedia: [Int: Anime] = [:], now: Date = Date()) -> [ReleaseEvent] {
        var media = knownMedia
        for item in upcoming { if let anime = item.media?.media { media[anime.id] = anime } }
        var byEpisode: [String: ReleaseEvent] = [:]
        // A recorded release overrides a schedule estimate for the same exact AniList ID and episode.
        for item in history {
            guard item.episode.aired > 0, let date = item.episode.airedAt?.date, date <= now else { continue }
            let anime = media[item.id] ?? Anime(id: item.id, title: "Anime #\(item.id)")
            let event = ReleaseEvent(anime: anime, episode: item.episode.aired, kind: .dub, date: date, certainty: .recorded)
            if byEpisode[event.id] == nil { byEpisode[event.id] = event }
        }
        for item in upcoming {
            guard let anime = item.media?.media, anime.isAdult != true else { continue }
            let nodes = anime.airingSchedule?.nodes ?? []
            let expanded: [(Int, Date?)]
            if !nodes.isEmpty { expanded = nodes.compactMap { node in node.episode.map { ($0, node.airingAt?.date) } } }
            else if let number = item.episodeNumber { expanded = [(number, item.episodeDate?.date)] }
            else { expanded = [] }
            let indefinite = item.delayedIndefinitely == true
            let postponed = item.delayedUntil?.date.map { $0 > now } ?? false
            for (episode, date) in expanded where episode > 0 {
                let certainty: ScheduleCertainty = indefinite || postponed ? .delayed : (item.verified == true ? .verified : .unverified)
                let event = ReleaseEvent(anime: anime, episode: episode, kind: .dub, date: indefinite ? nil : date,
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
    private enum CodingKeys: String, CodingKey { case dubbed, partial }
    public init(from decoder: Decoder) throws {
        if let list = try? decoder.singleValueContainer().decode([Int].self) {
            dubbed = Set(list); partial = []
        } else {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            // A changed/missing schema is an error, never evidence that every anime lacks a dub.
            dubbed = Set(try c.decode([Int].self, forKey: .dubbed))
            partial = Set(try c.decodeIfPresent([Int].self, forKey: .partial) ?? [])
        }
    }
    public func availability(malId: Int?) -> DubAvailability {
        guard let malId else { return .unknown }
        if partial.contains(malId) { return .partial }
        return dubbed.contains(malId) ? .dubbed : .notReported
    }
}

public actor DubClient {
    public static let scheduleURL = URL(string: "https://raw.githubusercontent.com/Bas1874/AniSchedule/refs/heads/master/raw/dub-schedule.json")!
    public static let feedURL = URL(string: "https://raw.githubusercontent.com/Bas1874/AniSchedule/refs/heads/master/raw/dub-episode-feed.json")!
    public static let indexURL = URL(string: "https://raw.githubusercontent.com/Joelis57/MyDubList/refs/heads/main/dubs/confidence/normal/dubbed_english.json")!
    private let transport: any HTTPTransport
    private var cachedSnapshot: DubSnapshot?
    private var cachedIndex: (Date, DubIndex)?
    public init(transport: any HTTPTransport = URLSessionTransport()) { self.transport = transport }
    private func load<T: Decodable>(_ type: T.Type, from url: URL) async throws -> T {
        var request = URLRequest(url: url); request.timeoutInterval = 25
        let (data, response) = try await transport.data(for: request)
        try HTTPValidation.check(response)
        return try JSONDecoder().decode(type, from: data)
    }
    public func snapshot(refresh: Bool = false) async throws -> DubSnapshot {
        if !refresh, let cachedSnapshot, Date().timeIntervalSince(cachedSnapshot.fetchedAt) < 1800 { return cachedSnapshot }
        async let upcoming = load([RawDubItem].self, from: Self.scheduleURL)
        async let history = load([RawDubFeedItem].self, from: Self.feedURL)
        let snapshot = try await DubSnapshot(upcoming: upcoming, history: history)
        cachedSnapshot = snapshot
        return snapshot
    }
    public func availability(malId: Int?) async throws -> DubAvailability {
        guard malId != nil else { return .unknown }
        if let (date, index) = cachedIndex, Date().timeIntervalSince(date) < 86400 { return index.availability(malId: malId) }
        let index = try await load(DubIndex.self, from: Self.indexURL)
        cachedIndex = (Date(), index)
        return index.availability(malId: malId)
    }
}
