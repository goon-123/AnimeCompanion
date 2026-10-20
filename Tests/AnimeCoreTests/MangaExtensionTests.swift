import XCTest
import CZlib
@testable import AnimeCore
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

    func testRepositoryJoinsChecksumsByPackageAndExactFilename() async throws {
        let transport = MangaFixtureTransport(index: try gzip(fixtureIndex()), filename: "fixture-v1.6.1.apk")
        let catalog = try await MangaRepositoryClient(transport: transport).catalog()
        XCTAssertEqual(catalog.extensions[0].sha256, String(repeating: "a", count: 64))
        let wrong = MangaFixtureTransport(index: fixtureIndex(), filename: "old-version.apk")
        let stale = try await MangaRepositoryClient(transport: wrong).catalog()
        XCTAssertNil(stale.extensions[0].sha256)
        do { _ = try await MangaRepositoryClient(transport: wrong).package(stale.extensions[0]); XCTFail("Unverified APK was requested") }
        catch { XCTAssertEqual(error as? MangaExtensionError, .checksumUnavailable) }
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
        let catalog = try await MangaRepositoryClient().catalog()
        XCTAssertGreaterThan(catalog.extensions.count, 500)
        let mangaPlus = try XCTUnwrap(catalog.extensions.first { $0.packageName == "eu.kanade.tachiyomi.extension.all.mangaplus" })
        XCTAssertEqual(mangaPlus.apiVersion, "1.6")
        XCTAssertNotNil(mangaPlus.sha256)
        XCTAssertFalse(mangaPlus.adult)
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
private struct MangaFixtureTransport: HTTPTransport {
    let index: Data
    let filename: String
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let url = try XCTUnwrap(request.url)
        let data: Data
        if url.path.hasSuffix("index.pb") { data = index }
        else if url.path.hasSuffix("release-assets.json") {
            data = try JSONSerialization.data(withJSONObject: ["eu.kanade.tachiyomi.extension.en.fixture": ["apk": ["name": filename, "sha256": String(repeating: "a", count: 64)]]])
        } else { throw ServiceError.invalidResponse }
        return (data, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
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
private func fixtureIndex(signingKey: String = MangaRepository.fingerprint, duplicate: Bool = false, api: String = "1.6", warning: UInt64 = 1, extra: Data = Data()) -> Data {
    let source = integerField(1, 918273645546372819) + stringField(2, "Fixture") + stringField(3, "en") + stringField(4, "https://example.com")
    let resources = stringField(1, "https://github.com/keiyoushi/extensions/releases/download/fixture/fixture-v1.6.1.apk")
        + stringField(2, "https://cdn.jsdelivr.net/gh/keiyoushi/extensions-source@main/src/en/fixture/res/mipmap-xhdpi/ic_launcher.png")
    var entry = stringField(1, "Fixture") + stringField(2, "eu.kanade.tachiyomi.extension.en.fixture") + bytesField(3, resources)
    entry += stringField(4, api) + integerField(5, 106001) + stringField(6, "1.6.1") + integerField(7, warning) + bytesField(8, source)
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
