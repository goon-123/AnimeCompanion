import SwiftUI

/// The system storyboard and this overlay use the same fixed artwork, size,
/// center and background. No live text or appearance tint changes at handoff.
struct LaunchLoadingView: View {
    var body: some View {
        ZStack {
            AniNextBrand.background
            Image("CinematicLaunch")
                .renderingMode(.original)
                .resizable().scaledToFit()
                .frame(width: 232, height: 280)
                .accessibilityHidden(true)
        }.ignoresSafeArea()
            .accessibilityElement(children: .ignore).accessibilityLabel("Loading AniNext")
            .accessibilityIdentifier("app-startup-logo")
    }
}
