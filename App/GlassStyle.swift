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

/// A single native glass surface for floating header controls outside a toolbar.
/// Toolbar items retain the system's own glass instead of stacking two effects.
struct FloatingHeaderGlass<S: Shape>: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let shape: S
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26.0, *), !reduceTransparency {
            content.glassEffect(.regular.interactive(), in: shape)
        } else { content.silverGlass(in: shape) }
    }
}
extension View {
    func floatingHeaderGlass<S: Shape>(in shape: S) -> some View { modifier(FloatingHeaderGlass(shape: shape)) }
}
