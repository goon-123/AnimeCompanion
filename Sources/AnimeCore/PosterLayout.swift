import Foundation

/// Fit the saved density to the actual window, without overwriting the user's choice.
public enum PosterLayout {
    public static func featuredHeight(preferred: Double, viewportHeight: Double, fillScreen: Bool) -> Double {
        let viewport = viewportHeight.isFinite ? max(320, viewportHeight) : 800
        let saved = preferred.isFinite ? min(1100, max(400, preferred)) : 680
        return fillScreen ? min(1100, max(400, viewport * 0.88)) : saved
    }
    public static func columns(requested: Int, availableWidth: Double, minimumWidth: Double = 80, spacing: Double = 12) -> Int {
        let preferred = min(8, max(1, requested))
        guard availableWidth.isFinite, availableWidth > 0 else { return 1 }
        let gap = spacing.isFinite ? max(0, spacing) : 12
        let minimum = minimumWidth.isFinite ? max(1, minimumWidth) : 80
        let fitting = min(8, max(1, Int(min(8, floor((availableWidth + gap) / (minimum + gap))))))
        return min(preferred, fitting)
    }

    public static func listWidth(preferred: Double, availableWidth: Double) -> Double {
        let width = availableWidth.isFinite ? max(0, availableWidth) : 320
        let saved = preferred.isFinite ? min(240, max(60, preferred)) : 100
        return min(saved, max(40, width * 0.38))
    }
}
