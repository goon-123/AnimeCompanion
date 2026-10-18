import Foundation

public enum TabletLayout: String, CaseIterable, Sendable {
    case fullWidth, sideBySide
    public static let preferenceKey = "display.ipad.layout"

    public init(preference: String?) { self = preference.flatMap(Self.init(rawValue:)) ?? .fullWidth }

    /// Favor the catalog over an oversized detail pane. The native split view
    /// still adapts/collapses for compact windows without changing this choice.
    public static func browseWidth(windowWidth: Double) -> Double {
        guard windowWidth.isFinite, windowWidth > 0 else { return 560 }
        return min(820, max(480, windowWidth * 0.60))
    }
}
