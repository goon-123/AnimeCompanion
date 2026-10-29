import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Official, read-only MAL v2 forum endpoints. A registered client ID is required.
/// The app supplies it at call time; this actor stores no credentials or comments on disk.
public actor MALCommunityClient {
    private let transport: any HTTPTransport
    private let minimumInterval: TimeInterval
    private var nextSlot = Date.distantPast
    private var cache: [String: (Date, Data)] = [:]
    public init(transport: any HTTPTransport = URLSessionTransport(session: URLSession(configuration: .ephemeral)), minimumRequestInterval: TimeInterval = 0.7) {
        self.transport = transport; minimumInterval = max(0, minimumRequestInterval)
    }
    public func topics(clientID: String, query: String? = nil, page: Int = 1, refresh: Bool = false) async throws -> CommunityThreadPage {
        guard (1...200).contains(page) else { throw ServiceError.invalidResponse }
        var items = [URLQueryItem(name: "limit", value: "25"), URLQueryItem(name: "offset", value: String((page - 1) * 25)), URLQueryItem(name: "sort", value: "recent")]
        if let query, !query.isEmpty { items.append(URLQueryItem(name: "q", value: String(query.prefix(150)))) }
        else { items.append(URLQueryItem(name: "board_id", value: "1")) }
        let result: MALTopicList = try await get("forum/topics", items: items, clientID: clientID, refresh: refresh)
        return CommunityThreadPage(threads: result.data.map(\.value), hasNextPage: result.paging?.next != nil && page < 200)
    }
    public func comments(threadID: Int, clientID: String, page: Int = 1, refresh: Bool = false) async throws -> CommunityCommentPage {
        guard threadID > 0, (1...200).contains(page) else { throw ServiceError.invalidResponse }
        let result: MALTopicDetail = try await get("forum/topic/\(threadID)", items: [
            URLQueryItem(name: "limit", value: "25"), URLQueryItem(name: "offset", value: String((page - 1) * 25))], clientID: clientID, refresh: refresh)
        return CommunityCommentPage(title: result.data.title, body: nil, comments: (result.data.posts ?? []).map(\.value), hasNextPage: result.paging?.next != nil && page < 200)
    }
    private func get<T: Decodable>(_ path: String, items: [URLQueryItem], clientID: String, refresh: Bool) async throws -> T {
        let id = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { throw ServiceError.message("Add your registered MyAnimeList client ID in Community sources to enable native reading.") }
        var parts = URLComponents(string: "https://api.myanimelist.net/v2/\(path)")!
        parts.queryItems = items
        guard let url = parts.url else { throw ServiceError.invalidResponse }
        let key = id + "|" + url.absoluteString
        if !refresh, let (expiry, data) = cache[key], expiry > Date() { return try JSONDecoder().decode(T.self, from: data) }
        while true {
            try Task.checkCancellation()
            let wait = nextSlot.timeIntervalSinceNow
            if wait <= 0 { nextSlot = Date().addingTimeInterval(minimumInterval); break }
            try await Task.sleep(nanoseconds: UInt64(min(wait, 60) * 1_000_000_000))
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 25)
        request.setValue(id, forHTTPHeaderField: "X-MAL-CLIENT-ID")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await transport.data(for: request)
        try Task.checkCancellation()
        switch response.statusCode {
        case 200..<300: break
        case 401, 403: throw ServiceError.message("MyAnimeList declined access. Check the registered client ID and API permissions, or use the official page.")
        case 404: throw ServiceError.message("This MyAnimeList discussion was removed or is unavailable.")
        case 429:
            let supplied = Double(response.value(forHTTPHeaderField: "Retry-After") ?? "60") ?? 60
            let delay = supplied.isFinite ? min(3600, max(1, supplied)) : 60
            nextSlot = max(nextSlot, Date().addingTimeInterval(delay))
            throw ServiceError.message("MyAnimeList is busy. Try again in \(Int(delay)) seconds.")
        default: throw ServiceError.message("MyAnimeList returned HTTP \(response.statusCode). Try again or open the official page.")
        }
        let result = try JSONDecoder().decode(T.self, from: data)
        cache = cache.filter { $0.value.0 > Date() }
        if cache.count >= 40, let oldest = cache.min(by: { $0.value.0 < $1.value.0 })?.key { cache.removeValue(forKey: oldest) }
        cache[key] = (Date().addingTimeInterval(300), data)
        return result
    }
}

private struct MALPaging: Decodable { let next: String? }
private struct MALUser: Decodable { let name: String? }
private struct MALTopicList: Decodable { let data: [MALTopic]; let paging: MALPaging? }
private struct MALTopic: Decodable {
    let id: Int
    let title: String
    let created_by: MALUser?
    let created_at: String?
    let last_post_created_at: String?
    let number_of_posts: Int?
    var value: CommunityThread {
        CommunityThread(source: .myAnimeList, threadID: id, title: title, author: created_by?.name,
            activityAt: MALDate.parse(last_post_created_at ?? created_at), commentCount: number_of_posts.map { max(0, $0 - 1) },
            url: URL(string: "https://myanimelist.net/forum/?topicid=\(id)")!)
    }
}
private struct MALTopicDetail: Decodable {
    struct Topic: Decodable { let title: String; let posts: [MALPost]? }
    let data: Topic
    let paging: MALPaging?
}
private struct MALPost: Decodable {
    let id: Int
    let body: String?
    let created_at: String?
    let created_by: MALUser?
    var value: CommunityComment {
        CommunityComment(id: id, author: created_by?.name ?? "Deleted user", body: body ?? "[Post unavailable]", createdAt: MALDate.parse(created_at), score: nil)
    }
}
private enum MALDate {
    static func parse(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: raw) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: raw)
    }
}
