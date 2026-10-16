import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum TorBoxError: LocalizedError, Equatable {
    case missingKey, unauthorized, rateLimited, notCached, quota, unavailable, invalidResponse, invalidTorrent, notReady, invalidFile
    case planRestricted, missingTorrent, offline, timedOut
    case playbackResponse, missingPlaybackLink, invalidPlaybackLink, privatePlaybackLink
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
        case .playbackResponse: return "TorBox's playback-link response could not be read. Refresh the files and try again."
        case .missingPlaybackLink: return "TorBox returned no playback link for this file. Refresh the files and try again."
        case .invalidPlaybackLink: return "TorBox returned an unsupported playback address. Try another file or check your TorBox CDN setting."
        case .privatePlaybackLink: return "TorBox returned an account link instead of a temporary video link. It could not be sent to VidHub."
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
    private enum CodingKeys: String, CodingKey { case id, name, short_name, size, mimetype, infected, zipped }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(TorBoxID.self, forKey: .id).value
        name = try c.decode(String.self, forKey: .name)
        // Optional display metadata must not make an otherwise valid file list fail.
        short_name = try? c.decode(String.self, forKey: .short_name)
        size = try? c.decode(Double.self, forKey: .size)
        mimetype = try? c.decode(String.self, forKey: .mimetype)
        // An unrecognised safety flag is not permission to play that file.
        func safetyFlag(_ key: CodingKeys) -> Bool? {
            guard c.contains(key), (try? c.decodeNil(forKey: key)) != true else { return nil }
            return (try? c.decode(Bool.self, forKey: key)) ?? true
        }
        infected = safetyFlag(.infected); zipped = safetyFlag(.zipped)
    }
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
    public let hash: String?
    public let alternative_hashes: [String]?
    private enum CodingKeys: String, CodingKey { case id, name, download_state, download_present, download_finished, progress, files, hash, alternative_hashes }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(TorBoxID.self, forKey: .id).value
        name = try? c.decode(String.self, forKey: .name)
        download_state = try? c.decode(String.self, forKey: .download_state)
        download_present = try? c.decode(Bool.self, forKey: .download_present)
        download_finished = try? c.decode(Bool.self, forKey: .download_finished)
        progress = try? c.decode(Double.self, forKey: .progress)
        files = try c.decodeIfPresent([TorBoxFile].self, forKey: .files)
        hash = try? c.decode(String.self, forKey: .hash)
        alternative_hashes = try? c.decode([String].self, forKey: .alternative_hashes)
    }
    public var ready: Bool { download_present == true && download_finished == true }
    public var videoFiles: [TorBoxFile] { (files ?? []).filter(\.isVideo) }
}

/// A queued ID is not a torrent ID. Keep the content hash so a queued or
/// interrupted submission can be found later using GET requests alone.
public struct TorBoxJob: Codable, Equatable, Sendable {
    public let torrentID: Int?
    public let queuedID: Int?
    public let infoHash: String?
    public init(torrentID: Int? = nil, queuedID: Int? = nil, infoHash: String? = nil) {
        self.torrentID = torrentID; self.queuedID = queuedID; self.infoHash = infoHash
    }
    public init(magnet: String) throws {
        guard let parts = URLComponents(string: magnet), parts.scheme?.lowercased() == "magnet",
              let xt = parts.queryItems?.first(where: { $0.name == "xt" })?.value,
              xt.lowercased().hasPrefix("urn:btih:"),
              let hash = Self.normalizedHash(String(xt.dropFirst(9))),
              magnet.utf8.count <= 32_000, !magnet.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { throw TorBoxError.invalidTorrent }
        self.init(infoHash: hash)
    }
    static func normalizedHash(_ value: String) -> String? {
        if value.range(of: "^[a-fA-F0-9]{40}$", options: .regularExpression) != nil { return value.lowercased() }
        guard value.range(of: "^[a-zA-Z2-7]{32}$", options: .regularExpression) != nil else { return nil }
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567".utf8)
        var bits = 0, buffer = 0, bytes: [UInt8] = []
        for char in value.uppercased().utf8 {
            guard let digit = alphabet.firstIndex(of: char) else { return nil }
            buffer = (buffer << 5) | digit; bits += 5
            if bits >= 8 { bits -= 8; bytes.append(UInt8((buffer >> bits) & 255)); buffer &= (1 << bits) - 1 }
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}

private struct TorBoxID: Decodable {
    let value: Int
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let number = try? c.decode(Int.self), number >= 0 { value = number; return }
        if let text = try? c.decode(String.self), text.range(of: "^[0-9]{1,19}$", options: .regularExpression) != nil,
           let number = Int(text) { value = number; return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "Expected a nonnegative integer ID")
    }
}
private struct TorBoxEnvelope<T: Decodable>: Decodable {
    let data: T
}
private struct TorBoxCreated: Decodable { let torrent_id: TorBoxID?; let queued_id: TorBoxID? }
private struct TorBoxUser: Decodable { let id: Int }
private struct TorBoxStatus: Decodable {
    let success: Bool; let error: String?; let detail: String?
    private enum CodingKeys: String, CodingKey { case success, error, detail }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        success = try c.decode(Bool.self, forKey: .success)
        // TorBox's SDK declares error as an arbitrary JSON value, even on success.
        error = try? c.decode(String.self, forKey: .error)
        detail = try? c.decode(String.self, forKey: .detail)
    }
}
private struct TorBoxList: Decodable {
    let values: [TorBoxTorrent]
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { values = [] }
        else if let list = try? container.decode([TorBoxTorrent].self) { values = list }
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
    public func add(magnet: String, cachedOnly: Bool) async throws -> TorBoxJob {
        let pending = try TorBoxJob(magnet: magnet)
        let boundary = "AnimeCompanion-" + UUID().uuidString
        let values = [("magnet", magnet), ("allow_zip", "false"), ("add_only_if_cached", cachedOnly ? "true" : "false")]
        let body = values.map { "--\(boundary)\r\nContent-Disposition: form-data; name=\"\($0.0)\"\r\n\r\n\($0.1)\r\n" }.joined() + "--\(boundary)--\r\n"
        let (data, _) = try await response("torrents/createtorrent", method: "POST", body: Data(body.utf8), contentType: "multipart/form-data; boundary=\(boundary)", cachedOnly: cachedOnly)
        // Success means the account accepted the request, including queued jobs.
        // If its receipt omits IDs, recover by the exact hash instead of POSTing again.
        let result = try? JSONDecoder().decode(TorBoxEnvelope<TorBoxCreated>.self, from: data).data
        return TorBoxJob(torrentID: result?.torrent_id?.value, queuedID: result?.queued_id?.value, infoHash: pending.infoHash)
    }
    public func torrent(id: Int) async throws -> TorBoxTorrent {
        guard id >= 0 else { throw TorBoxError.invalidTorrent }
        let list: TorBoxList = try await request("torrents/mylist", query: [.init(name: "id", value: String(id)), .init(name: "bypass_cache", value: "true")])
        guard let torrent = list.values.first(where: { $0.id == id }),
              Set((torrent.files ?? []).map(\.id)).count == (torrent.files ?? []).count else { throw TorBoxError.invalidResponse }
        return torrent
    }
    public func resolve(_ job: TorBoxJob) async throws -> TorBoxTorrent? {
        if let id = job.torrentID {
            guard id >= 0 else { throw TorBoxError.invalidTorrent }
            let list: TorBoxList = try await request("torrents/mylist", query: [.init(name: "id", value: String(id)), .init(name: "bypass_cache", value: "true")])
            if list.values.isEmpty { return nil }
            guard let torrent = list.values.first(where: { $0.id == id }),
                  Set((torrent.files ?? []).map(\.id)).count == (torrent.files ?? []).count else { throw TorBoxError.invalidResponse }
            return torrent
        }
        guard let hash = job.infoHash.flatMap(TorBoxJob.normalizedHash) else { throw TorBoxError.invalidTorrent }
        // Names, episode guesses and queue IDs must never select an unrelated file.
        // Page the account list because older accepted jobs may not be on page one.
        var previousIDs: Set<Int> = []
        for page in 0..<100 {
            let list: TorBoxList = try await request("torrents/mylist", query: [
                .init(name: "bypass_cache", value: "true"), .init(name: "offset", value: String(page * 100)), .init(name: "limit", value: "100")])
            if let value = list.values.first(where: { torrent in
                ([torrent.hash].compactMap { $0 } + (torrent.alternative_hashes ?? [])).contains { TorBoxJob.normalizedHash($0) == hash }
            }) {
                guard Set((value.files ?? []).map(\.id)).count == (value.files ?? []).count else { throw TorBoxError.invalidResponse }
                return value
            }
            if list.values.count < 100 { return nil }
            let ids = Set(list.values.map(\.id))
            guard ids != previousIDs else { throw TorBoxError.invalidResponse }
            previousIDs = ids
        }
        throw TorBoxError.invalidResponse
    }
    public func download(torrent: TorBoxTorrent, fileID: Int) async throws -> URL {
        guard torrent.ready else { throw TorBoxError.notReady }
        guard torrent.videoFiles.contains(where: { $0.id == fileID }) else { throw TorBoxError.invalidFile }
        // Request the documented redirect, but never follow it with account
        // authentication. ProviderHTTPTransport leaves Location untouched.
        // Only the resolved CDN URL is handed to the external player.
        let data: Data, http: HTTPURLResponse
        do {
            (data, http) = try await response("torrents/requestdl", query: [
                .init(name: "token", value: key), .init(name: "torrent_id", value: String(torrent.id)),
                .init(name: "file_id", value: String(fileID)), .init(name: "redirect", value: "true")], downloadRedirect: true)
        } catch TorBoxError.invalidResponse { throw TorBoxError.playbackResponse }
        let value: String
        if Self.downloadRedirects.contains(http.statusCode) {
            guard let location = http.value(forHTTPHeaderField: "Location"), !location.isEmpty else { throw TorBoxError.missingPlaybackLink }
            value = location
        } else {
            // Some API deployments return the JSON result even with redirect
            // requested. Keep support for the documented data:string envelope.
            guard let envelope = try? JSONDecoder().decode(TorBoxEnvelope<String?>.self, from: data) else { throw TorBoxError.playbackResponse }
            guard let link = envelope.data, !link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw TorBoxError.missingPlaybackLink }
            value = link
        }
        return try playbackURL(value)
    }
    private static let downloadRedirects: Set<Int> = [302, 303, 307, 308]
    private func playbackURL(_ value: String) throws -> URL {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.utf8.count <= 32_000,
              !text.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              let parts = URLComponents(string: text), parts.scheme?.lowercased() == "https",
              let host = parts.host, SeanimeNetworkPolicy.publicHost(host) != nil,
              parts.fragment == nil, parts.port.map({ (1...65535).contains($0) }) ?? true,
              let url = parts.url else { throw TorBoxError.invalidPlaybackLink }
        // CDN playback is not an extension network request: valid HTTPS ports
        // must survive along with signed path/query bytes. Keep credentials out.
        guard parts.user == nil, parts.password == nil, host.lowercased() != "api.torbox.app",
              !text.contains(key), text.removingPercentEncoding?.contains(key) != true else { throw TorBoxError.privatePlaybackLink }
        return url
    }
    private func request<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        let (data, _) = try await response(path, query: query)
        guard let envelope = try? JSONDecoder().decode(TorBoxEnvelope<T>.self, from: data) else { throw TorBoxError.invalidResponse }
        return envelope.data
    }
    private func response(_ path: String, method: String = "GET", query: [URLQueryItem] = [], body: Data? = nil, contentType: String? = nil, cachedOnly: Bool = false, downloadRedirect: Bool = false) async throws -> (Data, HTTPURLResponse) {
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
            // A redirect is a result only for the file-link request. All other
            // account/provider calls continue to reject redirects.
            if downloadRedirect, Self.downloadRedirects.contains(response.statusCode) { return (data, response) }
            let httpSuccess = (200..<300).contains(response.statusCode)
            // TorBox uses HTTP 400 for cache misses/account limits and HTTP 5xx
            // for service errors. Decode its error envelope before status gating.
            let status = try? JSONDecoder().decode(TorBoxStatus.self, from: data)
            if let status, !status.success {
                throw rejection(status, http: response.statusCode, cachedOnly: cachedOnly)
            }
            if response.statusCode == 401 { throw TorBoxError.unauthorized }
            guard httpSuccess else { throw TorBoxError.rejected(status: response.statusCode, code: nil) }
            guard status != nil else { throw TorBoxError.invalidResponse }
            return (data, response)
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
