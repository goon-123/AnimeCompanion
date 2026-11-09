import SwiftUI
import AnimeCore

struct CinematicBackdropKey: PreferenceKey {
    static let defaultValue: URL? = nil
    static func reduce(value: inout URL?, nextValue: () -> URL?) { value = nextValue() ?? value }
}

struct CinematicScreenBackground: View {
    let url: URL?
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Theme.background
                ArtworkImage(url: url, pointSize: 600) { $0.resizable().scaledToFill() } placeholder: { Color.clear }
                    .frame(width: geometry.size.width, height: geometry.size.height).clipped().blur(radius: 42)
                Theme.background.opacity(0.9)
                LinearGradient(colors: [.clear, Theme.background], startPoint: .top, endPoint: .bottom)
            }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }.ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)
    }
}

extension ExploreStory {
    var cinematicCoverURL: URL? {
        switch self { case .anime(let anime): return anime.coverURL; case .reading(let series): return series.fullCoverURL ?? series.coverURL }
    }
    var cinematicBackgroundURL: URL? {
        switch self {
        case .anime(let anime): return anime.bannerImage.flatMap(URL.init(string:)) ?? anime.coverURL
        case .reading: return cinematicCoverURL
        }
    }
    var cinematicSummary: String {
        switch self { case .anime(let anime): return anime.synopsis; case .reading(let series): return series.synopsis }
    }
    var cinematicProvider: String { switch self { case .anime: return "AniList"; case .reading: return "MangaBaka" } }
}

/// Only the selected story asks for matched artwork; the existing client caches it.
struct CinematicStorySpotlight: View {
    let stories: [ExploreStory]
    var eyebrow = "Spotlight"
    var topInset: CGFloat = 0
    @EnvironmentObject private var store: AppStore
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selected = 0
    @State private var artwork = SeriesArtwork()
    @State private var artworkID: String?
    private var items: [ExploreStory] { Array(stories.prefix(5)) }
    private var active: ExploreStory? { items.indices.contains(selected) ? items[selected] : items.first }
    private var height: CGFloat { (sizeClass == .regular ? 470 : 420) + topInset + (textSize.isAccessibilitySize ? 190 : 0) }
    var body: some View {
        if !items.isEmpty {
            TabView(selection: $selected) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, story in
                    CinematicSpotlightPanel(story: story, eyebrow: eyebrow,
                        artwork: story.id == artworkID ? artwork : SeriesArtwork()).tag(index)
                }
            }.tabViewStyle(.page(indexDisplayMode: .never)).frame(height: height)
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .overlay(alignment: .bottom) { pages.padding(.bottom, 14) }
                .overlay { RoundedRectangle(cornerRadius: 24).strokeBorder(.white.opacity(0.1), lineWidth: 1).allowsHitTesting(false) }
                .preference(key: CinematicBackdropKey.self, value: active?.id == artworkID ? artwork.backdrop ?? active?.cinematicBackgroundURL : active?.cinematicBackgroundURL)
                .accessibilityIdentifier("cinematic-story-spotlight")
                .onChange(of: items.map(\.id)) { _, _ in selected = min(selected, max(0, items.count - 1)) }
                .task(id: active?.id) { await loadArtwork() }
        }
    }
    private var pages: some View {
        HStack(spacing: 0) {
            ForEach(items.indices, id: \.self) { index in
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { selected = index }
                } label: {
                    Capsule().fill(selected == index ? Color.white : .white.opacity(0.35))
                        .frame(width: selected == index ? 22 : 6, height: 5).frame(width: 36, height: 30)
                }.buttonStyle(.plain).accessibilityLabel("Spotlight \(index + 1) of \(items.count)")
                    .accessibilityAddTraits(selected == index ? .isSelected : [])
            }
        }
    }
    private func loadArtwork() async {
        artwork = SeriesArtwork(); artworkID = nil
        guard let active, case .anime(let anime) = active else { return }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--ui-") }) { return }
        #endif
        let result = await store.seriesArtwork.artwork(for: anime)
        guard !Task.isCancelled, self.active?.id == active.id else { return }
        artwork = result; artworkID = active.id
    }
}

private struct CinematicSpotlightPanel: View {
    let story: ExploreStory
    let eyebrow: String
    let artwork: SeriesArtwork
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var books: MangaBakaStore
    @EnvironmentObject private var sourceLinks: MangaSourceLinkStore
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var watching: Anime?
    @State private var editingAnime: Anime?
    @State private var editingReading: MangaBakaSeries?
    @State private var settings = false
    @State private var readingAccount = false
    private var background: URL? { artwork.backdrop ?? story.cinematicBackgroundURL }
    private var isSaved: Bool {
        switch story { case .anime(let anime): return store.entry(for: anime.id) != nil; case .reading(let series): return books.entries[series.id] != nil }
    }
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomLeading) {
                ExploreStoryLink(item: story) {
                    ArtworkImage(url: background, pointSize: max(geometry.size.width, geometry.size.height)) { $0.resizable().scaledToFill() }
                        placeholder: { Theme.surface }
                        .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                }.accessibilityLabel("Details for " + story.title)
                LinearGradient(stops: [.init(color: .black.opacity(0.24), location: 0),
                    .init(color: .black.opacity(0.08), location: 0.25), .init(color: .black.opacity(0.75), location: 0.65),
                    .init(color: .black.opacity(0.97), location: 1)], startPoint: .top, endPoint: .bottom).allowsHitTesting(false)
                HStack(alignment: .bottom, spacing: 28) {
                    information.frame(maxWidth: 650, alignment: .leading)
                    if geometry.size.width > 700 && !textSize.isAccessibilitySize {
                        ExploreStoryLink(item: story) { ExploreStoryCover(item: story, width: 146).shadow(color: .black.opacity(0.4), radius: 16, y: 8) }
                    }
                }.padding(.horizontal, geometry.size.width > 700 ? 32 : 22).padding(.bottom, 52)
            }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }.foregroundStyle(.white)
            .sheet(item: $watching) { WatchAnimeView(anime: $0) }
            .sheet(item: $editingAnime) { TrackingEditorView(anime: $0, entry: store.entry(for: $0.id)) }
            .sheet(item: $editingReading) { series in AppNavigationStack { MangaBakaTrackingView(series: series) } }
            .appSettingsSheet(isPresented: $settings)
            .sheet(isPresented: $readingAccount) {
                AppNavigationStack { MangaBakaAccountView().toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { readingAccount = false } } } }
            }
    }
    private var information: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(eyebrow.uppercased()).font(.caption2.bold()).tracking(2).foregroundStyle(.white.opacity(0.75))
            if let logo = artwork.logo {
                ArtworkImage(url: logo, pointSize: 700) { $0.resizable().scaledToFit() } placeholder: { title }
                    .frame(maxWidth: 360, alignment: .leading).frame(height: 90, alignment: .leading).accessibilityLabel(story.title)
            } else { title }
            HStack(spacing: 8) {
                Text(story.format.uppercased()).font(.caption2.bold()).tracking(1)
                Text("· " + story.cinematicProvider).font(.caption).foregroundStyle(.white.opacity(0.65))
            }
            if !story.cinematicSummary.isEmpty {
                Text(story.cinematicSummary).font(.subheadline).foregroundStyle(.white.opacity(0.75))
                    .lineLimit(textSize.isAccessibilitySize ? 3 : 2)
            }
            HStack(spacing: 12) { primaryAction; detailsAction; libraryAction }.padding(.top, 4)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var title: some View {
        Text(story.title).font(.system(.title, design: .rounded, weight: .bold)).lineLimit(textSize.isAccessibilitySize ? 4 : 3)
            .fixedSize(horizontal: false, vertical: true).shadow(color: .black.opacity(0.3), radius: 6, y: 2)
    }
    @ViewBuilder private var primaryAction: some View {
        switch story {
        case .anime(let anime):
            Button { watching = anime } label: {
                actionLabel((store.entry(for: anime.id)?.progressValue ?? 0) > 0 ? "Continue" : "Watch", symbol: "play.fill")
            }.buttonStyle(.plain).disabled(anime.status == "NOT_YET_RELEASED")
        case .reading(let series):
            if series.type != "novel", let target = books.sourceLinkTarget(for: series), let link = sourceLinks.link(for: target) {
                NavigationLink { MangaTitleDetailView(title: link.title, linkingTo: target, resumeOnOpen: true) } label: { actionLabel("Continue", symbol: "book.fill") }.buttonStyle(.plain)
            } else {
                ExploreStoryLink(item: story) { actionLabel("Read", symbol: "book.fill") }
            }
        }
    }
    private func actionLabel(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol).font(.subheadline.bold()).padding(.horizontal, 20).frame(minHeight: 46)
            .foregroundStyle(.black).background(.white, in: Capsule())
    }
    private var detailsAction: some View {
        ExploreStoryLink(item: story) { Image(systemName: "info.circle").font(.title3).frame(width: 46, height: 46).silverGlass(in: Circle()) }
            .accessibilityLabel("Details for " + story.title)
    }
    private var libraryAction: some View {
        Button {
            switch story {
            case .anime(let anime): if store.isSignedIn { editingAnime = anime } else { settings = true }
            case .reading(let series): if books.connected { editingReading = series } else { readingAccount = true }
            }
        } label: {
            Image(systemName: isSaved ? "checkmark" : "plus").font(.title3.weight(.semibold)).frame(width: 46, height: 46).silverGlass(in: Circle())
        }.buttonStyle(.plain).accessibilityLabel(isSaved ? "Edit library entry" : "Add to library")
    }
}

struct CinematicStoryPoster: View {
    let item: ExploreStory
    var width: CGFloat? = nil
    @EnvironmentObject private var reading: MangaBakaStore
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GeometryReader { geometry in ExploreStoryCover(item: item, width: geometry.size.width) }
                .aspectRatio(1 / 1.45, contentMode: .fit).environment(\.posterArtworkBadgesEnabled, false)
            VStack(alignment: .leading, spacing: 7) {
                Text(item.format.uppercased()).font(.system(size: 9, weight: .bold)).tracking(1.1).foregroundStyle(Theme.accent)
                Text(item.title).font(.subheadline.weight(.semibold)).lineLimit(2, reservesSpace: true)
                switch item {
                case .anime(let anime): DiscoveryPosterSummary(anime: anime); DiscoveryLibraryBadge(anime: anime)
                case .reading(let series):
                    if let score = series.rating { Label(score.formatted(.number.precision(.fractionLength(0))) + "%", systemImage: "star.fill").font(.caption2).foregroundStyle(Theme.highlight) }
                    Text(reading.entries[series.id].map { MangaBakaReadingStatus(rawValue: $0.state)?.label ?? $0.state.capitalized } ?? series.status.capitalized)
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }.padding(10)
        }.frame(width: width, alignment: .topLeading).frame(maxWidth: .infinity, alignment: .topLeading)
            .background(LinearGradient(colors: [Theme.surface, Theme.secondarySurface], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 16))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.border, lineWidth: 1).allowsHitTesting(false) }
            .foregroundStyle(.primary).contentShape(RoundedRectangle(cornerRadius: 16))
    }
}
