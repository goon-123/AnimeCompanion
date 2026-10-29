import SwiftUI
import AnimeCore

struct CommunityThreadReader: View {
    @EnvironmentObject private var store: AppStore
    @AppStorage(CommunityConfiguration.revisionKey) private var revision = 0
    let thread: CommunityThread
    var anime: Anime? = nil
    var localEpisode: Int? = nil
    var confirmIdentity = false
    @State private var spoilersAllowed = false
    @State private var identityConfirmed = false
    @State private var sort = CommunityCommentSort.oldest
    @State private var comments: [CommunityComment] = []
    @State private var opening: String?
    @State private var loading = false
    @State private var error: String?
    @State private var page = 1
    @State private var hasMore = false
    @State private var attempt = UUID()
    private var episode: Int? { localEpisode ?? thread.episode }
    private var unwatched: Bool {
        guard thread.mentionsEpisode || localEpisode != nil else { return false }
        guard let episode else { return true }
        let ids = anime.map { [$0.id] } ?? thread.media.filter { $0.type == "ANIME" }.map(\.id)
        return ids.isEmpty || ids.contains { (store.entry(for: $0)?.progressValue ?? 0) < episode }
    }
    private var spoilerGate: Bool { unwatched && !spoilersAllowed }
    private var identityGate: Bool { confirmIdentity && !identityConfirmed }
    private var canLoad: Bool { !spoilerGate && !identityGate }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if spoilerGate {
                    VStack(alignment: .leading, spacing: 14) {
                        Label(episode.map { "Episode \($0) discussion" } ?? "Episode discussion", systemImage: "eye.slash").font(.title3.bold())
                        Text("This episode is beyond your marked-watched progress, or its numbering is unverified. Titles, opening posts and comments stay hidden until you choose to read.").font(.subheadline).foregroundStyle(.secondary)
                        Button("Read anyway") { spoilersAllowed = true }.buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("community-reveal-unwatched")
                    }.companionPanel()
                } else if identityGate {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Confirm this discussion", systemImage: "checkmark.shield").font(.headline)
                        Text(confirmationTitle).font(.subheadline.weight(.semibold))
                        if let anime { Text(anime.displayTitle + (localEpisode.map { " · Your episode \($0)" } ?? "")).font(.caption).foregroundStyle(Theme.accent) }
                        Text("MyAnimeList’s topic search does not supply a series ID. Check the season/cour and episode in this title before reading. This match has not been verified by an ID.").font(.caption).foregroundStyle(.secondary)
                        Button("This is the discussion I want") { identityConfirmed = true }.buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("community-confirm-match")
                    }.companionPanel()
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(thread.title).font(.title3.bold()).fixedSize(horizontal: false, vertical: true)
                        CommunityThreadMetadata(thread: thread)
                        HStack {
                            Label("Native reader", systemImage: "text.bubble").font(.caption).foregroundStyle(Theme.accent)
                            Spacer()
                            CommunityWebButton(title: "Original", url: thread.url)
                        }
                        if let episode, let anime {
                            Text("\(anime.displayTitle) · Your episode \(episode)").font(.caption).foregroundStyle(.secondary)
                        }
                    }.companionPanel()
                    if let opening, !opening.isEmpty { CommunityTextView(opening).companionPanel().id("body-" + thread.id + opening) }
                    HStack {
                        Text("Comments & replies").font(.headline)
                        Spacer()
                        if thread.source == .aniList {
                            Picker("Comment order", selection: $sort) { ForEach(CommunityCommentSort.allCases) { Text($0.title).tag($0) } }.pickerStyle(.menu)
                        } else { Text("Oldest first").font(.caption).foregroundStyle(.secondary) }
                    }
                    if let error { NoticeView(message: error) { Task { await load(reset: comments.isEmpty, refresh: true) } } }
                    ForEach(comments) { comment in CommunityCommentBranch(comment: comment).id("\(thread.id)-\(comment.id)") }
                    if loading { ProgressView("Loading comments…").frame(maxWidth: .infinity).padding() }
                    else if comments.isEmpty && error == nil { Text("No comments yet. You can check the original discussion for updates.").font(.subheadline).foregroundStyle(.secondary).companionPanel() }
                    if hasMore && !loading { Button("Load more comments") { Task { await load(reset: false) } }.buttonStyle(.bordered).frame(maxWidth: .infinity) }
                    CommunityWebButton(title: "Read or reply on \(thread.source.title)", url: thread.url)
                }
            }.padding(16).frame(maxWidth: 860, alignment: .leading).frame(maxWidth: .infinity)
        }.background(Theme.background).navigationTitle("Discussion").navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
            .task(id: "\(thread.id)-\(sort.rawValue)-\(canLoad)-\(revision)") {
                if canLoad { await load(reset: true) }
                else { attempt = UUID(); comments = []; opening = nil; loading = false }
            }
            .refreshable { if canLoad { await load(reset: true, refresh: true) } }
            .onChange(of: store.viewer?.id) { _, _ in spoilersAllowed = false; identityConfirmed = false }
            .accessibilityIdentifier("community-native-reader")
    }
    private var confirmationTitle: String {
        if let parsed = CommunityEpisodeTitle.parse(thread.title) { return "\(parsed.titlePrefix) · Episode \(parsed.episode)" }
        return thread.mentionsEpisode ? "Episode discussion · Unverified numbering" : thread.title
    }
    @MainActor private func load(reset: Bool, refresh: Bool = false) async {
        guard canLoad, reset || !loading else { return }
        let current = UUID(); attempt = current
        let requestedPage = reset ? 1 : page + 1
        if reset { comments = []; opening = nil; hasMore = false; page = 1 }
        loading = true; error = nil
        defer { if attempt == current { loading = false } }
        do {
            let result: CommunityCommentPage
            switch thread.source {
            case .aniList: result = try await store.aniList.communityComments(threadID: thread.threadID, page: requestedPage, sort: sort, refresh: refresh)
            case .myAnimeList: result = try await store.communityMAL.comments(threadID: thread.threadID, clientID: CommunityConfiguration.malClientID ?? "", page: requestedPage, refresh: refresh)
            case .reddit: throw ServiceError.message("Reddit comments are available in the official in-app browser.")
            }
            try Task.checkCancellation(); guard attempt == current, canLoad else { return }
            if let number = thread.episode, CommunityEpisodeTitle.parse(result.title)?.episode != number {
                throw ServiceError.message("The discussion’s episode title changed. Return to the discussion list and refresh before reading.")
            }
            if let anime, localEpisode != nil, thread.source == .aniList,
               Set((result.media ?? []).filter { $0.type == "ANIME" }.map(\.id)) != [anime.id] {
                throw ServiceError.message("This discussion no longer has an unambiguous match to this season. Return to the series and choose another thread.")
            }
            if !store.includeAdult && (result.media ?? []).contains(where: { $0.isAdult == true }) {
                throw ServiceError.message("This discussion is hidden by your content preferences.")
            }
            var ids = Set(comments.map(\.id))
            comments += result.comments.filter { ids.insert($0.id).inserted }
            opening = result.body; page = requestedPage; hasMore = result.hasNextPage
        } catch is CancellationError {} catch { if attempt == current { self.error = error.localizedDescription } }
    }
}

struct CommunityThreadMetadata: View {
    let thread: CommunityThread
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { source; count; time }
            VStack(alignment: .leading, spacing: 4) { source; HStack(spacing: 8) { count; time } }
        }.font(.caption2).foregroundStyle(.secondary)
    }
    private var source: some View { Text(thread.source.title).fontWeight(.semibold).foregroundStyle(Theme.accent) }
    @ViewBuilder private var count: some View { if let count = thread.commentCount { Label(count.formatted(), systemImage: "bubble.right").accessibilityLabel("\(count) comments") } }
    @ViewBuilder private var time: some View { if let date = thread.activityAt { Text(date, style: .relative) } }
}

struct CommunityCommentBranch: View {
    let comment: CommunityComment
    var depth = 0
    @State private var expanded = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(comment.author).font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
                if let date = comment.createdAt { Text(date, style: .relative).font(.caption2).foregroundStyle(.secondary) }
                Spacer(minLength: 0)
                if let score = comment.score { Label(score.formatted(), systemImage: "heart").font(.caption2).foregroundStyle(.secondary).accessibilityLabel("\(score) likes") }
            }
            CommunityTextView(comment.body).id(comment.body)
            if !comment.replies.isEmpty {
                Button { expanded.toggle() } label: {
                    Label(expanded ? "Hide replies" : "\(comment.replies.count) replies", systemImage: expanded ? "chevron.up" : "arrow.turn.down.right")
                        .font(.caption.weight(.semibold)).frame(minHeight: 44, alignment: .leading)
                }.accessibilityIdentifier("community-replies-\(comment.id)")
                if expanded {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(comment.replies) { reply in
                            AnyView(CommunityCommentBranch(comment: reply, depth: depth + 1))
                        }
                    }.padding(.leading, depth < 3 ? 12 : 0)
                        .overlay(alignment: .leading) { Rectangle().fill(Theme.accent.opacity(0.20)).frame(width: 2) }
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(depth == 0 ? 14 : 4)
            .background(depth == 0 ? Theme.surface : .clear, in: RoundedRectangle(cornerRadius: 14))
    }
}

struct CommunityTextView: View {
    private let pieces: [CommunityTextSegment]
    @State private var revealed = Set<Int>()
    init(_ value: String) { pieces = CommunityText.segments(value) }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(pieces.enumerated()), id: \.offset) { index, piece in
                switch piece {
                case .text(let text): Text(text).font(.subheadline).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                case .spoiler(let text):
                    if revealed.contains(index) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(text).font(.subheadline).textSelection(.enabled)
                            Button("Hide spoiler") { revealed.remove(index) }.font(.caption)
                        }.padding(10).background(Theme.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
                    } else {
                        Button { revealed.insert(index) } label: {
                            Label("Spoiler · Tap to reveal", systemImage: "eye.slash").font(.caption.weight(.semibold)).padding(10).frame(minHeight: 44)
                                .background(Theme.secondarySurface, in: RoundedRectangle(cornerRadius: 8))
                        }.accessibilityIdentifier("community-spoiler-\(index)")
                    }
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CommunityWebButton: View {
    let title: String
    let url: URL
    @State private var showing = false
    var body: some View {
        Button { showing = true } label: { Label(title, systemImage: "safari").font(.caption.weight(.semibold)).frame(minHeight: 44) }
            .sheet(isPresented: $showing) { ArticleBrowser(url: url).ignoresSafeArea() }
    }
}

struct CommunityBrowserPanel: View {
    let source: CommunitySource
    let url: URL
    var episode: Int? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(source.title, systemImage: "bubble.left.and.bubble.right").font(.headline)
            Text("Official page · In-app browser").font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
            Text(source == .reddit ? "Browse live r/anime conversations, episode threads and replies inside the app. Reddit may ask you to sign in." : "Read discussions on MyAnimeList’s official site, or add a registered client ID for native reading.")
                .font(.subheadline).foregroundStyle(.secondary)
            if let episode { Text("Search for episode \(episode). Check the season/cour and number before opening a result. Website previews follow the community’s own spoiler rules.").font(.caption).foregroundStyle(.secondary) }
            CommunityWebButton(title: "Browse \(source.title)", url: url)
        }.companionPanel().accessibilityIdentifier("community-browser-fallback")
    }
}

struct CommunitySourcesView: View {
    @State private var clientID = ""
    @State private var message: String?
    var body: some View {
        Form {
            Section("AniList · Native reader") {
                Text("Public discussions, comments and nested replies need no extra sign-in. Reading uses the existing AniList integration.")
                Link("AniList API terms", destination: URL(string: "https://docs.anilist.co/guide/terms-of-use")!)
            }
            Section("Reddit · Official in-app browser") {
                Text("Native Reddit data access requires approval and registered OAuth access. AnimeCompanion currently opens official r/anime pages in Safari inside the app.")
                Link("Reddit API access requirements", destination: URL(string: "https://support.reddithelp.com/hc/en-us/articles/16160319875092-Reddit-Data-API-Wiki")!)
            }
            Section {
                SecureField("Registered MyAnimeList client ID", text: $clientID).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("Save MyAnimeList client ID") {
                    do { try CommunityConfiguration.saveMALClientID(clientID); message = clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Saved. MyAnimeList will use its official page." : "Client ID saved. Native reading is enabled when the ID has API access." }
                    catch { message = error.localizedDescription }
                }
                if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
                Link("Register an API client", destination: URL(string: "https://myanimelist.net/apiconfig")!)
                Link("MyAnimeList API agreement", destination: URL(string: "https://myanimelist.net/static/apiagreement.html")!)
            } header: { Text("MyAnimeList · Native reader with client ID") } footer: {
                Text("Use your registered client ID. It stays securely on this device. Public forum reading needs no separate user sign-in. MAL posts are chronological; quote-based replies retain their text, and the API does not provide a nested reply tree or scores.")
            }
        }.navigationTitle("Community sources").navigationBarTitleDisplayMode(.inline)
            .onAppear { clientID = CommunityConfiguration.malClientID ?? "" }
    }
}
