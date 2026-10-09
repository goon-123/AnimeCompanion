import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum QueryValue: Codable, Sendable {
    case string(String), int(Int), bool(Bool), ints([Int])
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let x = try? c.decode(Int.self) { self = .int(x) }
        else if let x = try? c.decode(Bool.self) { self = .bool(x) }
        else if let x = try? c.decode([Int].self) { self = .ints(x) }
        else { self = .string(try c.decode(String.self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let x): try c.encode(x)
        case .int(let x): try c.encode(x)
        case .bool(let x): try c.encode(x)
        case .ints(let x): try c.encode(x)
        }
    }
}
public struct MediaPage: Codable, Sendable {
    public let media: [Anime]?
    public let pageInfo: PageInfo?
}
public struct PageInfo: Codable, Sendable { public let hasNextPage: Bool? }
public struct ExploreResponse: Codable, Sendable {
    public let seasonal: MediaPage
    public let trending: MediaPage
    public let upcoming: MediaPage
}
private struct GraphQLError: Decodable { let message: String; let status: Int? }
private struct GraphQLResponse<T: Decodable>: Decodable { let data: T?; let errors: [GraphQLError]? }
private struct RequestBody: Encodable { let query: String; let variables: [String: QueryValue] }
private struct PageResponse: Decodable { let Page: MediaPage }
private struct DetailResponse: Decodable { let Media: Anime? }
private struct ViewerResponse: Decodable { let Viewer: Viewer }
private struct MutationResponse: Decodable { let SaveMediaListEntry: LibraryEntry }
private struct DeleteResponse: Decodable { let DeleteMediaListEntry: DeletedEntry }
private struct DeletedEntry: Decodable { let deleted: Bool? }
private struct CollectionResponse: Decodable { let MediaListCollection: ListCollection? }
private struct ListCollection: Decodable { let lists: [ListGroup]? }
private struct ListGroup: Decodable { let entries: [LibraryEntry]? }
private struct AiringPage: Decodable { let pageInfo: PageInfo?; let airingSchedules: [ScheduledAiring]? }
private struct AiringResponse: Decodable { let Page: AiringPage }
private struct ScheduledAiring: Decodable { let airingAt: Int; let episode: Int; let media: Anime? }

public enum AniListQueries {
    public static let card = """
    fragment AnimeCard on Media {
      id idMal title { romaji english userPreferred }
      coverImage { extraLarge large medium color } bannerImage
      episodes duration format status season seasonYear averageScore genres isAdult
      nextAiringEpisode { airingAt episode }
    }
    """
    public static let explore = """
    query Explore($season: MediaSeason!, $year: Int!, $nextSeason: MediaSeason!, $nextYear: Int!, $isAdult: Boolean) {
      seasonal: Page(page: 1, perPage: 16) {
        media(type: ANIME, season: $season, seasonYear: $year, isAdult: $isAdult, sort: POPULARITY_DESC) { ...AnimeCard description(asHtml: false) }
        pageInfo { hasNextPage }
      }
      trending: Page(page: 1, perPage: 12) {
        media(type: ANIME, isAdult: $isAdult, sort: TRENDING_DESC) { ...AnimeCard description(asHtml: false) }
      }
      upcoming: Page(page: 1, perPage: 12) {
        media(type: ANIME, season: $nextSeason, seasonYear: $nextYear, status: NOT_YET_RELEASED,
              isAdult: $isAdult, sort: POPULARITY_DESC) { ...AnimeCard description(asHtml: false) }
      }
    }
    """ + card
    public static let seasonal = """
    query Season($season: MediaSeason!, $year: Int!, $page: Int!, $isAdult: Boolean) {
      Page(page: $page, perPage: 24) {
        pageInfo { hasNextPage }
        media(type: ANIME, season: $season, seasonYear: $year, isAdult: $isAdult, sort: POPULARITY_DESC) { ...AnimeCard }
      }
    }
    """ + card
    public static let search = """
    query Search($search: String!, $page: Int!, $isAdult: Boolean) {
      Page(page: $page, perPage: 24) {
        pageInfo { hasNextPage }
        media(type: ANIME, search: $search, isAdult: $isAdult, sort: SEARCH_MATCH) { ...AnimeCard }
      }
    }
    """ + card
    public static let detail = """
    query Details($id: Int!, $isAdult: Boolean) {
      Media(id: $id, type: ANIME, isAdult: $isAdult) {
        ...AnimeCard description(asHtml: false)
        startDate { year month day } endDate { year month day }
        popularity favourites
        rankings { id rank type context year season allTime }
        studios(isMain: true) { nodes { id name } }
        characters(perPage: 12, sort: ROLE) { nodes { id name { full } image { medium } } }
        relations { edges { relationType node { id type isAdult title { romaji english userPreferred } coverImage { large } } } }
        staff(perPage: 12) { edges { id role node { id name { full } image { large medium } } } }
        recommendations(perPage: 12, sort: RATING_DESC) {
          nodes { id mediaRecommendation { id type isAdult title { romaji english userPreferred } coverImage { large } } }
        }
        reviews(perPage: 3, sort: RATING_DESC) { nodes { id summary score siteUrl } }
        externalLinks { id site url isDisabled }
        trailer { id site thumbnail }
      }
    }
    """ + card
    public static let viewer = "query ViewerProfile { Viewer { id name avatar { large } } }"
    public static let browse = """
    query Browse($page: Int!, $search: String, $genre: String,
                 $year: Int, $season: MediaSeason, $format: MediaFormat, $status: MediaStatus,
                 $sort: [MediaSort], $minimumScore: Int, $isAdult: Boolean) {
      Page(page: $page, perPage: 24) {
        pageInfo { hasNextPage }
        media(type: ANIME, search: $search, genre: $genre, seasonYear: $year, season: $season,
              format: $format, status: $status, sort: $sort, averageScore_greater: $minimumScore, isAdult: $isAdult) {
          ...AnimeCard description(asHtml: false)
        }
      }
    }
    """ + card
    public static let lookup = """
    query MediaLookup($ids: [Int]!) {
      Page(page: 1, perPage: 50) { media(id_in: $ids, type: ANIME) { ...AnimeCard } }
    }
    """ + card
    public static let library = """
    query Library($userId: Int!) {
      MediaListCollection(userId: $userId, type: ANIME) {
        lists { entries { id mediaId status progress score(format: POINT_100) repeat notes updatedAt media { ...AnimeCard } } }
      }
    }
    """ + card
    public static let save = """
    mutation SaveEntry($id: Int, $mediaId: Int!, $progress: Int!, $status: MediaListStatus!, $scoreRaw: Int, $notes: String, $repeat: Int) {
      SaveMediaListEntry(id: $id, mediaId: $mediaId, progress: $progress, status: $status, scoreRaw: $scoreRaw, notes: $notes, repeat: $repeat) {
        id mediaId status progress score(format: POINT_100) repeat notes updatedAt media { ...AnimeCard }
      }
    }
    """ + card
    public static let delete = "mutation DeleteEntry($id: Int!) { DeleteMediaListEntry(id: $id) { deleted } }"
    public static let airings = """
    query Airings($start: Int!, $end: Int!, $page: Int!) {
      Page(page: $page, perPage: 50) {
        pageInfo { hasNextPage }
        airingSchedules(airingAt_greater: $start, airingAt_lesser: $end, sort: TIME) {
          airingAt episode media { ...AnimeCard }
        }
      }
    }
    """ + card
}

public actor AniListClient {
    private let transport: any HTTPTransport
    private let interval: TimeInterval
    private var nextSlot = Date.distantPast
    private var cache: [String: (Date, Data)] = [:]
    public init(transport: any HTTPTransport = URLSessionTransport(), minimumRequestInterval: TimeInterval = 2.1) {
        self.transport = transport; interval = minimumRequestInterval
    }
    private func request<T: Decodable>(_ query: String, variables: [String: QueryValue] = [:], token: String? = nil,
                                       bypassCache: Bool = false) async throws -> T {
        let body = try JSONEncoder().encode(RequestBody(query: query, variables: variables))
        // Sort the JSON to make public-response cache keys independent of dictionary ordering.
        let object = try JSONSerialization.jsonObject(with: body)
        let canonical = try JSONSerialization.data(withJSONObject: object, options: .sortedKeys)
        let key = canonical.base64EncodedString()
        if token == nil, !bypassCache, let (stored, data) = cache[key], Date().timeIntervalSince(stored) < 300 {
            return try decode(data)
        }
        // Recheck after every suspension: a 429 must also delay callers already waiting.
        while true {
            try Task.checkCancellation()
            let wait = nextSlot.timeIntervalSinceNow
            if wait <= 0 { nextSlot = Date().addingTimeInterval(interval); break }
            try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
        }
        try Task.checkCancellation()
        var request = URLRequest(url: URL(string: "https://graphql.anilist.co")!)
        request.httpMethod = "POST"; request.httpBody = body; request.timeoutInterval = 25
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await transport.data(for: request)
        if response.statusCode == 429 {
            let retry = Double(response.value(forHTTPHeaderField: "Retry-After") ?? "60") ?? 60
            nextSlot = max(nextSlot, Date().addingTimeInterval(retry))
        }
        try HTTPValidation.check(response)
        let result: T = try decode(data)
        if token == nil {
            cache[key] = (Date(), data)
            if cache.count > 80 { cache = cache.filter { Date().timeIntervalSince($0.value.0) < 300 } }
        }
        return result
    }
    private func decode<T: Decodable>(_ data: Data) throws -> T {
        let response = try JSONDecoder().decode(GraphQLResponse<T>.self, from: data)
        if let error = response.errors?.first {
            if error.status == 401 { throw ServiceError.unauthorized }
            if error.status == 429 { throw ServiceError.rateLimited(60) }
            throw ServiceError.message(error.message)
        }
        guard let result = response.data else { throw ServiceError.invalidResponse }
        return result
    }
    public func explore(_ selection: SeasonSelection, refresh: Bool = false, includeAdult: Bool = false) async throws -> ExploreResponse {
        let next = selection.advanced(by: 1)
        var vars: [String: QueryValue] = ["season": .string(selection.season.rawValue),
            "year": .int(selection.year), "nextSeason": .string(next.season.rawValue), "nextYear": .int(next.year)]
        if !includeAdult { vars["isAdult"] = .bool(false) }
        return try await request(AniListQueries.explore, variables: vars, bypassCache: refresh)
    }
    public func seasonal(_ selection: SeasonSelection, page: Int, includeAdult: Bool = false) async throws -> MediaPage {
        var vars: [String: QueryValue] = ["season": .string(selection.season.rawValue), "year": .int(selection.year), "page": .int(page)]
        if !includeAdult { vars["isAdult"] = .bool(false) }
        let result: PageResponse = try await request(AniListQueries.seasonal, variables: vars)
        return result.Page
    }
    public func search(_ text: String, page: Int = 1, includeAdult: Bool = false) async throws -> MediaPage {
        var vars: [String: QueryValue] = ["search": .string(text), "page": .int(page)]
        if !includeAdult { vars["isAdult"] = .bool(false) }
        let result: PageResponse = try await request(AniListQueries.search, variables: vars)
        return result.Page
    }
    public func browse(_ filters: DiscoveryFilters, page: Int = 1, refresh: Bool = false, includeAdult: Bool = false) async throws -> MediaPage {
        var vars = filters.variables(page: page)
        if !includeAdult { vars["isAdult"] = .bool(false) }
        let result: PageResponse = try await request(AniListQueries.browse, variables: vars, bypassCache: refresh)
        return result.Page
    }
    public func details(id: Int, includeAdult: Bool = false, refresh: Bool = false) async throws -> Anime {
        var vars: [String: QueryValue] = ["id": .int(id)]
        if !includeAdult { vars["isAdult"] = .bool(false) }
        let result: DetailResponse = try await request(AniListQueries.detail, variables: vars, bypassCache: refresh)
        guard let media = result.Media else { throw ServiceError.message("Anime not found.") }
        return media
    }
    public func viewer(token: String) async throws -> Viewer {
        let result: ViewerResponse = try await request(AniListQueries.viewer, token: token)
        return result.Viewer
    }
    public func media(ids: [Int]) async throws -> [Anime] {
        var media: [Anime] = []
        let ids = Array(Set(ids)).sorted()
        for start in stride(from: 0, to: ids.count, by: 50) {
            let group = Array(ids[start..<min(start + 50, ids.count)])
            let result: PageResponse = try await request(AniListQueries.lookup, variables: ["ids": .ints(group)])
            media += result.Page.media ?? []
        }
        return media
    }
    public func library(userId: Int, token: String) async throws -> [LibraryEntry] {
        let result: CollectionResponse = try await request(AniListQueries.library, variables: ["userId": .int(userId)], token: token)
        // Include custom groups: AniList lets users hide entries from the default status groups.
        let entries = result.MediaListCollection?.lists?.flatMap { $0.entries ?? [] } ?? []
        var seen = Set<Int>()
        return entries.filter { seen.insert($0.mediaId).inserted }
    }
    public func save(mediaId: Int, entryId: Int?, progress: Int, status: LibraryStatus, token: String,
                     scoreRaw: Int? = nil, notes: String? = nil, repeatCount: Int? = nil) async throws -> LibraryEntry {
        var vars: [String: QueryValue] = ["mediaId": .int(mediaId), "progress": .int(max(0, progress)), "status": .string(status.rawValue)]
        if let entryId { vars["id"] = .int(entryId) }
        if let scoreRaw { vars["scoreRaw"] = .int(scoreRaw) }
        if let notes { vars["notes"] = .string(notes) }
        if let repeatCount { vars["repeat"] = .int(repeatCount) }
        let result: MutationResponse = try await request(AniListQueries.save, variables: vars, token: token)
        return result.SaveMediaListEntry
    }
    public func delete(entryId: Int, token: String) async throws {
        let result: DeleteResponse = try await request(AniListQueries.delete, variables: ["id": .int(entryId)], token: token)
        guard result.DeleteMediaListEntry.deleted == true else { throw ServiceError.message("AniList did not confirm removal. Refresh your library and try again.") }
    }
    public func airings(in window: DateInterval, refresh: Bool = false, includeAdult: Bool = false) async throws -> [ReleaseEvent] {
        var events: [ReleaseEvent] = []; var page = 1
        while true {
            try Task.checkCancellation()
            let result: AiringResponse = try await request(AniListQueries.airings, variables: [
                "start": .int(Int(window.start.timeIntervalSince1970) - 1), "end": .int(Int(window.end.timeIntervalSince1970)),
                "page": .int(page)], bypassCache: refresh)
            events += (result.Page.airingSchedules ?? []).compactMap { airing in
                guard let media = airing.media, includeAdult || media.isAdult != true else { return nil }
                return ReleaseEvent(anime: media, episode: airing.episode, kind: .sub,
                    date: Date(timeIntervalSince1970: Double(airing.airingAt)), certainty: .broadcast)
            }
            guard result.Page.pageInfo?.hasNextPage == true, page * 50 < 5000 else { break }
            page += 1
        }
        return events
    }
}
