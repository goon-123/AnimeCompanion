import Foundation
import Security
import AnimeCore

enum CommunityConfiguration {
    static let revisionKey = "community.sources.revision"
    static let offsetKey = "community.episodeOffsets.v1"
    private static let service = "com.animecompanion.community"
    private static let account = "myanimelist-client-id"
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }
    static var malClientID: String? {
        var parameters = query
        parameters[kSecReturnData as String] = true; parameters[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        if SecItemCopyMatching(parameters as CFDictionary, &result) == errSecSuccess,
           let data = result as? Data, let value = String(data: data, encoding: .utf8), !value.isEmpty { return value }
        let bundled = Bundle.main.object(forInfoDictionaryKey: "MyAnimeListClientID") as? String
        return bundled.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
    }
    static func saveMALClientID(_ raw: String) throws {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw ServiceError.message("Could not remove the MyAnimeList client ID.") }
        } else {
            let attributes = [kSecValueData as String: Data(value.utf8), kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly] as [String: Any]
            var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            if status == errSecItemNotFound { status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil) }
            guard status == errSecSuccess else { throw ServiceError.message("Could not save the MyAnimeList client ID securely.") }
        }
        UserDefaults.standard.set(UserDefaults.standard.integer(forKey: revisionKey) + 1, forKey: revisionKey)
    }
    static func offset(source: CommunitySource, animeID: Int, saved: String) -> Int {
        guard let data = saved.data(using: .utf8), let values = try? JSONDecoder().decode([String: Int].self, from: data) else { return 0 }
        return min(100_000, max(-100_000, values["\(source.rawValue)-\(animeID)"] ?? 0))
    }
    static func updatingOffset(_ offset: Int, source: CommunitySource, animeID: Int, saved: String) -> String {
        var values = saved.data(using: .utf8).flatMap { try? JSONDecoder().decode([String: Int].self, from: $0) } ?? [:]
        values["\(source.rawValue)-\(animeID)"] = offset == 0 ? nil : min(100_000, max(-100_000, offset))
        return (try? JSONEncoder().encode(values)).flatMap { String(data: $0, encoding: .utf8) } ?? saved
    }
}
