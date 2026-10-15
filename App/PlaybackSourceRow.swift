import SwiftUI
import AnimeCore

struct PlaybackAudioBadge: View {
    let audio: StreamAudioInfo
    private var color: Color { audio.english ? .green : (audio.japanese ? .secondary : .orange) }
    var body: some View {
        Label(audio.label, systemImage: audio.english ? "waveform.circle.fill" : "waveform")
            .font(.subheadline.weight(.semibold)).foregroundStyle(color)
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The primary row prioritizes audio; provider, quality and size stay readable without a text wall.
struct PlaybackSourceRow: View {
    let stream: StremioStream
    let index: Int
    let preferred: Bool
    let openingPlayer: Bool
    var play: () -> Void
    var information: () -> Void
    var body: some View {
        let metadata = StreamSourceMetadata(stream: stream)
        HStack(alignment: .top, spacing: 8) {
            Button(action: play) {
                VStack(alignment: .leading, spacing: 9) {
                    if preferred {
                        Text(metadata.audio.english ? "ENGLISH AUDIO · FIRST CHOICE" : "FIRST PLAYABLE SOURCE")
                            .font(.caption2.weight(.bold)).tracking(0.7).foregroundStyle(.secondary)
                    }
                    PlaybackAudioBadge(audio: metadata.audio)
                    Text(stream.displayName).font(.headline).foregroundStyle(.primary).lineLimit(2)
                    if !metadata.technicalSummary.isEmpty {
                        Text(metadata.technicalSummary).font(.caption.weight(.semibold)).foregroundStyle(.primary)
                    }
                    Text(stream.details).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                    if let reason = stream.unavailableReason { Text(reason).font(.caption).foregroundStyle(.orange) }
                    if preferred { Label("Play in VidHub", systemImage: "play.fill").font(.subheadline.bold()).foregroundStyle(.primary) }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8).contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(stream.unavailableReason != nil || openingPlayer)
                .accessibilityIdentifier("playback-source-\(index)")
            Button(action: information) { Image(systemName: "info.circle").frame(width: 44, height: 44) }
                .buttonStyle(.borderless).accessibilityLabel("Source information")
                .accessibilityIdentifier("playback-source-info-\(index)")
        }
    }
}
