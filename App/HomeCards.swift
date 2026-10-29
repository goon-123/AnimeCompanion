import SwiftUI
import AnimeCore

/// Medium covers and wrapping metadata keep normal Home cards horizontal.
/// Accessibility text stacks without imposing a fixed card height.
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
                HStack(alignment: .center, spacing: 12) {
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
        HomeMediaCardLayout {
            MangaCover(title: record.title, width: 72).frame(width: 72, height: 72 * 1.45)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        } content: {
            VStack(alignment: .leading, spacing: 5) {
                Text(record.title.manga.title).font(.subheadline.weight(.semibold)).lineLimit(2)
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
        }.companionPanel(padding: 12)
    }
}

struct HomeTrackedReadingCard: View {
    let entry: MangaBakaLibraryEntry
    let series: MangaBakaSeries

    var body: some View {
        HomeMediaCardLayout {
            MangaBakaCover(series: series, width: 72)
        } content: {
            VStack(alignment: .leading, spacing: 5) {
                Text(series.displayTitle).font(.subheadline.weight(.semibold)).lineLimit(2)
                Text("Chapter " + (entry.chapter ?? 0).formatted())
                    .font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(Theme.accent)
                HStack {
                    Text(series.formatLabel + " · MangaBaka").lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").accessibilityHidden(true)
                }.font(.caption).foregroundStyle(.secondary)
            }
        }.companionPanel(padding: 12)
    }
}

struct HomeUpNextCard: View {
    let anime: Anime
    let episode: AiringEpisode

    var body: some View {
        HomeMediaCardLayout {
            AnimeCover(anime: anime, width: 64, cornerRadius: 12, identifierPrefix: "home", badgeStyle: .none)
        } content: {
            VStack(alignment: .leading, spacing: 5) {
                Text(anime.displayTitle).font(.subheadline.weight(.semibold)).lineLimit(2)
                Text("Episode \(episode.episode) · Original broadcast").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Text(episode.date, format: .dateTime.weekday(.abbreviated).hour().minute())
                        .fontWeight(.semibold).foregroundStyle(Theme.accent)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").foregroundStyle(.secondary).accessibilityHidden(true)
                }.font(.caption)
            }
        }.companionPanel(padding: 12)
    }
}
