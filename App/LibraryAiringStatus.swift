import SwiftUI
import AnimeCore

extension AiringCatchUpState {
    var color: Color {
        switch self {
        case .caughtUp: return .green
        case .behind: return .yellow
        case .waiting, .unknown: return .secondary
        }
    }
    var symbol: String {
        switch self {
        case .caughtUp: return "checkmark.circle.fill"
        case .behind: return "clock.badge.exclamationmark"
        case .waiting: return "clock"
        case .unknown: return "questionmark.circle"
        }
    }
}

struct LibraryAiringStatus: View {
    let status: LibraryAiringProgress
    let animeID: Int
    var compact = false
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 5) {
                Image(systemName: status.state.symbol).accessibilityHidden(true)
                Text(status.label).accessibilityIdentifier("library-airing-status-\(animeID)")
            }.font(compact ? .caption2.bold() : .caption.bold()).foregroundStyle(status.state.color)
            Text("Watched Ep \(status.watched)" + (status.released.map { " · Aired Ep \($0)" } ?? ""))
                .font(compact ? .caption2 : .caption).accessibilityIdentifier("library-airing-progress-\(animeID)")
            if let released = status.released, released > 0 {
                ProgressView(value: Double(min(status.watched, released)), total: Double(released))
                    .tint(status.state.color).accessibilityLabel("\(status.watched) watched, \(released) aired")
            }
            if let next = status.nextEpisode, let date = status.nextDate {
                Text("Next \(status.source.shortLabel)\(status.estimatedDate ? " estimate" : "") · Ep \(next) · \(date.formatted(.dateTime.weekday(.abbreviated).hour().minute()))")
                    .font(.caption2).foregroundStyle(.secondary).accessibilityIdentifier("library-airing-next-\(animeID)")
                Text(date, style: .relative).font(.caption2).foregroundStyle(.secondary)
                    .accessibilityLabel("Time until next airing")
            } else {
                Text("Next \(status.source.shortLabel) time not announced").font(.caption2).foregroundStyle(.secondary)
            }
        }.fixedSize(horizontal: false, vertical: true).padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(status.state.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
    }
}
