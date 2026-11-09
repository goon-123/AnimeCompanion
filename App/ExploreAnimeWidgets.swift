import SwiftUI
import AnimeCore

struct HomeTrendingAnimeWidget: View {
    let refreshID: Int
    let activationID: Int
    var ranked = true
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var dubs: ExploreDubStore
    @EnvironmentObject private var filters: DiscoveryFilterStore
    @State private var items: [Anime] = []
    @State private var loading = false
    @State private var failed = false
    @State private var retry = 0
    @State private var appliedRefresh = 0
    private var visible: [Anime] { items.filter { store.isVisible($0) && filters.includes($0, dubs: dubs, library: store) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if ranked { TopTrendingAnimeWidget(anime: visible) }
            else { PlainTrendingAnimeWidget(anime: visible) }
            if loading { ProgressView().controlSize(.small) }
            if failed {
                HStack { Text(items.isEmpty ? "Trending unavailable" : "Showing saved trending titles").font(.caption).foregroundStyle(.secondary); Spacer(); Button("Retry") { retry += 1 }.font(.caption) }
            }
        }.task(id: "\(store.includeAdult)-\(refreshID)-\(activationID)-\(retry)") { await load() }
            .task { await dubs.load(using: store.dubs) }
    }
    private func load() async {
        let adult = store.includeAdult
        let key = "home-trending-v1-\(adult)"
        let refresh = refreshID != appliedRefresh || retry > 0
        loading = true; failed = false
        defer { if !Task.isCancelled { loading = false } }
        let saved = await store.homeContentCache.load([Anime].self, key: key)
        guard !Task.isCancelled, store.includeAdult == adult else { return }
        items = saved?.value ?? []
        if !refresh, let saved, !saved.needsRefresh() { return }
        do {
            let page = try await store.aniList.browse(DiscoveryFilters(category: .trending), page: 1, refresh: refresh || saved != nil, includeAdult: adult)
            guard !Task.isCancelled, store.includeAdult == adult else { return }
            items = page.media ?? []; appliedRefresh = refreshID
            await store.homeContentCache.save(HomeContentSnapshot(items), key: key)
        } catch is CancellationError {} catch { if !Task.isCancelled { failed = true } }
    }
}

struct PlainTrendingAnimeWidget: View {
    let anime: [Anime]
    @Environment(\.horizontalSizeClass) private var sizeClass
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            NavigationLink(value: DiscoveryRoute(category: .trending, selection: .current())) {
                WidgetHeading(title: "Trending anime")
            }.buttonStyle(.plain)
            if !anime.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(Array(anime.prefix(10))) { anime in
                            AnimeCard(anime: anime, posterWidth: sizeClass == .regular ? 184 : 164)
                        }
                    }
                }
            } else { Text("Trending titles will appear when the catalog is available.").font(.caption).foregroundStyle(.secondary) }
        }.accessibilityIdentifier("plain-trending-anime-widget")
    }
}

struct TopTrendingAnimeWidget: View {
    let anime: [Anime]
    var selection = SeasonSelection.current()
    @EnvironmentObject private var store: AppStore
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var editing: Anime?
    @State private var settings = false
    private var width: CGFloat { sizeClass == .regular ? 188 : 164 }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            NavigationLink(value: DiscoveryRoute(category: .trending, selection: selection)) {
                WidgetHeading(title: "Top 10 Trending Anime")
            }.buttonStyle(.plain).accessibilityIdentifier("explore-category-topTen")
            if !anime.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(Array(anime.prefix(10).enumerated()), id: \.element.id) { index, show in
                            rankedPoster(show, rank: index + 1)
                        }
                    }.padding(.vertical, 4)
                }
            } else { Text("Trending titles will appear when the catalog is available.").font(.caption).foregroundStyle(.secondary) }
        }.accessibilityIdentifier("explore-top-ten-widget")
            .sheet(item: $editing) { TrackingEditorView(anime: $0, entry: store.entry(for: $0.id)) }
            .appSettingsSheet(isPresented: $settings)
    }
    private func rankedPoster(_ anime: Anime, rank: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            AnimeLink(id: anime.id) {
                VStack(alignment: .leading, spacing: 12) {
                    AnimeCover(anime: anime, width: width, cornerRadius: 0)
                    HStack(alignment: .top, spacing: 8) {
                        Text(String(format: "%02d", rank)).font(.subheadline.bold().monospacedDigit())
                            .foregroundStyle(Theme.accent).frame(width: 30, height: 30)
                            .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                            .accessibilityHidden(true)
                        Text(anime.displayTitle).font(.subheadline.weight(.semibold))
                            .lineLimit(2, reservesSpace: true).frame(maxWidth: .infinity, alignment: .leading)
                    }.padding(.horizontal, 10)
                }
            }.buttonStyle(.plain).foregroundStyle(.primary)
                .accessibilityLabel("Number \(rank). \(anime.displayTitle)")
            HStack(spacing: 4) {
                DiscoveryPosterSummary(anime: anime)
                Spacer(minLength: 0)
                Button {
                    if store.isSignedIn { editing = anime } else { settings = true }
                } label: {
                    Image(systemName: store.entry(for: anime.id) == nil ? "plus" : "checkmark")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accent).frame(width: 36, height: 44)
                }.buttonStyle(.plain).disabled(store.loadingLibrary || store.savingMedia.contains(anime.id))
                    .accessibilityLabel(store.entry(for: anime.id) == nil ? "Add \(anime.displayTitle) to library" : "Edit \(anime.displayTitle) in library")
            }.padding(.horizontal, 10).padding(.top, 2).padding(.bottom, 4)
        }.frame(width: width, alignment: .leading).background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.border, lineWidth: 1).allowsHitTesting(false) }
    }
}

struct AnimeStudioCollectionsWidget: View {
    var refreshID = 0
    @EnvironmentObject private var store: AppStore
    @Environment(\.exploreCollectionSize) private var cardSize
    @State private var collections: [AnimeStudioCollection] = []
    @State private var error: String?
    @State private var loading = false
    private var studios: [Studio] { collections.isEmpty ? AnimeStudioCollection.featured : collections.map(\.studio) }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Animation Studios").font(.title3.bold())
                Spacer()
                if loading { ProgressView().controlSize(.small) }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(Array(studios.enumerated()), id: \.element.id) { index, studio in
                        NavigationLink { StudioAnimeView(studio: studio) } label: {
                            AnimeCollectionTile(title: studio.name, image: collections.first { $0.id == studio.id }?.anime.first?.coverURL,
                                color: collectionColor(index), symbol: "film.stack", size: cardSize, genre: false)
                        }.buttonStyle(.plain).accessibilityIdentifier("explore-studio-\(studio.id)")
                    }
                }
            }
            if let error {
                HStack { Text(error).font(.caption).foregroundStyle(.secondary); Spacer(); Button("Retry") { Task { await load(refresh: true) } }.font(.caption.weight(.semibold)) }
            }
        }.accessibilityIdentifier("explore-studios-widget")
            .task(id: "\(store.includeAdult)-\(refreshID)") { await load(refresh: refreshID > 0) }
    }
    private func load(refresh: Bool) async {
        let adult = store.includeAdult
        collections = collections.map { AnimeStudioCollection(studio: $0.studio, anime: $0.anime.filter { adult || $0.isAdult != true }) }
        loading = true; error = nil
        defer { loading = false }
        let key = "studio-directory-v2-\(adult)"
        if let saved = await store.homeContentCache.load([AnimeStudioCollection].self, key: key) {
            guard !Task.isCancelled, store.includeAdult == adult else { return }
            collections = saved.value
            if !refresh, Date().timeIntervalSince(saved.savedAt) < 3600 { return }
        }
        do {
            let result = try await store.aniList.studioCollections(includeAdult: adult, refresh: refresh)
            guard !Task.isCancelled, store.includeAdult == adult else { return }
            collections = result
            await store.homeContentCache.save(HomeContentSnapshot(result), key: key)
        } catch is CancellationError { } catch { if !Task.isCancelled { self.error = collections.isEmpty ? "Artwork unavailable. Collections still open." : "Showing saved studio artwork." } }
    }
}

struct AnimeGenreCollectionsWidget: View {
    let anime: [Anime]
    @EnvironmentObject private var store: AppStore
    @Environment(\.exploreCollectionSize) private var cardSize
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Anime Genres").font(.title3.bold())
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(Array(DiscoveryGenres.all.enumerated()), id: \.element) { index, genre in
                        NavigationLink {
                            DiscoveryBrowseView(category: .trending, titleOverride: genre, initialGenre: genre)
                        } label: {
                            AnimeCollectionTile(title: genre,
                                image: anime.first { store.isVisible($0) && ($0.genres ?? []).contains(genre) }?.coverURL,
                                color: collectionColor(index + 2), symbol: "sparkles", size: cardSize, genre: true)
                        }.buttonStyle(.plain).accessibilityIdentifier("explore-genre-" + genre)
                    }
                }
            }
        }.accessibilityIdentifier("explore-genres-widget")
    }
}

private struct WidgetHeading: View {
    let title: String
    var body: some View {
        HStack { Text(title).font(.title3.bold()); Spacer(); Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.secondary) }
            .frame(minHeight: 44).foregroundStyle(.primary)
    }
}

private struct AnimeCollectionTile: View {
    let title: String
    let image: URL?
    let color: Color
    let symbol: String
    let size: ExploreCollectionSize
    let genre: Bool
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var width: CGFloat {
        switch size {
        case .small: return sizeClass == .regular ? 152 : 132
        case .medium: return sizeClass == .regular ? 188 : 164
        case .large: return sizeClass == .regular ? 220 : 190
        }
    }
    private var height: CGFloat {
        if genre { return width * (size == .small ? 0.64 : 0.72) }
        return width * (size == .small ? 1.15 : 1.45)
    }
    var body: some View {
        ZStack(alignment: .bottom) {
            ArtworkImage(url: image, pointSize: max(width, height)) { $0.resizable().scaledToFill() } placeholder: {
                ZStack { color.opacity(0.35); Image(systemName: symbol).font(size == .small ? .title : .largeTitle).foregroundStyle(.white.opacity(0.4)) }
            }.frame(width: width, height: height).clipped()
            LinearGradient(colors: [.clear, color.opacity(0.65), color.opacity(0.96)], startPoint: .center, endPoint: .bottom)
            VStack(spacing: 6) {
                Text(title).font(size == .small ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                    .lineLimit(2).multilineTextAlignment(.center)
                if size == .large && !genre { Text("COLLECTION").font(.caption2).tracking(2).opacity(0.8) }
            }.foregroundStyle(.white).padding(size == .small ? 10 : 14)
        }.frame(width: width, height: height).clipShape(RoundedRectangle(cornerRadius: size == .small ? 12 : 16))
            .accessibilityElement(children: .ignore).accessibilityLabel(title + " collection")
    }
}

private func collectionColor(_ index: Int) -> Color {
    let colors: [Color] = [.red, .purple, .teal, .indigo, .orange, .blue, .pink, .green]
    return colors[index % colors.count]
}
