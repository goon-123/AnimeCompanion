import Foundation

public struct OAuthToken: Codable, Sendable {
    public let accessToken: String
    public let expiresAt: Date
    public init(accessToken: String, expiresAt: Date) { self.accessToken = accessToken; self.expiresAt = expiresAt }
    public var isExpired: Bool { expiresAt <= Date() }
}

public enum OAuthCallback {
    public static func parse(_ url: URL, expectedRedirect: URL, now: Date = Date()) throws -> OAuthToken {
        guard let actual = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let expected = URLComponents(url: expectedRedirect, resolvingAgainstBaseURL: false),
              actual.scheme?.lowercased() == expected.scheme?.lowercased(),
              actual.host?.lowercased() == expected.host?.lowercased(), actual.path == expected.path,
              actual.port == expected.port else { throw ServiceError.message("Unexpected sign-in callback.") }
        var values: [String: String] = [:]
        let fragment = URLComponents(string: "https://callback.invalid/?" + (actual.fragment ?? ""))?.queryItems ?? []
        for item in (actual.queryItems ?? []) + fragment {
            guard values[item.name] == nil else { throw ServiceError.message("Invalid sign-in response.") }
            values[item.name] = item.value
        }
        if let error = values["error"] { throw ServiceError.message(values["error_description"] ?? error) }
        guard let token = values["access_token"], !token.isEmpty,
              values["token_type"]?.lowercased() == "bearer" else { throw ServiceError.message("AniList did not return an access token.") }
        let seconds = TimeInterval(values["expires_in"] ?? "31536000") ?? 31536000
        guard seconds > 0, seconds.isFinite else { throw ServiceError.message("The sign-in token has expired.") }
        return OAuthToken(accessToken: token, expiresAt: now.addingTimeInterval(seconds))
    }
}
