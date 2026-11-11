import SwiftUI
import AnimeCore

struct CinematicAnimeHero: View {
    @EnvironmentObject private var dubs: ExploreDubStore
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var textSize
    @AppStorage(SeriesArtworkPreferences.logoKey) private var logoFallback = false
    @AppStorage(SeriesArtworkPreferences.bannerKey) private var bannerFallback = false
    @AppStorage(SeriesArtworkPreferences.posterKey) private var posterFallback = false
    let anime: Anime
    let artwork: SeriesArtwork
    var artworkResolved = true
    let trailer: () -> Void
    let expand: (URL) -> Void
    private var bannerHeight: CGFloat { sizeClass == .regular ? 530 : 390 }
    private var posterWidth: CGFloat { sizeClass == .regular ? 186 : 138 }
    private var preferences: SeriesArtworkPreferences { .init(logo: logoFallback, banner: bannerFallback, poster: posterFallback) }
    private var presentation: CinematicArtworkPresentation { .init(artwork: artwork, anime: anime, preferences: preferences, resolved: artworkResolved) }
    private var backgroundURL: URL? { presentation.banner }
    private var posterURL: URL? { presentation.poster }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            banner
            Group {
                if textSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 18) { poster; identity }
                } else {
                    HStack(alignment: .bottom, spacing: 16) { poster; identity }
                }
            }.padding(.horizontal, 20).padding(.top, -72).padding(.bottom, 18)
                .readableContent(width: 1060).frame(maxWidth: .infinity, alignment: .leading)
        }.accessibilityElement(children: .contain).accessibilityIdentifier("cinematic-series-hero")
    }
    private var banner: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomTrailing) {
                Button { if let backgroundURL { expand(backgroundURL) } } label: {
                    ArtworkImage(url: backgroundURL, pointSize: max(geometry.size.width, bannerHeight)) {
                        $0.resizable().scaledToFill().blur(radius: presentation.blurredCover ? 24 : 0)
                            .scaleEffect(presentation.blurredCover ? 1.08 : 1)
                    } placeholder: {
                        ArtworkImage(url: bannerFallback ? anime.bannerImage.flatMap(URL.init(string:)) ?? anime.coverURL : nil, pointSize: max(geometry.size.width, bannerHeight)) {
                            $0.resizable().scaledToFill()
                        } placeholder: { LinearGradient(colors: [Theme.accent.opacity(0.18), Theme.background], startPoint: .topLeading, endPoint: .bottomTrailing) }
                    }
                        .frame(width: geometry.size.width, height: bannerHeight).clipped()
                }.buttonStyle(.plain).disabled(backgroundURL == nil).accessibilityLabel("Expand anime banner").accessibilityIdentifier("expand-anime-banner")
                LinearGradient(stops: [.init(color: .black.opacity(0.08), location: 0),
                    .init(color: .clear, location: 0.38), .init(color: Theme.background.opacity(0.45), location: 0.72),
                    .init(color: Theme.background, location: 1)], startPoint: .top, endPoint: .bottom)
                    .allowsHitTesting(false)
                if anime.trailer?.url != nil {
                    Button(action: trailer) {
                        Label("Trailer", systemImage: "play.fill").font(.subheadline.bold())
                            .padding(.horizontal, 16).frame(height: 48).silverGlass(in: Capsule())
                    }.buttonStyle(.plain).padding(.trailing, 22).padding(.bottom, 100)
                        .accessibilityLabel("Play trailer").accessibilityIdentifier("detail-hero-trailer")
                }
            }.frame(width: geometry.size.width, height: bannerHeight).clipped()
        }.frame(height: bannerHeight)
    }
    private var poster: some View {
        Button { if let posterURL { expand(posterURL) } } label: {
            ArtworkImage(url: posterURL, pointSize: posterWidth * 1.45) { $0.resizable().scaledToFill() } placeholder: {
                ArtworkImage(url: posterFallback ? anime.coverURL : nil, pointSize: posterWidth * 1.45) { $0.resizable().scaledToFill() } placeholder: {
                    ZStack {
                        LinearGradient(colors: [Theme.accent.opacity(0.25), Theme.surface], startPoint: .topLeading, endPoint: .bottomTrailing)
                        Image(systemName: "play.rectangle").font(.largeTitle).foregroundStyle(Theme.accent.opacity(0.6))
                    }
                }
            }.frame(width: posterWidth, height: posterWidth * 1.45).clipped().clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay { RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.18), lineWidth: 1) }
                .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
        }.buttonStyle(.plain).disabled(posterURL == nil).accessibilityLabel("Expand anime cover").accessibilityIdentifier("expand-anime-cover")
    }
    private var identity: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let logo = artwork.logo {
                ArtworkImage(url: logo, pointSize: 700) { $0.resizable().scaledToFit() } placeholder: { logoPlaceholder }
                    .frame(maxWidth: .infinity, alignment: .leading).frame(height: sizeClass == .regular ? 132 : 96, alignment: .leading)
                    .accessibilityLabel(anime.displayTitle).accessibilityIdentifier("detail-series-logo")
            } else { logoPlaceholder }
            Text([anime.season.map { $0.label + (anime.seasonYear.map { " \($0)" } ?? "") },
                anime.format?.replacingOccurrences(of: "_", with: " ")].compactMap { $0 }.joined(separator: " · "))
                .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                if let score = anime.averageScore {
                    Label("\(Double(score) / 10, specifier: "%.1f")", systemImage: "star.fill").foregroundStyle(Theme.highlight)
                }
                Text(anime.isCurrentlyAiring ? "Airing now" : anime.status?.replacingOccurrences(of: "_", with: " ").capitalized ?? "Anime")
                    .foregroundStyle(anime.isCurrentlyAiring ? Color.green : Color.secondary)
                    .accessibilityIdentifier("detail-release-status")
            }.font(.caption.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            DubStatusBadge(anime: anime, progress: dubs.progress(for: anime)).accessibilityIdentifier("detail-dub-summary")
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var title: some View {
        Text(anime.displayTitle).font(sizeClass == .regular ? .largeTitle.bold() : .title2.bold())
            .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("detail-title")
    }
    @ViewBuilder private var logoPlaceholder: some View {
        if presentation.textTitle || logoFallback { title }
        else { Color.clear.frame(height: sizeClass == .regular ? 132 : 96).accessibilityHidden(true) }
    }
}

struct SeriesAiringCountdown: View {
    let anime: Anime
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if let next = AnimeSeriesContent.nextBroadcast(for: anime, now: context.date) {
                let remaining = max(0, Int(next.date.timeIntervalSince(context.date)))
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { label(next); Spacer(minLength: 8); digits(remaining) }
                    VStack(alignment: .leading, spacing: 12) { label(next); digits(remaining) }
                }.companionPanel(padding: 14).accessibilityElement(children: .combine)
                    .accessibilityIdentifier("detail-next-episode-countdown")
            }
        }
    }
    private func label(_ next: AiringEpisode) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("EPISODE \(next.episode)").font(.subheadline.bold())
            Text("Next episode airs in").font(.caption).foregroundStyle(.secondary)
        }.fixedSize(horizontal: true, vertical: false)
    }
    private func digits(_ seconds: Int) -> some View {
        HStack(spacing: 5) {
            unit(seconds / 86400, "d"); unit(seconds % 86400 / 3600, "h")
            unit(seconds % 3600 / 60, "m"); unit(seconds % 60, "s")
        }.accessibilityIdentifier("detail-countdown")
    }
    private func unit(_ value: Int, _ suffix: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(String(format: "%02d", value)).font(.subheadline.bold().monospacedDigit())
            Text(suffix).font(.caption2).foregroundStyle(.secondary)
        }.padding(.horizontal, 7).padding(.vertical, 9).background(Theme.secondarySurface, in: RoundedRectangle(cornerRadius: 9))
    }
}

struct SeriesWatchActions: View {
    @EnvironmentObject private var store: AppStore
    let anime: Anime
    let resumeLabel: String
    let play: () -> Void
    let edit: () -> Void
    private var busy: Bool { store.savingMedia.contains(anime.id) || (store.isSignedIn && (store.loadingLibrary || store.savedAt == nil)) }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Button(action: play) {
                    HStack(spacing: 10) {
                        Image(systemName: "play.fill").font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Watch Now").font(.headline)
                            Text(resumeLabel).font(.caption)
                        }
                    }.frame(maxWidth: .infinity, minHeight: 60)
                        .foregroundStyle(Theme.background).background(Theme.accent, in: RoundedRectangle(cornerRadius: 14))
                }.buttonStyle(.plain).disabled(AnimePremiere.defersEpisodes(for: anime))
                    .accessibilityLabel("Watch Now. " + resumeLabel).accessibilityIdentifier("detail-watch-now")
                Button(action: edit) {
                    Image(systemName: store.entry(for: anime.id) == nil ? "plus" : "checkmark")
                        .font(.title2.weight(.semibold)).frame(width: 60, height: 60)
                        .foregroundStyle(Theme.accent).background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
                }.buttonStyle(.plain).disabled(busy)
                    .accessibilityLabel(store.entry(for: anime.id) == nil ? "Add to library and choose status" : "In library. Edit status and progress")
                    .accessibilityIdentifier("detail-library-status")
            }
            if let entry = store.entry(for: anime.id) {
                Text("\(entry.status?.label ?? "In library") · \(entry.progressValue) / \(anime.episodes.map(String.init) ?? "?") watched")
                    .font(.caption).foregroundStyle(.secondary)
            }
            TrackingFeedback(anime: anime)
        }
    }
}

struct SeriesCharacters: View {
    let anime: Anime
    @Environment(\.horizontalSizeClass) private var sizeClass
    var body: some View {
        if let characters = anime.characters?.nodes, !characters.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text("Characters").font(.title3.bold())
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(characters) { character in
                            VStack(alignment: .leading, spacing: 8) {
                                ArtworkImage(url: character.image?.medium.flatMap(URL.init(string:)), pointSize: 210) {
                                    $0.resizable().scaledToFill()
                                } placeholder: { Theme.surface }
                                    .frame(width: sizeClass == .regular ? 144 : 112, height: sizeClass == .regular ? 166 : 132)
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                                Text(character.name?.full ?? "Character").font(.caption.weight(.semibold)).lineLimit(2)
                            }.frame(width: sizeClass == .regular ? 144 : 112, alignment: .leading)
                        }
                    }
                }
            }.accessibilityIdentifier("detail-characters")
        }
    }
}
