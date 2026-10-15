import Foundation

public struct OAuthToken: Codable, Sendable {
    public let accessToken: String
    public let expiresAt: Date
    public init(accessToken: String, expiresAt: Date) { self.accessToken = accessToken; self.expiresAt = expiresAt }
    public var isExpired: Bool { expiresAt <= Date() }
}

public enum OAuthCallback {
    public static func parse(_ url: URL, expectedRedirect: URL, expectedState: String? = nil, now: Date = Date()) throws -> OAuthToken {
        guard let actual = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let expected = URLComponents(url: expectedRedirect, resolvingAgainstBaseURL: false),
              actual.scheme?.lowercased() == expected.scheme?.lowercased(),
              actual.host?.lowercased() == expected.host?.lowercased(), actual.path == expected.path,
              actual.port == expected.port, actual.user == nil, actual.password == nil else { throw ServiceError.message("Unexpected sign-in callback.") }
        var values: [String: String] = [:]
        var seen = Set<String>()
        let fragment = URLComponents(string: "https://callback.invalid/?" + (actual.fragment ?? ""))?.queryItems ?? []
        for item in (actual.queryItems ?? []) + fragment {
            guard seen.insert(item.name).inserted, let value = item.value else { throw ServiceError.message("Invalid sign-in response.") }
            values[item.name] = value
        }
        if let expectedState {
            guard !expectedState.isEmpty, values["state"] == expectedState else {
                throw ServiceError.message("This sign-in response does not match your current request. Please connect AniList again.")
            }
        }
        if let error = values["error"] { throw ServiceError.message(values["error_description"] ?? error) }
        guard let token = values["access_token"], !token.isEmpty, !token.contains(where: { $0.isWhitespace }),
              values["token_type"]?.lowercased() == "bearer" else { throw ServiceError.message("AniList did not return an access token.") }
        guard let seconds = TimeInterval(values["expires_in"] ?? "31536000"), seconds > 0, seconds.isFinite,
              now.addingTimeInterval(seconds).timeIntervalSinceReferenceDate.isFinite else { throw ServiceError.message("The sign-in token has expired or has an invalid expiry.") }
        return OAuthToken(accessToken: token, expiresAt: now.addingTimeInterval(seconds))
    }
}
