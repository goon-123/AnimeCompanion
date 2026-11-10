import SwiftUI
import AnimeCore

struct CommunityFeedView: View {
    @EnvironmentObject private var store: AppStore
    @AppStorage(CommunityDestination.storageKey) private var savedSource = CommunityDestination.aniList.rawValue
    @State private var filter: CommunityFilter
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
    @State private var pendingGroups: [Int] = []
    @State private var pagesByGroup: [Int: Int] = [:]
    @State private var hasMore = false
    @State private var attempt = UUID()
    @State private var loadedScope = ""
    init(initialFilter: CommunityFilter = .season) { _filter = State(initialValue: initialFilter.feedFilter) }
    private var source: CommunityDestination { CommunityDestination(preference: savedSource) }
    private var myShows: [Anime] {
        var seen = Set<Int>()
        return store.entries.sorted { ($0.updatedAt ?? 0) > ($1.updatedAt ?? 0) }.compactMap(\.media)
            .filter { store.isVisible($0) && seen.insert($0.id).inserted }
    }
    private var shows: [Anime] { filter == .myShows ? myShows : seasonal.filter { store.isVisible($0) } }
    private var selectedAnime: Anime? { shows.first { $0.id == selectedShow } }
    private var mediaIDs: [Int] { selectedAnime.map { [$0.id] } ?? shows.map(\.id) }
    private var visibleThreads: [CommunityThread] {
        guard loadedScope == scopeKey else { return [] }
        let ids = Set(mediaIDs)
        return threads.filter { thread in
            thread.source == .aniList && !ids.isDisjoint(with: thread.media.filter { $0.type == "ANIME" }.map(\.id)) &&
                (store.includeAdult || !thread.media.contains { $0.isAdult == true })
        }.sorted {
            if sort == .newest { return $0.threadID > $1.threadID }
            if sort == .comments, $0.commentCount != $1.commentCount { return ($0.commentCount ?? 0) > ($1.commentCount ?? 0) }
            if $0.activityAt != $1.activityAt { return ($0.activityAt ?? .distantPast) > ($1.activityAt ?? .distantPast) }
            return $0.threadID > $1.threadID
        }
    }
    private var progress: [Int: Int] { Dictionary(store.entries.map { ($0.mediaId, $0.progressValue) }, uniquingKeysWith: max) }
    private var scopeKey: String { "\(source)-\(filter)-\(sort)-\(selectedShow)-\(store.includeAdult)-\(store.viewer?.id ?? 0)" }
    private var loadKey: String { scopeKey + "-\(mediaIDs)" }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    CompanionSectionHeading(title: "Community", subtitle: "Conversations about this season and your shows")
                    CommunitySourcePicker()
                }
                if source == .fapservice {
                    CommunityWebsitePanel()
                } else {
                    Picker("Discussions", selection: $filter) {
                        ForEach(CommunityFilter.feedCases) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented).onChange(of: filter) { _, _ in selectedShow = 0 }
                    showPicker
                    if shows.isEmpty {
                        if loadingShows { ProgressView("Loading this season…") }
                        else { Text(filter == .myShows ? "Connect AniList and add shows to your library to see their discussions." : "No seasonal shows are available yet.").foregroundStyle(.secondary).companionPanel() }
                    } else { nativeFeed }
                }
            }.padding(16).frame(maxWidth: 940, alignment: .leading).frame(maxWidth: .infinity)
        }.background(Theme.background).navigationTitle("Community").navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
            .task(id: loadKey) {
                if source == .aniList { await load(reset: true) }
                else { attempt = UUID(); threads = []; loading = false }
            }
            .task(id: "\(source)-\(filter)-\(store.includeAdult)") {
                if source == .aniList && filter == .season && (seasonal.isEmpty || showsAdult != store.includeAdult) { await loadShows(replace: true) }
            }
            .refreshable {
                guard source == .aniList else { return }
                if filter == .season { await loadShows(replace: true) }
                await load(reset: true, refresh: true)
            }
            .accessibilityIdentifier("community-feed")
    }
    private var showPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Anime", selection: $selectedShow) {
                Text("All listed shows").tag(0)
                ForEach(shows) { Text($0.displayTitle).tag($0.id) }
            }.pickerStyle(.menu)
            if filter == .season {
                Text(SeasonSelection.current().label).font(.caption).foregroundStyle(.secondary)
                if loadingShows { ProgressView("Loading shows…") }
                else if moreSeasonal { Button("Load more seasonal shows") { Task { await loadShows() } }.font(.caption).frame(minHeight: 44) }
            }
            if let showsError { NoticeView(message: showsError) { Task { await loadShows() } } }
        }.frame(maxWidth: .infinity, alignment: .leading).companionPanel(padding: 12)
    }
    private var nativeFeed: some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("AniList", systemImage: "text.bubble").font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
                Spacer()
                Picker("Thread order", selection: $sort) { ForEach(CommunityThreadSort.allCases) { Text($0.title).tag($0) } }.pickerStyle(.menu)
            }
            if let error { NoticeView(message: error) { Task { await load(reset: threads.isEmpty, refresh: true) } } }
            ForEach(visibleThreads) { thread in
                NavigationLink { CommunityThreadReader(thread: thread, anime: selectedAnime) } label: {
                    CommunityThreadRow(thread: thread, title: thread.previewTitle(progress: progress, mediaID: selectedAnime?.id),
                        hiddenPreview: thread.hidesPreview(progress: progress, mediaID: selectedAnime?.id), anime: selectedAnime)
                }.buttonStyle(.plain)
            }
            if loading { ProgressView("Loading discussions…").frame(maxWidth: .infinity).padding() }
            else if visibleThreads.isEmpty && error == nil {
                Text("No discussions found for these shows yet. Choose a show or load more discussions.").foregroundStyle(.secondary).companionPanel()
            }
            if hasMore && !loading { Button("Load more discussions") { Task { await load(reset: false) } }.buttonStyle(.bordered).frame(maxWidth: .infinity) }
        }
    }
    @MainActor private func loadShows(replace: Bool = false) async {
        guard replace || !loadingShows else { return }
        let current = UUID(); showsAttempt = current
        let adult = store.includeAdult
        if showsAdult != adult { seasonal = []; seasonPage = 0; moreSeasonal = true; showsAdult = adult }
        let requestedPage = replace ? 1 : seasonPage + 1
        loadingShows = true; showsError = nil
        defer { if showsAttempt == current { loadingShows = false } }
        do {
            let result = try await store.aniList.seasonal(.current(), page: requestedPage, includeAdult: adult)
            try Task.checkCancellation()
            guard showsAttempt == current, source == .aniList, store.includeAdult == adult else { return }
            var ids = Set(replace ? [] : seasonal.map(\.id))
            let incoming = (result.media ?? []).filter { ids.insert($0.id).inserted }
            seasonal = replace ? incoming : seasonal + incoming
            seasonPage = requestedPage; moreSeasonal = result.pageInfo?.hasNextPage == true
        } catch is CancellationError {} catch { if showsAttempt == current { showsError = error.localizedDescription } }
    }
    @MainActor private func load(reset: Bool, refresh: Bool = false) async {
        guard source == .aniList, reset || !loading else { return }
        let current = UUID(); attempt = current
        let wantedScope = scopeKey, ids = mediaIDs
        if reset {
            threads = []; loadedScope = wantedScope; hasMore = false; pagesByGroup = [:]
            pendingGroups = Array(0..<((ids.count + 7) / 8))
        }
        loading = false; error = nil
        guard !ids.isEmpty, let group = pendingGroups.first else { return }
        let batch = Array(ids.dropFirst(group * 8).prefix(8))
        let page = (pagesByGroup[group] ?? 0) + 1
        loading = true
        defer { if attempt == current { loading = false } }
        do {
            let result = try await store.aniList.communityThreads(mediaIDs: batch, page: page, sort: sort, refresh: refresh)
            try Task.checkCancellation()
            guard attempt == current, scopeKey == wantedScope else { return }
            var seen = Set(threads.map(\.id))
            threads += result.threads.filter { seen.insert($0.id).inserted }
            pagesByGroup[group] = page
            pendingGroups.removeFirst()
            if result.hasNextPage { pendingGroups.append(group) }
            hasMore = !pendingGroups.isEmpty
        } catch is CancellationError {} catch { if attempt == current { self.error = error.localizedDescription } }
    }
}

struct CommunityThreadRow: View {
    @Environment(\.homeVisuals) private var visuals
    let thread: CommunityThread
    let title: String
    let hiddenPreview: Bool
    var anime: Anime? = nil
    private var imageURL: URL? {
        anime?.coverURL ?? thread.media.first?.coverURL ?? (!thread.mentionsEpisode ? CommunityText.previewImage(thread.body ?? "") : nil)
    }
    private var snippet: String { hiddenPreview ? "" : CommunityText.preview(thread.body ?? "") }
    var body: some View {
        HStack(alignment: .top, spacing: visuals.value(12, 16)) {
            CommunityThreadArtwork(url: imageURL)
            VStack(alignment: .leading, spacing: 7) {
                if !thread.mentionsEpisode, let name = anime?.displayTitle ?? thread.seriesName {
                    Text(name).font(.caption.weight(.semibold)).foregroundStyle(Theme.accent).lineLimit(2)
                }
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
                if hiddenPreview {
                    Label("Plot preview hidden · Tap to read", systemImage: "eye.slash")
                        .font(.caption2).foregroundStyle(.secondary)
                } else if !snippet.isEmpty && snippet != "[No text]" {
                    Text(snippet).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                CommunityThreadMetadata(thread: thread)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
            .companionPanel(padding: visuals.value(14, 18)).contentShape(Rectangle())
    }
}

struct HomeCommunityWidget: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.homeVisuals) private var visuals
    @AppStorage(CommunityDestination.storageKey) private var savedSource = CommunityDestination.aniList.rawValue
    let refreshID: Int
    var activationID = 0
    @State private var filter = CommunityFilter.season
    @State private var threads: [CommunityThread] = []
    @State private var loading = false
    @State private var failed = false
    @State private var attempt = UUID()
    @State private var appliedRefreshID = 0
    @State private var loadedKey = ""
    private var source: CommunityDestination { CommunityDestination(preference: savedSource) }
    private var progress: [Int: Int] { Dictionary(store.entries.map { ($0.mediaId, $0.progressValue) }, uniquingKeysWith: max) }
    private var libraryIDs: [Int] {
        var seen = Set<Int>()
        return store.visibleEntries.sorted { ($0.updatedAt ?? 0) > ($1.updatedAt ?? 0) }.compactMap(\.media)
            .map(\.id).filter { seen.insert($0).inserted }
    }
    private var requestKey: String { "\(source)-\(filter)-\(SeasonSelection.current().label)-\(store.includeAdult)-\(store.viewer?.id ?? 0)-\(filter == .myShows ? libraryIDs : [])" }
    private var previews: [CommunityThread] {
        guard loadedKey == requestKey else { return [] }
        return Array(threads.filter { store.includeAdult || !$0.media.contains { $0.isAdult == true } }.prefix(2))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                CompanionSectionHeading(title: "Community")
                CommunitySourcePicker()
                NavigationLink { CommunityFeedView(initialFilter: filter) } label: {
                    Image(systemName: "arrow.up.right.circle.fill").font(visuals.circleIconFont).foregroundStyle(Theme.accent).frame(minWidth: 44, minHeight: 44)
                }.accessibilityLabel("Open Community")
            }
            if source == .fapservice { CommunityWebsitePanel() }
            else {
                Picker("Discussions", selection: $filter) { ForEach(CommunityFilter.feedCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
                ForEach(previews) { thread in
                    NavigationLink { CommunityThreadReader(thread: thread) } label: {
                        CommunityThreadRow(thread: thread, title: thread.previewTitle(progress: progress),
                            hiddenPreview: thread.hidesPreview(progress: progress))
                    }.buttonStyle(.plain)
                }
                if loading && previews.isEmpty { ProgressView("Loading conversations…").font(.caption) }
                else if previews.isEmpty {
                    Text(filter == .myShows && libraryIDs.isEmpty ? "Add shows to AniList to see their conversations." :
                        (failed ? "Open Community to retry." : "No conversations found for these shows yet."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if failed && !previews.isEmpty { Text("Showing saved conversations · Open Community to retry").font(.caption2).foregroundStyle(.secondary) }
            }
        }.companionPanel().accessibilityIdentifier("home-community-widget")
            .task(id: "\(requestKey)-\(refreshID)-\(activationID)") { await load() }
    }
    @MainActor private func load() async {
        let current = UUID(); attempt = current
        let key = requestKey, adult = store.includeAdult, selected = filter
        loading = false; failed = false
        guard source == .aniList else { threads = []; return }
        loading = true
        defer { if attempt == current { loading = false } }
        do {
            var ids: [Int] = []
            if selected == .myShows { ids = libraryIDs }
            else {
                if let saved = await store.homeCatalog.cached(.current(), includeAdult: adult) {
                    ids = saved.value.filter { store.isVisible($0) }.map(\.id)
                    if let cached = await store.homeCommunity.cached(mediaIDs: ids, includeAdult: adult) {
                        guard attempt == current, requestKey == key, !Task.isCancelled else { return }
                        threads = cached.value.threads; loadedKey = key
                    }
                }
                do {
                    let lineup = try await store.homeCatalog.season(.current(), includeAdult: adult, refresh: refreshID != appliedRefreshID)
                    ids = lineup.value.filter { store.isVisible($0) }.map(\.id)
                } catch is CancellationError { return }
                catch { if ids.isEmpty { throw error }; failed = true }
            }
            try Task.checkCancellation()
            guard attempt == current, requestKey == key else { return }
            if let cached = await store.homeCommunity.cached(mediaIDs: ids, includeAdult: adult) {
                guard attempt == current, requestKey == key else { return }
                threads = cached.value.threads; loadedKey = key
            }
            let result = try await store.homeCommunity.feed(mediaIDs: ids, includeAdult: adult, refresh: refreshID != appliedRefreshID)
            try Task.checkCancellation()
            guard attempt == current, requestKey == key else { return }
            threads = result.value.threads; loadedKey = key; appliedRefreshID = refreshID
        } catch is CancellationError {} catch { if attempt == current { failed = true } }
    }
}
