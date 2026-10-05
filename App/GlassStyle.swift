import SwiftUI

/// Native Liquid Glass on iOS 26, with a silver material fallback on iOS 17–18.
struct SilverGlass<S: Shape>: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let shape: S
    @ViewBuilder func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Color(white: 0.23), in: shape)
                .overlay(shape.strokeBorderFallback(Color.white.opacity(0.22)))
        } else if #available(iOS 26.0, *) {
            content.glassEffect(.regular.tint(.white.opacity(0.08)).interactive(), in: shape)
        } else {
            content.background(.ultraThinMaterial, in: shape)
                .overlay(shape.fill(.white.opacity(0.07)).allowsHitTesting(false))
                .overlay(shape.strokeBorderFallback(Color.white.opacity(0.18)))
        }
    }
}
private extension Shape {
    func strokeBorderFallback(_ color: Color) -> some View { stroke(color, lineWidth: 0.75).allowsHitTesting(false) }
}
extension View {
    func silverGlass<S: Shape>(in shape: S) -> some View { modifier(SilverGlass(shape: shape)) }
}
