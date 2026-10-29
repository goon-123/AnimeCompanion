import SwiftUI
import AnimeCore

/// Keeps the poster/list tap unchanged while exposing a specific episode action to touch and VoiceOver.
private struct EpisodeDiscussionActions: ViewModifier {
    let anime: Anime
    let episode: Int
    @State private var showing = false
    func body(content: Content) -> some View {
        content.contextMenu {
            Button("Discuss Episode \(episode)", systemImage: "text.bubble") { showing = true }
        }.accessibilityAction(named: "Discuss Episode \(episode)") { showing = true }
            .sheet(isPresented: $showing) {
                AppNavigationStack {
                    SeriesDiscussionsView(anime: anime, requestedEpisode: episode)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showing = false } } }
                }
            }
    }
}
extension View {
    func episodeDiscussionActions(anime: Anime, episode: Int) -> some View {
        modifier(EpisodeDiscussionActions(anime: anime, episode: episode))
    }
}
