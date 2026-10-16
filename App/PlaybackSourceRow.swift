import SwiftUI
import AnimeCore

struct PlaybackAudioBadge: View {
    let audio: StreamAudioInfo
    var compact = false
    private var color: Color { audio.english ? .green : (audio.japanese ? .secondary : .orange) }
    private var title: String {
        guard compact else { return audio.label }
        if audio.english && audio.japanese { return "EN + JA" }
        if audio.english { return "EN audio" }
        if audio.japanese { return "JA audio" }
        return audio.multiAudio ? "Multi · Unconfirmed" : "Audio unlisted"
    }
    var body: some View {
        Text(title).font(compact ? .caption.weight(.semibold) : .subheadline.weight(.semibold)).foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, compact ? 4 : 6)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(audio.label)
    }
}

/// The primary row prioritizes audio; provider, quality and size stay readable without a text wall.
struct PlaybackSourceRow: View {
    let stream: StremioStream
    let index: Int
    let preferred: Bool
    let openingPlayer: Bool
    var addonName: String? = nil
    var play: () -> Void
    var information: () -> Void
    var body: some View {
        let metadata = StreamSourceMetadata(stream: stream)
        HStack(alignment: .top, spacing: 4) {
            Button(action: play) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(stream.displayName).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(2)
                    PlaybackAudioBadge(audio: metadata.audio, compact: true)
                    if !metadata.technicalSummary.isEmpty {
                        Text(metadata.technicalSummary).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    }
                    Text(stream.details).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    if let reason = stream.unavailableReason { Text(reason).font(.caption).foregroundStyle(.orange) }
                    HStack {
                        if let addonName { Text("From \(addonName)").lineLimit(1) }
                        Spacer(minLength: 8)
                        if stream.unavailableReason == nil { Label("Play", systemImage: "play.fill").foregroundStyle(.mint) }
                    }.font(.caption)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 2).contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(stream.unavailableReason != nil || openingPlayer)
                .accessibilityLabel([stream.displayName, metadata.audio.label, metadata.technicalSummary, stream.details, addonName.map { "From \($0)" }].compactMap { $0 }.joined(separator: " · "))
                .accessibilityIdentifier("playback-source-\(index)")
            Button(action: information) { Image(systemName: "info.circle").frame(width: 44, height: 44) }
                .buttonStyle(.borderless).accessibilityLabel("Source information")
                .accessibilityIdentifier("playback-source-info-\(index)")
        }
    }
}
