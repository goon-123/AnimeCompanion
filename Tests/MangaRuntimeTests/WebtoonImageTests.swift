import XCTest
import UIKit
import AnimeCore
@testable import AnimeCompanion

final class WebtoonImageTests: XCTestCase {
    @MainActor
    func testRepositoryPNGIconDecodesAndReusesThePublicImageCache() async throws {
        let pipeline = MangaReaderPreview.iconPipeline
        let url = try XCTUnwrap(MangaReaderPreview.descriptor.iconURL)
        let first = try await pipeline.image(at: url, pixels: 128)
        let second = try await pipeline.image(at: url, pixels: 128)
        XCTAssertEqual(first.image.width, 96)
        XCTAssertEqual(first.image.height, 96)
        XCTAssertTrue(first.image === second.image)
    }
    @MainActor
    func testLongStripKeepsItsAspectRatioWithinDecodedMemoryBudget() async throws {
        let data = drawing(width: 1000, height: 12000)
        let key = MangaImageKey(source: "owned", version: "one", page: SourceMangaImage(index: 0, imageURL: "https://example.invalid/strip"))
        let bitmap = try await MangaImagePipeline().image(key: key, width: 1600) { data }
        XCTAssertEqual(bitmap.ratio, 12, accuracy: 0.03)
        XCTAssertLessThanOrEqual(bitmap.image.width * bitmap.image.height, 8_100_000)
        XCTAssertGreaterThan(bitmap.image.width, 750, "A long strip should not become a cover-sized thumbnail")
    }
    @MainActor
    func testHTMLIsRejectedAndExplicitRetryCanLoadTheCorrectImage() async throws {
        let pipeline = MangaImagePipeline()
        let key = MangaImageKey(source: "owned", version: "one", page: SourceMangaImage(index: 0, imageURL: "https://example.invalid/page"))
        do {
            _ = try await pipeline.image(key: key, width: 400) { Data("<html>not an image</html>".utf8) }
            XCTFail("HTML accepted as a chapter page")
        } catch {}
        let data = drawing(width: 400, height: 800)
        let bitmap = try await pipeline.image(key: key, width: 400, refresh: true) { data }
        XCTAssertEqual(bitmap.ratio, 2, accuracy: 0.01)
    }
    @MainActor
    func testDifferentSourcesDoNotReuseTheSameURLBitmap() async throws {
        let pipeline = MangaImagePipeline(), page = SourceMangaImage(index: 0, imageURL: "https://example.invalid/shared")
        let a = drawing(width: 100, height: 100), b = drawing(width: 100, height: 200)
        let one = try await pipeline.image(key: MangaImageKey(source: "one", version: "one", page: page), width: 400) { a }
        let two = try await pipeline.image(key: MangaImageKey(source: "two", version: "one", page: page), width: 400) { b }
        XCTAssertEqual(one.ratio, 1); XCTAssertEqual(two.ratio, 2)
    }
    @MainActor private func drawing(width: Int, height: Int) -> Data {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: CGFloat(width), height: CGFloat(height)), format: format).pngData { context in
            UIColor.darkGray.setFill(); context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
            UIColor.cyan.setFill(); context.fill(CGRect(x: 20, y: 20, width: CGFloat(width - 40), height: 60))
        }
    }
}
