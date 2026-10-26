import SwiftUI
import AnimeCore

struct CombinedLibraryView: View {
    @EnvironmentObject private var anime: AppStore
    @EnvironmentObject private var reading: MangaBakaStore
    @Environment(\.scenePhase) private var scene
    @Environment(\.dynamicTypeSize) private var textSize
    @AppStorage("mangabaka.library.layout") private var layout = "grid"
    @AppStorage("library.combined.defaultStatus") private var defaultStatus = LibraryScope.combined.initialStatus
    @State private var status = CombinedLibraryStatus(rawValue: LibraryScope.combined.openingStatus()) ?? .active
    @AppStorage("combined.library.sort") private var sortValue = ReadingLibrarySort.title.rawValue
    @AppStorage("combined.library.ascending") private var ascending = true
    @State private var search = ""
    @State private var settings = false
    private var items: [CombinedLibraryItem] {
        let values = CombinedLibraryItem.merge(anime: anime.isSignedIn ? anime.entries : [], reading: reading.connected ? reading.library : [],
            includeAdult: anime.includeAdult, query: search, status: status, contentFilter: anime.mangaBakaContent)
        return (ReadingLibrarySort(rawValue: sortValue) ?? .title).sorted(values, ascending: ascending)
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    Text("All your stories").font(.title2.bold())
                    Spacer()
                    Text("\(items.count) loaded").font(.caption).foregroundStyle(.secondary)
                }
                LibraryLayoutPicker(layout: $layout)
                ReadingLibrarySortControls(scope: .combined, sortValue: $sortValue, ascending: $ascending)
                MangaBakaContentButton().font(.subheadline)
                filters
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search your library", text: $search).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("combined-library-search")
                    if !search.isEmpty { Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }.accessibilityLabel("Clear library search") }
                }.padding(13).background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
                if !anime.isSignedIn || !reading.connected {
                    Button { settings = true } label: {
                        Label(!anime.isSignedIn && !reading.connected ? "Connect your libraries" : !anime.isSignedIn ? "Add your AniList library" : "Add your MangaBaka library",
                            systemImage: "person.crop.circle.badge.plus")
                    }.buttonStyle(.bordered)
                }
                if let error = anime.libraryError, anime.isSignedIn { NoticeView(message: error) { Task { await anime.reloadLibrary() } } }
                if let error = reading.libraryError, reading.connected { NoticeView(message: error) { Task { await loadReading(refresh: true) } } }
                results
                if anime.loadingLibrary || reading.loadingLibrary { ProgressView("Loading your stories…").frame(maxWidth: .infinity).padding() }
                if items.isEmpty && !anime.loadingLibrary && !reading.loadingLibrary {
                    ContentUnavailableView("No matching titles", systemImage: "books.vertical",
                        description: Text("Choose another status, change your search, or add a title from Explore."))
                }
                if reading.hasMoreLibrary {
                    VStack(spacing: 8) {
                        Text("Syncing remaining books for complete search and sorting…")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Continue syncing books") { Task { await loadReading() } }.buttonStyle(.bordered)
                            .disabled(reading.loadingLibrary)
                    }.frame(maxWidth: .infinity)
                }
                Text("Anime progress syncs with AniList. Reading progress syncs with MangaBaka.")
                    .font(.caption2).foregroundStyle(.secondary)
            }.padding(20).frame(maxWidth: 1180).frame(maxWidth: .infinity)
        }.scrollDismissesKeyboard(.interactively).background(Theme.background).navigationTitle("My Library").navigationBarTitleDisplayMode(.inline)
            .animeNavigation().accessibilityIdentifier("combined-library")
            .toolbar { ToolbarItem(placement: .topBarTrailing) {
                Button { settings = true } label: { Image(systemName: "gearshape") }.accessibilityLabel("Account and settings")
            } }
            .appSettingsSheet(isPresented: $settings)
            .onChange(of: defaultStatus) { _, _ in status = CombinedLibraryStatus(rawValue: LibraryScope.combined.openingStatus()) ?? .active }
            .task(id: "\(reading.connected)-\(reading.connectionID)-\(reading.revision)") { await loadReading(refresh: true) }
            .task(id: "\(anime.isSignedIn)-\(scene)") {
                guard scene == .active else { return }
                while !Task.isCancelled {
                    await anime.refreshLibraryIfNeeded()
                    do { try await Task.sleep(for: .seconds(60)) } catch { return }
                }
            }
            .refreshable {
                async let watched: Void = anime.reloadLibrary()
                async let books: Void = loadReading(refresh: true)
                _ = await (watched, books)
            }
    }
    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(CombinedLibraryStatus.allCases) { value in
                    Button { status = value } label: {
                        Text(value.label).font(.subheadline.weight(.semibold)).padding(.horizontal, 14).padding(.vertical, 9)
                            .background(status == value ? Color.white : Theme.surface, in: Capsule())
                            .foregroundStyle(status == value ? Color.black : Color.white)
                    }.buttonStyle(.plain).accessibilityIdentifier("combined-library-status-" + value.rawValue)
                        .accessibilityAddTraits(status == value ? .isSelected : [])
                }
            }
        }
    }
    @ViewBuilder private var results: some View {
        if layout == "grid" {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: textSize.isAccessibilitySize ? 190 : 140), spacing: 14)], alignment: .leading, spacing: 22) {
                ForEach(items) { item in destination(item) { CombinedLibraryCard(item: item, grid: true) } }
            }.accessibilityIdentifier("combined-library-grid")
        } else {
            LazyVStack(spacing: 14) {
                ForEach(items) { item in destination(item) { CombinedLibraryCard(item: item, grid: false) } }
            }.accessibilityIdentifier("combined-library-list")
        }
    }
    @ViewBuilder private func destination<Content: View>(_ item: CombinedLibraryItem, @ViewBuilder content: () -> Content) -> some View {
        switch item {
        case .anime(let entry): AnimeLink(id: entry.mediaId, label: content).buttonStyle(.plain).accessibilityIdentifier("combined-entry-" + item.id)
        case .reading(let entry):
            if let series = entry.series { NavigationLink(value: MangaBakaSeriesRoute(series: series), label: content).buttonStyle(.plain).accessibilityIdentifier("combined-entry-" + item.id) }
        }
    }
    private func loadReading(refresh: Bool = false) async {
        guard reading.connected else { return }
        await reading.loadCompleteLibrary(state: nil, refresh: refresh)
    }
}

private struct CombinedLibraryCard: View {
    let item: CombinedLibraryItem
    let grid: Bool
    private var format: String {
        switch item { case .anime: return "Anime"; case .reading(let value): return value.series?.formatLabel ?? "Book" }
    }
    private var status: String {
        switch item { case .anime(let value): return value.status?.label ?? "Unlisted"
        case .reading(let value): return MangaBakaReadingStatus(rawValue: value.state)?.label ?? value.state.capitalized }
    }
    private var progress: String {
        switch item { case .anime(let value): return "Ep. \(value.progressValue)" + (value.media?.episodes.map { " / \($0)" } ?? "")
        case .reading(let value): return "Ch. " + (value.chapter ?? 0).formatted() + (value.volume.map { " · Vol. " + $0.formatted() } ?? "") }
    }
    var body: some View {
        Group {
            if grid {
                VStack(alignment: .leading, spacing: 8) {
                    GeometryReader { geometry in cover(width: geometry.size.width) }
                        .aspectRatio(1 / 1.45, contentMode: .fit)
                        .overlay(alignment: .topLeading) { LibraryFormatBadge(title: format).padding(7) }
                    Text(item.title).font(.subheadline.weight(.semibold)).lineLimit(2, reservesSpace: true)
                    Text(status).font(.caption).foregroundStyle(.secondary)
                    Text(progress).font(.caption.monospacedDigit()).lineLimit(2)
                }
            } else {
                HStack(spacing: 14) {
                    cover(width: 76)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(item.title).font(.headline).lineLimit(3)
                        Text(format + " · " + status).font(.caption).foregroundStyle(.secondary)
                        Text(progress).font(.subheadline.monospacedDigit())
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                }.padding(13).background(Theme.surface, in: RoundedRectangle(cornerRadius: 20))
            }
        }.frame(maxWidth: .infinity, alignment: .topLeading).contentShape(Rectangle())
            .accessibilityIdentifier("combined-title-" + item.id)
    }
    @ViewBuilder private func cover(width: CGFloat) -> some View {
        switch item {
        case .anime(let entry): if let media = entry.media { AnimeCover(anime: media, width: width, cornerRadius: 14) }
        case .reading(let entry): if let series = entry.series { MangaBakaCover(series: series, width: width) }
        }
    }
}
