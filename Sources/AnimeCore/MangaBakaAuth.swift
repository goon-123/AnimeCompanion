import Foundation

public enum MangaBakaError: LocalizedError, Equatable {
    case unauthorized, invalidResponse, rateLimited(Int), http(Int), message(String)
    public var errorDescription: String? {
        switch self {
        case .unauthorized: return "Your MangaBaka connection needs attention. Reconnect your account."
        case .invalidResponse: return "MangaBaka returned an unreadable response. Please try again."
        case .rateLimited(let seconds): return "MangaBaka is busy. Try again in \(seconds) seconds."
        case .http(403): return "This MangaBaka connection does not have permission for that action."
        case .http(404): return "This MangaBaka entry could not be found."
        case .http(let code): return "MangaBaka returned HTTP \(code). Please try again."
        case .message(let message): return message
        }
    }
}

public struct MangaBakaCredential: Codable, Sendable, Equatable {
    private enum CodingKeys: String, CodingKey { case kind, secret, refreshToken, expiresAt, clientID }
    public enum Kind: String, Codable, Sendable { case oauth, apiKey }
    public let kind: Kind
    public let secret: String
    public let refreshToken: String?
    public let expiresAt: Date?
    public let clientID: String?
    public init(kind: Kind, secret: String, refreshToken: String? = nil, expiresAt: Date? = nil, clientID: String? = nil) throws {
        let value = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.utf8.count <= 16_384,
              value.unicodeScalars.allSatisfy({ $0.value > 32 && $0.value < 127 }) else { throw MangaBakaError.message("Enter a valid MangaBaka connection key.") }
        self.kind = kind; self.secret = value; self.refreshToken = refreshToken
        self.expiresAt = expiresAt; self.clientID = clientID
    }
    public func needsRefresh(at date: Date = Date()) -> Bool { kind == .oauth && expiresAt.map { $0 <= date.addingTimeInterval(60) } == true }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(kind: c.decode(Kind.self, forKey: .kind), secret: c.decode(String.self, forKey: .secret),
            refreshToken: c.decodeIfPresent(String.self, forKey: .refreshToken), expiresAt: c.decodeIfPresent(Date.self, forKey: .expiresAt),
            clientID: c.decodeIfPresent(String.self, forKey: .clientID))
    }
}

public enum MangaBakaOAuth {
    public static let callback = URL(string: "animecompanion://oauth/mangabaka")!
    public static let issuer = "https://mangabaka.org/auth"
    public static let tokenURL = URL(string: "https://mangabaka.org/auth/oauth2/token")!
    public static let scope = "openid profile library.read library.write offline_access"
    public static func authorize(clientID: String, state: String, challenge: String) throws -> URL {
        guard !clientID.isEmpty, clientID.count <= 200, !state.isEmpty, !challenge.isEmpty else { throw MangaBakaError.message("Configure a MangaBaka app ID first.") }
        var c = URLComponents(string: "https://mangabaka.org/auth/oauth2/authorize")!
        c.queryItems = [URLQueryItem(name: "client_id", value: clientID), .init(name: "redirect_uri", value: callback.absoluteString),
            .init(name: "response_type", value: "code"), .init(name: "scope", value: scope), .init(name: "state", value: state),
            .init(name: "code_challenge", value: challenge), .init(name: "code_challenge_method", value: "S256")]
        return c.url!
    }
    public static func code(from url: URL, expectedState: String, startedAt: Date, now: Date = Date()) throws -> String {
        guard !expectedState.isEmpty, now.timeIntervalSince(startedAt) >= 0, now.timeIntervalSince(startedAt) <= 600,
              url.scheme == callback.scheme, url.host == callback.host, url.path == callback.path,
              url.user == nil, url.password == nil, url.port == nil, url.fragment == nil,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { throw MangaBakaError.message("The MangaBaka sign-in response did not match this attempt.") }
        var values: [String: String] = [:]
        for item in parts.queryItems ?? [] {
            guard values[item.name] == nil else { throw MangaBakaError.invalidResponse }
            values[item.name] = item.value ?? ""
        }
        guard values["state"] == expectedState, values["iss"].map({ $0 == issuer }) ?? true else { throw MangaBakaError.message("The MangaBaka sign-in response did not match this attempt.") }
        guard values["error"] == nil else { throw MangaBakaError.message("MangaBaka sign-in was not authorized.") }
        guard let code = values["code"], !code.isEmpty, code.count <= 2048 else { throw MangaBakaError.invalidResponse }
        return code
    }
    public static func form(_ values: [String: String]) -> Data {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return Data(values.sorted { $0.key < $1.key }.map {
            "\($0.key.addingPercentEncoding(withAllowedCharacters: allowed)!)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed)!)"
        }.joined(separator: "&").utf8)
    }
}
