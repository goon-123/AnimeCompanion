import SwiftUI

/// Short, consistent motion; native navigation and reader gestures retain ownership.
enum AppMotion {
    static func page(_ reduced: Bool) -> Animation { .easeInOut(duration: reduced ? 0.12 : 0.28) }
    static func content(_ reduced: Bool) -> Animation { .easeOut(duration: reduced ? 0.12 : 0.30) }
    static func replacement(_ reduced: Bool) -> AnyTransition {
        .opacity
    }
}

/// Stable-size placeholders and real content use the same light arrival motion.
struct ContentArrival: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var delay = 0.0
    @State private var appeared = false
    func body(content: Content) -> some View {
        content.opacity(appeared ? 1 : 0)
            .task {
                guard !appeared else { return }
                await Task.yield()
                guard !Task.isCancelled else { return }
                withAnimation(AppMotion.content(reduceMotion).delay(reduceMotion ? 0 : min(delay, 0.12))) { appeared = true }
            }
    }
}

struct HomeRowPlaceholder: View {
    var height: CGFloat = 132
    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 10).fill(Theme.border).frame(width: 78)
            VStack(alignment: .leading, spacing: 12) {
                Capsule().fill(Theme.border).frame(height: 14)
                Capsule().fill(Theme.border).frame(maxWidth: 160).frame(height: 10)
                Capsule().fill(Theme.border).frame(maxWidth: 110).frame(height: 10)
            }.padding(.trailing, 18)
        }.padding(14).frame(height: height).background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius))
            .accessibilityElement(children: .ignore).accessibilityLabel("Loading saved content")
    }
}
