import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class MBNoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
private struct MBEnvelope<Value: Decodable>: Decodable { let data: Value }
private struct MBRecommendationRecord: Decodable {
    let series: MangaBakaSeries?
    init(from decoder: Decoder) throws { series = try? MangaBakaSeries(from: decoder) }
}
struct MBRecommendationResponse: Decodable {
    let items: [MangaBakaSeries]
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: MBKey.self)
        // This beta endpoint uses `results`; `data` is a supported alternative,
        // not a reason to discard a populated results array.
        let records = try c.decodeIfPresent([MBRecommendationRecord].self, forKey: .results)
            ?? c.decode([MBRecommendationRecord].self, forKey: .data)
        items = records.compactMap(\.series)
        guard records.isEmpty || !items.isEmpty else { throw MangaBakaError.invalidResponse }
    }
}
private struct MBToken: Decodable {
    let access_token: String
    let refresh_token: String?
    let expires_in: Double?
}
private struct MBCachedPayload: Codable {
    let url: URL
    let date: Date
    let data: Data
}

public actor MangaBakaClient {
    private let transport: any HTTPTransport
    private let spacing: Double
    private let cacheFile: URL?
    private var cache: [URL: MBCachedPayload] = [:]
    private var pending: [URL: Task<Data, Error>] = [:]
    private var nextRequest = Date.distantPast
    private var nextSearch = Date.distantPast
    private var blockedUntil = Date.distantPast
    public static func publicSession() -> URLSession {
        let c = URLSessionConfiguration.ephemeral
        c.httpCookieStorage = nil; c.httpShouldSetCookies = false; c.urlCredentialStorage = nil; c.urlCache = nil
        return URLSession(configuration: c, delegate: MBNoRedirects(), delegateQueue: nil)
    }
    public init(transport: (any HTTPTransport)? = nil, directory: URL? = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("MangaBaka", isDirectory: true), minimumRequestInterval: Double = 0.35) {
        self.transport = transport ?? URLSessionTransport(session: Self.publicSession())
        spacing = max(0, minimumRequestInterval); cacheFile = directory?.appendingPathComponent("catalog.json")
        if let file = cacheFile, let bytes = try? Data(contentsOf: file), bytes.count <= 9_000_000,
           let records = try? JSONDecoder().decode([MBCachedPayload].self, from: bytes) {
            for record in records.prefix(60) where record.url.host == "api.mangabaka.org" && !record.url.path.contains("/my/") && Date().timeIntervalSince(record.date) < 86400 {
                cache[record.url] = record
            }
        }
    }
    public static func browseURL(_ query: MangaBakaQuery, page: Int, limit: Int, includeAdult: Bool, now: Date = Date()) -> URL {
        let searching = !query.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        // /v1/genres and /v1/tags supply the legacy facet vocabulary. The v2
        // search schema rejects `genre`; use its supported v1 search contract
        // for taxonomy filters while retaining v2 for the other catalog rails.
        let taxonomyFilters = !query.genres.isEmpty || !query.tags.isEmpty || !query.excludedTags.isEmpty
            || (query.publisher != nil && query.publisher?.id == nil)
        var path = taxonomyFilters ? "/v1/series/search" : "/v2/series/search"
        let curated = !searching && query.format == nil && query.status == nil && !query.hasFacets
        if curated && query.shelf == .rising { path = "/v2/series/discover/rising" }
        if curated && query.shelf == .hiddenGems { path = "/v2/series/discover/hidden-gems" }
        var c = URLComponents(string: "https://api.mangabaka.org" + path)!
        var items = [URLQueryItem(name: "limit", value: String(min(100, max(1, limit))))]
        let ratings = query.allowedRatings(includeAdult: includeAdult).map(\.rawValue)
        if path.hasSuffix("/hidden-gems") {
            if !includeAdult {
                for rating in ["erotica", "pornographic"] { items.append(.init(name: "not_content_rating", value: rating)) }
            }
        } else {
            for rating in ratings { items.append(.init(name: "content_rating", value: rating)) }
        }
        if path.hasSuffix("/search") {
            items.append(.init(name: "page", value: String(min(10000, max(1, page)))))
            if !searching { items.append(.init(name: "sort_by", value: query.shelf.sort)) }
            if searching { items.append(.init(name: "q", value: String(query.text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300)))) }
            if let format = query.format { items.append(.init(name: "type", value: format.rawValue)) }
            if let status = query.status { items.append(.init(name: "status", value: status)) }
            for genre in query.genres { items.append(.init(name: "genre", value: genre.value)) }
            for tag in query.tags { if let id = tag.id { items.append(.init(name: "tag", value: String(id))) } }
            for tag in query.excludedTags { if let id = tag.id { items.append(.init(name: "tag_not", value: String(id))) } }
            if let publisher = query.publisher {
                if let id = publisher.id { items.append(.init(name: "publisher_id", value: String(id))) }
                else { items.append(.init(name: "publisher", value: publisher.name)) }
            }
            if query.shelf == .topRated { items.append(.init(name: "rating_lower", value: "1")) }
            if query.shelf == .newReleases {
                let f = ISO8601DateFormatter(); f.formatOptions = [.withFullDate]
                items.append(.init(name: "published_start_date_lower", value: f.string(from: now.addingTimeInterval(-365 * 86400))))
            }
        }
        c.queryItems = items
        return c.url!
    }
    public func browse(_ query: MangaBakaQuery, page: Int = 1, limit: Int = 24, includeAdult: Bool, refresh: Bool = false) async throws -> MangaBakaPage<MangaBakaSeries> {
        guard query.shelf != .recommended else { throw MangaBakaError.message("Connect MangaBaka to load personal recommendations.") }
        if let publisher = query.publisher, publisher.id == nil, publisher.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw MangaBakaError.message("This publisher is missing its identity.")
        }
        guard !query.allowedRatings(includeAdult: includeAdult).isEmpty else { throw MangaBakaError.message("Enable mature titles or choose another content rating.") }
        let url = Self.browseURL(query, page: page, limit: limit, includeAdult: includeAdult)
        let data = try await publicData(url, refresh: refresh)
        do { return try decode(MangaBakaPage<MangaBakaSeries>.self, data) }
        catch { cache[url] = nil; trimCache(); throw error }
    }
    public func genres(refresh: Bool = false) async throws -> [MangaBakaGenre] {
        let bytes = try await publicData(api("/v1/genres"), refresh: refresh)
        return try decode(MBEnvelope<[MangaBakaGenre]>.self, bytes).data.filter { !$0.value.isEmpty }
    }
    public func tags(refresh: Bool = false) async throws -> [MangaBakaTag] {
        let bytes = try await publicData(api("/v1/tags"), refresh: refresh)
        return try decode(MBEnvelope<[MangaBakaTag]>.self, bytes).data.filter { $0.id != nil && !$0.name.isEmpty }
    }
    public func covers(id: Int, page: Int = 1, refresh: Bool = false) async throws -> MangaBakaPage<MangaBakaCoverImage> {
        guard id > 0 else { throw MangaBakaError.invalidResponse }
        var c = URLComponents(url: api("/v1/series/\(id)/images"), resolvingAgainstBaseURL: false)!
        c.queryItems = [.init(name: "page", value: String(max(1, page))), .init(name: "limit", value: "40")]
        let bytes = try await publicData(c.url!, refresh: refresh)
        let result = try decode(MangaBakaPage<MangaBakaCoverImage>.self, bytes)
        guard result.items.allSatisfy({ $0.seriesID == nil || $0.seriesID == id }) else { throw MangaBakaError.invalidResponse }
        return result
    }
    public func related(id: Int, kind: MangaBakaRelatedKind, includeAdult: Bool, refresh: Bool = false) async throws -> [MangaBakaRelatedSeries] {
        guard id > 0 else { throw MangaBakaError.invalidResponse }
        let version = kind == .relationships ? "v1" : "v2"
        var c = URLComponents(url: api("/\(version)/series/\(id)/\(kind.rawValue)"), resolvingAgainstBaseURL: false)!
        c.queryItems = [.init(name: "limit", value: "24")]
        for rating in MangaBakaQuery().allowedRatings(includeAdult: includeAdult) {
            c.queryItems?.append(.init(name: "content_rating", value: rating.rawValue))
        }
        let bytes = try await publicData(c.url!, refresh: refresh)
        let list = try decode(MBEnvelope<[MangaBakaRelatedSeries]>.self, bytes).data
        var seen = Set<Int>()
        return list.filter { $0.id != id && $0.series.isVisible(includeAdult: includeAdult) && seen.insert($0.id).inserted }
    }
    /// Resolve the written work's AniList ID, which is distinct from both the
    /// parent anime ID and MangaBaka's series ID. Titles are never guessed.
    public func series(anilistID: Int, refresh: Bool = false) async throws -> [MangaBakaSeries] {
        guard anilistID > 0 else { throw MangaBakaError.invalidResponse }
        let url = api("/v1/source/anilist/\(anilistID)")
        let data: Data
        do { data = try await publicData(url, refresh: refresh) }
        catch MangaBakaError.http(404) { return [] }
        do {
            let lookup = try decode(MBEnvelope<MBAniListSourceLookup>.self, data).data
            let records = lookup.series.filter { $0.state == nil || $0.state == "active" }.map(\.record)
            guard records.allSatisfy({ $0.anilistID == anilistID }) else { throw MangaBakaError.invalidResponse }
            var seen = Set<Int>()
            return records.filter { seen.insert($0.id).inserted }
        } catch { cache[url] = nil; trimCache(); throw error }
    }
    public func details(id: Int, refresh: Bool = false) async throws -> MangaBakaSeries {
        guard id > 0 else { throw MangaBakaError.invalidResponse }
        // v1 still supplies the richer genres, publisher links and full detail metadata.
        let url = URL(string: "https://api.mangabaka.org/v1/series/\(id)")!
        let data = try await publicData(url, refresh: refresh)
        do {
            let record = try decode(MBEnvelope<MangaBakaSeries>.self, data).data
            guard record.id == id else { throw MangaBakaError.invalidResponse }
            return record
        } catch { cache[url] = nil; trimCache(); throw error }
    }
    public func profile(_ credential: MangaBakaCredential) async throws -> MangaBakaProfile {
        try decode(MBEnvelope<MangaBakaProfile>.self, await request(api("/v1/my/profile"), credential: credential)).data
    }
    public func library(_ credential: MangaBakaCredential, page: Int, state: String?) async throws -> MangaBakaPage<MangaBakaLibraryEntry> {
        var c = URLComponents(url: api("/v1/my/library"), resolvingAgainstBaseURL: false)!
        c.queryItems = [.init(name: "page", value: String(max(1, page))), .init(name: "limit", value: "40")]
        if let state { c.queryItems?.append(.init(name: "state", value: state)) }
        let result = try decode(MangaBakaPage<MangaBakaLibraryEntry>.self, await request(c.url!, credential: credential))
        guard result.items.allSatisfy({ $0.id > 0 && $0.series != nil }) else { throw MangaBakaError.invalidResponse }
        return result.withLibraryPaging(requestedPage: max(1, page), limit: 40)
    }
    public func entry(id: Int, credential: MangaBakaCredential) async throws -> MangaBakaLibraryEntry? {
        guard id > 0 else { throw MangaBakaError.invalidResponse }
        do {
            let record = try decode(MBEnvelope<MangaBakaLibraryEntry>.self, await request(api("/v1/my/library/\(id)"), credential: credential)).data
            guard record.seriesID == nil || record.seriesID == id else { throw MangaBakaError.invalidResponse }
            return record
        } catch MangaBakaError.http(404) { return nil }
    }
    public func recommendations(_ credential: MangaBakaCredential, includeAdult: Bool) async throws -> [MangaBakaSeries] {
        try await recommendationPayload(credential, includeAdult: includeAdult).records()
    }
    public func recommendationPayload(_ credential: MangaBakaCredential, includeAdult: Bool) async throws -> MangaBakaRecommendationPayload {
        var c = URLComponents(url: api("/v1/my/series/recommendations"), resolvingAgainstBaseURL: false)!
        c.queryItems = [.init(name: "limit", value: "24")]
        for rating in includeAdult ? ["safe", "suggestive", "erotica", "pornographic"] : ["safe", "suggestive"] { c.queryItems?.append(.init(name: "content_rating", value: rating)) }
        let response = try await request(c.url!, credential: credential)
        let payload = MangaBakaRecommendationPayload(response: response)
        let unique = try payload.records()
        // Lean recommendation records may omit the catalog content rating.
        // Resolve it before applying the allow-list, rather than silently
        // dropping every otherwise valid recommendation.
        let unknown = unique.filter { MangaBakaContentRating(rawValue: $0.contentRating ?? "") == nil }
        guard !includeAdult, !unknown.isEmpty else { return payload }
        let details = try await recommendationDetails(ids: unknown.map(\.id))
        let hydrated = MangaBakaRecommendationPayload(response: response, details: details)
        _ = try hydrated.records()
        return hydrated
    }
    public func recommendationStatus(_ credential: MangaBakaCredential) async throws -> MangaBakaRecommendationStatus {
        try decode(MangaBakaRecommendationStatus.self, await request(api("/v1/my/series/recommendations/status"), credential: credential))
    }
    public func details(ids: [Int]) async throws -> [MangaBakaSeries] {
        let bytes = try await recommendationDetails(ids: ids)
        return try decode(MBEnvelope<[MangaBakaSeries]>.self, bytes).data
    }
    private func recommendationDetails(ids: [Int]) async throws -> Data {
        let wanted = Set(ids.filter { $0 > 0 }.prefix(24))
        guard !wanted.isEmpty else { return Data(#"{"data":[]}"#.utf8) }
        var c = URLComponents(url: api("/v1/series/batch"), resolvingAgainstBaseURL: false)!
        c.queryItems = wanted.sorted().map { URLQueryItem(name: "id", value: String($0)) }
        // IDs may come from a private recommendation feed. Send no credentials
        // to this public endpoint or the public catalog cache.
        let bytes = try await request(c.url!)
        let records = try decode(MBEnvelope<[MangaBakaSeries]>.self, bytes).data
        guard records.allSatisfy({ wanted.contains($0.id) }) else { throw MangaBakaError.invalidResponse }
        return bytes
    }
    public func save(id: Int, update: MangaBakaLibraryUpdate, existing: Bool, credential: MangaBakaCredential) async throws {
        guard id > 0 else { throw MangaBakaError.invalidResponse }
        let bytes = try await request(api("/v1/my/library/\(id)"), method: existing ? "PUT" : "POST", body: JSONEncoder().encode(update), credential: credential)
        guard bytes.isEmpty || (try? decode(MBEnvelope<Bool>.self, bytes).data) == true else { throw MangaBakaError.invalidResponse }
    }
    public func remove(id: Int, credential: MangaBakaCredential) async throws {
        guard id > 0 else { throw MangaBakaError.invalidResponse }
        let bytes = try await request(api("/v1/my/library/\(id)"), method: "DELETE", credential: credential)
        guard bytes.isEmpty || (try? decode(MBEnvelope<Bool>.self, bytes).data) == true else { throw MangaBakaError.invalidResponse }
    }
    public func exchange(code: String, verifier: String, clientID: String) async throws -> MangaBakaCredential {
        try await token(["grant_type": "authorization_code", "code": code, "code_verifier": verifier,
            "code_challenge_method": "S256", "client_id": clientID, "redirect_uri": MangaBakaOAuth.callback.absoluteString, "scope": MangaBakaOAuth.scope], clientID: clientID, fallbackRefresh: nil)
    }
    public func refresh(_ credential: MangaBakaCredential) async throws -> MangaBakaCredential {
        guard let refresh = credential.refreshToken, let client = credential.clientID else { throw MangaBakaError.unauthorized }
        return try await token(["grant_type": "refresh_token", "refresh_token": refresh, "client_id": client, "redirect_uri": MangaBakaOAuth.callback.absoluteString], clientID: client, fallbackRefresh: refresh)
    }
    private func token(_ fields: [String: String], clientID: String, fallbackRefresh: String?) async throws -> MangaBakaCredential {
        let bytes = try await request(MangaBakaOAuth.tokenURL, method: "POST", body: MangaBakaOAuth.form(fields), form: true)
        let value = try decode(MBToken.self, bytes)
        return try MangaBakaCredential(kind: .oauth, secret: value.access_token, refreshToken: value.refresh_token ?? fallbackRefresh,
            expiresAt: Date().addingTimeInterval(min(31_536_000, max(0, value.expires_in ?? 3600))), clientID: clientID)
    }
    private func api(_ path: String) -> URL { URL(string: "https://api.mangabaka.org" + path)! }
    private func decode<T: Decodable>(_ type: T.Type, _ bytes: Data) throws -> T {
        do { return try JSONDecoder().decode(type, from: bytes) } catch { throw MangaBakaError.invalidResponse }
    }
    private func publicData(_ url: URL, refresh: Bool) async throws -> Data {
        try Task.checkCancellation()
        if !refresh, let record = cache[url], Date().timeIntervalSince(record.date) < 900 { return record.data }
        if let task = pending[url] { return try await task.value }
        let task = Task { try await self.request(url) }; pending[url] = task
        defer { pending[url] = nil }
        do {
            let data = try await task.value
            // Keep only successful, bounded catalog JSON. Account data never uses this path.
            guard (try? JSONSerialization.jsonObject(with: data)) != nil else { throw MangaBakaError.invalidResponse }
            cache[url] = MBCachedPayload(url: url, date: Date(), data: data)
            trimCache(); return data
        } catch {
            // A failed refresh is surfaced; callers retain their current visible data.
            throw error
        }
    }
    private func trimCache() {
        var kept: [URL: MBCachedPayload] = [:], size = 0
        for record in cache.values.sorted(by: { $0.date > $1.date }) where Date().timeIntervalSince(record.date) < 86400 {
            if kept.count < 60 && size + record.data.count <= 6_000_000 { kept[record.url] = record; size += record.data.count }
        }
        cache = kept
        if let file = cacheFile, let data = try? JSONEncoder().encode(Array(kept.values)) {
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: file, options: .atomic)
        }
    }
    private func request(_ url: URL, method: String = "GET", body: Data? = nil, form: Bool = false, credential: MangaBakaCredential? = nil) async throws -> Data {
        let now = Date()
        if blockedUntil > now { throw MangaBakaError.rateLimited(max(1, Int(ceil(blockedUntil.timeIntervalSince(now))))) }
        let searching = url.path.hasSuffix("/series/search")
        let start = max(now, nextRequest, searching ? nextSearch : .distantPast)
        let wait = start.timeIntervalSince(now)
        guard wait <= 30 else { throw MangaBakaError.rateLimited(Int(ceil(wait))) }
        nextRequest = start.addingTimeInterval(spacing)
        if searching { nextSearch = start.addingTimeInterval(spacing == 0 ? 0 : 2.1) }
        if wait > 0 { try await Task.sleep(for: .seconds(wait)) }
        try Task.checkCancellation()
        if blockedUntil > Date() { throw MangaBakaError.rateLimited(max(1, Int(ceil(blockedUntil.timeIntervalSinceNow)))) }
        var r = URLRequest(url: url); r.httpMethod = method; r.httpBody = body; r.timeoutInterval = 20
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        r.setValue("AnimeCompanion/0.25 (https://github.com/goon-123/AnimeCompanion)", forHTTPHeaderField: "User-Agent")
        if body != nil { r.setValue(form ? "application/x-www-form-urlencoded" : "application/json", forHTTPHeaderField: "Content-Type") }
        if let credential {
            guard url.host == "api.mangabaka.org", url.path.contains("/my/") else { throw MangaBakaError.invalidResponse }
            r.setValue(credential.kind == .oauth ? "Bearer " + credential.secret : credential.secret,
                       forHTTPHeaderField: credential.kind == .oauth ? "Authorization" : "X-API-Key")
        }
        let (data, response) = try await transport.data(for: r)
        let byteLimit = url.path == "/v1/tags" ? 16_000_000 : 4_000_000
        guard response.url == url, data.count <= byteLimit else { throw MangaBakaError.invalidResponse }
        switch response.statusCode {
        case 200..<300: return data
        case 401: throw MangaBakaError.unauthorized
        case 429:
            let seconds = min(86400, max(1, Int(response.value(forHTTPHeaderField: "Retry-After") ?? "60") ?? 60))
            blockedUntil = Date().addingTimeInterval(Double(seconds)); throw MangaBakaError.rateLimited(seconds)
        default: throw MangaBakaError.http(response.statusCode)
        }
    }
}

