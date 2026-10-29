import SwiftUI
import AnimeCore

struct CommunityFeedView: View {
    @EnvironmentObject private var store: AppStore
    @AppStorage(CommunityConfiguration.revisionKey) private var revision = 0
    @State private var filter: CommunityFilter
    @State private var source = CommunitySource.aniList
    @State private var sort = CommunityThreadSort.active
    @State private var selectedShow = 0
    @State private var seasonal: [Anime] = []
    @State private var seasonPage = 0
    @State private var moreSeasonal = true
    @State private var loadingShows = false
    @State private var showsError: String?
    @State private var showsAttempt = UUID()
    @State private var showsAdult: Bool?
    @State private var threads: [CommunityThread] = []
    @State private var loading = false
    @State private var error: String?
    @State private var page = 0
    @State private var pendingGroups: [Int] = []
    @State private var pagesByGroup: [Int: Int] = [:]
    @State private var hasMore = false
    @State private var attempt = UUID()
    init(initialFilter: CommunityFilter = .general) { _filter = State(initialValue: initialFilter) }
    private var myShows: [Anime] {
        var seen = Set<Int>()
        return store.entries.sorted { ($0.updatedAt ?? 0) > ($1.updatedAt ?? 0) }.compactMap(\.media)
            .filter { store.isVisible($0) && seen.insert($0.id).inserted }
    }
    private var shows: [Anime] { filter == .myShows ? myShows : seasonal.filter { store.isVisible($0) } }
    private var scoped: Bool { filter == .season || filter == .myShows }
    private var selectedAnime: Anime? { shows.first { $0.id == selectedShow } }
    private var visibleThreads: [CommunityThread] {
        let values = threads.filter { thread in
            if !store.includeAdult && thread.media.contains(where: { $0.isAdult == true }) { return false }
            if filter == .general { return !thread.mentionsEpisode }
            return filter != .episodes || thread.mentionsEpisode
        }
        guard source == .aniList else { return values }
        return values.sorted {
            if sort == .newest { return $0.threadID > $1.threadID }
            if sort == .comments, $0.commentCount != $1.commentCount { return ($0.commentCount ?? 0) > ($1.commentCount ?? 0) }
            if $0.activityAt != $1.activityAt { return ($0.activityAt ?? .distantPast) > ($1.activityAt ?? .distantPast) }
            return $0.threadID > $1.threadID
        }
    }
    private var progress: [Int: Int] { Dictionary(store.entries.map { ($0.mediaId, $0.progressValue) }, uniquingKeysWith: max) }
    private var loadKey: String {
        "\(source)-\(filter)-\(sort)-\(selectedShow)-\(shows.map(\.id))-\(store.includeAdult)-\(store.viewer?.id ?? 0)-\(revision)"
    }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("The conversation continues.").font(.title2.bold())
                    Text("Seasonal anime, your shows and the latest episode reactions.").font(.subheadline).foregroundStyle(.secondary)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(CommunityFilter.allCases) { item in
                            CompanionFilterChip(title: item.title, selected: filter == item) { filter = item; selectedShow = 0 }
                        }
                    }
                }
                Picker("Community source", selection: $source) { ForEach(CommunitySource.allCases) { Text($0.title).tag($0) } }.pickerStyle(.menu)
                    .accessibilityIdentifier("community-source-switcher")
                if scoped { showPicker }
                if source == .reddit {
                    if scoped && selectedAnime == nil {
                        Text("Choose a show above to search r/anime for its conversations.").font(.subheadline).foregroundStyle(.secondary).companionPanel()
                    } else {
                        CommunityBrowserPanel(source: .reddit, url: CommunityBrowserLinks.reddit(filter: filter, anime: selectedAnime))
                    }
                    Text("Reddit uses its official pages. Switch to AniList for the native comment reader.").font(.caption).foregroundStyle(.secondary)
                } else if source == .myAnimeList && CommunityConfiguration.malClientID == nil {
                    CommunityBrowserPanel(source: .myAnimeList, url: CommunityBrowserLinks.myAnimeList(anime: selectedAnime))
                    NavigationLink("Configure Community sources") { CommunitySourcesView() }.font(.subheadline)
                } else if scoped && shows.isEmpty {
                    if loadingShows { ProgressView("Loading this season…") }
                    else { Text(filter == .myShows ? "Connect AniList and add shows to your library to see their discussions." : "No seasonal shows are available yet.").font(.subheadline).foregroundStyle(.secondary).companionPanel() }
                } else if scoped && source == .myAnimeList && selectedAnime == nil {
                    Text("Choose a show to find its MyAnimeList discussions. Topic searches are checked by title and need your confirmation.").font(.subheadline).foregroundStyle(.secondary).companionPanel()
                } else {
                    nativeFeed
                }
            }.padding(16).frame(maxWidth: 940, alignment: .leading).frame(maxWidth: .infinity)
        }.background(Theme.background).navigationTitle("Community").navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { NavigationLink { CommunitySourcesView() } label: { Image(systemName: "slider.horizontal.3") }.accessibilityLabel("Community sources") } }
            .task(id: loadKey) { await load(reset: true) }
            .task(id: "\(filter)-\(store.includeAdult)") {
                if filter == .season && (seasonal.isEmpty || showsAdult != store.includeAdult) { await loadShows(replace: true) }
            }
            .refreshable { await load(reset: true, refresh: true) }
            .accessibilityIdentifier("community-feed")
    }
    private var showPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Anime", selection: $selectedShow) {
                Text(source == .aniList ? "All listed shows" : "Choose a show").tag(0)
                ForEach(shows) { Text($0.displayTitle).tag($0.id) }
            }.pickerStyle(.menu)
            if filter == .season {
                Text(SeasonSelection.current().label).font(.caption).foregroundStyle(.secondary)
                if loadingShows { ProgressView("Loading shows…") }
                else if moreSeasonal { Button("Load more seasonal shows") { Task { await loadShows() } }.font(.caption).frame(minHeight: 44) }
            }
            if let showsError { NoticeView(message: showsError) { Task { await loadShows() } } }
        }.companionPanel(padding: 12)
    }
    private var nativeFeed: some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Native reader", systemImage: "text.bubble").font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
                Spacer()
                if source == .aniList {
                    Picker("Thread order", selection: $sort) { ForEach(CommunityThreadSort.allCases) { Text($0.title).tag($0) } }.pickerStyle(.menu)
                } else { Text("Recent activity").font(.caption).foregroundStyle(.secondary) }
            }
            if let error {
                NoticeView(message: error) { Task { await load(reset: threads.isEmpty, refresh: true) } }
                CommunityWebButton(title: "Open official discussions", url: source == .myAnimeList ? CommunityBrowserLinks.myAnimeList(anime: selectedAnime) : URL(string: "https://anilist.co/forum/overview")!)
            }
            ForEach(visibleThreads) { thread in
                NavigationLink {
                    CommunityThreadReader(thread: thread, anime: selectedAnime, confirmIdentity: source == .myAnimeList && selectedAnime != nil)
                } label: {
                    CommunityThreadRow(thread: thread, title: thread.previewTitle(progress: progress, mediaID: selectedAnime?.id))
                }.buttonStyle(.plain)
            }
            if loading { ProgressView("Loading discussions…").frame(maxWidth: .infinity).padding() }
            else if visibleThreads.isEmpty && error == nil {
                Text("No matching discussions on this page. Try another source, choose a show, or search more threads.").font(.subheadline).foregroundStyle(.secondary).companionPanel()
            }
            if hasMore && !loading { Button("Load more discussions") { Task { await load(reset: false) } }.buttonStyle(.bordered).frame(maxWidth: .infinity) }
            if scoped && selectedShow == 0 && source == .aniList {
                Text("Results cover the shows listed above. Load more seasonal shows to include additional titles.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    @MainActor private func loadShows(replace: Bool = false) async {
        guard replace || !loadingShows else { return }
        let current = UUID(); showsAttempt = current
        let requestedAdult = store.includeAdult
        if showsAdult != requestedAdult { seasonal = []; seasonPage = 0; moreSeasonal = true; showsAdult = requestedAdult }
        let requestedPage = seasonPage + 1
        loadingShows = true; showsError = nil
        defer { if showsAttempt == current { loadingShows = false } }
        do {
            let result = try await store.aniList.seasonal(.current(), page: requestedPage, includeAdult: requestedAdult)
            try Task.checkCancellation(); guard showsAttempt == current, store.includeAdult == requestedAdult else { return }
            var ids = Set(seasonal.map(\.id))
            seasonal += (result.media ?? []).filter { ids.insert($0.id).inserted }
            seasonPage = requestedPage; moreSeasonal = result.pageInfo?.hasNextPage == true
        } catch is CancellationError {} catch { if showsAttempt == current { showsError = error.localizedDescription } }
    }
    @MainActor private func load(reset: Bool, refresh: Bool = false) async {
        guard reset || !loading else { return }
        let current = UUID(); attempt = current
        if reset {
            threads = []; page = 0; hasMore = false; pagesByGroup = [:]
            pendingGroups = Array(0..<((shows.count + 7) / 8))
        }
        loading = false; error = nil
        guard source != .reddit, !(scoped && shows.isEmpty),
              !(source == .myAnimeList && (CommunityConfiguration.malClientID == nil || (scoped && selectedAnime == nil))) else { return }
        let wantedSource = source
        let ids = shows.map(\.id)
        let requestedGroup = pendingGroups.first ?? 0
        let batch = scoped && selectedShow == 0 ? Array(ids.dropFirst(requestedGroup * 8).prefix(8)) : []
        let requestedPage = batch.isEmpty ? page + 1 : (pagesByGroup[requestedGroup] ?? 0) + 1
        loading = true
        defer { if attempt == current { loading = false } }
        do {
            let result: CommunityThreadPage
            if source == .aniList {
                if !batch.isEmpty { result = try await store.aniList.communityThreads(mediaIDs: batch, page: requestedPage, sort: sort, refresh: refresh) }
                else { result = try await store.aniList.communityThreads(mediaID: selectedAnime?.id, search: filter == .episodes ? "Episode" : nil, page: requestedPage, sort: sort, refresh: refresh) }
            } else {
                let query = selectedAnime?.displayTitle ?? (filter == .episodes ? "Episode" : nil)
                result = try await store.communityMAL.topics(clientID: CommunityConfiguration.malClientID ?? "", query: query, page: requestedPage, refresh: refresh)
            }
            try Task.checkCancellation(); guard attempt == current, source == wantedSource else { return }
            var seen = Set(threads.map(\.id))
            threads += result.threads.filter { seen.insert($0.id).inserted }
            page = requestedPage; hasMore = result.hasNextPage
            if !batch.isEmpty {
                pagesByGroup[requestedGroup] = requestedPage
                if !pendingGroups.isEmpty { pendingGroups.removeFirst() }
                if result.hasNextPage { pendingGroups.append(requestedGroup) }
                hasMore = !pendingGroups.isEmpty
            }
        } catch is CancellationError {} catch { if attempt == current { self.error = error.localizedDescription } }
    }
}

struct CommunityThreadRow: View {
    let thread: CommunityThread
    let title: String
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(3).multilineTextAlignment(.leading)
            CommunityThreadMetadata(thread: thread)
        }.frame(maxWidth: .infinity, alignment: .leading).companionPanel(padding: 14).contentShape(Rectangle())
    }
}

struct HomeCommunityWidget: View {
    @EnvironmentObject private var store: AppStore
    let refreshID: Int
    @State private var threads: [CommunityThread] = []
    @State private var loading = false
    @State private var failed = false
    @State private var attempt = UUID()
    private var progress: [Int: Int] { Dictionary(store.entries.map { ($0.mediaId, $0.progressValue) }, uniquingKeysWith: max) }
    private var previews: [CommunityThread] { Array(threads.filter { store.includeAdult || !$0.media.contains { $0.isAdult == true } }.prefix(2)) }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                CompanionSectionHeading(title: "Community", subtitle: "Keep up with the conversation")
                NavigationLink { CommunityFeedView() } label: { Image(systemName: "arrow.up.right.circle.fill").font(.title2).foregroundStyle(Theme.accent).frame(minWidth: 44, minHeight: 44) }
                    .accessibilityLabel("Open Community")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(CommunityFilter.allCases) { filter in
                        NavigationLink { CommunityFeedView(initialFilter: filter) } label: {
                            Text(filter.title).font(.caption.weight(.semibold)).foregroundStyle(Theme.accent).padding(.horizontal, 12).frame(minHeight: 36)
                                .background(Theme.accent.opacity(0.1), in: Capsule())
                        }.buttonStyle(.plain)
                    }
                }
            }
            ForEach(previews) { thread in
                NavigationLink { CommunityThreadReader(thread: thread) } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(thread.previewTitle(progress: progress)).font(.subheadline.weight(.medium)).foregroundStyle(.primary).lineLimit(2).multilineTextAlignment(.leading)
                        CommunityThreadMetadata(thread: thread)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 3).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            if loading && previews.isEmpty { ProgressView("Loading conversations…").font(.caption) }
            else if previews.isEmpty { Text(failed ? "Open Community to retry or browse r/anime." : "Explore today’s conversations and episode threads.").font(.caption).foregroundStyle(.secondary) }
            if failed && !previews.isEmpty { Text("Couldn’t refresh · Open Community to retry").font(.caption2).foregroundStyle(.secondary) }
            HStack {
                CommunityWebButton(title: "Browse r/anime", url: CommunityBrowserLinks.reddit(filter: .general))
                Spacer()
                Text("Official browser").font(.caption2).foregroundStyle(.secondary)
            }
        }.companionPanel().overlay(alignment: .top) {
            RoundedRectangle(cornerRadius: 2).fill(Theme.accent.opacity(0.55)).frame(width: 52, height: 3)
        }.accessibilityIdentifier("home-community-widget")
            .task(id: "\(refreshID)-\(store.includeAdult)") {
                let current = UUID(); attempt = current
                loading = true; failed = false
                defer { if attempt == current { loading = false } }
                do {
                    let result = try await store.aniList.communityThreads(refresh: refreshID > 0)
                    try Task.checkCancellation(); guard attempt == current else { return }; threads = result.threads
                } catch is CancellationError {} catch { if attempt == current { failed = true } }
            }
    }
}
