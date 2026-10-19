import XCTest
import Security
import CryptoKit
import AnimeCore
@testable import AnimeCompanion

final class MangaSourceSettingsVaultTests: XCTestCase {
    func testKeychainValuesSurviveNewVaultAndRemainSeparateForEachSource() async throws {
        let service = "com.animecompanion.settings-test.\(UUID().uuidString)"
        defer { SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service] as CFDictionary) }
        let first = MangaSourceSettings(values: ["password": .string("owned password"), "quality": .string("high")])
        let second = MangaSourceSettings(values: ["password": .string("another owned password")])
        let vault = MangaSourceSettingsVault(service: service)
        try await vault.save(first, sourceID: "extension-A/source-1")
        try await vault.save(second, sourceID: "extension-A/source-2")
        let reopened = MangaSourceSettingsVault(service: service)
        let loadedFirst = try await reopened.load("extension-A/source-1")
        let loadedSecond = try await reopened.load("extension-A/source-2")
        let missing = try await reopened.load("extension-B/source-1")
        XCTAssertEqual(loadedFirst, first); XCTAssertEqual(loadedSecond, second); XCTAssertTrue(missing.values.isEmpty)
        try await reopened.save(.init(), sourceID: "extension-A/source-1")
        let cleared = try await reopened.load("extension-A/source-1")
        let retained = try await reopened.load("extension-A/source-2")
        XCTAssertTrue(cleared.values.isEmpty); XCTAssertEqual(retained, second)
    }

    func testUnreadableFutureSettingsArePreservedAndOversizedSaveKeepsPreviousItem() async throws {
        let service = "com.animecompanion.settings-test.\(UUID().uuidString)", source = "owned/source"
        let account = SHA256.hash(data: Data(source.utf8)).map { String(format: "%02x", $0) }.joined()
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        defer { SecItemDelete(query as CFDictionary) }
        let future = Data(#"{"schema":999,"values":{}}"#.utf8)
        var item = query; item[kSecValueData as String] = future
        XCTAssertEqual(SecItemAdd(item as CFDictionary, nil), errSecSuccess)
        let vault = MangaSourceSettingsVault(service: service)
        do { _ = try await vault.load(source); XCTFail("Future settings must remain unreadable") } catch {}
        do {
            try await vault.save(.init(values: ["password": .string(String(repeating: "x", count: 16_385))]), sourceID: source)
            XCTFail("Oversized save must fail")
        } catch {}
        var read = query; read[kSecReturnData as String] = true
        var result: CFTypeRef?
        XCTAssertEqual(SecItemCopyMatching(read as CFDictionary, &result), errSecSuccess)
        XCTAssertEqual(result as? Data, future)
    }
}
