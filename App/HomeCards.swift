import SwiftUI
import AnimeCore

/// Medium covers and wrapping metadata keep normal Home cards horizontal.
/// Accessibility text stacks without imposing a fixed card height.
struct HomeMediaCardLayout<Artwork: View, Content: View>: View {
    @Environment(\.dynamicTypeSize) private var textSize
    let artwork: Artwork
    let content: Content
    let spacing: CGFloat

    init(spacing: CGFloat = 12, @ViewBuilder artwork: () -> Artwork, @ViewBuilder content: () -> Content) {
        self.artwork = artwork(); self.content = content(); self.spacing = spacing
    }

    var body: some View {
        Group {
            if textSize.isAccessibilitySize {
                stacked
            } else {
                HStack(alignment: .center, spacing: spacing) {
                    artwork
                    content.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading).foregroundStyle(.primary).contentShape(Rectangle())
    }

    private var stacked: some View {
        VStack(alignment: .leading, spacing: 12) {
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
        HomeMediaCardLayout {
            AnimeLink(id: anime.id) {
                AnimeCover(anime: anime, width: 80, cornerRadius: 12, identifierPrefix: "home", badgeStyle: .none)
            }.buttonStyle(.plain).accessibilityHidden(true)
        } content: { metadata }
            .companionPanel(padding: 12)
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 6) {
            AnimeLink(id: anime.id) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(anime.displayTitle).font(.subheadline.weight(.semibold)).lineLimit(2, reservesSpace: true)
                    Text("Watched \(entry.progressValue)" + (anime.episodes.map { " / \($0)" } ?? " episodes"))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("home-anime-\(anime.id)")
                .accessibilityHint("Open series details")
            if let total = anime.episodes, total > 0 {
                ProgressView(value: min(1, max(0, Double(entry.progressValue) / Double(total))))
                    .tint(Theme.accent).accessibilityLabel("Watched progress")
            } else { Color.clear.frame(height: 4).accessibilityHidden(true) }
            // Resume remains outside both detail links and sizes naturally
            // with the text; no oversized footer or overlapping hit areas.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { episodeLabel; Spacer(minLength: 0); continueAction }
                VStack(alignment: .leading, spacing: 4) { episodeLabel; continueAction }
            }
        }
    }

    private var episodeLabel: some View {
        Text(anime.format == "MOVIE" ? "Movie" : "Ep \(episode)")
            .font(.caption.weight(.semibold)).foregroundStyle(Theme.accent).fixedSize()
    }

    private var continueAction: some View {
        Button(action: resume) {
            Label(anime.format == "MOVIE" ? "Watch movie" : "Continue", systemImage: "play.fill")
                .font(.caption.weight(.semibold)).imageScale(.small)
                .padding(.horizontal, 10).padding(.vertical, 6)
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
        HomeMediaCardLayout(spacing: 10) {
            MangaCover(title: record.title, width: 44).frame(width: 44, height: 44 * 1.45)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } content: {
            VStack(alignment: .leading, spacing: 3) {
                Text(record.title.manga.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                if let position {
                    HStack(spacing: 6) {
                        Text(position.chapterName).lineLimit(1).foregroundStyle(.secondary)
                        if position.pageCount > 0 {
                            Text("p. \(position.pageIndex + 1)/\(position.pageCount)")
                                .monospacedDigit().foregroundStyle(Theme.accent).fixedSize().layoutPriority(1)
                                .accessibilityLabel("Page \(position.pageIndex + 1) of \(position.pageCount)")
                        }
                    }.font(.caption)
                }
                Text(record.title.source.name).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }.companionPanel(padding: 10)
    }
}

struct HomeTrackedReadingCard: View {
    let entry: MangaBakaLibraryEntry
    let series: MangaBakaSeries

    var body: some View {
        HomeMediaCardLayout(spacing: 10) {
            MangaBakaCover(series: series, width: 44)
        } content: {
            VStack(alignment: .leading, spacing: 3) {
                Text(series.displayTitle).font(.subheadline.weight(.semibold)).lineLimit(2)
                Text("Ch. " + (entry.chapter ?? 0).formatted())
                    .font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(Theme.accent)
                Text(series.formatLabel + " · MangaBaka").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }.companionPanel(padding: 10)
    }
}

struct HomeUpNextCard: View {
    let anime: Anime
    let episode: AiringEpisode

    var body: some View {
        HomeMediaCardLayout(spacing: 10) {
            AnimeCover(anime: anime, width: 40, cornerRadius: 8, identifierPrefix: "home", badgeStyle: .none)
        } content: {
            VStack(alignment: .leading, spacing: 3) {
                Text(anime.displayTitle).font(.subheadline.weight(.semibold)).lineLimit(2)
                Text("Ep \(episode.episode) · Original broadcast").font(.caption2).foregroundStyle(.secondary)
                Text(episode.date, format: .dateTime.weekday(.abbreviated).hour().minute())
                    .font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
            }
        }.companionPanel(padding: 10)
    }
}
