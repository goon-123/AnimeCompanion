import SwiftUI

/// Matches the system launch storyboard while cached data and the first public
/// requests prepare underneath. No animated scale, motion or progress jump.
struct LaunchLoadingView: View {
    var body: some View {
        ZStack {
            Color.black
            Image("CinematicLaunch").resizable().scaledToFit().frame(width: 224, height: 224)
        }.ignoresSafeArea()
            .accessibilityElement(children: .ignore).accessibilityLabel("Loading Anime Companion")
            .accessibilityIdentifier("app-startup-logo")
    }
}
