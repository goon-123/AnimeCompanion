import SwiftUI
import UIKit
import AnimeCore

/// One rendering path for every widget, whether it is placed on Home or Explore.
struct HomeWidgetContent: View {
    let section: HomeSection
    @Binding var saved: String
    var editing = false
    var refreshID = 0
    var activationID = 0
    @EnvironmentObject private var anime: AppStore
    @EnvironmentObject private var playback: PlaybackStore
    @EnvironmentObject private var books: MangaBakaStore
    @EnvironmentObject private var reading: MangaReadingStore
    @EnvironmentObject private var navigation: AppNavigationStore
    @EnvironmentObject private var sourceLinks: MangaSourceLinkStore
    @EnvironmentObject private var extensions: MangaExtensionStore
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.homeVisuals) private var visuals
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("manga.showMatureSources") private var matureSources = false
    @State private var settings = false
    @State private var watching: Anime?
    private var preferences: HomePreferences { HomePreferences(saved: saved) }
    private var cardColumns: [GridItem] {
        [GridItem(sizeClass == .regular && !textSize.isAccessibilitySize ? .adaptive(minimum: visuals.gridMinimum) : .flexible(), spacing: 12, alignment: .top)]
    }
    private var shows: [ContinueWatchingItem] {
        Array(ContinueWatchingItem.items(entries: anime.watching, playback: playback.progress)
            .prefix(preferences.size(for: .watching).itemLimit))
    }
    private var recent: [MangaReadingRecord] {
        guard !extensions.loading else { return [] }
        return Array(reading.state.records.filter { record in
            let mature = record.title.source.adult || extensions.installed(record.title.source.extensionID)?.descriptor.adult == true
            return record.lastReadAt != nil && (matureSources || !mature)
        }
            .sorted { ($0.lastReadAt ?? .distantPast) > ($1.lastReadAt ?? .distantPast) }.prefix(preferences.size(for: .reading).itemLimit))
    }
    private var trackedBooks: [MangaBakaLibraryEntry] {
        let resumed = Set(recent.map { $0.title.id })
        return Array(books.library.map { books.entries[$0.id] ?? $0 }.filter { entry in
            guard ["reading", "rereading"].contains(entry.state), let series = entry.series,
                  series.isVisible(contentFilter: anime.mangaBakaContent) else { return false }
            if let target = books.sourceLinkTarget(for: series), let link = sourceLinks.link(for: target), resumed.contains(link.title.id) { return false }
            return true
        }.prefix(max(0, preferences.size(for: .reading).itemLimit - recent.count)))
    }
    private var upcoming: [Anime] {
        Array(anime.watching.compactMap(\.media).filter { ($0.nextAiringEpisode?.date ?? .distantPast) > .now }
            .sorted { ($0.nextAiringEpisode?.date ?? .distantFuture) < ($1.nextAiringEpisode?.date ?? .distantFuture) }.prefix(preferences.size(for: .airing).itemLimit))
    }
    var body: some View {
        widget(section)
            .environment(\.posterArtworkBadgesEnabled, false)
            .animation(AppMotion.content(reduceMotion), value: shows.map(\.id))
            .animation(AppMotion.content(reduceMotion), value: recent.map(\.id))
            .animation(AppMotion.content(reduceMotion), value: trackedBooks.map(\.id))
            .appSettingsSheet(isPresented: $settings)
            .sheet(item: $watching) { WatchAnimeView(anime: $0) }
    }
    private func refreshBooks() async { if books.connected { await books.loadLibrary(state: nil, refresh: true) } }
    @ViewBuilder private func widget(_ section: HomeSection) -> some View {
        switch section {
        case .greeting: header
        case .search: CompanionSearchLink().accessibilityIdentifier("home-search")
        case .featureLinks: HomeFeatureShortcuts(savedOverride: $saved)
        case .welcome:
            if !anime.isSignedIn && !books.connected && recent.isEmpty { welcome }
            else { empty("Welcome & setup", detail: "This widget appears when no library is connected.", symbol: "sparkles") }
        case .syncStatus: syncStatus
        case .weekly: AiringThisWeekView()
        case .news: HomeNewsSection(refreshID: refreshID)
        case .community: HomeCommunityWidget(refreshID: refreshID, activationID: activationID)
        case .trendingAnime: HomeTrendingAnimeWidget(refreshID: refreshID, activationID: activationID)
        case .trendingAnimePlain: HomeTrendingAnimeWidget(refreshID: refreshID, activationID: activationID, ranked: false)
        case .watching: watchSection
        case .reading: readingSection
        case .airing: airingSection
        case .shortcuts: shortcuts
        case .today: HomeTodayWidget(limit: preferences.size(for: .today).itemLimit, refreshID: refreshID)
        case .catchUp, .libraryStats, .planned, .randomPick:
            HomeLibraryWidget(section: section, limit: preferences.size(for: section).itemLimit)
        case .savedNews: HomeSavedStoriesWidget(limit: preferences.size(for: .savedNews).itemLimit)
        case .seasonCountdown, .nextSeason, .returningSeries, .tonightPick, .hallOfFame:
            HomeSeasonWidget(section: section, limit: preferences.size(for: section).itemLimit, refreshID: refreshID, activationID: activationID)
        case .seasonSpotlight, .nextEpisode, .watchlistBanners:
            HomeBannerWidget(section: section, limit: preferences.size(for: section).itemLimit, refreshID: refreshID, activationID: activationID)
        }
    }
    private var syncStatus: some View {
        VStack(alignment: .leading, spacing: 10) {
            if anime.loadingLibrary { ProgressView("Syncing AniList…").font(.caption) }
            if let error = anime.libraryError, anime.isSignedIn {
                NoticeView(message: error) { Task { await anime.reloadLibrary() } }
            }
            if let error = reading.error { NoticeView(message: error) }
            if books.loadingLibrary {
                ProgressView("Syncing reading library…").font(.caption).accessibilityIdentifier("home-reading-sync")
            }
            if let error = books.libraryError, books.connected {
                NoticeView(message: error) { Task { await refreshBooks() } }
            }
            if editing && !anime.loadingLibrary && !books.loadingLibrary && anime.libraryError == nil && books.libraryError == nil && reading.error == nil {
                empty("Library sync status", detail: "Loading and retry messages appear here when needed.", symbol: "arrow.triangle.2.circlepath")
            } else if !editing && !anime.loadingLibrary && !books.loadingLibrary && anime.libraryError == nil && books.libraryError == nil && reading.error == nil {
                Label("Libraries are up to date", systemImage: "checkmark.circle").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(Date.now, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                .font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
            Text("Your daily companion.").font(.title2.weight(.bold)).tracking(-0.4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    private var welcome: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Make yourself at home", systemImage: "sparkles").font(.headline)
            Text("Connect a library to bring your watchlist and reading progress here. You can explore without an account.")
                .font(.subheadline).foregroundStyle(.secondary)
            HStack {
                Button("Connect a library") { settings = true }.buttonStyle(.borderedProminent).foregroundStyle(Theme.background)
                Button("Explore") { navigation.open(.explore) }.buttonStyle(.bordered)
            }
        }.companionPanel().accessibilityIdentifier("home-welcome")
    }
    private var watchSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeading(.watching, destination: .library)
            if (anime.restoring || anime.loadingLibrary) && shows.isEmpty { HomeRowPlaceholder(height: visuals.value(136, 180)) }
            else if shows.isEmpty {
                empty("Your watching list starts here.", detail: "Add an anime from Explore, or connect AniList.", symbol: "play.rectangle")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(shows) { entry in
                            if let value = entry.entry.media {
                                HomeContinueWatchingCard(anime: value, entry: entry.entry, episode: entry.episode, resume: entry.resume) { watching = value }
                                    .containerRelativeFrame(.horizontal, alignment: .leading) { width, _ in min(visuals.watchingCardLimit, width * 0.90) }
                            }
                        }
                    }.padding(.vertical, 1)
                }
            }
        }
    }
    private var readingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeading(.reading, destination: .library)
            if recent.isEmpty && trackedBooks.isEmpty && (reading.loading || books.restoring || books.loadingLibrary || (!reading.state.records.isEmpty && extensions.loading)) {
                HomeRowPlaceholder(height: visuals.value(104, 144))
            } else if recent.isEmpty && trackedBooks.isEmpty {
                empty("Your next chapter is waiting.", detail: "Read from a source to see your saved place here.", symbol: "book")
            } else {
                LazyVGrid(columns: cardColumns, alignment: .leading, spacing: 12) {
                    ForEach(recent) { record in
                        NavigationLink { MangaTitleDetailView(title: record.title, resumeOnOpen: true) } label: {
                            HomeContinueReadingCard(record: record)
                        }.buttonStyle(.plain).accessibilityIdentifier("home-read-" + record.id)
                    }
                    ForEach(trackedBooks) { entry in
                        if let series = entry.series {
                            NavigationLink(value: MangaBakaSeriesRoute(series: series)) {
                                HomeTrackedReadingCard(entry: entry, series: series)
                            }.buttonStyle(.plain).accessibilityIdentifier("home-reading-library-\(entry.id)")
                        }
                    }
                }
            }
        }
    }
    private var airingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeading(.airing, destination: .schedule)
            if upcoming.isEmpty {
                empty("See what’s airing.", detail: "Upcoming original broadcasts from your watching list will appear here.", symbol: "calendar")
            } else {
                LazyVGrid(columns: cardColumns, alignment: .leading, spacing: 12) {
                    ForEach(upcoming) { value in
                        if let next = value.nextAiringEpisode {
                            AnimeLink(id: value.id) {
                                HomeUpNextCard(anime: value, episode: next)
                            }.buttonStyle(.plain).accessibilityIdentifier("home-up-next-\(value.id)")
                        }
                    }
                }
            }
        }
    }
    private var shortcuts: some View {
        VStack(alignment: .leading, spacing: 12) {
            CompanionSectionHeading(title: HomeSection.shortcuts.title)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: visuals.shortcutMinimum), spacing: 12)], spacing: 12) {
                quickLink("Reading sources", detail: "Extensions & history", symbol: "book.closed", tab: .manga)
                NavigationLink { CommunityFeedView() } label: { shortcutLabel("Community", detail: "Conversations & episodes", symbol: "bubble.left.and.bubble.right") }
                NavigationLink { SourcesSettingsView() } label: { shortcutLabel("Sources & playback", detail: "Manage your connections", symbol: "puzzlepiece.extension") }.accessibilityIdentifier("home-sources")
                NavigationLink { MangaBakaRecommendationsView().mangaBakaNavigation() } label: { shortcutLabel("For your next read", detail: "MangaBaka recommendations", symbol: "sparkles") }
                Button { settings = true } label: { shortcutLabel("Settings", detail: "Accounts & preferences", symbol: "gearshape") }
            }.buttonStyle(.plain)
        }
    }
    private func sectionHeading(_ section: HomeSection, destination: AppTab) -> some View {
        HStack {
            CompanionSectionHeading(title: section.title)
            Button("See all") { navigation.open(destination) }.font(visuals.actionTextFont).frame(minHeight: 44)
                .accessibilityLabel("\(section.title), see all")
        }
    }
    private func empty(_ title: String, detail: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(visuals.iconFont).foregroundStyle(Theme.accent).frame(width: visuals.value(26, 40))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).companionPanel()
    }
    private func quickLink(_ title: String, detail: String, symbol: String, tab: AppTab) -> some View {
        Button { navigation.open(tab) } label: { shortcutLabel(title, detail: detail, symbol: symbol) }
            .accessibilityIdentifier("home-open-" + tab.rawValue)
    }
    private func shortcutLabel(_ title: String, detail: String, symbol: String) -> some View {
        HStack(spacing: visuals.value(10, 16)) {
            Image(systemName: symbol).font(visuals.iconFont).foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(visuals.actionTextFont).foregroundStyle(.primary)
                Text(detail).font(visuals.enlarged ? .caption : .caption2).foregroundStyle(.secondary).lineLimit(2)
            }
        }.frame(maxWidth: .infinity, minHeight: visuals.value(48, 68), alignment: .leading).companionPanel(padding: visuals.value(12, 16)).contentShape(Rectangle())
    }
}
