import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum TorBoxError: LocalizedError, Equatable {
    case missingKey, unauthorized, rateLimited, notCached, quota, unavailable, invalidResponse, invalidTorrent, notReady, invalidFile
    case planRestricted, missingTorrent, offline, timedOut
    case rejected(status: Int, code: String?)
    public var errorDescription: String? {
        switch self {
        case .missingKey: return "Enter your TorBox API key in Seanime & TorBox settings."
        case .unauthorized: return "TorBox rejected the API key. Check it in your TorBox account."
        case .rateLimited: return "TorBox is rate limiting requests. Wait before retrying."
        case .notCached: return "This torrent is not cached on TorBox. Turn off Cached only if you want TorBox to download it."
        case .quota: return "TorBox could not add this torrent because of an account, storage or download limit. Check your TorBox dashboard."
        case .unavailable: return "The connection to TorBox failed. Check your connection and TorBox service status before retrying."
        case .offline: return "This device is offline. Reconnect to the internet, then retry."
        case .timedOut: return "TorBox took too long to respond. Check your TorBox dashboard before submitting the torrent again."
        case .planRestricted: return "Your TorBox plan does not support this request. Check your plan in the TorBox dashboard."
        case .missingTorrent: return "This torrent or file is no longer available in TorBox. Check your dashboard and forget the local reference if it was deleted."
        case let .rejected(status, code):
            let reason = code.map { " · \($0)" } ?? ""
            return "TorBox returned HTTP \(status)\(reason). Check your TorBox dashboard or try another release."
        case .invalidResponse: return "TorBox returned an unexpected response."
        case .invalidTorrent: return "This result has no valid BitTorrent v1 magnet or info hash."
        case .notReady: return "TorBox is still preparing this torrent. Check readiness again later; it has not been added a second time."
        case .invalidFile: return "Choose an available video file from this torrent. Archives, infected files and other file types are not playable here."
        }
    }
}
public struct TorBoxFile: Decodable, Identifiable, Sendable {
    public let id: Int
    public let name: String
    public let short_name: String?
    public let size: Double?
    public let mimetype: String?
    public let infected: Bool?
    public let zipped: Bool?
    public var isVideo: Bool {
        guard id >= 0, infected != true, zipped != true else { return false }
        let ext = (name as NSString).pathExtension.lowercased()
        return ["mkv", "mp4", "m4v", "mov", "avi", "webm", "ts", "m2ts"].contains(ext)
    }
}
public struct TorBoxTorrent: Decodable, Identifiable, Sendable {
    public let id: Int
    public let name: String?
    public let download_state: String?
    public let download_present: Bool?
    public let download_finished: Bool?
    public let progress: Double?
    public let files: [TorBoxFile]?
    public var ready: Bool { download_present == true && download_finished == true }
    public var videoFiles: [TorBoxFile] { (files ?? []).filter(\.isVideo) }
}

private struct TorBoxEnvelope<T: Decodable>: Decodable {
    let success: Bool
    let error: String?
    let data: T?
}
private struct TorBoxCreated: Decodable { let torrent_id: Int }
private struct TorBoxUser: Decodable { let id: Int }
private struct TorBoxStatus: Decodable { let success: Bool; let error: String?; let detail: String? }
private struct TorBoxList: Decodable {
    let values: [TorBoxTorrent]
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let list = try? container.decode([TorBoxTorrent].self) { values = list }
        else { values = [try container.decode(TorBoxTorrent.self)] }
    }
}

/// TorBox account calls are completely separate from the extension runtime.
/// Authentication is sent only to this fixed API origin, never to provider code.
public struct TorBoxClient: Sendable {
    private let key: String
    private let transport: any HTTPTransport
    public init(key: String, transport: any HTTPTransport = ProviderHTTPTransport()) throws {
        let value = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.utf8.count <= 4096, !value.contains(where: { $0.isWhitespace }),
              !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { throw TorBoxError.missingKey }
        self.key = value; self.transport = transport
    }
    public func verify() async throws {
        let _: TorBoxUser = try await request("user/me", query: [.init(name: "settings", value: "false")])
    }
    /// Call only after explicit user confirmation: this mutates the TorBox account.
    /// No search, account verification or file refresh can implicitly add torrents.
    public func add(magnet: String, cachedOnly: Bool) async throws -> Int {
        guard let parts = URLComponents(string: magnet), parts.scheme?.lowercased() == "magnet",
              let hash = parts.queryItems?.first(where: { $0.name == "xt" })?.value,
              hash.range(of: "^urn:btih:(?:[a-fA-F0-9]{40}|[a-zA-Z2-7]{32})$", options: .regularExpression) != nil,
              magnet.utf8.count <= 32_000, !magnet.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { throw TorBoxError.invalidTorrent }
        let boundary = "AnimeCompanion-" + UUID().uuidString
        let values = [("magnet", magnet), ("allow_zip", "false"), ("add_only_if_cached", cachedOnly ? "true" : "false")]
        let body = values.map { "--\(boundary)\r\nContent-Disposition: form-data; name=\"\($0.0)\"\r\n\r\n\($0.1)\r\n" }.joined() + "--\(boundary)--\r\n"
        let result: TorBoxCreated = try await request("torrents/createtorrent", method: "POST", body: Data(body.utf8), contentType: "multipart/form-data; boundary=\(boundary)", cachedOnly: cachedOnly)
        guard result.torrent_id >= 0 else { throw TorBoxError.invalidResponse }
        return result.torrent_id
    }
    public func torrent(id: Int) async throws -> TorBoxTorrent {
        guard id >= 0 else { throw TorBoxError.invalidTorrent }
        let list: TorBoxList = try await request("torrents/mylist", query: [.init(name: "id", value: String(id)), .init(name: "bypass_cache", value: "true")])
        guard let torrent = list.values.first(where: { $0.id == id }),
              Set((torrent.files ?? []).map(\.id)).count == (torrent.files ?? []).count else { throw TorBoxError.invalidResponse }
        return torrent
    }
    public func download(torrent: TorBoxTorrent, fileID: Int) async throws -> URL {
        guard torrent.ready else { throw TorBoxError.notReady }
        guard torrent.videoFiles.contains(where: { $0.id == fileID }) else { throw TorBoxError.invalidFile }
        // TorBox's documented requestdl API requires the token query argument.
        // Resolve the JSON CDN URL here; never hand the API-key permalink to VidHub.
        let value: String = try await request("torrents/requestdl", query: [
            .init(name: "token", value: key), .init(name: "torrent_id", value: String(torrent.id)),
            .init(name: "file_id", value: String(fileID)), .init(name: "zip_link", value: "false"), .init(name: "redirect", value: "false")])
        guard let url = try? SeanimeNetworkPolicy.httpsURL(value), url.host?.lowercased() != "api.torbox.app",
              !value.contains(key), value.removingPercentEncoding?.contains(key) != true else { throw TorBoxError.invalidResponse }
        return url
    }
    private func request<T: Decodable>(_ path: String, method: String = "GET", query: [URLQueryItem] = [], body: Data? = nil, contentType: String? = nil, cachedOnly: Bool = false) async throws -> T {
        do {
            var parts = URLComponents(string: "https://api.torbox.app/v1/api/\(path)")!
            if !query.isEmpty { parts.queryItems = query }
            var request = URLRequest(url: parts.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
            request.httpMethod = method; request.httpBody = body
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            if let contentType { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
            let (data, response) = try await transport.data(for: request)
            try Task.checkCancellation()
            if response.statusCode == 429 { throw TorBoxError.rateLimited }
            guard data.count <= 4_000_000 else { throw TorBoxError.invalidResponse }
            let httpSuccess = (200..<300).contains(response.statusCode)
            // TorBox uses HTTP 400 for cache misses/account limits and HTTP 5xx
            // for service errors. Decode its error envelope before status gating.
            let status = try? JSONDecoder().decode(TorBoxStatus.self, from: data)
            if let status, !status.success || status.error != nil {
                throw rejection(status, http: response.statusCode, cachedOnly: cachedOnly)
            }
            if response.statusCode == 401 { throw TorBoxError.unauthorized }
            guard httpSuccess else { throw TorBoxError.rejected(status: response.statusCode, code: nil) }
            guard status != nil else { throw TorBoxError.invalidResponse }
            guard let envelope = try? JSONDecoder().decode(TorBoxEnvelope<T>.self, from: data) else { throw TorBoxError.invalidResponse }
            guard let value = envelope.data else { throw TorBoxError.invalidResponse }
            return value
        } catch is CancellationError { throw CancellationError() }
        catch let error as TorBoxError { throw error }
        catch let error as URLError {
            switch error.code {
            case .cancelled: throw CancellationError()
            case .notConnectedToInternet: throw TorBoxError.offline
            case .timedOut: throw TorBoxError.timedOut
            default: throw TorBoxError.unavailable
            }
        }
        catch { throw TorBoxError.unavailable }
    }
    private func rejection(_ response: TorBoxStatus, http: Int, cachedOnly: Bool) -> TorBoxError {
        switch response.error {
        case "NO_AUTH", "BAD_TOKEN", "AUTH_ERROR": return .unauthorized
        case "DOWNLOAD_NOT_CACHED": return .notCached
        case "MONTHLY_LIMIT", "COOLDOWN_LIMIT", "ACTIVE_LIMIT", "DOWNLOAD_TOO_LARGE": return .quota
        case "PLAN_RESTRICTED_FEATURE": return .planRestricted
        case "BOZO_TORRENT": return .invalidTorrent
        case "ITEM_NOT_FOUND": return .missingTorrent
        case "DIFF_ISSUE":
            // Inspect only for known meanings; never display raw server detail,
            // which could echo credentials, private URLs or torrent metadata.
            let detail = (response.detail ?? "").lowercased()
            if cachedOnly, ["not cached", "isn't cached", "not in the cache"].contains(where: detail.contains) { return .notCached }
            if detail.contains("maximum queued downloads") { return .quota }
        default: break
        }
        let code = response.error.flatMap { value -> String? in
            guard value.range(of: "^[A-Z][A-Z0-9_]{0,63}$", options: .regularExpression) != nil,
                  value.range(of: key, options: .caseInsensitive) == nil else { return nil }
            return value
        }
        return .rejected(status: http, code: code)
    }
}
