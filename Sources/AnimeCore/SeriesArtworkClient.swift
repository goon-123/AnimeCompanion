import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct SeriesArtwork: Codable, Equatable, Sendable {
    public var logo: URL?
    public var backdrop: URL?
    public var poster: URL?
    public init(logo: URL? = nil, backdrop: URL? = nil, poster: URL? = nil) {
        self.logo = logo; self.backdrop = backdrop; self.poster = poster
    }
    public var isEmpty: Bool { logo == nil && backdrop == nil && poster == nil }
    public func fillingMissing(with other: Self) -> Self {
        Self(logo: logo ?? other.logo, backdrop: backdrop ?? other.backdrop, poster: poster ?? other.poster)
    }
}

/// Resolve by AniList/MAL identity, never by a fuzzy title or guessed season.
public enum SeriesArtworkDecoding {
    public struct Identity: Codable, Hashable, Sendable {
        public let aniList: Int
        public let mal: Int?
        public let imdb: String
        public let movie: Bool
    }
    public static func identities(_ data: Data) throws -> [Identity] {
        guard data.count <= 16_000_000,
              let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]], rows.count <= 100_000 else { throw ServiceError.invalidResponse }
        return rows.compactMap { row in
            guard let id = integer(row["anilist_id"]), id > 0,
                  let type = row["type"] as? String else { return nil }
            let ids = (row["imdb_id"] as? [String]) ?? (row["imdb_id"] as? String).map { [$0] } ?? []
            let valid = Set(ids.filter(validIMDb))
            guard valid.count == 1, let imdb = valid.first else { return nil }
            return Identity(aniList: id, mal: integer(row["mal_id"]), imdb: imdb, movie: type.uppercased() == "MOVIE")
        }
    }
    public static func identity(for anime: Anime, in rows: [Identity]) -> Identity? {
        let matches = Set(rows.filter { $0.aniList == anime.id && $0.movie == (anime.format == "MOVIE") })
        guard matches.count == 1, let match = matches.first else { return nil }
        if let mal = anime.idMal, let mapped = match.mal, mal != mapped { return nil }
        return match
    }
    public static func cinemeta(_ data: Data, imdb: String, movie: Bool) throws -> SeriesArtwork {
        guard data.count <= 2_000_000, validIMDb(imdb),
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let meta = root["meta"] as? [String: Any], meta["id"] as? String == imdb,
              meta["type"] as? String == (movie ? "movie" : "series") else { throw ServiceError.invalidResponse }
        return SeriesArtwork(logo: image(meta["logo"]), backdrop: image(meta["background"]), poster: image(meta["poster"]))
    }
    public static func aniZip(_ data: Data, anime: Anime) throws -> SeriesArtwork {
        guard data.count <= 8_000_000,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let mapping = root["mappings"] as? [String: Any], integer(mapping["anilist_id"]) == anime.id else { throw ServiceError.invalidResponse }
        if let mal = anime.idMal, let mapped = integer(mapping["mal_id"]), mal != mapped { throw ServiceError.invalidResponse }
        // TVDB artwork mapped to a movie may belong to the television adaptation.
        if anime.format == "MOVIE", (mapping["type"] as? String)?.uppercased() != "MOVIE" { return SeriesArtwork() }
        let images = root["images"] as? [[String: Any]] ?? []
        guard images.count <= 200 else { throw ServiceError.invalidResponse }
        func first(_ types: [String]) -> URL? {
            for type in types {
                if let url = images.filter({ ($0["coverType"] as? String)?.lowercased() == type }).compactMap({ image($0["url"]) }).first { return url }
            }
            return nil
        }
        return SeriesArtwork(logo: first(["clearlogo", "logo"]), backdrop: first(["fanart", "background", "banner"]))
    }
    private static func validIMDb(_ value: String) -> Bool {
        value.hasPrefix("tt") && (7...10).contains(value.dropFirst(2).count) && value.dropFirst(2).allSatisfy { $0.isASCII && $0.isNumber }
    }
    private static func integer(_ value: Any?) -> Int? { (value as? Int) ?? (value as? String).flatMap(Int.init) }
    private static func image(_ value: Any?) -> URL? {
        guard let raw = value as? String, raw.count <= 4096, let url = URL(string: raw), url.scheme == "https",
              let host = url.host, SeanimeNetworkPolicy.publicHost(host) != nil,
              url.user == nil, url.password == nil, url.port == nil || url.port == 443 else { return nil }
        return url
    }
}

/// Stremio's public artwork contract with ani.zip/TVDB fallback. No API key or server is required.
public actor SeriesArtworkClient {
    public static let mappingURL = URL(string: "https://raw.githubusercontent.com/Fribb/anime-lists/master/anime-list-full.json")!
    private let transport: any HTTPTransport
    private let cache: HomeContentCache
    private let requests = RequestCoalescer<String, SeriesArtwork>()
    private let indexRequests = RequestCoalescer<String, [SeriesArtworkDecoding.Identity]>()
    private var index: HomeContentSnapshot<[SeriesArtworkDecoding.Identity]>?
    private var indexRetry = Date.distantPast
    public init(transport: any HTTPTransport = AnimeVisualsClient.publicTransport(), cache: HomeContentCache = HomeContentCache(directory: HomeContentCache.defaultDirectory?.appendingPathComponent("SeriesArtwork"))) {
        self.transport = transport; self.cache = cache
    }
    public func artwork(for anime: Anime, refresh: Bool = false) async -> SeriesArtwork {
        guard anime.id > 0 else { return SeriesArtwork() }
        let key = "series-art-v1-\(anime.id)-\(anime.idMal ?? 0)-\(anime.format == "MOVIE")"
        let previous = await cache.load(SeriesArtwork.self, key: key)
        if !refresh, let saved = previous, Date().timeIntervalSince(saved.savedAt) < (saved.value.isEmpty ? 300 : 86400) { return saved.value }
        do {
            return try await requests.value(for: key) {
                let value = await self.fetch(anime)
                try Task.checkCancellation()
                let result = value.fillingMissing(with: previous?.value ?? SeriesArtwork())
                await self.cache.save(HomeContentSnapshot(result), key: key)
                return result
            }
        } catch { return previous?.value ?? SeriesArtwork() }
    }
    private func fetch(_ anime: Anime) async -> SeriesArtwork {
        var result = SeriesArtwork()
        do {
            let identities = try await identities()
            if let identity = SeriesArtworkDecoding.identity(for: anime, in: identities) {
                let type = identity.movie ? "movie" : "series"
                let url = URL(string: "https://v3-cinemeta.strem.io/meta/\(type)/\(identity.imdb).json")!
                result = try SeriesArtworkDecoding.cinemeta(await get(url, maximum: 2_000_000), imdb: identity.imdb, movie: identity.movie)
            }
        } catch { }
        if result.logo == nil || result.backdrop == nil {
            do {
                let url = URL(string: "https://api.ani.zip/mappings?anilist_id=\(anime.id)")!
                let fallback = try SeriesArtworkDecoding.aniZip(await get(url, maximum: 8_000_000), anime: anime)
                result = result.fillingMissing(with: fallback)
            } catch { }
        }
        return result
    }
    private func identities() async throws -> [SeriesArtworkDecoding.Identity] {
        if index == nil { index = await cache.load([SeriesArtworkDecoding.Identity].self, key: "series-art-identities-v1") }
        if let index, Date().timeIntervalSince(index.savedAt) < 86400 { return index.value }
        if indexRetry > Date() { return index?.value ?? [] }
        do {
            let values = try await indexRequests.value(for: "index") {
                try SeriesArtworkDecoding.identities(await self.get(Self.mappingURL, maximum: 16_000_000))
            }
            guard !values.isEmpty else { throw ServiceError.invalidResponse }
            let saved = HomeContentSnapshot(values); index = saved
            await cache.save(saved, key: "series-art-identities-v1")
            return values
        } catch {
            indexRetry = Date().addingTimeInterval(300)
            if let index { return index.value }; throw error
        }
    }
    private func get(_ url: URL, maximum: Int) async throws -> Data {
        try Task.checkCancellation()
        var request = URLRequest(url: url, timeoutInterval: 12)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await transport.data(for: request)
        try Task.checkCancellation()
        guard response.statusCode == 200, data.count <= maximum else { throw ServiceError.invalidResponse }
        return data
    }
}
