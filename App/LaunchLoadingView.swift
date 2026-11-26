import SwiftUI

/// Match the system launch screen, then let the session's existing two-second
/// launch budget and reduce-motion-aware content reveal own the transition.
struct LaunchLoadingView: View {
    var body: some View {
        ZStack {
            AniNextBrand.background
            VStack(spacing: 4) {
                Image("CinematicLaunch").resizable().scaledToFit().frame(width: 232, height: 232)
                    .accessibilityHidden(true)
                AniNextWordmark()
            }
        }.ignoresSafeArea()
            .accessibilityElement(children: .ignore).accessibilityLabel("Loading AniNext")
            .accessibilityIdentifier("app-startup-logo")
    }
}
