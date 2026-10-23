import SwiftUI

/// A section enters once, not every time its artwork finishes or a refresh updates it.
struct CatalogEntrance: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var delay = 0.0
    @State private var revealed = false

    func body(content: Content) -> some View {
        content.opacity(revealed ? 1 : 0)
            .offset(y: revealed || reduceMotion ? 0 : 14)
            .task {
                guard !revealed else { return }
                await Task.yield()
                guard !Task.isCancelled else { return }
                withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .easeOut(duration: 0.45).delay(delay)) {
                    revealed = true
                }
            }
    }
}

struct ExploreLoadingSkeleton: View {
    let featuredHeight: CGFloat
    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(colors: [Theme.surface, Theme.background], startPoint: .topLeading, endPoint: .bottomTrailing)
                VStack(alignment: .leading, spacing: 14) {
                    RoundedRectangle(cornerRadius: 8).frame(width: 220, height: 30)
                    RoundedRectangle(cornerRadius: 6).frame(width: 150, height: 16)
                    RoundedRectangle(cornerRadius: 24).frame(width: 120, height: 48)
                }.foregroundStyle(.white.opacity(0.06)).padding(24).padding(.bottom, 40)
            }.frame(height: featuredHeight + 40)
            ForEach(0..<3) { _ in
                VStack(alignment: .leading, spacing: 14) {
                    RoundedRectangle(cornerRadius: 6).frame(width: 140, height: 22)
                    HStack(spacing: 14) {
                        ForEach(0..<6) { _ in RoundedRectangle(cornerRadius: 14).frame(width: 150, height: 218) }
                    }
                }.foregroundStyle(.white.opacity(0.06)).padding(.horizontal)
            }
        }.clipped().accessibilityElement(children: .ignore)
            .accessibilityLabel("Loading anime catalogs")
            .accessibilityIdentifier("explore-loading")
    }
}
