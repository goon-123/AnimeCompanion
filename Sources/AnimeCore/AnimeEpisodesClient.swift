import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct AnimeEpisodeMetadata: Codable, Identifiable, Hashable, Sendable {
    public let number: Int
    public let title: String?
    public let overview: String?
    public let image: String?
    public let airDate: String?
    public let runtime: Int?
    public let rating: Double?
    public let filler: Bool
    public let recap: Bool
    public var id: Int { number }
    public var imageURL: URL? { image.flatMap(Self.publicImage) }
    public init(number: Int, title: String? = nil, overview: String? = nil, image: String? = nil, airDate: String? = nil,
                runtime: Int? = nil, rating: Double? = nil, filler: Bool = false, recap: Bool = false) {
        self.number = number; self.title = title; self.overview = overview; self.image = image; self.airDate = airDate
        self.runtime = runtime; self.rating = rating; self.filler = filler; self.recap = recap
    }
    public var dateLabel: String? {
        guard let airDate else { return nil }
        let parts = airDate.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = .current
        guard let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)) else { return nil }
        return date.formatted(.dateTime.month(.abbreviated).day().year())
    }
    public func isFuture(at now: Date = Date()) -> Bool {
        guard let airDate else { return false }
        if airDate.contains("T"), let date = ISO8601DateFormatter().date(from: airDate) { return date > now }
        let parts = airDate.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return false }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = .current
        guard let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else { return false }
        return date > calendar.startOfDay(for: now)
    }
    private static func publicImage(_ raw: String) -> URL? {
        guard let parts = URLComponents(string: raw), parts.scheme == "https", let host = parts.host,
              SeanimeNetworkPolicy.publicHost(host) != nil, parts.user == nil, parts.password == nil else { return nil }
        return parts.url
    }
}

public struct AnimeEpisodePage: Codable, Sendable {
    public let episodes: [AnimeEpisodeMetadata]
    public let hasMore: Bool
    public let source: String
    public let sourceURL: URL
    public var notice: String?
    public init(episodes: [AnimeEpisodeMetadata], hasMore: Bool, source: String, sourceURL: URL, notice: String? = nil) {
        self.episodes = episodes; self.hasMore = hasMore; self.source = source; self.sourceURL = sourceURL; self.notice = notice
    }
}

/// Canonical entry-local episode numbers only. Specials and guessed season offsets never join the list.
public enum AnimeEpisodeDecoding {
    public static func mapping(_ data: Data, anime: Anime) throws -> [AnimeEpisodeMetadata] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ids = root["mappings"] as? [String: Any], integer(ids["anilist_id"]) == anime.id,
              let episodes = root["episodes"] as? [String: Any], episodes.count <= 12_000 else { throw ServiceError.invalidResponse }
        if let known = anime.idMal, let mapped = integer(ids["mal_id"]), known != mapped { throw ServiceError.invalidResponse }
        return episodes.compactMap { key, value -> AnimeEpisodeMetadata? in
            guard let number = Int(key), String(number) == key, (1...10_000).contains(number), let row = value as? [String: Any],
                  integer(row["episode"]) == number else { return nil }
            if let total = anime.episodes, total > 0, number > total { return nil }
            let titles = row["title"] as? [String: Any] ?? [:]
            let numberMatches = integer(row["episodeNumber"]).map { $0 == number } == true ||
                integer(row["absoluteEpisodeNumber"]).map { $0 == number } == true
            // Some upstream TVDB records have a conflicting episode number. Keep the
            // AniDB title/summary but do not attach that record's still or plot overview.
            return AnimeEpisodeMetadata(number: number, title: text(titles["en"] ?? titles["x-jat"] ?? titles["ja"], limit: 300),
                overview: text(row["summary"] ?? (numberMatches ? row["overview"] : nil), limit: 6000),
                image: numberMatches ? text(row["image"], limit: 4096) : nil,
                airDate: text(row["airdate"] ?? row["airDateUtc"] ?? row["airDate"], limit: 40),
                runtime: integer(row["runtime"] ?? row["length"]).flatMap { (1...500).contains($0) ? $0 : nil },
                rating: decimal(row["rating"]).flatMap { (0...10).contains($0) ? $0 : nil })
        }.sorted { $0.number < $1.number }
    }
    public static func jikan(_ data: Data) throws -> ([AnimeEpisodeMetadata], Bool) {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], let rows = root["data"] as? [[String: Any]], rows.count <= 1000 else { throw ServiceError.invalidResponse }
        var seen = Set<Int>()
        let episodes = rows.compactMap { row -> AnimeEpisodeMetadata? in
            guard let number = integer(row["mal_id"]), (1...10_000).contains(number), seen.insert(number).inserted else { return nil }
            return AnimeEpisodeMetadata(number: number, title: text(row["title"] ?? row["title_romanji"], limit: 300),
                airDate: text(row["aired"], limit: 40), rating: decimal(row["score"]),
                filler: row["filler"] as? Bool ?? false, recap: row["recap"] as? Bool ?? false)
        }.sorted { $0.number < $1.number }
        return (episodes, (root["pagination"] as? [String: Any])?["has_next_page"] as? Bool == true)
    }
    private static func integer(_ value: Any?) -> Int? {
        if let number = value as? Int { return number }
        if let value = value as? String { return Int(value) }; return nil
    }
    private static func decimal(_ value: Any?) -> Double? {
        let number = (value as? NSNumber)?.doubleValue ?? (value as? String).flatMap(Double.init)
        return number.flatMap { $0.isFinite ? $0 : nil }
    }
    private static func text(_ value: Any?, limit: Int) -> String? {
        guard let value = value as? String else { return nil }
        let clean = TextSanitizer.plain(String(value.prefix(limit))).trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? nil : clean
    }
}

/// Public, credential-free metadata with bounded disk caching and coalesced requests.
public actor AnimeEpisodesClient {
    private let transport: any HTTPTransport
    private let cache: HomeContentCache
    private let requests = RequestCoalescer<String, AnimeEpisodePage>()
    private var nextRequest = Date.distantPast
    private let interval: TimeInterval
    public init(transport: any HTTPTransport = AnimeVisualsClient.publicTransport(), cache: HomeContentCache = HomeContentCache(), minimumRequestInterval: TimeInterval = 1.1) {
        self.transport = transport; self.cache = cache; interval = max(0, minimumRequestInterval)
    }
    private func mapKey(_ anime: Anime) -> String { "episode-map-v1-\(anime.id)-\(anime.idMal ?? 0)" }
    private func pageKey(_ anime: Anime, _ page: Int) -> String { "episode-page-v1-\(anime.id)-\(anime.idMal ?? 0)-\(page)" }
    public func cached(for anime: Anime, page: Int = 1) async -> AnimeEpisodePage? {
        guard (1...100).contains(page) else { return nil }
        let savedPage = await cache.load(AnimeEpisodePage.self, key: pageKey(anime, page))
        if let saved = await cache.load([AnimeEpisodeMetadata].self, key: mapKey(anime)), !saved.value.isEmpty,
           saved.savedAt >= (savedPage?.savedAt ?? .distantPast) {
            return mappedPage(saved.value, anime: anime, page: page)
        }
        return savedPage?.value
    }
    public func page(for anime: Anime, page: Int = 1, refresh: Bool = false) async throws -> AnimeEpisodePage {
        guard anime.id > 0, (1...100).contains(page) else { throw ServiceError.invalidResponse }
        let key = pageKey(anime, page)
        return try await requests.value(for: key) { try await self.fetch(anime, page: page, refresh: refresh) }
    }
    private func mappedPage(_ values: [AnimeEpisodeMetadata], anime: Anime, page: Int) -> AnimeEpisodePage {
        let start = (page - 1) * 100
        return AnimeEpisodePage(episodes: Array(values.dropFirst(start).prefix(100)), hasMore: values.count > start + 100,
            source: "ani.zip · AniDB / TVDB", sourceURL: URL(string: "https://api.ani.zip/mappings?anilist_id=\(anime.id)")!)
    }
    private func fetch(_ anime: Anime, page: Int, refresh: Bool) async throws -> AnimeEpisodePage {
        let cachedMap = await cache.load([AnimeEpisodeMetadata].self, key: mapKey(anime))
        let cachedPage = await cache.load(AnimeEpisodePage.self, key: pageKey(anime, page))
        if !refresh, let saved = cachedMap, Date().timeIntervalSince(saved.savedAt) < 3600, !saved.value.isEmpty,
           saved.savedAt >= (cachedPage?.savedAt ?? .distantPast) {
            return mappedPage(saved.value, anime: anime, page: page)
        }
        if !refresh, let saved = cachedPage, Date().timeIntervalSince(saved.savedAt) < 3600 { return saved.value }
        do {
            let data = try await get(URL(string: "https://api.ani.zip/mappings?anilist_id=\(anime.id)")!)
            let values = try AnimeEpisodeDecoding.mapping(data, anime: anime)
            guard !values.isEmpty else { throw ServiceError.invalidResponse }
            await cache.save(HomeContentSnapshot(values), key: mapKey(anime))
            return mappedPage(values, anime: anime, page: page)
        } catch is CancellationError { throw CancellationError() } catch {}
        if let mal = anime.idMal, mal > 0 {
            do {
                let data = try await get(URL(string: "https://api.jikan.moe/v4/anime/\(mal)/episodes?page=\(page)")!)
                let (values, more) = try AnimeEpisodeDecoding.jikan(data)
                let result = AnimeEpisodePage(episodes: values, hasMore: more, source: "Jikan · MyAnimeList", sourceURL: URL(string: "https://myanimelist.net/anime/\(mal)/_/episode")!)
                await cache.save(HomeContentSnapshot(result), key: pageKey(anime, page))
                return result
            } catch is CancellationError { throw CancellationError() } catch {}
        }
        if let saved = await cached(for: anime, page: page) {
            var result = saved; result.notice = "Showing saved episode metadata · Refresh unavailable"; return result
        }
        throw ServiceError.message("Episode metadata is unavailable right now. You can still choose an episode from Find streams.")
    }
    private func get(_ url: URL) async throws -> Data {
        while nextRequest > Date() {
            try await Task.sleep(for: .seconds(min(1, nextRequest.timeIntervalSinceNow)))
        }
        try Task.checkCancellation(); nextRequest = Date().addingTimeInterval(interval)
        var request = URLRequest(url: url); request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await transport.data(for: request)
        guard (200..<300).contains(response.statusCode), data.count <= 8_000_000 else { throw ServiceError.invalidResponse }
        return data
    }
}
