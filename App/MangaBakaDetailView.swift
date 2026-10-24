import SwiftUI
import AnimeCore

struct MangaBakaDetailView: View {
    @EnvironmentObject private var account: MangaBakaStore
    @EnvironmentObject private var preferences: AppStore
    @EnvironmentObject private var navigation: AppNavigationStore
    @State var series: MangaBakaSeries
    @State private var error: String?
    @State private var editing = false
    @State private var signingIn = false
    @State private var expanding = false
    @State private var refreshToken = 0
    @State private var preview: AnimeImagePreview?
    private var entry: MangaBakaLibraryEntry? { account.entries[series.id] }
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if series.isVisible(includeAdult: preferences.includeAdult) {
                    VStack(alignment: .leading, spacing: 26) {
                        header.id("overview")
                        MangaBakaBadges(series: series)
                        jumpLinks(proxy)
                        actions
                        if let notice = account.notice { Text(notice).font(.subheadline).foregroundStyle(.mint) }
                        if let error { NoticeView(message: error) { Task { await reload(refresh: true) } } }
                        story
                        metadata
                        sourceRatings
                        MangaBakaSeriesTags(series: series).id("tags")
                        readingSource
                        officialLinks
                        MangaBakaCoverGallery(series: series, refreshToken: refreshToken).id("covers")
                        ForEach(MangaBakaRelatedKind.allCases, id: \.self) { kind in
                            MangaBakaRelatedSection(series: series, kind: kind, refreshToken: refreshToken).id(kind.rawValue)
                        }
                        MangaBakaAttribution(providers: series.providers)
                    }.padding(20).frame(maxWidth: 1000, alignment: .leading).frame(maxWidth: .infinity)
                } else { ContentUnavailableView("Hidden by content settings", systemImage: "eye.slash") }
            }
        }.background(Theme.background).navigationTitle("Series").navigationBarTitleDisplayMode(.inline)
            .task(id: account.connected) { await reload() }
            .refreshable { refreshToken += 1; await reload(refresh: true) }
            .sheet(isPresented: $editing) { NavigationStack { MangaBakaTrackingView(series: series) } }
            .sheet(isPresented: $signingIn) {
                NavigationStack { MangaBakaAccountView().toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { signingIn = false } } } }
            }
            .fullScreenCover(item: $preview) { AnimeImageViewer(preview: $0) }
            .onChange(of: preferences.includeAdult) { _, _ in preview = nil }
    }
    private var header: some View {
        HStack(alignment: .top, spacing: 20) {
            Button {
                if let url = series.fullCoverURL { preview = AnimeImagePreview(url: url, title: series.displayTitle, source: "MangaBaka") }
            } label: { MangaBakaCover(series: series, width: 118) }
                .buttonStyle(.plain).accessibilityLabel("Enlarge series cover")
            VStack(alignment: .leading, spacing: 10) {
                Text(series.formatLabel.uppercased()).font(.caption.bold()).tracking(1.2).foregroundStyle(.mint)
                Text(series.displayTitle).font(.title2.bold()).textSelection(.enabled)
                if let native = series.nativeTitle, !native.isEmpty, native != series.displayTitle {
                    Text(native).font(.subheadline).foregroundStyle(.secondary).textSelection(.enabled)
                }
                if let rating = series.rating, rating > 0 {
                    Label(rating.formatted(.number.precision(.fractionLength(0...1))) + "% · Community score", systemImage: "star.fill")
                        .font(.caption).foregroundStyle(.yellow)
                }
                if let rank = series.popularityRank, rank > 0 { Text("Popularity #" + rank.formatted()).font(.caption).foregroundStyle(.secondary) }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func jumpLinks(_ proxy: ScrollViewProxy) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 9) {
                jump("Info", id: "overview", proxy: proxy)
                jump("Tags", id: "tags", proxy: proxy)
                jump("Covers", id: "covers", proxy: proxy)
                jump("Related", id: "relationships", proxy: proxy)
                jump("Similar", id: "similar", proxy: proxy)
                jump("Readers also like", id: "readers-also-like", proxy: proxy)
            }
        }
    }
    private func jump(_ title: String, id: String, proxy: ScrollViewProxy) -> some View {
        Button(title) { proxy.scrollTo(id, anchor: .top) }.font(.subheadline.weight(.semibold)).buttonStyle(.bordered)
    }
    private var actions: some View {
        Button { if account.connected { editing = true } else { signingIn = true } } label: {
            HStack {
                Image(systemName: entry == nil ? "plus" : "checkmark.circle.fill")
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.map { MangaBakaReadingStatus(rawValue: $0.state)?.label ?? $0.state.capitalized } ?? "Add to My Library").font(.headline)
                    if let entry { Text("Chapter \(entry.chapter ?? 0, specifier: "%g") · Edit progress").font(.caption) }
                    else if !account.connected { Text("Connect your MangaBaka account").font(.caption) }
                }
                Spacer(); Image(systemName: "chevron.right")
            }.padding(18).foregroundStyle(.black).background(.white, in: RoundedRectangle(cornerRadius: 20))
        }.buttonStyle(.plain)
    }
    @ViewBuilder private var story: some View {
        if !series.synopsis.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("The story").font(.title2.bold())
                Text(series.synopsis).font(.body).foregroundStyle(.secondary).lineLimit(expanding ? nil : 7)
                Button(expanding ? "Show less" : "Read more") { expanding.toggle() }.font(.subheadline.bold())
            }
        }
    }
    private var metadata: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Details").font(.title2.bold())
            if !series.authors.isEmpty { LabeledContent("Story", value: series.authors.joined(separator: ", ")) }
            if !series.artists.isEmpty { LabeledContent("Art", value: series.artists.joined(separator: ", ")) }
            if let start = series.publishedStart { LabeledContent("Publication began", value: start) }
            if let end = series.publishedEnd { LabeledContent("Publication ended", value: end) }
            if !series.publishers.isEmpty { LabeledContent("Publishers", value: series.publishers.map(\.name).joined(separator: ", ")) }
            if !series.titles.isEmpty { alternativeTitles }
        }.font(.subheadline)
    }
    private var alternativeTitles: some View {
        DisclosureGroup("Alternative titles (\(series.titles.count))") {
            ForEach(Array(series.titles.enumerated()), id: \.offset) { _, title in
                HStack(alignment: .top, spacing: 12) {
                    Text(title.language.uppercased()).font(.caption.monospaced()).foregroundStyle(.secondary).frame(width: 62, alignment: .leading)
                    Text(title.title).font(.subheadline).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }.padding(.vertical, 4)
            }
        }
    }
    @ViewBuilder private var sourceRatings: some View {
        if !series.sourceRatings.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Community ratings").font(.headline)
                MangaBakaFlowLayout {
                    ForEach(series.sourceRatings, id: \.provider) { value in
                        Text(value.provider + " · " + value.score.formatted(.number.precision(.fractionLength(0...1))) + "%")
                            .font(.caption).padding(9).background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }
    }
    @ViewBuilder private var readingSource: some View {
        if series.type == "novel" {
            VStack(alignment: .leading, spacing: 8) {
                Label("Novel discovery & tracking", systemImage: "text.book.closed").font(.headline)
                Text("Use an official publisher or reading service for the book. MangaBaka provides metadata and progress tracking.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        } else {
            Button { navigation.openMangaSearch(titles: series.searchTitles) } label: {
                HStack(spacing: 14) {
                    Image(systemName: "book.closed").font(.title2)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Find a reading source").font(.headline)
                        Text("Search your installed manga extensions").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(); Image(systemName: "arrow.right")
                }.padding(18).background(Theme.surface, in: RoundedRectangle(cornerRadius: 20))
            }.buttonStyle(.plain)
        }
    }
    private var officialLinks: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Links").font(.headline)
            Link(destination: series.websiteURL) { Label("View on MangaBaka", systemImage: "arrow.up.right.square") }
            ForEach(Array(series.links.compactMap(MangaBakaSeries.publicURL).prefix(40).enumerated()), id: \.offset) { _, url in
                Link(url.host ?? "Related site", destination: url).font(.subheadline)
            }
        }
    }
    private func reload(refresh: Bool = false) async {
        error = nil
        do {
            let loaded = try await account.api.details(id: series.id, refresh: refresh)
            try Task.checkCancellation(); series = loaded
        } catch is CancellationError { return } catch { self.error = error.localizedDescription }
        if account.connected {
            do { _ = try await account.loadEntry(series) } catch is CancellationError {} catch { self.error = error.localizedDescription }
        }
    }
}
