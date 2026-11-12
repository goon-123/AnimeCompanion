import XCTest
import CoreGraphics
import CoreFoundation
@testable import AnimeCompanion

final class SpotlightLogoBitmapTests: XCTestCase {
    func testTransparentPaddingIsRemovedWithoutLosingOffCenterPaintedPixels() async throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 800, height: 310, bitsPerComponent: 8,
            bytesPerRow: 3200, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
        context.setShouldAntialias(false); context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 120, y: 40, width: 200, height: 80))
        let bitmap = ArtworkBitmap(image: try XCTUnwrap(context.makeImage()), expiresAt: .distantFuture)
        let trimmed = await SpotlightLogoBitmap.shared.trim(bitmap)
        XCTAssertEqual(trimmed.image.width, 206); XCTAssertEqual(trimmed.image.height, 86)
        let normalized = try XCTUnwrap(CGContext(data: nil, width: trimmed.image.width, height: trimmed.image.height,
            bitsPerComponent: 8, bytesPerRow: trimmed.image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
        normalized.interpolationQuality = .none
        normalized.draw(trimmed.image, in: CGRect(x: 0, y: 0, width: CGFloat(trimmed.image.width), height: CGFloat(trimmed.image.height)))
        let data = try XCTUnwrap(normalized.makeImage()?.dataProvider?.data)
        let bytes = try XCTUnwrap(CFDataGetBytePtr(data))
        var painted = 0
        for y in 0..<trimmed.image.height {
            for x in 0..<trimmed.image.width where bytes[y * trimmed.image.width * 4 + x * 4 + 3] > 4 { painted += 1 }
        }
        XCTAssertEqual(painted, 16000, "All painted pixels must survive, including asymmetric padding")
        XCTAssertEqual(trimmed.expiresAt, bitmap.expiresAt)
    }
    func testEmptyTransparentImageKeepsItsOriginalBitmap() async throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 100, height: 40, bitsPerComponent: 8,
            bytesPerRow: 400, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let bitmap = ArtworkBitmap(image: try XCTUnwrap(context.makeImage()), expiresAt: .distantFuture)
        let trimmed = await SpotlightLogoBitmap.shared.trim(bitmap)
        XCTAssertTrue(trimmed.image === bitmap.image)
    }
}
