import SwiftUI
import AnimeCore
import WebKit

struct CommunityThreadReader: View {
    @EnvironmentObject private var store: AppStore
    let thread: CommunityThread
    var anime: Anime? = nil
    var localEpisode: Int? = nil
    @State private var spoilersAllowed = false
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
    private var canLoad: Bool { !spoilerGate }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if thread.seriesName != nil || anime != nil {
                    CommunitySeriesContext(thread: thread, anime: anime, episode: episode)
                }
                if spoilerGate {
                    VStack(alignment: .leading, spacing: 14) {
                        Label(episode.map { "Episode \($0) discussion" } ?? "Episode discussion", systemImage: "eye.slash").font(.title3.bold())
                        Text("This episode is beyond your marked-watched progress, or its numbering is unverified. Plot previews, episode subtitles and comments stay hidden until you choose to read.").font(.subheadline).foregroundStyle(.secondary)
                        Button("Read anyway") { spoilersAllowed = true }.buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("community-reveal-unwatched")
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
            .companionDockHidden()
            .task(id: "\(thread.id)-\(sort.rawValue)-\(canLoad)") {
                if canLoad { await load(reset: true) }
                else { attempt = UUID(); comments = []; opening = nil; loading = false }
            }
            .refreshable { if canLoad { await load(reset: true, refresh: true) } }
            .onChange(of: store.viewer?.id) { _, _ in spoilersAllowed = false }
            .accessibilityIdentifier("community-native-reader")
    }
    @MainActor private func load(reset: Bool, refresh: Bool = false) async {
        guard canLoad, reset || !loading else { return }
        let current = UUID(); attempt = current
        let requestedPage = reset ? 1 : page + 1
        if reset { hasMore = false; page = 1 }
        loading = true; error = nil
        defer { if attempt == current { loading = false } }
        do {
            let result: CommunityCommentPage
            switch thread.source {
            case .aniList: result = try await store.aniList.communityComments(threadID: thread.threadID, page: requestedPage, sort: sort, refresh: refresh)
            case .myAnimeList, .reddit: throw ServiceError.message("This Community source is no longer available. Choose AniList.")
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
            var ids = Set(reset ? [] : comments.map(\.id))
            let incoming = result.comments.filter { ids.insert($0.id).inserted }
            comments = reset ? incoming : comments + incoming
            opening = result.body; page = requestedPage; hasMore = result.hasNextPage
        } catch is CancellationError {} catch { if attempt == current { self.error = error.localizedDescription } }
    }
}

struct CommunityThreadMetadata: View {
    @Environment(\.homeVisuals) private var visuals
    let thread: CommunityThread
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { source; count; time }
            VStack(alignment: .leading, spacing: 4) { source; HStack(spacing: 8) { count; time } }
        }.font(visuals.enlarged ? .caption : .caption2).foregroundStyle(.secondary)
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
                case .text(let text):
                    Text((try? AttributedString(markdown: text)) ?? AttributedString(text))
                        .font(.subheadline).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                case .image(let url, let alt): CommunityInlineImage(url: url, alt: alt)
                case .spoiler(let text):
                    if revealed.contains(index) {
                        VStack(alignment: .leading, spacing: 4) {
                            AnyView(CommunityTextView(text))
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

struct CommunitySeriesContext: View {
    let thread: CommunityThread
    var anime: Anime?
    var episode: Int?
    var body: some View {
        HStack(spacing: 12) {
            CommunityThreadArtwork(url: anime?.coverURL ?? thread.media.first?.coverURL)
            VStack(alignment: .leading, spacing: 5) {
                Text(anime?.displayTitle ?? thread.seriesName ?? "Anime discussion").font(.headline)
                if let episode { Text("Episode \(episode)").font(.subheadline).foregroundStyle(Theme.accent) }
                Text(thread.source.title).font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.companionPanel(padding: 12)
    }
}

struct CommunityThreadArtwork: View {
    @Environment(\.homeVisuals) private var visuals
    let url: URL?
    var body: some View {
        Group {
            if let url, url.pathExtension.lowercased() == "svg" {
                CommunitySVGImage(url: url)
            } else {
                ArtworkImage(url: url, pointSize: visuals.value(64, 128)) { $0.resizable().scaledToFill() } placeholder: {
                    ZStack {
                        LinearGradient(colors: [Theme.accent.opacity(0.25), Theme.secondarySurface], startPoint: .topLeading, endPoint: .bottomTrailing)
                        Image(systemName: "bubble.left.and.bubble.right").font(visuals.enlarged ? .largeTitle : .body).foregroundStyle(Theme.accent)
                    }
                }
            }
        }.frame(width: visuals.communityCover, height: visuals.value(78, 122)).clipShape(RoundedRectangle(cornerRadius: 9)).accessibilityHidden(true)
    }
}

struct CommunityInlineImage: View {
    let url: URL
    let alt: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if url.pathExtension.lowercased() == "svg" {
                CommunitySVGImage(url: url).frame(height: 180).accessibilityLabel(alt)
            } else {
                ArtworkPhaseView(url: url, pointSize: 860) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: 420).accessibilityLabel(alt)
                    } else if phase.error != nil {
                        Label("Image unavailable", systemImage: "photo").font(.caption).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 70)
                    } else {
                        ProgressView("Loading image…").font(.caption).frame(maxWidth: .infinity, minHeight: 70)
                    }
                }
            }
            CommunityWebButton(title: "Open image", url: url)
        }.clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

/// SVGs are image-only documents, isolated from account cookies and with scripts disabled.
private struct CommunitySVGImage: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.isOpaque = false; view.backgroundColor = .clear
        view.scrollView.isScrollEnabled = false; view.scrollView.backgroundColor = .clear
        return view
    }
    func updateUIView(_ view: WKWebView, context: Context) {
        guard view.accessibilityIdentifier != url.absoluteString else { return }
        view.accessibilityIdentifier = url.absoluteString
        let escaped = url.absoluteString.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "<", with: "&lt;")
        view.loadHTMLString("""
        <html><head><meta name="viewport" content="width=device-width, initial-scale=1"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src https:; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'"><style>html,body{margin:0;height:100%;background:transparent}img{width:100%;height:100%;object-fit:contain}</style></head><body><img src="\(escaped)"></body></html>
        """, baseURL: nil)
    }
}

struct CommunityWebButton: View {
    @Environment(\.homeVisuals) private var visuals
    let title: String
    let url: URL
    @State private var showing = false
    var body: some View {
        Button { showing = true } label: { Label(title, systemImage: "safari").font(visuals.actionTextFont).frame(minHeight: 44) }
            .sheet(isPresented: $showing) { ArticleBrowser(url: url).ignoresSafeArea() }
    }
}

struct CommunitySourcePicker: View {
    @AppStorage(CommunityDestination.storageKey) private var saved = CommunityDestination.aniList.rawValue
    var body: some View {
        Label("AniList", systemImage: "text.bubble").font(.caption).foregroundStyle(.secondary)
            .onAppear { if saved != CommunityDestination.aniList.rawValue { saved = CommunityDestination.aniList.rawValue } }
    }
}

struct CommunitySourcesView: View {
    var body: some View {
        Form {
            Section("Community source") { CommunitySourcePicker() }
            Section("AniList") {
                Text("Read discussions, comments and replies for This Season or My Shows. My Shows uses your connected AniList library.")
            }
        }.navigationTitle("Community sources").navigationBarTitleDisplayMode(.inline)
    }
}
