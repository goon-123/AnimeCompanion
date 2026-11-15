import Foundation

public enum ExternalVideoPlayer: String, CaseIterable, Codable, Identifiable, Sendable {
    case vidHub = "vidhub", outplayer, infuse
    public static let storageKey = "playback.player"
    public var id: String { rawValue }
    public init(preference: String?) { self = preference.flatMap(Self.init(rawValue:)) ?? .vidHub }
    public var label: String {
        switch self {
        case .vidHub: return "VidHub"
        case .outplayer: return "Outplayer"
        case .infuse: return "Infuse"
        }
    }
    public var resumeDescription: String {
        switch self {
        case .vidHub: return "Videos open in VidHub. Supported versions return your position and completion status when you come back."
        case .outplayer: return "Videos open in Outplayer. Closing a video returns your resume position; finishing it can mark the episode watched."
        case .infuse: return "Requires Infuse 8.4.7 or later. Returning from Infuse saves your resume position. Infuse does not report episode completion, so mark watched in AnimeCompanion."
        }
    }
    public var helpURL: URL {
        switch self {
        case .vidHub: return URL(string: "https://vidhub.okaapps.com/3rd-party-app-integration/")!
        case .outplayer: return URL(string: "https://apps.apple.com/app/id1449923287")!
        case .infuse: return URL(string: "https://support.firecore.com/hc/en-us/articles/215090997-API-for-Third-Party-Apps-Services")!
        }
    }
}

/// Direct network video handoff. Each player has its own callback contract;
/// Infuse's success also means early close, whereas Outplayer's means finished.
public enum ExternalPlayerPlayback {
    public static func launchURL(stream: StremioStream, pending: PendingPlayback, position: Double = 0, subtitle: URL? = nil) throws -> URL {
        let player = pending.destination
        if player == .vidHub {
            return try VidHubPlayback.launchURL(stream: stream, pending: pending, position: position, subtitle: subtitle)
        }
        var parts = try components(player: player, stream: stream, title: pending.title, position: position, subtitle: subtitle)
        // Players preserve these opaque callbacks and append their own values.
        // Put the random request identity inside the callback itself: neither
        // Outplayer nor Infuse promises to echo a custom launch parameter.
        for action in player == .outplayer ? ["success", "cancel", "error"] : ["success", "error"] {
            var callback = URLComponents()
            callback.scheme = "animecompanion"; callback.host = "playback"; callback.path = "/" + action
            callback.queryItems = [URLQueryItem(name: "request-id", value: pending.requestID.uuidString)]
            parts.queryItems?.append(URLQueryItem(name: "x-" + action, value: callback.string))
        }
        return try encodedURL(parts)
    }
    /// Provider catalogs and independent TorBox files have no confirmed AniList
    /// identity. Launch without callbacks so they cannot mutate an old episode.
    public static func untrackedLaunchURL(player: ExternalVideoPlayer, stream: StremioStream, title: String, subtitle: URL? = nil) throws -> URL {
        if player == .vidHub { return try VidHubPlayback.untrackedLaunchURL(stream: stream, title: title, subtitle: subtitle) }
        return try encodedURL(components(player: player, stream: stream, title: title, position: 0, subtitle: subtitle))
    }
    private static func components(player: ExternalVideoPlayer, stream: StremioStream, title: String, position: Double, subtitle: URL?) throws -> URLComponents {
        guard stream.behaviorHints?.proxyHeaders?.isRequired != true else { throw PlaybackError.needsProxy }
        guard let video = stream.videoURL else { throw PlaybackError.invalidVideo }
        var parts = URLComponents()
        parts.scheme = player.rawValue; parts.host = "x-callback-url"; parts.path = "/play"
        let start = position.isFinite ? min(VidHubPlayback.maximumPosition, max(0, position)) : 0
        parts.queryItems = [URLQueryItem(name: "url", value: video.absoluteString), URLQueryItem(name: "position", value: String(Int(start)))]
        if player == .infuse {
            parts.queryItems?.append(URLQueryItem(name: "filename", value: PlaybackSourceText.clean(stream.behaviorHints?.filename, maximumLines: 1, maximumCharacters: 180) ?? title))
        }
        if let subtitle, StremioStream.networkURL(subtitle.absoluteString) != nil {
            parts.queryItems?.append(URLQueryItem(name: player == .outplayer ? "subtitle" : "sub", value: subtitle.absoluteString))
        }
        return parts
    }
    private static func encodedURL(_ components: URLComponents) throws -> URL {
        var parts = components
        let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        // Encode nested URLs once, including literal '+' in signed queries.
        // Some receivers parse '+' as a space unless it is escaped as %2B.
        parts.percentEncodedQuery = parts.queryItems?.map { item in
            item.name + "=" + (item.value ?? "").addingPercentEncoding(withAllowedCharacters: safe)!
        }.joined(separator: "&")
        guard let url = parts.url else { throw PlaybackError.invalidVideo }
        return url
    }
    public static func outcome(url: URL, pending: PendingPlayback, now: Date = Date()) throws -> PlaybackOutcome? {
        if pending.destination == .vidHub { return try VidHubPlayback.outcome(url: url, pending: pending, now: now) }
        guard url.scheme?.lowercased() == "animecompanion", url.host?.lowercased() == "playback",
              url.user == nil, url.password == nil, url.port == nil, url.fragment == nil,
              ["/success", "/error", "/cancel"].contains(url.path),
              now.timeIntervalSince(pending.createdAt) >= -60, now.timeIntervalSince(pending.createdAt) <= 86400,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        var values: [String: String] = [:]
        for item in parts.queryItems ?? [] {
            guard values[item.name] == nil, let value = item.value else { throw PlaybackError.invalidCallback }
            values[item.name] = value
        }
        guard values["request-id"].flatMap(UUID.init(uuidString:)) == pending.requestID else { return nil }
        if url.path == "/error" { return .failed(code: values["errorCode"].flatMap(Int.init)) }
        switch (pending.destination, url.path) {
        case (.outplayer, "/success"):
            // No position is returned on completion. Do not fabricate a runtime.
            return .success(position: 0, duration: nil, finished: true)
        case (.outplayer, "/cancel"):
            return .success(position: try number(values["position"]), duration: try number(values["duration"]), finished: false)
        case (.infuse, "/success"):
            // Success is also returned when Infuse is closed before the end.
            return .success(position: try number(values["position"]), duration: nil, finished: false)
        default: return nil
        }
    }
    private static func number(_ raw: String?) throws -> Double {
        guard let raw, let value = Double(raw), value.isFinite, (0...VidHubPlayback.maximumPosition).contains(value) else { throw PlaybackError.invalidCallback }
        return value
    }
}
