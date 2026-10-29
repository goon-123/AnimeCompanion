import SwiftUI
import AnimeCore

/// Keep Home's rounded panels and give artwork more room. Narrow panes and
/// accessibility text can stack without imposing a fixed card height.
struct HomeMediaCardLayout<Artwork: View, Content: View>: View {
    @Environment(\.dynamicTypeSize) private var textSize
    let artwork: Artwork
    let content: Content

    init(@ViewBuilder artwork: () -> Artwork, @ViewBuilder content: () -> Content) {
        self.artwork = artwork(); self.content = content()
    }

    var body: some View {
        Group {
            if textSize.isAccessibilitySize {
                stacked
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        artwork
                        content.frame(minWidth: 120, maxWidth: .infinity, alignment: .leading)
                    }
                    stacked
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading).foregroundStyle(.primary).contentShape(Rectangle())
    }

    private var stacked: some View {
        VStack(alignment: .leading, spacing: 16) {
            artwork
            content.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct HomeContinueWatchingCard: View {
    let anime: Anime
    let entry: LibraryEntry
    let resume: () -> Void
    private var episode: Int { PlaybackEpisodeSelection.initial(anime: anime, entry: entry, resumeEpisode: nil) }

    var body: some View {
        VStack(alignment: .trailing, spacing: 12) {
            AnimeLink(id: anime.id) {
                HomeMediaCardLayout {
                    AnimeCover(anime: anime, width: 128, cornerRadius: 14, identifierPrefix: "home", badgeStyle: .none)
                } content: { metadata }
            }.buttonStyle(.plain).accessibilityIdentifier("home-anime-\(anime.id)")
                .accessibilityHint("Open series details")
            continueAction
        }.companionPanel()
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(anime.displayTitle).font(.headline).lineLimit(3, reservesSpace: true)
            Text("Watched \(entry.progressValue)" + (anime.episodes.map { " / \($0)" } ?? " episodes"))
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            if let total = anime.episodes, total > 0 {
                ProgressView(value: min(1, max(0, Double(entry.progressValue) / Double(total))))
                    .tint(Theme.accent).accessibilityLabel("Watched progress")
            } else { Color.clear.frame(height: 4).accessibilityHidden(true) }
            Text(anime.format == "MOVIE" ? "Movie" : "Episode \(episode)")
                .font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
        }
    }

    private var continueAction: some View {
        Button(action: resume) {
            Label(anime.format == "MOVIE" ? "Watch movie" : "Continue", systemImage: "play.fill")
                .font(.caption.weight(.semibold)).imageScale(.small)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .foregroundStyle(Theme.accent)
                .background(Theme.accent.opacity(0.13), in: Capsule())
                .overlay { Capsule().stroke(Theme.accent.opacity(0.18), lineWidth: 1) }
                .frame(minHeight: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(anime.status == "NOT_YET_RELEASED")
            .accessibilityLabel(anime.format == "MOVIE" ? "Watch \(anime.displayTitle)" : "Continue \(anime.displayTitle), episode \(episode)")
            .accessibilityHint("Choose a stream and open it in VidHub")
            .accessibilityIdentifier("home-watch-\(anime.id)")
    }
}

struct HomeContinueReadingCard: View {
    let record: MangaReadingRecord
    private var position: MangaReadingPosition? { record.lastChapterURL.flatMap { record.position(for: $0) } }

    var body: some View {
        HomeMediaCardLayout {
            MangaCover(title: record.title, width: 112).frame(width: 112, height: 112 * 1.45)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        } content: {
            VStack(alignment: .leading, spacing: 9) {
                Text(record.title.manga.title).font(.headline).lineLimit(3)
                if let position {
                    Text(position.chapterName).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    if position.pageCount > 0 {
                        Text("Page \(position.pageIndex + 1) of \(position.pageCount)")
                            .font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(Theme.accent)
                    }
                }
                HStack(spacing: 8) {
                    Text(record.title.source.name).lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").accessibilityHidden(true)
                }.font(.caption).foregroundStyle(.secondary)
            }
        }.companionPanel()
    }
}

struct HomeTrackedReadingCard: View {
    let entry: MangaBakaLibraryEntry
    let series: MangaBakaSeries

    var body: some View {
        HomeMediaCardLayout {
            MangaBakaCover(series: series, width: 112)
        } content: {
            VStack(alignment: .leading, spacing: 9) {
                Text(series.displayTitle).font(.headline).lineLimit(3)
                Text("Chapter " + (entry.chapter ?? 0).formatted())
                    .font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(Theme.accent)
                Text(series.formatLabel).font(.caption).foregroundStyle(.secondary)
                HStack {
                    Text("MangaBaka")
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").accessibilityHidden(true)
                }.font(.caption).foregroundStyle(.secondary)
            }
        }.companionPanel()
    }
}

struct HomeUpNextCard: View {
    let anime: Anime
    let episode: AiringEpisode

    var body: some View {
        HomeMediaCardLayout {
            AnimeCover(anime: anime, width: 88, cornerRadius: 14, identifierPrefix: "home", badgeStyle: .none)
        } content: {
            VStack(alignment: .leading, spacing: 9) {
                Text(anime.displayTitle).font(.headline).lineLimit(3)
                Text("Episode \(episode.episode) · Original broadcast").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Text(episode.date, format: .dateTime.weekday(.abbreviated).hour().minute())
                        .fontWeight(.semibold).foregroundStyle(Theme.accent)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").foregroundStyle(.secondary).accessibilityHidden(true)
                }.font(.caption)
            }
        }.companionPanel()
    }
}
