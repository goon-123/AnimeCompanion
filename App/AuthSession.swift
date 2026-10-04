import AuthenticationServices
import Security
import UIKit
import AnimeCore

enum AppConfiguration {
    static let callback = URL(string: "animecompanion://oauth/anilist")!
    static var clientID: String? {
        let stored = UserDefaults.standard.string(forKey: "anilist.clientID")?.trimmingCharacters(in: .whitespacesAndNewlines)
        let bundled = (Bundle.main.object(forInfoDictionaryKey: "AniListClientID") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return [stored, bundled].compactMap { $0 }.first { !$0.isEmpty && Int($0) != nil }
    }
}

enum KeychainTokenStore {
    private static let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.animecompanion.anilist", kSecAttrAccount as String: "oauth"]
    static func load() throws -> OAuthToken? {
        var query = base; query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw ServiceError.message("Unable to read the saved AniList connection.") }
        return try JSONDecoder().decode(OAuthToken.self, from: data)
    }
    static func save(_ token: OAuthToken) throws {
        let data = try JSONEncoder().encode(token)
        let updates = [kSecValueData as String: data] as CFDictionary
        let status = SecItemUpdate(base as CFDictionary, updates)
        if status == errSecItemNotFound {
            var query = base
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(query as CFDictionary, nil) == errSecSuccess else { throw ServiceError.message("Unable to save the AniList connection securely.") }
        } else if status != errSecSuccess { throw ServiceError.message("Unable to update the saved AniList connection.") }
    }
    static func delete() throws {
        let status = SecItemDelete(base as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw ServiceError.message("Unable to remove the saved connection.") }
    }
}

@MainActor
final class AuthSession: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?
    func signIn(clientID: String) async throws -> OAuthToken {
        var url = URLComponents(string: "https://anilist.co/api/v2/oauth/authorize")!
        // AniList's implicit mobile flow expects only the client ID and response type here.
        // The registered AniList application decides which redirect URI receives the token.
        url.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "token")
        ]
        return try await withCheckedThrowingContinuation { continuation in
            let web = ASWebAuthenticationSession(url: url.url!, callbackURLScheme: AppConfiguration.callback.scheme) { callback, error in
                Task { @MainActor in
                    self.session = nil
                    if let error { continuation.resume(throwing: error); return }
                    guard let callback else { continuation.resume(throwing: ServiceError.invalidResponse); return }
                    do { continuation.resume(returning: try OAuthCallback.parse(callback, expectedRedirect: AppConfiguration.callback)) }
                    catch { continuation.resume(throwing: error) }
                }
            }
            web.presentationContextProvider = self
            web.prefersEphemeralWebBrowserSession = false
            session = web
            if !web.start() { session = nil; continuation.resume(throwing: ServiceError.message("Could not open AniList sign-in.")) }
        }
    }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?.windows.first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}
