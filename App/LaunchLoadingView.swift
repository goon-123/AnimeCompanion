import SwiftUI

/// Matches the system launch storyboard while cached data and the first public
/// requests prepare underneath. No animated scale, motion or progress jump.
struct LaunchLoadingView: View {
    var body: some View {
        ZStack {
            Color.black
            Image("LaunchMark").resizable().scaledToFit().frame(width: 96, height: 96)
        }.ignoresSafeArea()
            .accessibilityElement(children: .ignore).accessibilityLabel("Loading Anime Companion")
            .accessibilityIdentifier("app-startup-logo")
    }
}
