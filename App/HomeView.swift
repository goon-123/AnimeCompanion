import SwiftUI
import AnimeCore

struct HomeView: View {
    @EnvironmentObject private var anime: AppStore
    @EnvironmentObject private var books: MangaBakaStore
    @EnvironmentObject private var reading: MangaReadingStore
    @EnvironmentObject private var navigation: AppNavigationStore
    @EnvironmentObject private var sourceLinks: MangaSourceLinkStore
    @EnvironmentObject private var extensions: MangaExtensionStore
    @AppStorage(HomePreferences.storageKey) private var sections = ""
    @AppStorage("manga.showMatureSources") private var matureSources = false
    @State private var customize = false
    @State private var settings = false
    @State private var watching: Anime?
    private var preferences: HomePreferences { HomePreferences(saved: sections) }
    private var shows: [LibraryEntry] {
        Array(anime.watching.filter { $0.media != nil }.sorted { ($0.updatedAt ?? 0) > ($1.updatedAt ?? 0) }.prefix(8))
    }
    private var recent: [MangaReadingRecord] {
        guard !extensions.loading else { return [] }
        return Array(reading.state.records.filter { record in
            let mature = record.title.source.adult || extensions.installed(record.title.source.extensionID)?.descriptor.adult == true
            return record.lastReadAt != nil && (matureSources || !mature)
        }
            .sorted { ($0.lastReadAt ?? .distantPast) > ($1.lastReadAt ?? .distantPast) }.prefix(6))
    }
    private var trackedBooks: [MangaBakaLibraryEntry] {
        let resumed = Set(recent.map { $0.title.id })
        return Array(books.library.map { books.entries[$0.id] ?? $0 }.filter { entry in
            guard ["reading", "rereading"].contains(entry.state), let series = entry.series,
                  series.isVisible(contentFilter: anime.mangaBakaContent) else { return false }
            if let target = books.sourceLinkTarget(for: series), let link = sourceLinks.link(for: target), resumed.contains(link.title.id) { return false }
            return true
        }.prefix(6))
    }
    private var upcoming: [Anime] {
        Array(anime.watching.compactMap(\.media).filter { ($0.nextAiringEpisode?.date ?? .distantPast) > .now }
            .sorted { ($0.nextAiringEpisode?.date ?? .distantFuture) < ($1.nextAiringEpisode?.date ?? .distantFuture) }.prefix(4))
    }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                header
                CompanionSearchLink().accessibilityIdentifier("home-search")
                if !anime.isSignedIn && !books.connected && recent.isEmpty { welcome }
                if let error = anime.libraryError, anime.isSignedIn {
                    NoticeView(message: error) { Task { await anime.reloadLibrary() } }
                }
                if let error = reading.error { NoticeView(message: error) }
                if let error = books.libraryError, books.connected {
                    NoticeView(message: error) { Task { await refreshBooks() } }
                }
                ForEach(preferences.visible) { section in
                    switch section {
                    case .watching: if anime.isSignedIn || anime.loadingLibrary { watchSection }
                    case .reading: if !recent.isEmpty || !trackedBooks.isEmpty { readingSection }
                    case .airing: if !upcoming.isEmpty { airingSection }
                    case .shortcuts: shortcuts
                    }
                }
            }.padding(20).padding(.bottom, 20).frame(maxWidth: 1180, alignment: .leading).frame(maxWidth: .infinity)
        }.background(Theme.background).navigationTitle("Home").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { AccountSwitcherButton() }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { customize = true } label: { Image(systemName: "slider.horizontal.3") }
                        .accessibilityLabel("Customize Home").accessibilityIdentifier("home-customize")
                }
            }
            .animeNavigation().mangaBakaNavigation()
            .navigationDestination(for: ExploreSearchRoute.self) { _ in UnifiedExploreSearchView().animeNavigation().mangaBakaNavigation() }
            .task {
                await reading.load(); await sourceLinks.load()
                if !reading.state.records.isEmpty { await extensions.load() }
            }
            .task(id: "\(books.connected)-\(books.connectionID)-\(books.revision)") { if books.connected { await books.loadLibrary(state: nil) } }
            .refreshable {
                async let shows: Void = refreshAnime()
                async let titles: Void = refreshBooks()
                _ = await (shows, titles)
            }
            .appSettingsSheet(isPresented: $settings)
            .sheet(isPresented: $customize) {
                AppNavigationStack {
                    HomeCustomizationView().toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { customize = false } } }
                }
            }
            .sheet(item: $watching) { WatchAnimeView(anime: $0) }
            .accessibilityIdentifier("home-dashboard")
    }
    private func refreshAnime() async { if anime.isSignedIn { await anime.reloadLibrary() } }
    private func refreshBooks() async { if books.connected { await books.loadLibrary(state: nil, refresh: true) } }
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Date.now, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                .font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
            Text("A little time for your world.").font(.largeTitle.weight(.bold)).tracking(-0.7)
                .fixedSize(horizontal: false, vertical: true)
            Text("Pick up a story. Find your next favorite.").font(.subheadline).foregroundStyle(.secondary)
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
            if anime.loadingLibrary && shows.isEmpty { ProgressView("Loading your library…").frame(minHeight: 70) }
            else if shows.isEmpty {
                empty("Your watching list starts here.", detail: "Add an anime from Explore, or connect AniList.", symbol: "play.rectangle")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 14) {
                        ForEach(shows) { entry in
                            if let value = entry.media { watchCard(value, entry: entry) }
                        }
                    }.padding(.vertical, 1)
                }
            }
        }
    }
    private func watchCard(_ value: Anime, entry: LibraryEntry) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            AnimeLink(id: value.id) {
                HStack(alignment: .top, spacing: 12) {
                    AnimeCover(anime: value, width: 66, cornerRadius: 10)
                    VStack(alignment: .leading, spacing: 7) {
                        Text(value.displayTitle).font(.headline).lineLimit(2)
                        Text("Episode \(entry.progressValue)" + (value.episodes.map { " of \($0)" } ?? " watched"))
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        if let total = value.episodes, total > 0 {
                            ProgressView(value: min(1, Double(entry.progressValue) / Double(total))).tint(Theme.accent)
                                .accessibilityLabel("Watched progress")
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.foregroundStyle(.primary).contentShape(Rectangle())
            }.buttonStyle(.plain)
            let episode = PlaybackEpisodeSelection.initial(anime: value, entry: entry, resumeEpisode: nil)
            Button { watching = value } label: {
                Label(value.format == "MOVIE" ? "Watch movie" : "Continue · Episode \(episode)", systemImage: "play.fill")
                    .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
            }.buttonStyle(.borderedProminent).foregroundStyle(Theme.background).disabled(value.status == "NOT_YET_RELEASED")
                .accessibilityIdentifier("home-watch-\(value.id)")
        }.frame(width: 275).companionPanel()
    }
    private var readingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeading(.reading, destination: .library)
            if recent.isEmpty && trackedBooks.isEmpty {
                empty("Your next chapter is waiting.", detail: "Read from a source to see your saved place here.", symbol: "book")
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 270), spacing: 14)], spacing: 14) {
                    ForEach(recent) { record in
                        NavigationLink { MangaTitleDetailView(title: record.title, resumeOnOpen: true) } label: {
                            HStack(spacing: 12) {
                                MangaCover(title: record.title, width: 52).frame(width: 52, height: 76).clipShape(RoundedRectangle(cornerRadius: 8))
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(record.title.manga.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                                    if let url = record.lastChapterURL, let position = record.position(for: url) {
                                        Text(position.chapterName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                        Text("Page \(position.pageIndex + 1) of \(position.pageCount)").font(.caption2.monospacedDigit()).foregroundStyle(Theme.accent)
                                    }
                                    Text(record.title.source.name).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                            }.foregroundStyle(.primary).companionPanel(padding: 12).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityIdentifier("home-read-" + record.id)
                    }
                    ForEach(trackedBooks) { entry in
                        if let series = entry.series {
                            NavigationLink(value: MangaBakaSeriesRoute(series: series)) {
                                HStack(spacing: 12) {
                                    MangaBakaCover(series: series, width: 52)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(series.displayTitle).font(.subheadline.weight(.semibold)).lineLimit(2)
                                        Text("Chapter " + (entry.chapter ?? 0).formatted()).font(.caption.monospacedDigit()).foregroundStyle(Theme.accent)
                                        Text(series.formatLabel + " · MangaBaka").font(.caption2).foregroundStyle(.secondary)
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                                }.foregroundStyle(.primary).companionPanel(padding: 12).contentShape(Rectangle())
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
                VStack(spacing: 0) {
                    ForEach(upcoming) { value in
                        if let next = value.nextAiringEpisode {
                            AnimeLink(id: value.id) {
                                HStack(spacing: 12) {
                                    AnimeCover(anime: value, width: 40, cornerRadius: 7)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(value.displayTitle).font(.subheadline.weight(.semibold)).lineLimit(2)
                                        Text("Episode \(next.episode) · Original broadcast").font(.caption2).foregroundStyle(.secondary)
                                        Text(next.date, format: .dateTime.weekday(.abbreviated).hour().minute()).font(.caption).foregroundStyle(Theme.accent)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                                }.foregroundStyle(.primary).padding(.vertical, 10).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            if value.id != upcoming.last?.id { Divider() }
                        }
                    }
                }.companionPanel(padding: 14)
            }
        }
    }
    private var shortcuts: some View {
        VStack(alignment: .leading, spacing: 12) {
            CompanionSectionHeading(title: HomeSection.shortcuts.title)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 12)], spacing: 12) {
                quickLink("Reading sources", detail: "Extensions & history", symbol: "book.closed", tab: .manga)
                quickLink("Release calendar", detail: "Original & English dub", symbol: "calendar", tab: .schedule)
                quickLink("News", detail: "Headlines & your stories", symbol: "newspaper", tab: .news)
                NavigationLink { SourcesSettingsView() } label: { shortcutLabel("Sources & playback", detail: "Manage your connections", symbol: "puzzlepiece.extension") }.accessibilityIdentifier("home-sources")
                NavigationLink { MangaBakaRecommendationsView().mangaBakaNavigation() } label: { shortcutLabel("For your next read", detail: "MangaBaka recommendations", symbol: "sparkles") }
                Button { settings = true } label: { shortcutLabel("Settings", detail: "Accounts & preferences", symbol: "gearshape") }
            }.buttonStyle(.plain)
        }
    }
    private func sectionHeading(_ section: HomeSection, destination: AppTab) -> some View {
        HStack {
            CompanionSectionHeading(title: section.title)
            Button("See all") { navigation.open(destination) }.font(.caption.weight(.semibold)).frame(minHeight: 44)
                .accessibilityLabel("\(section.title), see all")
        }
    }
    private func empty(_ title: String, detail: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.title3).foregroundStyle(Theme.accent).frame(width: 26)
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
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: symbol).font(.title3).foregroundStyle(Theme.accent)
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
            Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
        }.frame(maxWidth: .infinity, minHeight: 100, alignment: .leading).companionPanel(padding: 14).contentShape(Rectangle())
    }
}

struct HomeCustomizationView: View {
    @AppStorage(HomePreferences.storageKey) private var saved = ""
    private var preferences: HomePreferences { HomePreferences(saved: saved) }
    var body: some View {
        List {
            Section {
                ForEach(preferences.order) { section in
                    Toggle(isOn: Binding(get: { !preferences.hidden.contains(section) }, set: { shown in
                        var value = preferences; value.setVisible(section, shown); saved = value.saved
                    })) { Label(section.title, systemImage: section.symbol) }
                        .disabled(preferences.visible.count == 1 && !preferences.hidden.contains(section))
                        .accessibilityIdentifier("home-visible-" + section.rawValue)
                }.onMove { offsets, destination in
                    var value = preferences; value.order.move(fromOffsets: offsets, toOffset: destination); saved = value.saved
                }
            } header: { Text("Make it yours") } footer: { Text("Drag to reorder sections. Hidden sections keep their data. Home uses your existing library and saved reading positions.") }
            Section { Button("Restore Home layout") { saved = HomePreferences().saved } }
        }.environment(\.editMode, .constant(.active)).navigationTitle("Customize Home").navigationBarTitleDisplayMode(.inline)
    }
}
