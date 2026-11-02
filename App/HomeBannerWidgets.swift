import SwiftUI
import AnimeCore

/// Optional image-led shelves reuse AniList's catalog cache and the visible library.
struct HomeBannerWidget: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.homeVisuals) private var visuals
    @Environment(\.homeWidgetLayout) private var layout
    let section: HomeSection
    let limit: Int
    let refreshID: Int
    var activationID = 0
    @State private var appliedRefreshID = 0
    @State private var seasonal: [Anime] = []
    @State private var loading = false
    @State private var error: String?
    @State private var attempt = UUID()
    @State private var retry = 0
    private var watching: [Anime] {
        HomeLibraryContent.unique(store.visibleEntries).filter { $0.status == .watching || $0.status == .rewatching }
            .sorted { ($0.updatedAt ?? 0) > ($1.updatedAt ?? 0) }.compactMap(\.media)
    }
    private func items(at date: Date) -> [Anime] {
        switch section {
        case .seasonSpotlight: return Array(seasonal.filter { store.isVisible($0) }.prefix(limit))
        case .nextEpisode:
            return Array(watching.filter { ($0.nextAiringEpisode?.date ?? .distantPast) > date }
                .sorted { ($0.nextAiringEpisode?.date ?? .distantFuture) < ($1.nextAiringEpisode?.date ?? .distantFuture) }.prefix(1))
        default: return Array(watching.prefix(limit))
        }
    }
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            VStack(alignment: .leading, spacing: 12) {
                CompanionSectionHeading(title: section.title, subtitle: subtitle)
                let values = items(at: timeline.date)
                if !values.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 12) {
                            ForEach(values) { anime in
                                AnimeLink(id: anime.id) {
                                    HomeAnimeBanner(anime: anime, caption: caption(for: anime))
                                        .containerRelativeFrame(.horizontal, alignment: .leading) { width, _ in min(layout == .compact ? visuals.value(300, 400) : (layout == .poster ? visuals.value(340, 460) : visuals.animeBannerLimit), width * (section == .nextEpisode ? 1 : 0.92)) }
                                }.buttonStyle(.plain).accessibilityIdentifier("home-banner-\(section.rawValue)-\(anime.id)")
                            }
                        }.scrollTargetLayout()
                    }.scrollTargetBehavior(.viewAligned)
                } else if loading {
                    ProgressView("Loading spotlight…").frame(maxWidth: .infinity, minHeight: 120).companionPanel()
                } else {
                    HomeWidgetEmpty(symbol: section.symbol, title: emptyTitle,
                        detail: section == .seasonSpotlight ? "Popular seasonal anime will appear here." : "Add anime to your watching list to bring it here.")
                }
                if let error {
                    NoticeView(message: error) { retry += 1 }
                }
            }
        }.task(id: "\(section)-\(store.includeAdult)-\(refreshID)-\(activationID)-\(retry)") {
            guard section == .seasonSpotlight else { return }
            let current = UUID(); attempt = current; loading = true; error = nil
            defer { if attempt == current { loading = false } }
            if let saved = await store.homeCatalog.cached(.current(), includeAdult: store.includeAdult), attempt == current, !Task.isCancelled {
                seasonal = saved.value
            }
            do {
                let result = try await store.homeCatalog.season(.current(), includeAdult: store.includeAdult, refresh: refreshID != appliedRefreshID || retry > 0)
                try Task.checkCancellation(); guard attempt == current else { return }
                seasonal = result.value; appliedRefreshID = refreshID
            } catch is CancellationError {} catch { if attempt == current { self.error = error.localizedDescription } }
        }
    }
    private var subtitle: String {
        switch section {
        case .seasonSpotlight: return SeasonSelection.current().label + " · Discover something new"
        case .nextEpisode: return "The next original broadcast from your watching list"
        default: return "Your current anime, front and center"
        }
    }
    private var emptyTitle: String {
        section == .nextEpisode ? "No upcoming broadcast announced." : (section == .seasonSpotlight ? "Your seasonal spotlight is waiting." : "Make room for your favorites.")
    }
    private func caption(for anime: Anime) -> String {
        if section == .nextEpisode, let next = anime.nextAiringEpisode { return "EPISODE \(next.episode) · UP NEXT" }
        if section == .seasonSpotlight { return SeasonSelection.current().label.uppercased() }
        let progress = store.entry(for: anime.id)?.progressValue ?? 0
        return "WATCHING · \(progress)\(anime.episodes.map { "/\($0)" } ?? "") EPISODES"
    }
}

struct HomeAnimeBanner: View {
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.homeVisuals) private var visuals
    @Environment(\.homeWidgetLayout) private var layout
    let anime: Anime
    let caption: String
    var body: some View {
        Group {
            if layout == .banner { cinematic }
            else { tile(compact: layout == .compact) }
        }
    }
    private func tile(compact: Bool) -> some View {
        let width = compact ? visuals.value(44, 60) : visuals.value(88, 104)
        return HStack(spacing: 14) {
            ArtworkImage(url: anime.coverURL, pointSize: width * 1.45) { $0.resizable().scaledToFill() } placeholder: { Theme.accent.opacity(0.15) }
                .frame(width: width, height: width * 1.45).clipped().clipShape(RoundedRectangle(cornerRadius: 10)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 7) {
                Text(caption).font(.caption2.weight(.bold)).foregroundStyle(Theme.accent).lineLimit(2)
                Text(anime.displayTitle).font(compact ? .subheadline.weight(.semibold) : .headline).foregroundStyle(.primary).lineLimit(compact ? 2 : 3)
                if caption.contains("UP NEXT"), let next = anime.nextAiringEpisode {
                    HStack(spacing: 4) { Image(systemName: "clock"); Text(next.date, style: .relative).monospacedDigit() }
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.companionPanel(padding: compact ? 12 : 14).accessibilityElement(children: .combine)
    }
    private var cinematic: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomLeading) {
                LinearGradient(colors: [Theme.accent.opacity(0.40), Theme.secondarySurface], startPoint: .topLeading, endPoint: .bottomTrailing)
                ArtworkImage(url: anime.bannerImage.flatMap(URL.init(string:)) ?? anime.coverURL, pointSize: geometry.size.width) { image in
                    image.resizable().scaledToFill()
                } placeholder: { Image(systemName: "sparkles").font(.largeTitle).foregroundStyle(Theme.accent.opacity(0.35)) }
                    .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                LinearGradient(colors: [.black.opacity(0.05), .black.opacity(0.93)], startPoint: .top, endPoint: .bottom)
                HStack(alignment: .bottom, spacing: 12) {
                    ArtworkImage(url: anime.coverURL, pointSize: visuals.bannerCover * 1.45) { $0.resizable().scaledToFill() } placeholder: { Theme.accent.opacity(0.25) }
                        .frame(width: visuals.bannerCover, height: visuals.value(80, 122)).clipShape(RoundedRectangle(cornerRadius: 9)).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(caption).font(.caption2.weight(.bold)).foregroundStyle(.white.opacity(0.82))
                        Text(anime.displayTitle).font(.headline).foregroundStyle(.white).lineLimit(textSize.isAccessibilitySize ? 4 : 2)
                        if caption.contains("UP NEXT"), let next = anime.nextAiringEpisode {
                            HStack(spacing: 4) {
                                Image(systemName: "clock")
                                Text("Airs in")
                                Text(next.date, style: .relative).monospacedDigit()
                            }.font(.caption.weight(.semibold)).foregroundStyle(.white)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "arrow.up.right").font(visuals.toolbarIconFont).foregroundStyle(.white.opacity(0.85)).accessibilityHidden(true)
                }.padding(16)
            }.clipShape(RoundedRectangle(cornerRadius: Theme.radius))
        }.frame(height: textSize.isAccessibilitySize ? visuals.value(300, 420) : visuals.bannerHeight).accessibilityElement(children: .combine)
    }
}
