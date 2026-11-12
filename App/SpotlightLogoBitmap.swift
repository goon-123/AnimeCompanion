import CoreGraphics

/// Crop only transparent canvas, never painted logo pixels. This worker runs
/// off the main actor, once when a Spotlight asset snapshot is prepared.
actor SpotlightLogoBitmap {
    static let shared = SpotlightLogoBitmap()
    func trim(_ bitmap: ArtworkBitmap) -> ArtworkBitmap {
        let image = bitmap.image, width = image.width, height = image.height
        guard width > 0, height > 0, width <= 3200, height <= 3200 else { return bitmap }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let result: CGImage? = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
                let data = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return nil }
            context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
            var left = width, right = -1, top = height, bottom = -1
            for y in 0..<height {
                for x in 0..<width where data[(y * width + x) * 4 + 3] > 4 {
                    left = min(left, x); right = max(right, x)
                    top = min(top, y); bottom = max(bottom, y)
                }
            }
            guard right >= left, bottom >= top else { return nil }
            left = max(0, left - 3); top = max(0, top - 3)
            right = min(width - 1, right + 3); bottom = min(height - 1, bottom + 3)
            // The normalized image uses the exact same row order as the buffer.
            return context.makeImage()?.cropping(to: CGRect(x: CGFloat(left), y: CGFloat(top), width: CGFloat(right - left + 1), height: CGFloat(bottom - top + 1)))
        }
        return result.map { ArtworkBitmap(image: $0, expiresAt: bitmap.expiresAt) } ?? bitmap
    }
}
