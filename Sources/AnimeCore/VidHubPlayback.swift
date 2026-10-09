import Foundation

public struct PlaybackEpisode: Codable, Hashable, Sendable {
    public let animeID: Int
    public let episode: Int
    public var key: String { "\(animeID):\(episode)" }
    public init(animeID: Int, episode: Int) { self.animeID = animeID; self.episode = episode }
}
public struct PendingPlayback: Codable, Sendable {
    public let requestID: UUID
    public let episode: PlaybackEpisode
    public let title: String
    public let createdAt: Date
    public init(episode: PlaybackEpisode, title: String, requestID: UUID = UUID(), createdAt: Date = Date()) {
        self.episode = episode; self.title = title; self.requestID = requestID; self.createdAt = createdAt
    }
}
public struct PlaybackProgress: Codable, Sendable {
    public let position: Double
    public let duration: Double?
    public let finished: Bool
    public let updatedAt: Date
    public init(position: Double, duration: Double?, finished: Bool, updatedAt: Date = Date()) {
        self.position = finished ? 0 : position; self.duration = duration; self.finished = finished; self.updatedAt = updatedAt
    }
}
public enum VidHubOutcome: Equatable, Sendable {
    case success(position: Double, duration: Double?, finished: Bool)
    case failed(code: Int?)
    case cancelled
}
public enum VidHubPlayback {
    public static let maximumPosition: Double = 31_536_000
    public static func launchURL(stream: StremioStream, pending: PendingPlayback, position: Double = 0, subtitle: URL? = nil) throws -> URL {
        guard stream.behaviorHints?.proxyHeaders?.isRequired != true else { throw PlaybackError.needsProxy }
        guard let video = stream.videoURL else { throw PlaybackError.invalidVideo }
        var parts = URLComponents()
        parts.scheme = "open-vidhub"; parts.host = "x-callback-url"; parts.path = "/play"
        let start = position.isFinite ? min(maximumPosition, max(0, position)) : 0
        parts.queryItems = [
            URLQueryItem(name: "url", value: video.absoluteString),
            URLQueryItem(name: "position", value: String(Int(start))),
            URLQueryItem(name: "filename", value: stream.behaviorHints?.filename ?? pending.title),
            URLQueryItem(name: "request-id", value: pending.requestID.uuidString),
            URLQueryItem(name: "x-source", value: "Anime Companion"),
            URLQueryItem(name: "x-success", value: "animecompanion://playback/success"),
            URLQueryItem(name: "x-error", value: "animecompanion://playback/error"),
            URLQueryItem(name: "x-cancel", value: "animecompanion://playback/cancel")
        ]
        if let subtitle, StremioStream.networkURL(subtitle.absoluteString) != nil {
            parts.queryItems?.append(URLQueryItem(name: "sub", value: subtitle.absoluteString))
        }
        guard let url = parts.url else { throw PlaybackError.invalidVideo }
        return url
    }
    /// Only a callback for the outstanding random request can change local progress.
    /// A success callback means the player exited; status, not callback name, means completion.
    public static func outcome(url: URL, pending: PendingPlayback, now: Date = Date()) throws -> VidHubOutcome? {
        guard url.scheme?.lowercased() == "animecompanion", url.host?.lowercased() == "playback",
              url.user == nil, url.password == nil, url.port == nil, url.fragment == nil,
              ["/success", "/error", "/cancel"].contains(url.path),
              now.timeIntervalSince(pending.createdAt) >= -60,
              now.timeIntervalSince(pending.createdAt) <= 86400,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        var values: [String: String] = [:]
        for item in parts.queryItems ?? [] {
            guard values[item.name] == nil, let value = item.value else { throw PlaybackError.invalidCallback }
            values[item.name] = value
        }
        guard values["request-id"].flatMap(UUID.init(uuidString:)) == pending.requestID else { return nil }
        switch url.path {
        case "/cancel": return .cancelled
        case "/error": return .failed(code: values["errorCode"].flatMap(Int.init))
        default:
            guard let status = values["status"], ["finished", "stopped"].contains(status),
                  let position = values["position"].flatMap(Double.init), position.isFinite,
                  (0...maximumPosition).contains(position) else { throw PlaybackError.invalidCallback }
            var duration: Double?
            if let raw = values["duration"] {
                guard let parsed = Double(raw), parsed.isFinite, parsed >= 0, parsed <= maximumPosition else { throw PlaybackError.invalidCallback }
                duration = parsed
            }
            return .success(position: position, duration: duration, finished: status == "finished")
        }
    }
}
