import SwiftUI
import AnimeCore

/// Each saved slot is independent of the widget's position and visibility.
struct HomeFeatureShortcuts: View {
    @EnvironmentObject private var navigation: AppNavigationStore
    @Environment(\.homeVisuals) private var visuals
    @AppStorage(HomePreferences.storageKey) private var saved = ""
    @State private var customizing = false
    private var preferences: HomePreferences { HomePreferences(saved: saved) }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Quick access").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Button("Customize", systemImage: "slider.horizontal.3") { customizing = true }
                    .font(visuals.actionTextFont).frame(minHeight: 44).accessibilityIdentifier("home-edit-shortcuts")
            }
            if preferences.shortcuts.allSatisfy({ $0 == nil }) {
                Button("Choose shortcuts", systemImage: "plus.circle") { customizing = true }
                    .frame(maxWidth: .infinity, minHeight: 64).companionPanel(padding: 12)
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { tiles }
                    VStack(spacing: 10) { tiles }
                }
            }
        }.sheet(isPresented: $customizing) {
            AppNavigationStack {
                HomeShortcutCustomizationView().toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { customizing = false } } }
            }
        }
    }
    @ViewBuilder private var tiles: some View {
        ForEach(0..<3, id: \.self) { index in
            if let shortcut = preferences.shortcuts[index] {
                Group {
                    if shortcut == .community {
                        NavigationLink { CommunityFeedView() } label: { tile(shortcut) }
                    } else {
                        Button { open(shortcut) } label: { tile(shortcut) }
                    }
                }.buttonStyle(.plain).accessibilityIdentifier("home-open-" + (shortcut == .calendar ? "schedule" : shortcut.rawValue))
                    .contextMenu {
                        Menu("Replace shortcut") {
                            ForEach(HomeShortcut.allCases) { item in
                                Button(item.title, systemImage: item.symbol) { replace(item, at: index) }
                            }
                        }
                        Button("Hide shortcut", systemImage: "minus.circle") { replace(nil, at: index) }
                        Button("Customize shortcuts", systemImage: "slider.horizontal.3") { customizing = true }
                    }
            }
        }
    }
    private func tile(_ value: HomeShortcut) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: value.symbol).font(visuals.iconFont).foregroundStyle(Theme.accent).accessibilityHidden(true)
            Text(value.title).font(visuals.actionTextFont).foregroundStyle(.primary)
            Text(value.detail).font(visuals.enlarged ? .caption : .caption2).foregroundStyle(.secondary).lineLimit(2)
        }.frame(maxWidth: .infinity, minHeight: visuals.value(64, 88), alignment: .leading)
            .companionPanel(padding: visuals.value(12, 16)).contentShape(Rectangle())
    }
    private func replace(_ shortcut: HomeShortcut?, at index: Int) {
        var value = preferences; value.setShortcut(shortcut, at: index); saved = value.saved
    }
    private func open(_ shortcut: HomeShortcut) {
        switch shortcut {
        case .calendar: navigation.openSchedule()
        case .airing: navigation.openSchedule(page: .airing)
        case .news: navigation.openNews()
        case .library: navigation.open(.library)
        case .explore: navigation.open(.explore)
        case .reading: navigation.open(.manga)
        case .savedNews: navigation.openNews(.saved)
        case .community: break // Uses the normal navigation stack above.
        }
    }
}

/// A small presentation of the existing feed, preferences, bookmarks and read
/// history. The full NewsView remains the place for searching and filtering.
struct HomeNewsSection: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var navigation: AppNavigationStore
    @Environment(\.homeVisuals) private var visuals
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("news.reader.v1") private var readerJSON = ""
    @AppStorage("news.readingHistory") private var historyJSON = ""
    @AppStorage("news.preferences.v1") private var preferencesJSON = ""
    var refreshID = 0
    @State private var appliedRefreshID = 0
    @State private var snapshot: NewsSnapshot?
    @State private var selected: NewsArticle?
    @State private var loading = false
    @State private var error: String?
    @State private var requestID = UUID()
    private var reader: NewsReaderState { decode(readerJSON) ?? NewsReaderState() }
    private var preferences: NewsPreferences { decode(preferencesJSON) ?? NewsPreferences() }
    private var stories: [NewsArticle] {
        Array(NewsFeed.articles(snapshot?.articles ?? [], query: NewsFeedQuery(), preferences: preferences,
            reader: reader, history: decode(historyJSON) ?? NewsReadingHistory(), library: []).prefix(4))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                CompanionSectionHeading(title: "Headlines")
                Menu {
                    Button("Latest headlines") { navigation.openNews() }
                    Button("For You", systemImage: "sparkles") { navigation.openNews(.forYou) }
                    Button("Saved stories", systemImage: "bookmark") { navigation.openNews(.saved) }
                    Button("Reading history", systemImage: "clock") { navigation.openNews(.history) }
                } label: {
                    Label("All news", systemImage: "chevron.down").font(visuals.actionTextFont).frame(minHeight: 44)
                }.accessibilityIdentifier("home-news-collections")
            }
            if !stories.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(stories) { article in
                            Button { open(article) } label: {
                                HomeNewsBanner(article: article, isSaved: reader.isSaved(article))
                                    .containerRelativeFrame(.horizontal, alignment: .leading) { width, _ in min(visuals.newsBannerLimit, width * 0.92) }
                            }.buttonStyle(.plain).accessibilityIdentifier("home-news-story-" + article.id)
                                .contextMenu {
                                    Button(reader.isSaved(article) ? "Remove saved story" : "Save story", systemImage: "bookmark") { toggleSaved(article) }
                                    Button("More headlines", systemImage: "newspaper") { navigation.openNews() }
                                }
                                .accessibilityAction(named: reader.isSaved(article) ? "Remove saved story" : "Save story") { toggleSaved(article) }
                        }
                    }
                }
                if snapshot?.isStale == true || error != nil {
                    Text("Showing saved headlines · Pull to refresh").font(.caption2).foregroundStyle(.secondary)
                }
            } else if loading {
                ProgressView("Loading headlines…").frame(maxWidth: .infinity, minHeight: 72).companionPanel(padding: 12)
            } else {
                Button { navigation.openNews() } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "newspaper").font(visuals.circleIconFont).foregroundStyle(Theme.accent)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(error == nil ? "Your anime briefing" : "Headlines are taking a break").font(.subheadline.weight(.semibold))
                            Text(preferences.enabledSources.isEmpty ? "Choose publishers and interests in News." : "Open News for stories, saved articles and your interests.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").foregroundStyle(Theme.accent)
                    }.foregroundStyle(.primary).companionPanel(padding: 14)
                }.buttonStyle(.plain)
            }
        }.accessibilityIdentifier("home-news-widget")
            .task(id: "\(scenePhase)-\(refreshID)") {
                guard scenePhase == .active else { return }
                await load(refresh: refreshID != appliedRefreshID)
                if !Task.isCancelled { appliedRefreshID = refreshID }
            }
            .sheet(item: $selected) { ArticleBrowser(url: $0.url).ignoresSafeArea() }
    }
    @MainActor private func load(refresh: Bool = false) async {
        let attempt = UUID(); requestID = attempt; loading = true; error = nil
        defer { if requestID == attempt { loading = false } }
        if let cached = await store.news.cachedSnapshot(), requestID == attempt, !Task.isCancelled { snapshot = cached }
        do {
            let fresh = try await store.news.snapshot(refresh: refresh)
            try Task.checkCancellation()
            if requestID == attempt { snapshot = fresh }
        } catch is CancellationError {} catch { if requestID == attempt { self.error = error.localizedDescription } }
    }
    private func open(_ article: NewsArticle) {
        guard article.source.accepts(article.url) else { return }
        var history: NewsReadingHistory = decode(historyJSON) ?? NewsReadingHistory()
        history.record(article); historyJSON = encode(history)
        var state = reader; state.migrate(history); state.markRead(article); readerJSON = encode(state)
        selected = article
    }
    private func toggleSaved(_ article: NewsArticle) {
        var state = reader; state.toggleSaved(article); readerJSON = encode(state)
    }
    private func decode<T: Decodable>(_ value: String) -> T? { try? JSONDecoder().decode(T.self, from: Data(value.utf8)) }
    private func encode<T: Encodable>(_ value: T) -> String { (try? JSONEncoder().encode(value)).flatMap { String(data: $0, encoding: .utf8) } ?? "" }
}

private struct HomeNewsBanner: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.homeVisuals) private var visuals
    let article: NewsArticle
    let isSaved: Bool
    @State private var imageURL: URL?
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomLeading) {
                Theme.accent.opacity(0.20)
                ArtworkImage(url: imageURL ?? article.imageURL, pointSize: geometry.size.width) { image in
                    image.resizable().scaledToFill()
                } placeholder: { Theme.accent.opacity(0.14) }
                    .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                LinearGradient(colors: [.black.opacity(0.05), .black.opacity(0.88)], startPoint: .top, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(article.source.label.uppercased()).fontWeight(.bold)
                        if isSaved { Image(systemName: "bookmark.fill").accessibilityLabel("Saved") }
                    }.font(.caption2).foregroundStyle(.white.opacity(0.85))
                    Text(article.title).font(.headline).lineLimit(3).foregroundStyle(.white)
                    if let date = article.publishedAt { Text(date, style: .relative).font(.caption2).foregroundStyle(.white.opacity(0.80)) }
                }.padding(14)
            }.clipShape(RoundedRectangle(cornerRadius: Theme.radius))
        }.frame(height: textSize.isAccessibilitySize ? visuals.value(250, 340) : visuals.newsBannerHeight)
            .accessibilityElement(children: .combine)
            .task(id: article.id) { imageURL = await store.news.thumbnail(for: article) }
    }
}
