import Foundation
import Security
import AnimeCore

struct MangaBakaAccountKeychain {
    let service: String
    init(service: String = "com.animecompanion.mangabaka") { self.service = service }
    private func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }
    private func read(_ account: String) throws -> Data? {
        var q = query(account); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &value)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let bytes = value as? Data, bytes.count <= 2_000_000 else {
            throw MangaBakaError.message("Your saved MangaBaka accounts could not be read. They have not been removed.")
        }
        return bytes
    }
    func load() throws -> (accounts: MangaBakaAccounts, migrated: Bool)? {
        if let bytes = try read("accounts.v1") {
            return (try JSONDecoder().decode(MangaBakaAccounts.self, from: bytes), false)
        }
        guard let old = try read("connection") else { return nil }
        let accounts = MangaBakaAccounts(legacy: try JSONDecoder().decode(MangaBakaCredential.self, from: old))
        // Write and validate the replacement before retiring the original item.
        try save(accounts)
        return (accounts, true)
    }
    func save(_ accounts: MangaBakaAccounts) throws {
        let bytes = try JSONEncoder().encode(accounts)
        guard bytes.count <= 2_000_000 else { throw MangaBakaError.message("The saved MangaBaka accounts are too large for this device.") }
        let base = query("accounts.v1")
        let status = SecItemUpdate(base as CFDictionary, [kSecValueData as String: bytes] as CFDictionary)
        if status == errSecItemNotFound {
            var q = base; q[kSecValueData as String] = bytes
            q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(q as CFDictionary, nil) == errSecSuccess else {
                throw MangaBakaError.message("The MangaBaka accounts could not be saved securely.")
            }
        } else if status != errSecSuccess { throw MangaBakaError.message("The MangaBaka accounts could not be updated.") }
        // A successfully saved empty registry also prevents old-account resurrection.
        SecItemDelete(query("connection") as CFDictionary)
    }
}
