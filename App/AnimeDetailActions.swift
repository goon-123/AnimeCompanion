import SwiftUI
import AnimeCore

/// One tap opens editing. Secondary actions stay available on a long press.
struct AnimeDetailActions: View {
    let resumeLabel: String
    let canWatch: Bool
    let canEdit: Bool
    let edit: () -> Void
    let resume: () -> Void
    let findManga: () -> Void
    var body: some View {
        Button(action: edit) {
            Image(systemName: "pencil").font(.system(size: 23, weight: .semibold))
                .frame(width: 56, height: 56).foregroundStyle(Theme.background).background(Theme.accent, in: Circle())
                .shadow(color: .black.opacity(0.22), radius: 12, y: 5)
        }.buttonStyle(.plain).disabled(!canEdit).padding(16)
            .accessibilityLabel("Edit watchlist").accessibilityHint("Edit status, watched episodes, rating and notes")
            .accessibilityIdentifier("detail-actions")
            .contextMenu {
                Button("Edit Entry", systemImage: "square.and.pencil", action: edit).disabled(!canEdit)
                Button(resumeLabel, systemImage: "play.fill", action: resume).disabled(!canWatch)
                Button("Read manga / novel", systemImage: "book.closed", action: findManga)
            }
    }
}

/// A pinned strip replaces the large progress panel, with the familiar +1 and
/// server-confirmed feedback/undo shared by the existing library controls.
struct AnimeWatchlistStrip: View {
    @EnvironmentObject private var store: AppStore
    let anime: Anime
    let resumeLabel: String
    let edit: () -> Void
    let play: () -> Void
    @State private var error: String?
    private var entry: LibraryEntry? { store.entry(for: anime.id) }
    private var busy: Bool { store.savingMedia.contains(anime.id) || (store.isSignedIn && (store.loadingLibrary || store.savedAt == nil)) }
    private var atEnd: Bool { anime.episodes.map { $0 > 0 && (entry?.progressValue ?? 0) >= $0 } ?? false }
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Button(action: edit) {
                    HStack(spacing: 9) {
                        Image(systemName: entry == nil ? "bookmark" : "checklist").foregroundStyle(Theme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry?.status?.label ?? "Add to watchlist").font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
                            if entry != nil {
                                Text("\(entry?.progressValue ?? 0) / \(anime.episodes.map(String.init) ?? "?") watched")
                                    .font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(.primary)
                            } else { Text(store.isSignedIn ? "Tap to add or edit" : "Connect AniList").font(.caption2).foregroundStyle(.secondary) }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(busy).accessibilityIdentifier("tracking-set-episode")
                if store.isSignedIn {
                    Button {
                        error = nil
                        Task { do { try await store.markNextWatched(anime: anime) } catch { self.error = error.localizedDescription } }
                    } label: {
                        if store.savingMedia.contains(anime.id) { ProgressView().frame(width: 44, height: 44) }
                        else { Text("+1").font(.subheadline.bold()).frame(width: 44, height: 44).background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12)) }
                    }.buttonStyle(.plain).foregroundStyle(Theme.accent).disabled(busy || atEnd)
                        .accessibilityLabel("Increase watched episodes").accessibilityIdentifier("tracking-next")
                }
                Button(action: play) {
                    Image(systemName: "play.fill").font(.subheadline.weight(.semibold)).frame(width: 44, height: 44)
                        .foregroundStyle(Theme.background).background(Theme.accent, in: RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(.plain).disabled(anime.status == "NOT_YET_RELEASED" || busy)
                    .accessibilityLabel(resumeLabel).accessibilityIdentifier("detail-compact-play")
            }.companionPanel(padding: 8)
            TrackingFeedback(anime: anime)
            if let error { Text(error).font(.caption).foregroundStyle(.orange).accessibilityIdentifier("detail-tracking-error") }
        }.accessibilityIdentifier("detail-watchlist-strip")
    }
}

/// The detailed counts stay in Info without the former large three-tile panel.
struct AnimeEpisodeFacts: View {
    let anime: Anime
    let entry: LibraryEntry?
    let dub: LibraryDubProgress?
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let summary = LibraryBroadcastSummary(anime: anime, watched: entry?.progressValue ?? 0, now: context.date)
            let aired = "\(summary.aired.map(String.init) ?? "—")/\(anime.episodes.flatMap { $0 > 0 ? String($0) : nil } ?? "?")"
            let dubbed = dub?.released.map(String.init) ?? "—"
            HStack(spacing: 8) {
                fact("Aired", value: aired, key: "aired")
                fact("Dubbed", value: (dub?.confidence == .estimated ? "~" : "") + dubbed, key: "dubbed")
                fact("Watched", value: entry.map { String($0.progressValue) } ?? "—", key: "watched")
            }.font(.caption).foregroundStyle(.secondary)
        }
    }
    private func fact(_ label: String, value: String, key: String) -> some View {
        Text(label + " " + value).frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(label + ": " + value).accessibilityIdentifier("detail-episodes-" + key)
    }
}
