import SwiftUI

/// Floating controls let the actual artwork and scrolling content show through.
struct SilverGlass<S: Shape>: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let shape: S
    func body(content: Content) -> some View {
        content.foregroundStyle(.primary).background {
            if reduceTransparency { shape.fill(Theme.surface) }
            else { shape.fill(.ultraThinMaterial) }
        }.overlay { shape.stroke(.white.opacity(0.16), lineWidth: 0.75).allowsHitTesting(false) }
    }
}
extension View {
    func silverGlass<S: Shape>(in shape: S) -> some View { modifier(SilverGlass(shape: shape)) }
}
