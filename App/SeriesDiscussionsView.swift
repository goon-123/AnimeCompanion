import SwiftUI
import AnimeCore

/// A single quiet entry point alongside the series reviews.
struct AnimeDiscussionsSection: View {
    let anime: Anime
    var body: some View {
        HStack(spacing: 0) {
            NavigationLink { SeriesCommunityView(anime: anime) } label: {
                HStack(spacing: 5) {
                    Image(systemName: "bubble.left.and.bubble.right")
                    Text("Discussions")
                    Image(systemName: "chevron.right").font(.caption2)
                }.font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(Theme.accent.opacity(0.08), in: Capsule()).frame(minHeight: 44)
            }.buttonStyle(.plain).accessibilityIdentifier("anime-discuss-latest")
        }.accessibilityIdentifier("anime-discussions-section")
    }
}

struct SeriesDiscussionsView: View {
    @EnvironmentObject private var store: AppStore
    @AppStorage(CommunityConfiguration.offsetKey) private var offsets = ""
    let anime: Anime
    var requestedEpisode: Int? = nil
    private let source = CommunitySource.aniList
    @State private var chosenEpisode = -1
    @State private var episodeText = ""
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
    private var matches: [CommunityThread] {
        threads.filter { thread in
            guard thread.source == .aniList, store.includeAdult || !thread.media.contains(where: { $0.isAdult == true }) else { return false }
            if let episode { return CommunityEpisodeTitle.matches(thread, anime: anime, episode: episode, offset: offset) }
            return !thread.mentionsEpisode
        }
    }
    private var progress: [Int: Int] { [anime.id: watched] }
    private var loadKey: String { "\(selection)-\(offset)-\(store.includeAdult)" }
    private var originalURL: URL { URL(string: "https://anilist.co/anime/\(anime.id)/social")! }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                Text(anime.displayTitle).font(.title3.bold())
                episodePicker
                Label("AniList · Native comments & replies", systemImage: "text.bubble").font(.caption).foregroundStyle(Theme.accent)
                if episode != nil {
                    HStack {
                        Text(offset == 0 ? "Uses this season’s episode numbering" : "Your episode \(selection) → AniList episode \(mappedEpisode ?? selection)")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer(minLength: 6)
                        Button("Numbering") { numbering = true }.font(.caption.weight(.semibold)).frame(minHeight: 44)
                    }
                }
                if let mappedEpisode, mappedEpisode < 1 {
                    Text("Open Numbering to correct or reset this episode adjustment.").foregroundStyle(.secondary).companionPanel()
                } else {
                    if let episode, episode > watched {
                        Label("Episode \(episode) previews hidden · Not marked watched", systemImage: "eye.slash").font(.caption).foregroundStyle(.secondary)
                    }
                    if let error { NoticeView(message: error) { Task { await load(reset: threads.isEmpty, refresh: true) } } }
                    ForEach(matches) { thread in
                        NavigationLink { CommunityThreadReader(thread: thread, anime: anime, localEpisode: episode) } label: {
                            CommunityThreadRow(thread: thread, title: thread.previewTitle(progress: progress, mappedEpisode: episode, mediaID: anime.id),
                                hiddenPreview: thread.hidesPreview(progress: progress, mappedEpisode: episode, mediaID: anime.id), anime: anime)
                        }.buttonStyle(.plain)
                    }
                    if loading { ProgressView("Finding AniList discussions…").frame(maxWidth: .infinity).padding() }
                    else if matches.isEmpty && error == nil {
                        Text(episode == nil ? "No series discussions found yet." : "No exact single-episode discussion found yet. Search more threads or adjust numbering if this series uses a known offset.")
                            .font(.caption).foregroundStyle(.secondary).companionPanel()
                    }
                    if hasMore && !loading { Button("Search more threads") { Task { await load(reset: false) } }.buttonStyle(.bordered) }
                    CommunityWebButton(title: "Open AniList discussions", url: originalURL)
                }
            }.padding(16).frame(maxWidth: 860, alignment: .leading).frame(maxWidth: .infinity)
        }.background(Theme.background).navigationTitle("Discussions").navigationBarTitleDisplayMode(.inline)
            .companionDockHidden()
            .task(id: loadKey) { await load(reset: true) }
            .refreshable { await load(reset: true, refresh: true) }
            .sheet(isPresented: $numbering) {
                AppNavigationStack { CommunityEpisodeNumberingView(source: source, animeID: anime.id, localEpisode: selection, offset: offset) }
            }
            .onAppear { episodeText = String(max(1, selection)) }
            .onChange(of: selection) { _, value in episodeText = String(max(1, value)) }
            .accessibilityIdentifier("series-discussions")
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
        guard mappedEpisode.map({ $0 > 0 }) ?? true else { return }
        loading = true
        let requestedPage = page + 1
        defer { if attempt == current { loading = false } }
        do {
            let result = try await store.aniList.communityThreads(mediaID: anime.id, page: requestedPage, refresh: refresh)
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
