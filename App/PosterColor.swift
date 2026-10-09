import SwiftUI
import UIKit
import AnimeCore

extension PosterAccent {
    var color: Color { Color(red: red, green: green, blue: blue) }
}

@MainActor
enum PosterColor {
    private static var cache: [URL: PosterAccent] = [:]
    static func accent(for anime: Anime) async -> PosterAccent {
        if let accent = PosterAccent(hex: anime.coverImage?.color) { return accent }
        guard let url = anime.coverURL, ["https", "http"].contains(url.scheme ?? "") else { return .fallback }
        if let cached = cache[url] { return cached }
        do {
            let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 15))
            try Task.checkCancellation()
            guard (response as? HTTPURLResponse)?.statusCode == 200, data.count < 12_000_000,
                  let image = UIImage(data: data)?.cgImage, let accent = sample(image) else { return .fallback }
            if cache.count >= 30 { cache.removeAll() }
            cache[url] = accent
            return accent
        } catch { return .fallback }
    }
    private static func sample(_ image: CGImage) -> PosterAccent? {
        let size = 24
        var bytes = [UInt8](repeating: 0, count: size * size * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: size, height: size, bitsPerComponent: 8,
                bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.interpolationQuality = .low
            context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
            return true
        }
        guard drawn else { return nil }
        var red = 0.0, green = 0.0, blue = 0.0, weight = 0.0
        for index in stride(from: 0, to: bytes.count, by: 4) where bytes[index + 3] > 200 {
            let r = Double(bytes[index]) / 255, g = Double(bytes[index + 1]) / 255, b = Double(bytes[index + 2]) / 255
            let amount = 0.3 + (max(r, g, b) - min(r, g, b)) * 2
            red += r * amount; green += g * amount; blue += b * amount; weight += amount
        }
        guard weight > 0 else { return nil }
        return PosterAccent(red: red / weight, green: green / weight, blue: blue / weight)
    }
}
