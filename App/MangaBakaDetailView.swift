import SwiftUI
import AnimeCore

struct MangaBakaDetailView: View {
    @EnvironmentObject private var account: MangaBakaStore
    @EnvironmentObject private var preferences: AppStore
    @EnvironmentObject private var navigation: AppNavigationStore
    @EnvironmentObject private var sourceLinks: MangaSourceLinkStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var tabIndicator
    @AppStorage("series.layout.manga.v1") private var sectionOrder = ""
    @State var series: MangaBakaSeries
    @State private var error: String?
    @State private var editing = false
    @State private var signingIn = false
    @State private var expanding = false
    @State private var linksExpanded = false
    @State private var refreshToken = 0
    @State private var preview: AnimeImagePreview?
    @State private var selectedTab = MangaTab.read
    @State private var arranging = false
    private enum MangaTab: String, CaseIterable { case read = "Read", info = "More Info", similar = "Similar" }
    private var tabs: [MangaTab] {
        var result: [MangaTab] = [.info]
        if layout.visible.contains(.reading) { result.insert(.read, at: 0) }
        if layout.visible.contains(.related) { result.append(.similar) }
        return result
    }
    init(series: MangaBakaSeries) {
        _series = State(initialValue: series)
        let saved = UserDefaults.standard.string(forKey: "series.layout.manga.v1") ?? ""
        _selectedTab = State(initialValue: SeriesDetailLayout(page: .manga, saved: saved).visible.contains(.reading) ? .read : .info)
    }
    private var entry: MangaBakaLibraryEntry? { account.entries[series.id] }
    private var layout: SeriesDetailLayout { SeriesDetailLayout(page: .manga, saved: sectionOrder) }
    private var visibleSections: [SeriesDetailSection] {
        layout.visible.filter { section in
            if [.watchlist, .reading, .synopsis, .related].contains(section) { return false }
            if section == .coverage { return series.animeAdaptation.map { $0.exists || $0.hasCoverage } == true }
            return true
        }
    }
    private var publishers: [MangaBakaPublisher] {
        Array(Set(series.publishers.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }))
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    var body: some View {
        detailScroll.seriesPosterSizing().ignoresSafeArea(.container, edges: .top)
            .background(Theme.background).navigationTitle(series.displayTitle).navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar).toolbar(.hidden, for: .tabBar)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { optionsMenu } }
            .navigationDestination(for: MangaBakaAnimeRoute.self) { route in
                AnimeDetailView(mediaID: route.id).id(route.id)
                    .environment(\.animeDetailContext, true).toolbar(.visible, for: .navigationBar)
                    .animeNavigation().mangaBakaNavigation()
            }
            .navigationDestination(for: MangaBakaAnimeSearchRoute.self) { route in
                DiscoveryBrowseView(category: .trending, selection: .current(), initialQuery: route.title)
                    .id(route).toolbar(.visible, for: .navigationBar).animeNavigation().mangaBakaNavigation()
            }
            .task(id: account.connectionID) { await reload() }
            .task { await sourceLinks.load() }
            .refreshable { refreshToken += 1; await reload(refresh: true) }
            .sheet(isPresented: $editing) { AppNavigationStack { MangaBakaTrackingView(series: series) } }
            .sheet(isPresented: $arranging) { AppNavigationStack { SeriesLayoutEditor(page: .manga) } }
            .sheet(isPresented: $signingIn) {
                AppNavigationStack { MangaBakaAccountView().toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { signingIn = false } } } }
            }
            .fullScreenCover(item: $preview) { AnimeImageViewer(preview: $0) }
            .onChange(of: preferences.mangaBakaContent) { _, _ in preview = nil }
            .onChange(of: sectionOrder) { _, _ in if !tabs.contains(selectedTab) { selectedTab = .info } }
    }
    private var detailScroll: some View {
        ScrollView {
            if series.isVisible(contentFilter: preferences.mangaBakaContent) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    CinematicMangaHero(series: series) { preview = AnimeImagePreview(url: $0, title: series.displayTitle, source: "MangaBaka") }
                    introduction.padding(.horizontal, 20).padding(.bottom, 20).readableContent(width: 1060)
                    tabPicker
                    VStack(alignment: .leading, spacing: 22) {
                        if let notice = account.notice { Text(notice).font(.caption).foregroundStyle(.mint) }
                        if let error { NoticeView(message: error) { Task { await reload(refresh: true) } } }
                        tabContent
                        MangaBakaAttribution(providers: series.providers)
                    }.id(selectedTab).transition(AppMotion.replacement(reduceMotion))
                        .padding(20).padding(.bottom, 28).readableContent(width: 1060)
                }
            } else { ContentUnavailableView("Hidden by content settings", systemImage: "eye.slash").padding(.top, 120) }
        }.ignoresSafeArea(.container, edges: .top).contentMargins(.top, 0, for: .scrollContent)
            .accessibilityIdentifier("mangabaka-detail-scroll")
    }
    private var introduction: some View {
        VStack(alignment: .leading, spacing: 16) {
            if layout.visible.contains(.reading) || layout.visible.contains(.watchlist) {
                HStack(spacing: 12) {
                    if layout.visible.contains(.reading) { readAction }
                    if layout.visible.contains(.watchlist) {
                        Button { editEntry() } label: {
                            Image(systemName: entry == nil ? "plus" : "checkmark").font(.title2.weight(.semibold))
                                .frame(width: 60, height: 60).background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
                        }.buttonStyle(.plain).foregroundStyle(Theme.accent).disabled(account.connecting || !account.saving.isEmpty)
                            .accessibilityLabel(entry == nil ? "Add to library and choose status" : "Edit reading status and progress")
                            .accessibilityIdentifier("mangabaka-library-status")
                    }
                }
            }
            if let entry {
                Text((MangaBakaReadingStatus(rawValue: entry.state)?.label ?? entry.state.capitalized) + " · Chapter " + (entry.chapter ?? 0).formatted())
                    .font(.caption).foregroundStyle(.secondary)
            }
            MangaBakaBadges(series: series)
            if layout.visible.contains(.synopsis) { story }
        }
    }
    @ViewBuilder private var readAction: some View {
        if series.type != "novel", let target = account.sourceLinkTarget(for: series), let link = sourceLinks.link(for: target) {
            NavigationLink { MangaTitleDetailView(title: link.title, linkingTo: target, resumeOnOpen: true) } label: {
                readLabel("Continue reading")
            }.buttonStyle(.plain).accessibilityIdentifier("mangabaka-read-now")
        } else {
            Button {
                if series.type == "novel" { withAnimation(AppMotion.page(reduceMotion)) { selectedTab = .read } }
                else { navigation.openMangaSearch(titles: series.searchTitles, linkingTo: account.sourceLinkTarget(for: series)) }
            } label: { readLabel(series.type == "novel" ? "Reading options" : "Find a reading source") }
                .buttonStyle(.plain).accessibilityIdentifier("mangabaka-read-now")
        }
    }
    private func readLabel(_ title: String) -> some View {
        Label(title, systemImage: "book.fill").font(.headline).frame(maxWidth: .infinity, minHeight: 60)
            .foregroundStyle(Theme.background).background(Theme.accent, in: RoundedRectangle(cornerRadius: 14))
    }
    private var tabPicker: some View {
        HStack(spacing: 0) {
            ForEach(tabs, id: \.self) { tab in
                Button {
                    withAnimation(AppMotion.page(reduceMotion)) { selectedTab = tab }
                } label: {
                    VStack(spacing: 14) {
                        Text(tab.rawValue).font(.subheadline.weight(selectedTab == tab ? .bold : .medium))
                            .foregroundStyle(selectedTab == tab ? .primary : .secondary).frame(maxWidth: .infinity)
                        ZStack {
                            Color.clear.frame(height: 3)
                            if selectedTab == tab { Capsule().fill(Theme.accent).frame(height: 3).matchedGeometryEffect(id: "manga-tab", in: tabIndicator) }
                        }
                    }.padding(.top, 14).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
                    .accessibilityIdentifier("mangabaka-tab-" + tab.rawValue)
            }
        }.background(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
    }
    @ViewBuilder private var tabContent: some View {
        switch selectedTab {
        case .read: readingSource
        case .info:
            if visibleSections.isEmpty { Text("Sections are hidden. Use Customize sections to show more.").font(.subheadline).foregroundStyle(.secondary) }
            ForEach(visibleSections) { section in detailSection(section).id(section.rawValue) }
        case .similar: detailSection(.related)
        }
    }
    private var optionsMenu: some View {
        Menu {
            Button("Customize sections", systemImage: "slider.horizontal.3") { arranging = true }
            Button("Edit reading status", systemImage: "square.and.pencil", action: editEntry)
                .disabled(account.connecting || !account.saving.isEmpty)
            Link(destination: series.websiteURL) { Label("View on MangaBaka", systemImage: "arrow.up.right.square") }
            Button("MangaBaka account", systemImage: "person.crop.circle") { signingIn = true }
        } label: { Image(systemName: "ellipsis").frame(width: 32, height: 32) }
            .accessibilityLabel("Series options")
    }
    private func editEntry() { if account.connected { editing = true } else { signingIn = true } }
    @ViewBuilder private func detailSection(_ section: SeriesDetailSection) -> some View {
        switch section {
        case .watchlist: actions
        case .reading: readingSource
        case .synopsis: story
        case .publication:
            DetailCard(title: "Information") {
                metadata
                if !series.sourceRatings.isEmpty { DisclosureGroup("Ratings across sources") { sourceRatings } }
            }
        case .artwork:
            DetailCard(title: "Artwork & covers") {
                MangaBakaCoverGallery(series: series, refreshToken: refreshToken)
            }.accessibilityIdentifier("series-artwork")
        case .related:
            DetailCard(title: "Related & recommendations") {
                ForEach(MangaBakaRelatedKind.allCases, id: \.self) { kind in
                    MangaBakaRelatedSection(series: series, kind: kind, refreshToken: refreshToken).id(kind.rawValue)
                }
            }.accessibilityIdentifier("series-related")
        case .adaptations: MangaBakaAnimeSection(series: series, refreshToken: refreshToken)
        case .coverage: animeCoverage
        case .tags: MangaBakaSeriesTags(series: series)
        case .links: officialLinks
        default: EmptyView()
        }
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
            }.padding(16).foregroundStyle(Theme.background).background(Theme.accent, in: RoundedRectangle(cornerRadius: 16))
        }.buttonStyle(.plain)
    }
    @ViewBuilder private var story: some View {
        if !series.synopsis.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("The story").font(.title3.bold())
                Text(series.synopsis).font(.body).foregroundStyle(.secondary).lineLimit(expanding ? nil : 4)
                Button(expanding ? "Show less" : "Read more") { expanding.toggle() }.font(.subheadline.bold())
            }
        }
    }
    private var metadata: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !series.authors.isEmpty { LabeledContent("Story", value: series.authors.joined(separator: ", ")) }
            if !series.artists.isEmpty { LabeledContent("Art", value: series.artists.joined(separator: ", ")) }
            if let start = series.publishedStart { LabeledContent("Publication began", value: start) }
            if let end = series.publishedEnd { LabeledContent("Publication ended", value: end) }
            if !publishers.isEmpty {
                Text("Publishers").foregroundStyle(.secondary)
                MangaBakaFlowLayout {
                    ForEach(publishers, id: \.self) { publisher in
                        NavigationLink(value: MangaBakaBrowseRoute(query: .init(publisher: publisher))) {
                            HStack(spacing: 6) { Text(publisher.name); Image(systemName: "chevron.right").font(.caption2) }
                                .font(.subheadline.weight(.medium)).foregroundStyle(.mint)
                                .padding(.horizontal, 12).padding(.vertical, 10)
                                .background(Color.mint.opacity(0.1), in: Capsule())
                        }.buttonStyle(.plain).accessibilityLabel("Browse series from " + publisher.name)
                    }
                }
            }
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
            MangaBakaSourceLinkSection(series: series)
        }
    }
    @ViewBuilder private var animeCoverage: some View {
        if let anime = series.animeAdaptation, anime.exists || anime.hasCoverage {
            VStack(alignment: .leading, spacing: 14) {
                Label("Anime chapter coverage", systemImage: "play.rectangle").font(.title3.bold())
                if let start = anime.start { coverageNote("Anime starts at", note: start) }
                if let end = anime.end { coverageNote("Anime ends at", note: end) }
                if !anime.hasCoverage {
                    Text("An anime adaptation exists, but chapter and volume coverage has not been listed yet.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Text("MangaBaka · MangaUpdates coverage notes").font(.caption).foregroundStyle(.secondary)
            }.accessibilityIdentifier("mangabaka-anime-coverage")
        }
    }
    private func coverageNote(_ title: String, note: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.subheadline.bold()).foregroundStyle(.mint)
            Text(note).font(.subheadline).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var officialLinks: some View {
        DisclosureGroup(isExpanded: $linksExpanded) {
            Link(destination: series.websiteURL) { Label("View on MangaBaka", systemImage: "arrow.up.right.square") }
                .padding(.vertical, 6)
            ForEach(officialURLs, id: \.self) { url in
                Link(destination: url) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(url.host ?? "Related site").font(.subheadline)
                        Text(url.absoluteString).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5)
                }
            }
        } label: {
            Text("Links (\(officialURLs.count + 1))").font(.headline)
        }
    }
    private var officialURLs: [URL] {
        var seen: Set<URL> = [series.websiteURL]
        return series.links.compactMap(MangaBakaSeries.publicURL).filter { seen.insert($0).inserted }
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
