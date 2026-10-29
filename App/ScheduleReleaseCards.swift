import SwiftUI
import AnimeCore

/// The poster owns a fixed width; long titles wrap in the remaining space.
/// Every day and the single-day list use exactly this row, without fit-driven
/// switches that moved the time rail above some posters but beside others.
struct ScheduleReleaseRow: View {
    let event: ReleaseEvent
    let now: Date
    var isToday = false
    @Environment(\.dynamicTypeSize) private var textSize

    var body: some View {
        AnimeLink(id: event.anime.id) {
            HStack(alignment: .top, spacing: 12) {
                if !textSize.isAccessibilitySize {
                    AnimeCover(anime: event.anime, width: 48, cornerRadius: 8, badgeStyle: .none)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(event.anime.displayTitle).font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 6) { episodeAndKind; releaseTime }
                        VStack(alignment: .leading, spacing: 4) { episodeAndKind; releaseTime }
                    }.font(.caption).foregroundStyle(.secondary)
                    Text(ScheduleCountdown.label(for: event, at: now))
                        .font(.caption2.weight(.medium)).foregroundStyle(timingColor)
                    ScheduleReleaseNotice(event: event)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(isToday ? Theme.accent.opacity(0.10) : Theme.surface, in: RoundedRectangle(cornerRadius: 16))
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityValue(isToday ? "Today" : "")
            .accessibilityIdentifier("release-entry-\(event.anime.id)-\(event.kind.rawValue)-\(event.episode)")
    }
    private var episodeAndKind: some View {
        HStack(spacing: 6) {
            Text("Episode \(event.episode)")
            Text(event.kind.rawValue.uppercased()).fontWeight(.semibold)
                .foregroundStyle(event.kind == .dub ? Color.mint : Theme.accent)
        }.fixedSize(horizontal: true, vertical: true)
    }
    private var releaseTime: some View {
        Group {
            if let date = event.date { Text(date, format: .dateTime.hour().minute()).monospacedDigit() }
            else { Text("Time TBA") }
        }.fixedSize(horizontal: true, vertical: true)
    }
    private var timingColor: Color {
        if event.certainty == .delayed || event.certainty == .unverified { return Theme.highlight }
        return (event.date ?? .distantPast) > now ? Theme.accent : .secondary
    }
}

struct ScheduleReleaseGridCard: View {
    let event: ReleaseEvent
    let now: Date
    var body: some View {
        AnimeLink(id: event.anime.id) {
            VStack(alignment: .leading, spacing: 6) {
                AnimePoster(anime: event.anime, cornerRadius: 11, badgeStyle: .none)
                    .aspectRatio(1 / 1.45, contentMode: .fit)
                    .overlay(alignment: .bottomLeading) {
                        Text(ScheduleCountdown.label(for: event, at: now, compact: true))
                            .font(.caption2.weight(.semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 4)
                            .background(Color.black.opacity(0.78), in: Capsule())
                            .padding(5)
                    }
                Text(event.anime.displayTitle).font(.caption.weight(.semibold))
                    .lineLimit(3, reservesSpace: true).foregroundStyle(.primary)
                if let date = event.date {
                    Text(date, format: .dateTime.hour().minute()).font(.caption.weight(.medium)).foregroundStyle(Theme.accent)
                }
                Text("Ep \(event.episode) · \(event.kind.rawValue.uppercased())").font(.caption2).foregroundStyle(.secondary)
                ScheduleReleaseNotice(event: event)
            }.frame(maxWidth: .infinity, alignment: .topLeading).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("release-grid-\(event.id)")
    }
}

private struct ScheduleReleaseNotice: View {
    let event: ReleaseEvent
    var body: some View {
        Group {
            if event.certainty == .unverified { Text("Estimated date").foregroundStyle(Theme.highlight) }
            if event.certainty == .delayed { Text(event.note ?? "Delayed · date unconfirmed").foregroundStyle(Theme.highlight) }
            else if event.date == nil { Text(event.note ?? "Date not confirmed").foregroundStyle(.secondary) }
        }.font(.caption2).fixedSize(horizontal: false, vertical: true)
    }
}

struct ScheduleRowInsets: ViewModifier {
    func body(content: Content) -> some View {
        content.listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            .listRowSeparator(.hidden)
    }
}
