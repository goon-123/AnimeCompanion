import SwiftUI

/// iOS's static launch screen is black. The in-app mark fades in, and the
/// parent fades this entire overlay out when the first content is ready.
struct LaunchLoadingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.black
            Image("CinematicLaunch").resizable().scaledToFit().frame(width: 224, height: 224)
                .opacity(appeared ? 1 : 0)
        }.ignoresSafeArea()
            .onAppear {
                withAnimation(.easeInOut(duration: reduceMotion ? 0.1 : 0.24)) { appeared = true }
            }
            .accessibilityElement(children: .ignore).accessibilityLabel("Loading Anime Companion")
            .accessibilityIdentifier("app-startup-logo")
    }
}
