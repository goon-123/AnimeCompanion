import Foundation

public enum AppAccent: String, CaseIterable, Identifiable, Codable, Sendable {
    case violet, ocean, rose, emerald, amber, monochrome
    public var id: String { rawValue }
    public var label: String { rawValue.capitalized }
    public func hex(dark: Bool) -> String {
        switch self {
        case .violet: return dark ? "C2B3FF" : "5C45D4"
        case .ocean: return dark ? "7ACBFF" : "0066AE"
        case .rose: return dark ? "FFA2C5" : "B52260"
        case .emerald: return dark ? "71DFB3" : "007C55"
        case .amber: return dark ? "FFD17A" : "8E5700"
        case .monochrome: return dark ? "EEEEF4" : "303038"
        }
    }
}

public enum AppCanvas: String, CaseIterable, Identifiable, Codable, Sendable {
    case classic, slate, midnight, warm, forest
    public var id: String { rawValue }
    public var label: String { rawValue.capitalized }
    public func background(dark: Bool) -> String {
        switch self {
        case .classic: return dark ? "000000" : "F5F5FA"
        case .slate: return dark ? "15191F" : "EFF3F8"
        case .midnight: return dark ? "080F21" : "EEF1FC"
        case .warm: return dark ? "201813" : "FAF3E8"
        case .forest: return dark ? "0E1B16" : "EFF6F0"
        }
    }
    public func surface(dark: Bool) -> String {
        switch self {
        case .classic: return dark ? "17171F" : "FFFFFF"
        case .slate: return dark ? "242B34" : "FFFFFF"
        case .midnight: return dark ? "15213C" : "FFFFFF"
        case .warm: return dark ? "30251E" : "FFFCF7"
        case .forest: return dark ? "1D3027" : "FCFFFC"
        }
    }
}

public struct ThemeRGB: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public init?(hex: String) {
        let clean = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        guard clean.count == 6, clean.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains($0) }),
              let value = UInt32(clean, radix: 16) else { return nil }
        red = Double((value >> 16) & 255) / 255
        green = Double((value >> 8) & 255) / 255
        blue = Double(value & 255) / 255
    }
    private init(red: Double, green: Double, blue: Double) { self.red = red; self.green = green; self.blue = blue }
    public var hex: String { String(format: "%02X%02X%02X", Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded())) }
    private var luminance: Double {
        func linear(_ value: Double) -> Double { value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }
    public func contrast(with other: Self) -> Double { (max(luminance, other.luminance) + 0.05) / (min(luminance, other.luminance) + 0.05) }
    /// Custom accents remain legible as small labels on both app surfaces.
    public func legible(on backgrounds: [Self], dark: Bool) -> Self {
        for step in 0...100 {
            let amount = Double(step) / 100, target = dark ? 1.0 : 0.0
            let color = Self(red: red + (target - red) * amount, green: green + (target - green) * amount, blue: blue + (target - blue) * amount)
            if backgrounds.allSatisfy({ color.contrast(with: $0) >= 4.5 }) { return color }
        }
        return Self(red: dark ? 1 : 0, green: dark ? 1 : 0, blue: dark ? 1 : 0)
    }
}

public struct AppThemePreferences: Codable, Equatable, Sendable {
    public static let storageKey = "appearance.theme.v1"
    public var accent: AppAccent = .violet
    public var canvas: AppCanvas = .classic
    public var customAccent: String? = nil
    public init() {}
    public init(saved: String?) {
        guard let data = saved?.data(using: .utf8), let decoded = try? JSONDecoder().decode(Self.self, from: data) else { self.init(); return }
        self = decoded
        customAccent = decoded.customAccent.flatMap { ThemeRGB(hex: $0)?.hex }
    }
    public var saved: String {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        return String(data: try! encoder.encode(self), encoding: .utf8)!
    }
    public func accentColor(dark: Bool) -> ThemeRGB {
        let color = ThemeRGB(hex: customAccent ?? accent.hex(dark: dark))!
        return color.legible(on: [ThemeRGB(hex: canvas.background(dark: dark))!, ThemeRGB(hex: canvas.surface(dark: dark))!], dark: dark)
    }
}
