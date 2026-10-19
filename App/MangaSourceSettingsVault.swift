import Foundation
import Security
import CryptoKit
import AnimeCore

/// Source credentials/settings never share the AniList or add-on Keychain item.
actor MangaSourceSettingsVault {
    private let service: String
    init(service: String = "com.animecompanion.manga-source-settings") { self.service = service }
    private func query(_ sourceID: String) -> [String: Any] {
        let account = SHA256.hash(data: Data(sourceID.utf8)).map { String(format: "%02x", $0) }.joined()
        return [kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account]
    }
    func load(_ sourceID: String) throws -> MangaSourceSettings {
        var request = query(sourceID)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return MangaSourceSettings() }
        guard status == errSecSuccess, let data = result as? Data else {
            throw ServiceError.message("Source settings could not be read. Unlock this device and try again. Existing values have been kept.")
        }
        return try MangaSourceSettings.decode(data)
    }
    func save(_ settings: MangaSourceSettings, sourceID: String) throws {
        let data = try settings.encoded()
        let base = query(sourceID)
        let status = SecItemUpdate(base as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var request = base
            request[kSecValueData as String] = data
            request[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(request as CFDictionary, nil) == errSecSuccess else {
                throw ServiceError.message("Source settings could not be saved securely. Previous values are unchanged.")
            }
        } else if status != errSecSuccess {
            throw ServiceError.message("Source settings could not be saved securely. Previous values are unchanged.")
        }
    }
}
