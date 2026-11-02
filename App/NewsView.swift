import SwiftUI
import SafariServices
import AnimeCore

struct NewsView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var navigation: AppNavigationStore
    @EnvironmentObject private var mangaBaka: MangaBakaStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var typeSize
    var anime: Anime? = nil
    var initialCollection: NewsCollection = .latest
    @AppStorage("news.readingHistory") private var historyJSON = ""
    @AppStorage("news.reader.v1") private var readerJSON = ""
    @AppStorage("news.preferences.v1") private var preferencesJSON = ""
    @AppStorage("news.compact") private var compact = false
    @AppStorage("news.unreadOnly") private var unreadOnly = false
    @State private var seriesUnreadOnly = false
    @AppStorage("news.popularPeriod") private var periodValue = NewsPeriod.week.rawValue
    @State private var articles: [NewsArticle] = []
    @State private var query = NewsFeedQuery()
    @State private var loading = false
    @State private var appSettings = false
    @State private var feedSettings = false
    @State private var error: String?
    @State private var selected: NewsArticle?
    @State private var snapshot: NewsSnapshot?
    @State private var seriesSnapshot: SeriesNewsSnapshot?
    @State private var history = NewsReadingHistory()
    @State private var reader = NewsReaderState()
    @State private var preferences = NewsPreferences()
    @State private var appliedCollection = false
    private var library: [NewsLibraryTitle] {
        let anime = store.visibleEntries.filter { $0.status != .dropped }.compactMap(\.media).map(NewsLibraryTitle.init(anime:))
        let written = mangaBaka.library.filter { $0.state != "dropped" }.compactMap(\.series)
            .filter { $0.isVisible(contentFilter: store.mangaBakaContent) }.map { NewsLibraryTitle(title: $0.displayTitle, aliases: $0.searchTitles) }
        return anime + written
    }
    private var effectiveQuery: NewsFeedQuery {
        var value = query; value.unreadOnly = unreadFilter.wrappedValue
        return value
    }
    private var unreadFilter: Binding<Bool> {
        anime == nil ? $unreadOnly : $seriesUnreadOnly
    }
    private var filtered: [NewsArticle] {
        let title = anime.map(NewsLibraryTitle.init(anime:))
        let relevant = articles.filter { title?.matches($0) ?? true }
        return NewsFeed.articles(relevant, query: effectiveQuery, preferences: preferences, reader: reader, history: history, library: library)
            .filter { title?.matches($0) ?? true }
    }
    private var hasFilters: Bool { query.topic != .all || query.source != nil || query.timeRange != .all || !query.text.isEmpty || unreadFilter.wrappedValue }
    private var usesRows: Bool { compact || !query.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var showsFeatured: Bool { !usesRows && query.sort == .newest && (query.collection == .latest || query.collection == .forYou) }

    var body: some View {
        Group {
            if let anime, !store.isVisible(anime) { ContentUnavailableView("Adult content is hidden", systemImage: "eye.slash") }
            else { headlines }
        }
        .navigationTitle(anime == nil ? "Anime News" : "Headlines")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query.text, prompt: "Search stories and publishers")
        .toolbar { toolbar }
        .appSettingsSheet(isPresented: $appSettings)
        .task {
            if !appliedCollection { query.collection = initialCollection; appliedCollection = true }
            history = decode(historyJSON) ?? NewsReadingHistory()
            reader = decode(readerJSON) ?? NewsReaderState()
            preferences = decode(preferencesJSON) ?? NewsPreferences()
            var value = reader; value.migrate(history); readerJSON = encode(value)
            reader = value
            await load()
        }
        .onChange(of: readerJSON) { _, value in reader = decode(value) ?? NewsReaderState() }
        .onChange(of: historyJSON) { _, value in history = decode(value) ?? NewsReadingHistory() }
        .onChange(of: preferencesJSON) { _, value in preferences = decode(value) ?? NewsPreferences() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await load() } } }
        .refreshable { await load(refresh: true) }
        .sheet(item: $selected) { ArticleBrowser(url: $0.url).ignoresSafeArea() }
        .sheet(isPresented: $feedSettings) {
            NewsPreferencesView(preferences: Binding(get: { preferences }, set: { preferences = $0; preferencesJSON = encode($0) }), compact: $compact)
        }
    }

    private var headlines: some View {
        let values = filtered
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                if anime != nil || query.text.isEmpty { masthead }
                if anime == nil {
                    Picker("News collection", selection: $query.collection) {
                        ForEach(NewsCollection.allCases, id: \.self) { Text($0.label).tag($0) }
                    }.pickerStyle(.segmented).accessibilityIdentifier("news-collections")
                }
                topicStrip
                filterSummary(count: values.count)
                if query.collection == .forYou {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "sparkles").foregroundStyle(Theme.accent)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("A little more you").font(.headline)
                            Text("Stories about series in your anime, manga and novel libraries, plus the topics you follow.")
                                .font(.caption).foregroundStyle(.secondary)
                            if mangaBaka.hasMoreLibrary { Text("Load more of your written library for more title matches.").font(.caption).foregroundStyle(.secondary) }
                            Button("Choose your interests") { feedSettings = true }.font(.subheadline.weight(.semibold))
                                .accessibilityIdentifier("news-choose-interests")
                        }
                    }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.cyan.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
                }
                feedStatus
                if loading && values.isEmpty && (query.collection == .latest || query.collection == .forYou) {
                    ProgressView("Loading headlines…").frame(maxWidth: .infinity).padding(30)
                }
                if let error { NoticeView(message: error) { Task { await load(refresh: true) } } }
                if query.collection == .history { readingHighlights }
                stories(values)
                if !values.isEmpty {
                    Text("You’re caught up with this selection. Pull down for the latest headlines.")
                        .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 12)
                }
            }.padding(18).readableContent(width: 1140)
        }.scrollDismissesKeyboard(.interactively).accessibilityIdentifier("news-list").background(Theme.background)
    }

    @ViewBuilder private var masthead: some View {
        if let anime {
            VStack(alignment: .leading, spacing: 8) {
                Text(anime.displayTitle).font(.title2.bold())
                Text("Series news from recent feeds and Anime Corner’s title search, including other seasons.").font(.caption).foregroundStyle(.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(Date(), format: .dateTime.weekday(.wide).month(.wide).day()).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text("Your anime briefing").font(.title2.bold())
                    }
                    Spacer(minLength: 8)
                    Button { feedSettings = true } label: {
                        Image(systemName: "slider.horizontal.3").font(.title3).foregroundStyle(Theme.accent)
                            .frame(width: 44, height: 44).background(Theme.surface, in: Circle())
                    }.buttonStyle(.plain).accessibilityLabel("Customize news").accessibilityIdentifier("news-customize")
                }
                HStack(spacing: 10) {
                    NavigationLink(value: AnimeVisualsRoute(anime: nil)) { Label("Visuals", systemImage: "photo.on.rectangle").frame(maxWidth: .infinity, minHeight: 44) }
                        .accessibilityIdentifier("news-open-visuals")
                    Button { navigation.openSchedule() } label: { Label("Schedules", systemImage: "calendar").frame(maxWidth: .infinity, minHeight: 44) }
                        .accessibilityIdentifier("news-open-schedule")
                }.font(.subheadline.weight(.medium)).buttonStyle(.bordered).tint(Theme.accent)
            }
        }
    }
    private var topicStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(NewsTopic.allCases, id: \.self) { topic in
                    Button { query.topic = topic } label: {
                        Label(topic.label, systemImage: topic.symbol).font(.caption.weight(.semibold))
                            .padding(.horizontal, 13).frame(minHeight: 44)
                            .background(query.topic == topic ? Color.cyan.opacity(0.2) : Theme.surface, in: Capsule())
                            .foregroundStyle(query.topic == topic ? Theme.accent : Color.primary)
                    }.buttonStyle(.plain).accessibilityIdentifier("news-topic-\(topic.rawValue)")
                        .accessibilityAddTraits(query.topic == topic ? .isSelected : [])
                }
            }
        }
    }
    private func filterSummary(count: Int) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text(anime != nil || query.collection == .latest ? "Latest headlines" : query.collection.label).font(.title3.bold())
                Text("\(count) \(count == 1 ? "story" : "stories")" + (query.source.map { " · " + $0.label } ?? "") + (unreadFilter.wrappedValue && query.collection != .history ? " · Unread" : ""))
                    .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("news-results-count")
            }
            Spacer(minLength: 6)
            if loading { ProgressView().controlSize(.small) }
            if hasFilters { Button("Reset") { resetFilters() }.font(.caption).accessibilityIdentifier("news-reset-filters") }
            filtersMenu(count: count)
        }
    }
    private func filtersMenu(count: Int) -> some View {
        Menu {
            Picker("Publisher", selection: $query.source) {
                Text("All sources").tag(NewsSource?.none)
                ForEach(NewsSource.allCases, id: \.self) { Text($0.label).tag(Optional($0)) }
            }
            Picker("Published", selection: $query.timeRange) { ForEach(NewsTimeRange.allCases, id: \.self) { Text($0.label).tag($0) } }
            if query.collection != .history {
                Picker("Sort", selection: $query.sort) { ForEach(NewsSort.allCases, id: \.self) { Text($0.label).tag($0) } }
                Toggle("Unread only", isOn: unreadFilter).accessibilityIdentifier("news-unread-only")
            }
            Toggle("Compact layout", isOn: $compact)
            Divider()
            Button("Mark this selection as read", systemImage: "checkmark.circle") {
                var value = reader; for article in filtered { value.markRead(article) }; saveReader(value)
            }.disabled(count == 0)
            Button("Customize news", systemImage: "slider.horizontal.3") { feedSettings = true }
        } label: { Image(systemName: "line.3.horizontal.decrease").frame(width: 44, height: 44).background(Theme.surface, in: Circle()) }
            .accessibilityLabel("Filter and sort news").accessibilityIdentifier("news-sources")
    }
    @ViewBuilder private var feedStatus: some View {
        if anime != nil {
            VStack(alignment: .leading, spacing: 6) {
                if loading {
                    Label("Checking recent feeds and searching the series archive…", systemImage: "arrow.clockwise")
                } else if let seriesSnapshot {
                    if seriesSnapshot.unavailable {
                        Label(seriesSnapshot.isStale ? "Some publisher searches are unavailable. Showing available series headlines." : "Publisher title search is temporarily unavailable. Recent feed matches are still shown.", systemImage: "exclamationmark.circle")
                    } else {
                        Label("Includes Anime Corner title-search results beyond the latest feeds.", systemImage: "text.magnifyingglass")
                    }
                }
            }.font(.caption2).foregroundStyle(.secondary).accessibilityIdentifier("news-series-status")
        }
        if let snapshot, query.collection == .latest || query.collection == .forYou {
            VStack(alignment: .leading, spacing: 6) {
                if loading {
                    Label("Showing cached headlines while checking publishers…", systemImage: "arrow.clockwise")
                } else {
                    HStack(spacing: 5) {
                        Image(systemName: snapshot.isStale ? "clock.arrow.circlepath" : "checkmark.circle")
                        Text("Updated \(snapshot.updatedAt.formatted(.relative(presentation: .named)))")
                        Text("· \(NewsSource.allCases.count - snapshot.unavailableSources.count) publishers available")
                    }
                    if !snapshot.unavailableSources.isEmpty {
                        Text((snapshot.isStale ? "Keeping cached headlines. Unavailable: " : "Temporarily unavailable: ") + snapshot.unavailableSources.joined(separator: ", "))
                    }
                }
            }.font(.caption2).foregroundStyle(.secondary).accessibilityIdentifier("news-feed-status")
        }
    }
    @ViewBuilder private func stories(_ values: [NewsArticle]) -> some View {
        if !values.isEmpty {
            if showsFeatured, let first = values.first { card(first, featured: true) }
            let remaining = showsFeatured ? Array(values.dropFirst()) : values
            if usesRows {
                LazyVStack(spacing: 12) { ForEach(remaining) { card($0) } }
            } else {
                LazyVGrid(columns: sizeClass == .compact || typeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.adaptive(minimum: 290), spacing: 18)], alignment: .leading, spacing: 18) {
                    ForEach(remaining) { card($0) }
                }
            }
        } else if !loading || query.collection == .saved || query.collection == .history {
            VStack(spacing: 13) {
                Image(systemName: query.collection == .saved ? "bookmark" : "newspaper").font(.largeTitle).foregroundStyle(.secondary)
                Text(emptyTitle).font(.headline)
                Text(emptyMessage).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                if hasFilters { Button("Clear filters") { resetFilters() }.buttonStyle(.bordered) }
                if let anime, let url = SeriesNewsClient.publisherSearchURL(for: anime) {
                    Link("Search publisher archive", destination: url).buttonStyle(.bordered)
                }
                if query.collection == .forYou || preferences.enabledSources.isEmpty { Button("Customize news") { feedSettings = true }.buttonStyle(.bordered) }
            }.padding(30).frame(maxWidth: .infinity).accessibilityIdentifier("news-empty")
        }
    }
    private func card(_ article: NewsArticle, featured: Bool = false) -> some View {
        NewsStoryCard(article: article, featured: featured, compact: usesRows, isRead: reader.isRead(article), isSaved: reader.isSaved(article),
            reason: query.collection == .forYou ? reason(for: article) : nil,
            open: open, openExternally: openExternal, save: { toggleSaved($0) }, markRead: { toggleRead($0) }, source: { query.source = $0 })
    }
    private var readingHighlights: some View {
        DisclosureGroup("Your reading highlights") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Popular news period", selection: $periodValue) {
                    ForEach(NewsPeriod.allCases, id: \.self) { Text($0.label).tag($0.rawValue) }
                }.pickerStyle(.segmented).accessibilityIdentifier("news-popular-period")
                Text("Most opened on this device. These are your reading habits, not publisher-wide popularity.").font(.caption).foregroundStyle(.secondary)
                ForEach(Array(history.popular(in: NewsPeriod(rawValue: periodValue) ?? .week).prefix(5))) { item in
                    Button { open(item.article) } label: {
                        HStack { Text(item.article.title).font(.subheadline).lineLimit(2); Spacer(); Text("\(item.opens) opens").font(.caption).foregroundStyle(.secondary) }
                            .frame(minHeight: 44).multilineTextAlignment(.leading)
                    }.buttonStyle(.plain)
                }
            }.padding(.top, 10)
        }.font(.subheadline.weight(.semibold)).padding(16).background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
    }
    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button { Task { await load(refresh: true) } } label: { Image(systemName: "arrow.clockwise") }
                .disabled(loading).accessibilityLabel("Refresh news").accessibilityIdentifier("news-refresh")
            if anime != nil {
                Button { feedSettings = true } label: { Image(systemName: "slider.horizontal.3") }
                    .accessibilityLabel("Customize news").accessibilityIdentifier("news-customize")
            }
            if anime == nil {
                Button { appSettings = true } label: { Image(systemName: "gearshape") }.accessibilityLabel("Account and settings")
            }
        }
    }
    private var emptyTitle: String {
        if hasFilters { return "No stories match these filters" }
        if anime != nil { return "No matching series headlines" }
        switch query.collection { case .saved: return "Keep a story for later"; case .history: return "Your reading starts here"; case .forYou: return "Let’s tune your feed"; case .latest: return "No headlines yet" }
    }
    private var emptyMessage: String {
        if hasFilters { return "Try another topic, publisher or date range, or clear your filters." }
        if anime != nil {
            return "No matching stories are available from the recent feeds or publisher title search. Check your publisher preferences or open the publisher archive."
        }
        switch query.collection {
        case .saved: return "Tap a bookmark on any story. Saved headlines and excerpts stay here even after leaving the feeds. Full articles open on the publisher’s website."
        case .history: return "Stories you open appear here, so you can find them again."
        case .forYou: return "Follow a few topics or add series to your libraries. Matches appear when those titles are mentioned in the current headlines."
        case .latest: return preferences.enabledSources.isEmpty ? "Enable a publisher in Customize news to fill your feed." : "Pull down to refresh or try again a little later."
        }
    }
    private func reason(for article: NewsArticle) -> String? {
        if let title = NewsFeed.matchingTitles(article, library: library).first { return "In your library · \(title)" }
        if let topic = NewsTopic.allCases.first(where: { $0 != .all && preferences.followedTopics.contains($0) && $0.matches(article) }) { return "You follow · \(topic.label)" }
        return nil
    }
    private func resetFilters() { let collection = query.collection; query = NewsFeedQuery(); query.collection = collection; unreadFilter.wrappedValue = false }
    private func toggleSaved(_ article: NewsArticle) { var value = reader; value.toggleSaved(article); saveReader(value) }
    private func toggleRead(_ article: NewsArticle) {
        var value = reader
        if value.isRead(article) { value.markUnread(article) } else { value.markRead(article) }
        saveReader(value)
    }
    private func open(_ article: NewsArticle) {
        guard article.source.accepts(article.url) else { return }
        recordRead(article)
        selected = article
    }
    private func openExternal(_ article: NewsArticle) {
        guard article.source.accepts(article.url) else { return }
        recordRead(article)
        openURL(article.url)
    }
    private func recordRead(_ article: NewsArticle) {
        var updated = history; updated.record(article); history = updated; historyJSON = encode(updated)
        var state = reader; state.markRead(article); saveReader(state)
    }
    @MainActor private func load(refresh: Bool = false) async {
        guard anime.map({ store.isVisible($0) }) ?? true, !loading else { return }
        loading = true; error = nil
        defer { loading = false }
        if articles.isEmpty, let cached = await store.news.cachedSnapshot() { snapshot = cached; articles = cached.articles }
        if let anime {
            if let saved = await store.news.cachedSeriesSnapshot(for: anime) {
                seriesSnapshot = saved; articles = (snapshot?.articles ?? []) + saved.articles
            }
            // Fetch independently: a feed outage must not discard successful archive matches.
            async let recent = try? store.news.snapshot(refresh: refresh)
            async let related = try? store.news.seriesSnapshot(for: anime, refresh: refresh)
            let (feed, series) = await (recent, related)
            guard !Task.isCancelled else { return }
            if let feed { snapshot = feed }
            if let series { seriesSnapshot = series }
            articles = (snapshot?.articles ?? []) + (seriesSnapshot?.articles ?? [])
            if snapshot == nil && seriesSnapshot?.unavailable != false {
                error = "Series headlines are temporarily unavailable. Pull to refresh."
            }
            return
        }
        do {
            let value = try await store.news.snapshot(refresh: refresh)
            try Task.checkCancellation()
            articles = value.articles; snapshot = value
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
    private func saveReader(_ value: NewsReaderState) { reader = value; readerJSON = encode(value) }
    private func decode<T: Decodable>(_ value: String) -> T? { try? JSONDecoder().decode(T.self, from: Data(value.utf8)) }
    private func encode<T: Encodable>(_ value: T) -> String { (try? JSONEncoder().encode(value)).flatMap { String(data: $0, encoding: .utf8) } ?? "" }
}

struct ArticleBrowser: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
