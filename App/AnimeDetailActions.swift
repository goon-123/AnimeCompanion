import SwiftUI
import AnimeCore

/// A scroll-independent trailing control; no custom back gesture or navigation
/// stack changes are needed, so native interactive pop remains available.
struct AnimeDetailActions: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false
    let resumeLabel: String
    let canWatch: Bool
    let canEdit: Bool
    let edit: () -> Void
    let resume: () -> Void
    let findManga: () -> Void

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if expanded {
                Button { expanded = false } label: {
                    Color.black.opacity(0.30).contentShape(Rectangle())
                }.buttonStyle(.plain).ignoresSafeArea()
                    .accessibilityLabel("Dismiss anime actions")
                    .accessibilityIdentifier("detail-actions-dismiss")
            }
            VStack(alignment: .trailing, spacing: 12) {
                if expanded {
                    VStack(spacing: 0) {
                        action("Edit Entry", symbol: "square.and.pencil", identifier: "detail-edit-entry", enabled: canEdit, perform: edit)
                        Divider().padding(.horizontal, 14)
                        action(resumeLabel, symbol: "play.fill", identifier: "watch-in-vidhub", enabled: canWatch, perform: resume)
                        Divider().padding(.horizontal, 14)
                        action("Find Manga / Manhwa", symbol: "book.closed", identifier: "detail-find-manga", perform: findManga)
                    }.frame(maxWidth: 300)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20))
                        .overlay { RoundedRectangle(cornerRadius: 20).stroke(Theme.border, lineWidth: 1) }
                        .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
                Button { expanded.toggle() } label: {
                    Image(systemName: expanded ? "xmark" : "line.3.horizontal")
                        .font(.system(size: 21, weight: .semibold)).frame(width: 56, height: 56)
                        .foregroundStyle(Theme.background).background(Theme.accent, in: Circle())
                        .shadow(color: .black.opacity(0.25), radius: 12, y: 5)
                }.buttonStyle(.plain).accessibilityLabel("Anime actions")
                    .accessibilityValue(expanded ? "Expanded" : "Collapsed")
                    .accessibilityIdentifier("detail-actions")
            }.padding(16)
        }.animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: expanded)
            .accessibilityAction(.escape) { expanded = false }
    }
    private func action(_ title: String, symbol: String, identifier: String, enabled: Bool = true, perform: @escaping () -> Void) -> some View {
        Button { expanded = false; perform() } label: {
            Label(title, systemImage: symbol).font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading).padding(.horizontal, 16).padding(.vertical, 3)
                .contentShape(Rectangle())
        }.buttonStyle(.plain).foregroundStyle(enabled ? Color.primary : Color.secondary)
            .disabled(!enabled).accessibilityIdentifier(identifier)
    }
}

struct AnimeEpisodeOverview: View {
    let anime: Anime
    let entry: LibraryEntry?
    let dub: LibraryDubProgress?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let broadcast = LibraryBroadcastSummary(anime: anime, watched: entry?.progressValue ?? 0, now: context.date)
            HStack(alignment: .top, spacing: 0) {
                metric("Aired", value: "\(broadcast.aired.map(String.init) ?? "—")/\(anime.episodes.flatMap { $0 > 0 ? String($0) : nil } ?? "?")", identifier: "aired")
                Divider()
                metric("Dubbed", value: dubCount, identifier: "dubbed")
                Divider()
                metric("Watched", value: entry.map { String($0.progressValue) } ?? "—", identifier: "watched")
            }.fixedSize(horizontal: false, vertical: true).padding(.vertical, 17)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
                .overlay { RoundedRectangle(cornerRadius: 18).stroke(Theme.border, lineWidth: 1) }
        }.accessibilityIdentifier("detail-episode-overview")
    }
    private var dubCount: String {
        guard let dub, let count = dub.released else { return "—" }
        return (dub.confidence == .estimated ? "~" : "") + String(count)
    }
    private func metric(_ title: String, value: String, identifier: String) -> some View {
        VStack(spacing: 7) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline.monospacedDigit()).foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore).accessibilityLabel("\(title): \(value)")
            .accessibilityIdentifier("detail-episodes-\(identifier)")
    }
}
