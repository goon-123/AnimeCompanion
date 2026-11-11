import SwiftUI
import AnimeCore

/// Medium covers and wrapping metadata keep normal Home cards horizontal.
/// Accessibility text stacks without imposing a fixed card height.
struct HomeMediaCardLayout<Artwork: View, Content: View>: View {
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.homeVisuals) private var visuals
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
                HStack(alignment: .center, spacing: visuals.value(spacing, max(spacing, 16))) {
                    artwork
                    content.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading).foregroundStyle(.primary).contentShape(Rectangle())
    }

    private var stacked: some View {
        VStack(alignment: .leading, spacing: visuals.value(12, 18)) {
            artwork
            content.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct HomeContinueWatchingCard: View {
    @Environment(\.homeVisuals) private var visuals
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var store: AppStore
    @State private var episodeDetails: AnimeEpisodeMetadata?
    let anime: Anime
    let entry: LibraryEntry
    let episode: Int
    let resume: PlaybackProgress?
    let onResume: () -> Void

    var body: some View {
        HomeMediaCardLayout {
            AnimeLink(id: anime.id) {
                ArtworkImage(url: episodeDetails?.imageURL, pointSize: visuals.watchingCover * 1.45, animatesCachedImages: true) {
                    $0.resizable().scaledToFill()
                } placeholder: {
                    // Display the existing poster immediately, then crossfade
                    // to an episode-specific still only after that still decodes.
                    AnimeCover(anime: anime, width: visuals.watchingCover,
                               cornerRadius: 12, identifierPrefix: "home", badgeStyle: .none)
                }
                .frame(width: visuals.watchingCover, height: visuals.watchingCover * 1.45)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel(episodeDetails?.imageURL == nil ? "Anime poster" : "Episode artwork")
            }.buttonStyle(.plain).accessibilityHidden(true)
        } content: { metadata }
            .companionPanel(padding: visuals.value(12, 16))
            .animation(AppMotion.content(reduceMotion), value: episodeDetails?.title)
            .task(id: "\(anime.id):\(episode)") { await fetchEpisodeDetails() }
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 6) {
            AnimeLink(id: anime.id) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(anime.displayTitle).font(.subheadline.weight(.semibold)).lineLimit(2, reservesSpace: true)
                    Text("Watched \(entry.progressValue)" + (anime.episodes.map { " / \($0) episodes" } ?? " episodes"))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("home-anime-\(anime.id)")
                .accessibilityHint("Open series details")
            if let resume, let duration = resume.duration, duration > 0 {
                ProgressView(value: min(1, max(0, resume.position / duration)))
                    .tint(Theme.accent).accessibilityLabel("Episode playback progress")
            } else if let total = anime.episodes, total > 0 {
                ProgressView(value: min(1, max(0, Double(entry.progressValue) / Double(total))))
                    .tint(Theme.accent).accessibilityLabel("Watched progress")
            } else { Color.clear.frame(height: 4).accessibilityHidden(true) }
            if let title = episodeDetails?.title, !title.isEmpty {
                Text(title).font(.caption2).foregroundStyle(.secondary).lineLimit(1).transition(.opacity)
            }
            if let resume {
                Text("Resume \(timeLabel(resume.position))" + (resume.duration.flatMap { $0 > 0 ? " / \(timeLabel($0))" : nil } ?? ""))
                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { episodeLabel; Spacer(minLength: 0); continueAction }
                VStack(alignment: .leading, spacing: 4) { episodeLabel; continueAction }
            }
        }
    }

    private func timeLabel(_ seconds: Double) -> String {
        let value = Int(max(0, min(seconds.isFinite ? seconds : 0, 31_536_000)))
        return String(format: "%d:%02d", value / 60, value % 60)
    }
    @MainActor private func fetchEpisodeDetails() async {
        episodeDetails = nil
        guard episode > 0, !AnimePremiere.defersEpisodes(for: anime) else { return }
        let pageNumber = (episode - 1) / 100 + 1
        if let cached = await store.episodeMetadata.cached(for: anime, page: pageNumber) {
            guard !Task.isCancelled else { return }
            episodeDetails = cached.episodes.first { $0.number == episode }
            if episodeDetails?.imageURL != nil { return }
        }
        if let fresh = try? await store.episodeMetadata.page(for: anime, page: pageNumber) {
            guard !Task.isCancelled else { return }
            episodeDetails = fresh.episodes.first { $0.number == episode } ?? episodeDetails
        }
    }

    private var episodeLabel: some View {
        Text(anime.format == "MOVIE" ? "Movie" : "Ep \(episode)")
            .font(.caption.weight(.semibold)).foregroundStyle(Theme.accent).fixedSize()
    }

    private var continueAction: some View {
        Button(action: onResume) {
            Label(anime.format == "MOVIE" ? "Watch movie" : (resume == nil ? "Continue" : "Resume"), systemImage: "play.fill")
                .font(visuals.actionTextFont).imageScale(visuals.enlarged ? .medium : .small)
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
    @Environment(\.homeVisuals) private var visuals
    let record: MangaReadingRecord
    private var position: MangaReadingPosition? { record.lastChapterURL.flatMap { record.position(for: $0) } }

    var body: some View {
        HomeMediaCardLayout(spacing: 10) {
            MangaCover(title: record.title, width: visuals.readingCover).frame(width: visuals.readingCover, height: visuals.readingCover * 1.45)
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
        }.companionPanel(padding: visuals.value(10, 14))
    }
}

struct HomeTrackedReadingCard: View {
    @Environment(\.homeVisuals) private var visuals
    let entry: MangaBakaLibraryEntry
    let series: MangaBakaSeries

    var body: some View {
        HomeMediaCardLayout(spacing: 10) {
            MangaBakaCover(series: series, width: visuals.readingCover)
        } content: {
            VStack(alignment: .leading, spacing: 3) {
                Text(series.displayTitle).font(.subheadline.weight(.semibold)).lineLimit(2)
                Text("Ch. " + (entry.chapter ?? 0).formatted())
                    .font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(Theme.accent)
                Text(series.formatLabel + " · MangaBaka").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }.companionPanel(padding: visuals.value(10, 14))
    }
}

struct HomeUpNextCard: View {
    @Environment(\.homeVisuals) private var visuals
    let anime: Anime
    let episode: AiringEpisode

    var body: some View {
        HomeMediaCardLayout(spacing: 10) {
            AnimeCover(anime: anime, width: visuals.upcomingCover, cornerRadius: 8, identifierPrefix: "home", badgeStyle: .none)
        } content: {
            VStack(alignment: .leading, spacing: 3) {
                Text(anime.displayTitle).font(.subheadline.weight(.semibold)).lineLimit(2)
                Text("Ep \(episode.episode) · Original broadcast").font(.caption2).foregroundStyle(.secondary)
                Text(episode.date, format: .dateTime.weekday(.abbreviated).hour().minute())
                    .font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
            }
        }.companionPanel(padding: visuals.value(10, 14))
    }
}
