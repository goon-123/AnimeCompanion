import XCTest
import AnimeCore

final class ExtensionCompatibilityRuntimeTests: XCTestCase {
    func testMangaPlusProtobufPagesAndSourceImageHeaders() throws {
        var viewer = proto(1, proto(1, proto(1, Data("https://images.example/owned-2.webp".utf8))))
        viewer += proto(1, proto(1, proto(1, Data("https://images.example/owned-1.webp".utf8))))
        viewer += proto(19, Data("owned-view-token".utf8))
        let host = try OwnedExtensionFixtureHTTP(apkName: "tachiyomi-all.mangaplus-v1.6.67.apk", responses: [
            "https://jumpg-webapi.tokyo-cdn.com/api/manga_viewer_v3": proto(1, proto(10, viewer)),
            "https://images.example/owned-2.webp": Data([0, 255, 23, 128])
        ])
        let pages: [SourceMangaImage] = try host.execute([
            "op": "pages", "chapter": ["url": "#/viewer/12345", "name": "Chapter 1"]
        ])
        XCTAssertEqual(pages.map(\.index), [0, 1])
        XCTAssertEqual(pages.map(\.imageURL), ["https://images.example/owned-2.webp", "https://images.example/owned-1.webp"])
        XCTAssertEqual(pages.map(\.url), ["owned-view-token", "owned-view-token"])
        let request = try XCTUnwrap(host.urls.first.flatMap { URLComponents(string: $0) })
        XCTAssertEqual(request.queryItems?.first { $0.name == "chapter_id" }?.value, "12345")
        let first = try XCTUnwrap(pages.first)
        let image: ImageResponse = try host.execute([
            "op": "image", "image": ["index": first.index, "url": first.url, "imageURL": first.imageURL]
        ])
        XCTAssertEqual(Data(base64Encoded: image.bodyBase64), Data([0, 255, 23, 128]))
        XCTAssertTrue(host.headersByURL[first.imageURL]?.contains { $0.count == 2 && $0[0].lowercased() == "plus-vw-token" && $0[1] == "owned-view-token" } == true)
    }

    func testTruncatedProtobufRemainsAnError() throws {
        let host = try OwnedExtensionFixtureHTTP(apkName: "tachiyomi-all.mangaplus-v1.6.67.apk", responses: [
            "https://jumpg-webapi.tokyo-cdn.com/api/manga_viewer_v3": Data([0x0a, 0x7f, 0x52])
        ])
        XCTAssertThrowsError(try host.execute([
            "op": "pages", "chapter": ["url": "#/viewer/12345", "name": "Chapter 1"]
        ]) as [SourceMangaImage])
    }

    private struct ImageResponse: Decodable { let bodyBase64: String }

    // Only owned URLs/tokens are encoded; no publisher response is captured.
    private func proto(_ field: UInt32, _ body: Data) -> Data {
        func varint(_ value: UInt32) -> Data {
            var n = value
            var result = Data()
            while n >= 128 { result.append(UInt8(truncatingIfNeeded: n) | 128); n >>= 7 }
            result.append(UInt8(n))
            return result
        }
        return varint((field << 3) | 2) + varint(UInt32(body.count)) + body
    }
}
