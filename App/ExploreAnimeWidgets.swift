import SwiftUI
import AnimeCore

struct TopTrendingAnimeWidget: View {
    let anime: [Anime]
    var selection = SeasonSelection.current()
    @EnvironmentObject private var store: AppStore
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var editing: Anime?
    @State private var settings = false
    private var width: CGFloat { sizeClass == .regular ? 220 : 192 }
    private var posterWidth: CGFloat { sizeClass == .regular ? 176 : 152 }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            NavigationLink(value: DiscoveryRoute(category: .trending, selection: selection)) {
                WidgetHeading(title: "Top 10 Trending Anime")
            }.buttonStyle(.plain).accessibilityIdentifier("explore-category-trending")
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
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .bottomLeading) {
                Text(String(rank)).font(.system(size: sizeClass == .regular ? 190 : 166, weight: .black, design: .rounded))
                    .tracking(-14).foregroundStyle(.primary).offset(x: -4, y: 28).accessibilityHidden(true)
                AnimeLink(id: anime.id) {
                    AnimeCover(anime: anime, width: posterWidth, cornerRadius: 13)
                }.buttonStyle(.plain).frame(maxWidth: .infinity, alignment: .trailing)
                    .accessibilityLabel("Number \(rank). \(anime.displayTitle)")
            }.frame(width: width, height: posterWidth * 1.45).clipped()
                .overlay(alignment: .topTrailing) {
                    Button {
                        if store.isSignedIn { editing = anime } else { settings = true }
                    } label: {
                        Image(systemName: store.entry(for: anime.id) == nil ? "plus" : "checkmark")
                            .font(.headline.bold()).foregroundStyle(Theme.highlight).frame(width: 44, height: 44)
                            .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 11))
                    }.buttonStyle(.plain).disabled(store.loadingLibrary || store.savingMedia.contains(anime.id))
                        .accessibilityLabel(store.entry(for: anime.id) == nil ? "Add \(anime.displayTitle) to library" : "Edit \(anime.displayTitle) in library")
                }
            Text(anime.displayTitle).font(.subheadline.weight(.semibold)).lineLimit(2, reservesSpace: true)
                .padding(.leading, width - posterWidth)
        }.frame(width: width, alignment: .leading)
    }
}

struct AnimeStudioCollectionsWidget: View {
    var refreshID = 0
    @EnvironmentObject private var store: AppStore
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
                                color: collectionColor(index), symbol: "film.stack")
                        }.buttonStyle(.plain).accessibilityIdentifier("explore-studio-\(studio.id)")
                    }
                }
            }
            if let error { NoticeView(message: error) { Task { await load(refresh: true) } } }
        }.accessibilityIdentifier("explore-studios-widget")
            .task(id: "\(store.includeAdult)-\(refreshID)") { await load(refresh: refreshID > 0) }
    }
    private func load(refresh: Bool) async {
        let adult = store.includeAdult
        collections = collections.map { AnimeStudioCollection(studio: $0.studio, anime: $0.anime.filter { adult || $0.isAdult != true }) }
        loading = true; error = nil
        defer { loading = false }
        do {
            let result = try await store.aniList.studioCollections(includeAdult: adult, refresh: refresh)
            guard !Task.isCancelled, store.includeAdult == adult else { return }
            collections = result
        } catch is CancellationError { } catch { if !Task.isCancelled { self.error = "Studio artwork is unavailable. You can still open each collection." } }
    }
}

struct AnimeGenreCollectionsWidget: View {
    let anime: [Anime]
    @EnvironmentObject private var store: AppStore
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
                                color: collectionColor(index + 2), symbol: "sparkles")
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
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var width: CGFloat { sizeClass == .regular ? 210 : 164 }
    var body: some View {
        ZStack(alignment: .bottom) {
            ArtworkImage(url: image, pointSize: 400) { $0.resizable().scaledToFill() } placeholder: {
                ZStack { color.opacity(0.35); Image(systemName: symbol).font(.system(size: 46)).foregroundStyle(.white.opacity(0.4)) }
            }.frame(width: width, height: width * 1.48).clipped()
            LinearGradient(colors: [.clear, color.opacity(0.65), color.opacity(0.96)], startPoint: .center, endPoint: .bottom)
            VStack(spacing: 8) {
                Text(title.uppercased()).font(.subheadline.weight(.semibold)).tracking(1).multilineTextAlignment(.center)
                Text("COLLECTION").font(.caption2).tracking(3).opacity(0.8)
            }.foregroundStyle(.white).padding(16)
        }.frame(width: width, height: width * 1.48).clipShape(RoundedRectangle(cornerRadius: 16))
            .accessibilityElement(children: .ignore).accessibilityLabel(title + " collection")
    }
}

private func collectionColor(_ index: Int) -> Color {
    let colors: [Color] = [.red, .purple, .teal, .indigo, .orange, .blue, .pink, .green]
    return colors[index % colors.count]
}
