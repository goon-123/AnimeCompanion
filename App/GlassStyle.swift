import SwiftUI

/// Retained API, now an opaque surface without blur or glass compositing.
struct SilverGlass<S: Shape>: ViewModifier {
    let shape: S
    func body(content: Content) -> some View {
        content.foregroundStyle(.primary).background(Theme.surface, in: shape)
            .overlay { shape.stroke(Theme.border, lineWidth: 1).allowsHitTesting(false) }
    }
}
extension View {
    func silverGlass<S: Shape>(in shape: S) -> some View { modifier(SilverGlass(shape: shape)) }
}
