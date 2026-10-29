import SwiftUI
import AnimeCore

struct AnimeDiscussionsSection: View {
    @EnvironmentObject private var store: AppStore
    let anime: Anime
    private var watched: Int { min(100_000, max(0, store.entry(for: anime.id)?.progressValue ?? 0)) }
    var body: some View {
        DetailCard(title: "Discussions") {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "bubble.left.and.bubble.right.fill").font(.title2).foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Talk through every episode.").font(.subheadline.weight(.semibold))
                    Text(watched > 0 ? "Starts at your latest marked-watched episode: \(watched)." : "Series conversations and episode reactions. Unwatched previews stay hidden.").font(.caption).foregroundStyle(.secondary)
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) { episodeLink; seriesLink }
                VStack(alignment: .leading, spacing: 6) { episodeLink; seriesLink }
            }
        }.accessibilityIdentifier("anime-discussions-section")
    }
    private var episodeLink: some View {
        NavigationLink { SeriesDiscussionsView(anime: anime) } label: {
            Label(watched > 0 ? "Discuss episode \(watched)" : "Browse discussions", systemImage: "text.bubble")
        }.buttonStyle(.borderedProminent).accessibilityIdentifier("anime-discuss-latest")
    }
    private var seriesLink: some View {
        NavigationLink("Series discussions") { SeriesDiscussionsView(anime: anime, requestedEpisode: 0) }
            .font(.subheadline).frame(minHeight: 44)
    }
}

struct SeriesDiscussionsView: View {
    @EnvironmentObject private var store: AppStore
    @AppStorage(CommunityConfiguration.revisionKey) private var revision = 0
    @AppStorage(CommunityConfiguration.offsetKey) private var offsets = ""
    let anime: Anime
    var requestedEpisode: Int? = nil
    @State private var source = CommunitySource.aniList
    @State private var chosenEpisode = -1
    @State private var episodeText = ""
    @State private var aliasIndex = 0
    @State private var numbering = false
    @State private var threads: [CommunityThread] = []
    @State private var loading = false
    @State private var error: String?
    @State private var page = 0
    @State private var hasMore = false
    @State private var attempt = UUID()
    private var watched: Int { min(100_000, max(0, store.entry(for: anime.id)?.progressValue ?? 0)) }
    private var selection: Int { min(100_000, chosenEpisode >= 0 ? chosenEpisode : max(0, requestedEpisode ?? watched)) }
    private var episode: Int? { selection > 0 ? selection : nil }
    private var offset: Int { CommunityConfiguration.offset(source: source, animeID: anime.id, saved: offsets) }
    private var mappedEpisode: Int? { episode.map { $0 + offset } }
    private var episodeLimit: Int { min(100_000, [1, anime.episodes.flatMap { $0 > 0 ? $0 : nil } ?? 100_000, watched, requestedEpisode ?? 0].max() ?? 1) }
    private var aliases: [String] {
        var seen = Set<String>()
        return ([anime.title?.english, anime.title?.romaji, anime.title?.userPreferred].compactMap { $0 } + (anime.synonyms ?? []))
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }
    private var searchTitle: String { aliases.indices.contains(aliasIndex) ? aliases[aliasIndex] : anime.displayTitle }
    private var matches: [CommunityThread] {
        threads.filter { thread in
            if !store.includeAdult && thread.media.contains(where: { $0.isAdult == true }) { return false }
            if let episode { return CommunityEpisodeTitle.matches(thread, anime: anime, episode: episode, offset: offset) }
            return !thread.mentionsEpisode
        }
    }
    private var progress: [Int: Int] { [anime.id: watched] }
    private var loadKey: String { "\(source)-\(selection)-\(offset)-\(searchTitle)-\(store.includeAdult)-\(revision)" }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(anime.displayTitle).font(.title3.bold())
                    Text("\(anime.season?.label ?? "") \(anime.seasonYear.map(String.init) ?? "")").font(.caption).foregroundStyle(.secondary)
                }
                episodePicker
                Picker("Discussion source", selection: $source) { ForEach(CommunitySource.allCases) { Text($0.title).tag($0) } }.pickerStyle(.menu)
                    .accessibilityIdentifier("series-discussion-source")
                if episode != nil {
                    HStack {
                        Text(offset == 0 ? "Uses this season’s episode numbering" : "Your episode \(selection) → \(source.title) episode \(mappedEpisode ?? selection)")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer(minLength: 6)
                        Button("Numbering") { numbering = true }.font(.caption.weight(.semibold)).frame(minHeight: 44)
                    }
                }
                if let mappedEpisode, mappedEpisode < 1 {
                    Text("This numbering adjustment produces an invalid episode. Open Numbering to correct or reset it.").font(.subheadline).foregroundStyle(.secondary).companionPanel()
                } else if source == .reddit {
                    CommunityBrowserPanel(source: .reddit, url: CommunityBrowserLinks.reddit(filter: .episodes, anime: anime, episode: mappedEpisode), episode: mappedEpisode)
                } else if source == .myAnimeList && CommunityConfiguration.malClientID == nil {
                    CommunityBrowserPanel(source: .myAnimeList, url: CommunityBrowserLinks.myAnimeList(anime: anime), episode: mappedEpisode)
                    NavigationLink("Enable MyAnimeList native reading") { CommunitySourcesView() }.font(.subheadline)
                } else {
                    if source == .myAnimeList {
                        if aliases.count > 1 {
                            Picker("Search title", selection: $aliasIndex) {
                                ForEach(Array(aliases.enumerated()), id: \.offset) { index, alias in Text(alias).tag(index) }
                            }.pickerStyle(.menu)
                        }
                        Text("Title matches · Confirm the season/cour before reading. MAL does not attach series IDs to topic results.").font(.caption).foregroundStyle(.secondary)
                    } else { Label("AniList series ID \(anime.id) · Native reader", systemImage: "checkmark.shield").font(.caption).foregroundStyle(Theme.accent) }
                    if let episode, episode > watched { Label("Episode \(episode) previews hidden · Not marked watched", systemImage: "eye.slash").font(.caption).foregroundStyle(.secondary) }
                    if let error {
                        NoticeView(message: error) { Task { await load(reset: threads.isEmpty, refresh: true) } }
                        CommunityWebButton(title: "Open official discussions", url: originalURL)
                    }
                    ForEach(matches) { thread in
                        NavigationLink {
                            CommunityThreadReader(thread: thread, anime: anime, localEpisode: episode, confirmIdentity: source == .myAnimeList)
                        } label: {
                            CommunityThreadRow(thread: thread, title: thread.previewTitle(progress: progress, mappedEpisode: episode, mediaID: anime.id))
                        }.buttonStyle(.plain)
                    }
                    if loading { ProgressView("Finding discussions…").frame(maxWidth: .infinity).padding() }
                    else if matches.isEmpty && error == nil {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("No exact discussion found on this page.").font(.headline)
                            Text(episode == nil ? "Try another source or search more threads. General conversations exclude episode threads." : "Only an exact single-episode match is shown. Ranges, specials and different seasons are never substituted. Try more threads, another title/source, or adjust numbering if you know the community uses an offset.")
                                .font(.caption).foregroundStyle(.secondary)
                            CommunityWebButton(title: "Browse official discussions", url: originalURL)
                        }.companionPanel()
                    }
                    if hasMore && !loading { Button("Search more threads") { Task { await load(reset: false) } }.buttonStyle(.bordered).frame(maxWidth: .infinity) }
                }
            }.padding(16).frame(maxWidth: 860, alignment: .leading).frame(maxWidth: .infinity)
        }.background(Theme.background).navigationTitle("Discussions").navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { NavigationLink { CommunitySourcesView() } label: { Image(systemName: "slider.horizontal.3") }.accessibilityLabel("Community sources") } }
            .task(id: loadKey) { await load(reset: true) }
            .refreshable { await load(reset: true, refresh: true) }
            .sheet(isPresented: $numbering) {
                AppNavigationStack { CommunityEpisodeNumberingView(source: source, animeID: anime.id, localEpisode: selection, offset: offset) }
            }
            .onAppear { episodeText = String(max(1, selection)) }
            .onChange(of: selection) { _, value in episodeText = String(max(1, value)) }
            .accessibilityIdentifier("series-discussions")
    }
    private var originalURL: URL {
        source == .myAnimeList ? CommunityBrowserLinks.myAnimeList(anime: anime) : URL(string: "https://anilist.co/anime/\(anime.id)/social")!
    }
    private var episodePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Discussion scope", selection: Binding(get: { episode == nil ? 0 : 1 }, set: { mode in
                chosenEpisode = mode == 0 ? 0 : max(1, min(episodeLimit, watched)); episodeText = String(max(1, chosenEpisode))
            })) { Text("Series").tag(0); Text("Episode").tag(1) }.pickerStyle(.segmented)
            if episode != nil {
                HStack(spacing: 10) {
                    Text("Episode").font(.subheadline.weight(.semibold))
                    TextField("Number", text: $episodeText).keyboardType(.numberPad).textFieldStyle(.roundedBorder).frame(width: 72)
                        .accessibilityIdentifier("discussion-episode-number")
                    Button("Go") {
                        if let number = Int(episodeText) { chosenEpisode = max(1, min(episodeLimit, number)); episodeText = String(chosenEpisode) }
                    }.disabled(Int(episodeText) == nil).frame(minHeight: 44)
                    Spacer(minLength: 0)
                    Stepper("Episode", value: Binding(get: { max(1, selection) }, set: { chosenEpisode = $0; episodeText = String($0) }), in: 1...episodeLimit).labelsHidden().accessibilityLabel("Choose discussion episode")
                }
            }
            if watched > 0 {
                Button("Latest marked watched · Episode \(watched)") { chosenEpisode = watched; episodeText = String(watched) }
                    .font(.caption).frame(minHeight: 36)
            }
        }.companionPanel(padding: 12)
    }
    @MainActor private func load(reset: Bool, refresh: Bool = false) async {
        guard reset || !loading else { return }
        let current = UUID(); attempt = current
        if reset { threads = []; page = 0; hasMore = false }
        loading = false; error = nil
        guard source != .reddit, mappedEpisode.map({ $0 > 0 }) ?? true,
              source != .myAnimeList || CommunityConfiguration.malClientID != nil else { return }
        loading = true
        let requestedPage = page + 1
        defer { if attempt == current { loading = false } }
        do {
            let result: CommunityThreadPage
            if source == .aniList { result = try await store.aniList.communityThreads(mediaID: anime.id, page: requestedPage, refresh: refresh) }
            else { result = try await store.communityMAL.topics(clientID: CommunityConfiguration.malClientID ?? "", query: searchTitle, page: requestedPage, refresh: refresh) }
            try Task.checkCancellation(); guard attempt == current else { return }
            var ids = Set(threads.map(\.id))
            threads += result.threads.filter { ids.insert($0.id).inserted }
            page = requestedPage; hasMore = result.hasNextPage
        } catch is CancellationError {} catch { if attempt == current { self.error = error.localizedDescription } }
    }
}

private struct CommunityEpisodeNumberingView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(CommunityConfiguration.offsetKey) private var saved = ""
    let source: CommunitySource
    let animeID: Int
    let localEpisode: Int
    @State private var number: String
    init(source: CommunitySource, animeID: Int, localEpisode: Int, offset: Int) {
        self.source = source; self.animeID = animeID; self.localEpisode = localEpisode
        _number = State(initialValue: String(localEpisode + offset))
    }
    var body: some View {
        Form {
            Section {
                Text("Your episode \(localEpisode)").font(.headline)
                TextField("Episode number on \(source.title)", text: $number).keyboardType(.numberPad)
                Text("Enter the community’s number for this exact episode. The adjustment is remembered for this series and this source. Titles and season identifiers are retained; no offset is inferred automatically.").font(.caption).foregroundStyle(.secondary)
            } header: { Text("Community episode numbering") }
            Section {
                Button("Use this numbering") {
                    guard let number = Int(number), (1...100_000).contains(number) else { return }
                    saved = CommunityConfiguration.updatingOffset(number - localEpisode, source: source, animeID: animeID, saved: saved); dismiss()
                }.disabled(Int(number).map { !(1...100_000).contains($0) } ?? true)
                Button("Reset to this season’s numbering") {
                    saved = CommunityConfiguration.updatingOffset(0, source: source, animeID: animeID, saved: saved); dismiss()
                }
            }
        }.navigationTitle("Episode numbering").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
    }
}
