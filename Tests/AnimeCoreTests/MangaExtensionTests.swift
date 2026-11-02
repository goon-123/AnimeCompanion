import XCTest
import CZlib
@testable import AnimeCore
#if canImport(CryptoKit)
import CryptoKit
#endif
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class MangaExtensionTests: XCTestCase {
    func testWebsiteGitHubAndOldInstallLinksResolveToTheCurrentIndex() throws {
        for url in ["https://keiyoushi.github.io", "https://keiyoushi.github.io/extensions/", "https://github.com/keiyoushi/extensions", "https://github.com/keiyoushi/extensions/raw/repo/index.pb", "https://github.com/keiyoushi/extensions/raw/refs/heads/repo/repo.json", "https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.min.json", "https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.pb"] {
            XCTAssertEqual(try MangaRepository(url), .keiyoushi, url)
        }
        for url in ["http://keiyoushi.github.io", "https://keiyoushi.github.io.evil.test", "https://github.com/other/extensions", "https://user:pass@github.com/keiyoushi/extensions", "https://github.com/keiyoushi/extensions?token=secret"] {
            XCTAssertThrowsError(try MangaRepository(url), url)
        }
    }

    func testGzippedModernIndexKeepsFullPrecisionIDsAndDownloadURLs() throws {
        let raw = fixtureIndex(extra: bytesField(999, Data("future field".utf8)))
        for data in [raw, try gzip(raw)] {
            let catalog = try MangaExtensionCatalog.decode(data)
            XCTAssertEqual(catalog.name, "Keiyoushi")
            XCTAssertEqual(catalog.extensions.count, 1)
            let entry = try XCTUnwrap(catalog.extensions.first)
            XCTAssertEqual(entry.sources[0].id, "918273645546372819")
            XCTAssertEqual(entry.apiVersion, "1.6")
            XCTAssertEqual(entry.versionCode, 106001)
            XCTAssertEqual(entry.apkURL.absoluteString, "https://github.com/keiyoushi/extensions/releases/download/fixture/fixture-v1.6.1.apk")
            XCTAssertEqual(entry.iconURL?.absoluteString, "https://cdn.jsdelivr.net/gh/keiyoushi/extensions-source@main/src/en/fixture/res/mipmap-xhdpi/ic_launcher.png")
            let restored = try JSONDecoder().decode(MangaExtensionDescriptor.self, from: JSONEncoder().encode(entry))
            XCTAssertEqual(restored.iconURL, entry.iconURL, "Installing/restarting must retain the repository icon")
            XCTAssertTrue(entry.supportsRuntime)
            XCTAssertNil(entry.sha256, "Digest comes from the separate published release inventory")
        }
    }

    func testMalformedWrongPublisherAndDuplicatePackagesFailClosed() throws {
        for data in [Data([0x80]), Data([0x0a, 0xff, 0xff, 0xff, 0xff, 0x7f]),
                     fixtureIndex(signingKey: String(repeating: "0", count: 64)),
                     fixtureIndex(duplicate: true), Data("[{\"name\":\"Outdated App\"}]".utf8)] {
            XCTAssertThrowsError(try MangaExtensionCatalog.decode(data))
        }
        XCTAssertThrowsError(try MangaExtensionCatalog.decode(gzip(Data(repeating: 0, count: 16_000_001)))) {
            XCTAssertEqual($0 as? MangaExtensionError, .oversized)
        }
    }

    func testFutureRuntimeVersionIsListedButCannotBeInstalled() throws {
        let entry = try XCTUnwrap(MangaExtensionCatalog.decode(fixtureIndex(api: "1.9")).extensions.first)
        XCTAssertFalse(entry.supportsRuntime)
    }

    func testFilteringSeparatesLanguagesAndMatureCollections() throws {
        let english = try fixtureEntry()
        XCTAssertTrue(english.matches(query: "fixture", language: "en", includeAdult: false))
        XCTAssertFalse(english.matches(query: "fixture", language: "es", includeAdult: false))
        let adult = try XCTUnwrap(MangaExtensionCatalog.decode(fixtureIndex(warning: 3)).extensions.first)
        XCTAssertFalse(adult.matches(query: "", language: "en", includeAdult: false))
        XCTAssertTrue(adult.matches(query: "", language: "en", includeAdult: true))
    }

    func testCatalogDoesNotUseBuildContentHashesAsAPKDigests() async throws {
        let transport = MangaFixtureTransport(index: try gzip(fixtureIndex()))
        let catalog = try await MangaRepositoryClient(transport: transport).catalog()
        XCTAssertNil(catalog.extensions[0].sha256)
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1, "release-assets.json is build metadata, not a package checksum feed")
        XCTAssertTrue(requests[0].url!.path.hasSuffix("index.pb"))
    }

    func testExactReleaseAssetReplacesPreviouslyCachedContentHash() async throws {
        let transport = MangaFixtureTransport(index: fixtureIndex())
        let client = MangaRepositoryClient(transport: transport)
        let old = try fixtureEntry(digest: "b")
        let verified = try await client.verifiedDescriptor(old)
        XCTAssertEqual(verified.sha256, String(repeating: "a", count: 64))
        XCTAssertEqual(old.sha256, String(repeating: "b", count: 64), "Old cached descriptors must not be trusted or mutated")
        let apk = try await client.package(verified)
        XCTAssertEqual(apk, Data("fixture-apk".utf8))
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].url?.absoluteString, "https://api.github.com/repos/keiyoushi/extensions/releases/tags/fixture")
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")
        XCTAssertTrue(requests.allSatisfy { $0.cachePolicy == .reloadIgnoringLocalCacheData })
    }

    func testVerificationRequiresTheExactUploadedAPKWithAnUnambiguousSHA256() async throws {
        let valid = fixtureReleaseAsset()
        var invalid: [[String: Any]] = []
        for (key, value) in [
            ("name", "old-version.apk"),
            ("browser_download_url", "https://github.com/other/extensions/releases/download/fixture/fixture-v1.6.1.apk"),
            ("digest", String(repeating: "a", count: 64)),
            ("digest", "sha256:invalid"), ("state", "new")
        ] {
            var asset = valid; asset[key] = value
            invalid.append(["tag_name": "fixture", "draft": false, "assets": [asset]])
        }
        var missing = valid; missing["digest"] = NSNull()
        invalid += [
            ["tag_name": "fixture", "draft": false, "assets": [missing]],
            ["tag_name": "other", "draft": false, "assets": [valid]],
            ["tag_name": "fixture", "draft": true, "assets": [valid]],
            ["tag_name": "fixture", "draft": false, "assets": [valid, valid]],
            ["tag_name": "fixture", "draft": false, "assets": []]
        ]
        for release in invalid {
            let transport = MangaFixtureTransport(index: fixtureIndex(), release: try JSONSerialization.data(withJSONObject: release))
            do {
                _ = try await MangaRepositoryClient(transport: transport).verifiedDescriptor(fixtureEntry())
                XCTFail("Unverified or ambiguous asset was accepted")
            } catch { XCTAssertEqual(error as? MangaExtensionError, .checksumUnavailable) }
            let requests = await transport.requests
            XCTAssertEqual(requests.count, 1, "No APK should be downloaded after verification fails")
        }
    }

    func testBatchReusesReleaseMetadataButExplicitRetryRefreshesIt() async throws {
        let replacement = try fixtureRelease(digest: "sha256:" + String(repeating: "c", count: 64))
        let transport = MangaFixtureTransport(index: fixtureIndex(), replacement: replacement)
        let client = MangaRepositoryClient(transport: transport), entry = try fixtureEntry()
        let first = try await client.verifiedDescriptor(entry)
        let second = try await client.verifiedDescriptor(entry)
        XCTAssertEqual(first.sha256, second.sha256)
        var requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
        let refreshed = try await client.verifiedDescriptor(entry, refresh: true)
        XCTAssertEqual(refreshed.sha256, String(repeating: "c", count: 64))
        requests = await transport.requests
        XCTAssertEqual(requests.count, 2)
    }

    func testUntrustedReleaseURLIsRejectedBeforeAnyNetworkRequest() async throws {
        let transport = MangaFixtureTransport(index: fixtureIndex())
        let client = MangaRepositoryClient(transport: transport)
        let entry = try fixtureEntry()
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(entry)) as? [String: Any])
        for url in [
            "https://github.com/other/extensions/releases/download/fixture/fixture-v1.6.1.apk",
            "https://github.com.evil.test/keiyoushi/extensions/releases/download/fixture/fixture-v1.6.1.apk",
            "https://github.com/keiyoushi/extensions/releases/download/fixture/fixture-v1.6.1.apk?token=anything"
        ] {
            object["apkURL"] = url
            let untrusted = try JSONDecoder().decode(MangaExtensionDescriptor.self, from: JSONSerialization.data(withJSONObject: object))
            do { _ = try await client.verifiedDescriptor(untrusted); XCTFail("Untrusted release requested") }
            catch { XCTAssertEqual(error as? MangaExtensionError, .invalidRepository) }
        }
        let requests = await transport.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func testUpdatePlanIncludesDisabledInstallationsAndFiltersMatureCollections() throws {
        let old = try installation(digest: "a", enabled: false)
        let same = try MangaExtensionCatalog.decode(fixtureIndex())
        XCTAssertTrue(same.updates(for: [old]).isEmpty)
        let updated = try MangaExtensionCatalog.decode(fixtureIndex(code: 106002))
        XCTAssertEqual(updated.updates(for: [old]).map(\.id), [old.id])
        XCTAssertEqual(updated.update(for: old)?.versionCode, 106002)
        let mature = try MangaExtensionCatalog.decode(fixtureIndex(warning: 3, code: 106002))
        XCTAssertTrue(mature.updates(for: [old], includeAdult: false).isEmpty)
        XCTAssertEqual(mature.updates(for: [old], includeAdult: true).count, 1)
    }

    func testInspectionMustMatchPackageAndVersionBeforeInstallation() throws {
        let entry = try fixtureEntry()
        let inspection = try fixtureInspection(package: "eu.kanade.tachiyomi.extension.en.other")
        XCTAssertThrowsError(try InstalledMangaExtension(descriptor: entry, inspection: inspection))
    }

    func testInstallUpdateDisableRestartAndRemovePersistCorrectly() async throws {
        let directory = temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let storage = MangaExtensionStorage(directory: directory)
        let initial = try installation(digest: "a")
        _ = try await storage.commit(initial, apk: Data([1, 2, 3]))
        _ = try await storage.setEnabled(initial.id, enabled: false)
        let restarted = MangaExtensionStorage(directory: directory)
        let restored = try await restarted.load()
        XCTAssertFalse(try XCTUnwrap(restored.installations.first).enabled)
        do { _ = try await restarted.package(initial.id); XCTFail("Disabled source was executable") } catch {}
        let update = try installation(digest: "b", enabled: false)
        _ = try await restarted.commit(update, apk: Data([4, 5]))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent(initial.filename).path))
        _ = try await restarted.setEnabled(initial.id, enabled: true)
        let (_, data) = try await restarted.package(initial.id)
        XCTAssertEqual(data, Data([4, 5]))
        let removed = try await restarted.remove(initial.id)
        XCTAssertTrue(removed.installations.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent(update.filename).path))
    }

    func testFailedStateWriteRollsBackTheNewPackage() async throws {
        let directory = temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let storage = MangaExtensionStorage(directory: directory)
        let previous = try installation(digest: "a")
        _ = try await storage.commit(previous, apk: Data([1]))
        let statePath = directory.appendingPathComponent("state.json")
        try FileManager.default.removeItem(at: statePath)
        try FileManager.default.createDirectory(at: statePath, withIntermediateDirectories: false)
        let update = try installation(digest: "b")
        do { _ = try await storage.commit(update, apk: Data([2])); XCTFail("State write should have failed") } catch {}
        let restored = try await storage.load()
        XCTAssertEqual(restored.installations[0].filename, previous.filename)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent(previous.filename).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent(update.filename).path))
    }

    func testUnreadableStateCannotBeSilentlyReplaced() async throws {
        let directory = temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent("state.json"), bad = Data("corrupt saved state".utf8)
        try bad.write(to: path)
        let storage = MangaExtensionStorage(directory: directory)
        do { _ = try await storage.commit(installation(digest: "a"), apk: Data([1])); XCTFail("Unreadable state was overwritten") } catch {}
        XCTAssertEqual(try Data(contentsOf: path), bad)
    }

    func testLiveKeiyoushiCatalogWhenExplicitlyEnabled() async throws {
        guard ProcessInfo.processInfo.environment["ANIMECOMPANION_LIVE_MANGA"] == "1" else { throw XCTSkip("Opt-in network check") }
        let client = MangaRepositoryClient()
        let catalog = try await client.catalog()
        XCTAssertGreaterThan(catalog.extensions.count, 500)
        let mangaPlus = try XCTUnwrap(catalog.extensions.first { $0.packageName == "eu.kanade.tachiyomi.extension.all.mangaplus" })
        XCTAssertEqual(mangaPlus.apiVersion, "1.6")
        XCTAssertNil(mangaPlus.sha256, "APK digests are resolved only when an extension is installed")
        XCTAssertFalse(mangaPlus.adult)
        for source in ["hiperdex", "toonily", "weebcentral"] {
            let entry = try XCTUnwrap(catalog.extensions.first { $0.packageName == "eu.kanade.tachiyomi.extension.en.\(source)" })
            let verified = try await client.verifiedDescriptor(entry)
            let apk = try await client.package(verified)
            XCTAssertEqual(try packageSHA256(apk), verified.sha256, "\(source) must match the actual APK bytes, not a build content hash")
            print("Verified live Keiyoushi APK: \(source) \(verified.versionName) (\(apk.count) bytes)")
        }
    }
}

private func temporaryDirectory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
private func fixtureEntry(digest: String = "a") throws -> MangaExtensionDescriptor {
    var entry = try XCTUnwrap(MangaExtensionCatalog.decode(fixtureIndex()).extensions.first)
    entry.sha256 = String(repeating: digest, count: 64); return entry
}
private func fixtureInspection(package: String = "eu.kanade.tachiyomi.extension.en.fixture") throws -> MangaExtensionInspection {
    let data = try JSONSerialization.data(withJSONObject: ["packageName": package, "versionName": "1.6.1", "sources": [
        ["index": 0, "id": "918273645546372819", "name": "Fixture", "language": "en", "homeURL": "https://example.com", "supportsLatest": true]
    ]])
    return try JSONDecoder().decode(MangaExtensionInspection.self, from: data)
}
private func installation(digest: String, enabled: Bool = true) throws -> InstalledMangaExtension {
    try InstalledMangaExtension(descriptor: fixtureEntry(digest: digest), inspection: fixtureInspection(), enabled: enabled)
}
private func fixtureReleaseAsset(digest: String = "sha256:" + String(repeating: "A", count: 64)) -> [String: Any] {
    ["name": "fixture-v1.6.1.apk",
     "browser_download_url": "https://github.com/keiyoushi/extensions/releases/download/fixture/fixture-v1.6.1.apk",
     "digest": digest, "state": "uploaded"]
}
private func fixtureRelease(digest: String = "sha256:" + String(repeating: "A", count: 64)) throws -> Data {
    try JSONSerialization.data(withJSONObject: ["tag_name": "fixture", "draft": false, "assets": [fixtureReleaseAsset(digest: digest)]])
}
private actor MangaFixtureTransport: HTTPTransport {
    let index: Data
    let release: Data?
    let replacement: Data?
    private(set) var requests: [URLRequest] = []
    private var releaseRequests = 0
    init(index: Data, release: Data? = nil, replacement: Data? = nil) {
        self.index = index; self.release = release; self.replacement = replacement
    }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let url = try XCTUnwrap(request.url)
        let data: Data
        if url.path.hasSuffix("index.pb") { data = index }
        else if url.host == "api.github.com" {
            releaseRequests += 1
            data = try (releaseRequests > 1 ? replacement ?? release : release) ?? fixtureRelease()
        } else if url.path.hasSuffix(".apk") { data = Data("fixture-apk".utf8) }
        else { throw ServiceError.invalidResponse }
        return (data, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

private func packageSHA256(_ data: Data) throws -> String {
    #if canImport(CryptoKit)
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    #elseif os(Linux)
    // Cross-check the app client's downloaded bytes on the Linux CI runner too.
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    try data.write(to: file)
    let task = Process(), output = Pipe()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/sha256sum"); task.arguments = [file.path]
    task.standardOutput = output
    try task.run()
    let result = output.fileHandleForReading.readDataToEndOfFile()
    task.waitUntilExit()
    guard task.terminationStatus == 0, let digest = String(data: result, encoding: .utf8)?.split(separator: " ").first else { throw ServiceError.invalidResponse }
    return String(digest)
    #else
    throw XCTSkip("No SHA-256 implementation on this test host")
    #endif
}

// Independently encoded upstream index schema; no downloaded catalogs or APKs
// are needed for these repository and transaction regression tests.
private func varint(_ value: UInt64) -> Data {
    var number = value, result = Data()
    repeat { let byte = UInt8(number & 0x7f); number >>= 7; result.append(byte | (number > 0 ? 0x80 : 0)) } while number > 0
    return result
}
private func bytesField(_ number: UInt64, _ data: Data) -> Data { varint(number << 3 | 2) + varint(UInt64(data.count)) + data }
private func stringField(_ number: UInt64, _ text: String) -> Data { bytesField(number, Data(text.utf8)) }
private func integerField(_ number: UInt64, _ value: UInt64) -> Data { varint(number << 3) + varint(value) }
private func fixtureIndex(signingKey: String = MangaRepository.fingerprint, duplicate: Bool = false, api: String = "1.6", warning: UInt64 = 1, code: UInt64 = 106001, extra: Data = Data()) -> Data {
    let source = integerField(1, 918273645546372819) + stringField(2, "Fixture") + stringField(3, "en") + stringField(4, "https://example.com")
    let resources = stringField(1, "https://github.com/keiyoushi/extensions/releases/download/fixture/fixture-v1.6.1.apk")
        + stringField(2, "https://cdn.jsdelivr.net/gh/keiyoushi/extensions-source@main/src/en/fixture/res/mipmap-xhdpi/ic_launcher.png")
    var entry = stringField(1, "Fixture") + stringField(2, "eu.kanade.tachiyomi.extension.en.fixture") + bytesField(3, resources)
    entry += stringField(4, api) + integerField(5, code) + stringField(6, "1.6.1") + integerField(7, warning) + bytesField(8, source)
    var list = bytesField(1, entry); if duplicate { list += bytesField(1, entry) }
    return stringField(1, "Keiyoushi") + stringField(3, signingKey) + bytesField(101, list) + extra
}
private func gzip(_ input: Data) throws -> Data {
    var stream = z_stream()
    guard deflateInit2_(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, MAX_WBITS + 16, 8, Z_DEFAULT_STRATEGY,
                        ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { throw ServiceError.invalidResponse }
    defer { deflateEnd(&stream) }
    return try input.withUnsafeBytes { raw in
        stream.next_in = UnsafeMutablePointer(mutating: raw.bindMemory(to: Bytef.self).baseAddress); stream.avail_in = uInt(input.count)
        var result = Data(), buffer = [UInt8](repeating: 0, count: 16384)
        while true {
            let (code, count) = buffer.withUnsafeMutableBytes { output -> (Int32, Int) in
                stream.next_out = output.bindMemory(to: Bytef.self).baseAddress; stream.avail_out = uInt(output.count)
                let code = deflate(&stream, Z_FINISH); return (code, output.count - Int(stream.avail_out))
            }
            result.append(contentsOf: buffer.prefix(count))
            if code == Z_STREAM_END { return result }
            guard code == Z_OK else { throw ServiceError.invalidResponse }
        }
    }
}
