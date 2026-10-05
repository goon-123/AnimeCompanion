import Foundation

/// Poster-derived RGB, independent of UIKit so color parsing and contrast stay testable.
public struct PosterAccent: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public static let fallback = Self(red: 0.12, green: 0.17, blue: 0.23)
    public init(red: Double, green: Double, blue: Double) {
        self.red = red.isFinite ? min(1, max(0, red)) : 0.12
        self.green = green.isFinite ? min(1, max(0, green)) : 0.17
        self.blue = blue.isFinite ? min(1, max(0, blue)) : 0.23
    }
    public init?(hex: String?) {
        guard var text = hex?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, text.allSatisfy({ $0.isHexDigit }), let number = UInt32(text, radix: 16) else { return nil }
        self.init(red: Double((number >> 16) & 255) / 255, green: Double((number >> 8) & 255) / 255, blue: Double(number & 255) / 255)
    }
    public var luminance: Double {
        func linear(_ value: Double) -> Double { value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4) }
        return linear(red) * 0.2126 + linear(green) * 0.7152 + linear(blue) * 0.0722
    }
    /// Preserve the actual hue while keeping white foreground text above 4.5:1 contrast.
    public var backdrop: Self {
        var result = Self(red: red * 0.70 + 0.025, green: green * 0.70 + 0.025, blue: blue * 0.70 + 0.025)
        while result.luminance > 0.16 {
            result = Self(red: result.red * 0.94, green: result.green * 0.94, blue: result.blue * 0.94)
        }
        return result
    }
}
