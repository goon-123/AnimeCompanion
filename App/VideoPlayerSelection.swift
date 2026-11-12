import SwiftUI
import AnimeCore

/// Shared by Settings and first-launch preferences, backed by the same saved choice.
struct VideoPlayerSelection: View {
    @EnvironmentObject private var playback: PlaybackStore
    var body: some View {
        Picker("Video player", selection: $playback.player) {
            ForEach(ExternalVideoPlayer.allCases) { player in Text(player.label).tag(player) }
        }.pickerStyle(.menu).accessibilityIdentifier("video-player-picker")
        Text(playback.player.resumeDescription).font(.subheadline).foregroundStyle(.secondary)
    }
}
