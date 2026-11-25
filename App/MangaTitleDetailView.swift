import SwiftUI
import AnimeCore

@MainActor
final class MangaBookModel: ObservableObject {
    @Published var manga: SourceManga
    @Published var chapters: [SourceMangaChapter] = []
    @Published var loading = false
    @Published var error: String?
    private var attempted = false
    init(_ title: MangaTitleReference) { manga = title.manga }
    func load(_ title: MangaTitleReference, extensions: MangaExtensionStore, reading: MangaReadingStore, force: Bool = false) async {
        guard !loading, !attempted || force else { return }
        attempted = true; loading = true; error = nil
        defer { loading = false }
        do {
            let book = try await extensions.book(title)
            try Task.checkCancellation()
            manga = title.manga.merging(book.manga)
            chapters = MangaChapterSequence.readingOrder(book.chapters)
            await reading.metadata(MangaTitleReference(source: title.source, manga: manga))
        } catch is CancellationError { attempted = false }
        catch { self.error = error.localizedDescription }
    }
}

struct MangaReaderRoute: Identifiable {
    let id = UUID()
    let title: MangaTitleReference
    let chapters: [SourceMangaChapter]
    let chapter: SourceMangaChapter
    var startAtBeginning = false
}

struct MangaTitleDetailView: View {
    @EnvironmentObject private var extensions: MangaExtensionStore
    @EnvironmentObject private var reading: MangaReadingStore
    @EnvironmentObject private var contentPreferences: AppStore
    private var showMature: Bool { contentPreferences.mangaBakaContent.allowsMatureSources }
    @AppStorage("manga.chaptersNewestFirst") private var newestFirst = false
    @AppStorage("series.layout.reader.v1") private var sectionOrder = ""
    let title: MangaTitleReference
    let linkingTo: MangaSourceLinkTarget?
    let resumeOnOpen: Bool
    @StateObject private var model: MangaBookModel
    @State private var expanded = false
    @State private var searchChapters = false
    @State private var chapterQuery = ""
    @State private var chapterFilter = MangaChapterFilter.all
    @State private var arranging = false
    @State private var sourceSettings = false
    @State private var marking: [SourceMangaChapter] = []
    @State private var confirmMark = false
    @State private var updatingChapters = false
    @State private var jumpURL: String?
    @State private var jumpToken = UUID()
    @State private var reader: MangaReaderRoute?
    @State private var showWebsite = false
    @State private var manageExtensions = false
    @State private var resumed = false
    init(title: MangaTitleReference, linkingTo: MangaSourceLinkTarget? = nil, resumeOnOpen: Bool = false) {
        self.title = title; self.linkingTo = linkingTo; self.resumeOnOpen = resumeOnOpen
        _model = StateObject(wrappedValue: MangaBookModel(title))
    }
    private var installed: InstalledMangaExtension? { extensions.installed(title.source.extensionID) }
    private var source: MangaSourceReference {
        guard let installed, let live = installed.sources.first(where: { $0.id == title.source.sourceID }) else { return title.source }
        return MangaSourceReference(installation: installed, source: live)
    }
    private var sourceReady: Bool { installed?.enabled == true && installed?.sources.contains(where: { $0.id == title.source.sourceID }) == true }
    private var matureSource: Bool { title.source.adult || source.adult }
    private var availabilityKey: String { "\(extensions.loading)-\(sourceReady)-\(installed?.descriptor.sha256 ?? "")-\(showMature)" }
    private var current: MangaTitleReference { MangaTitleReference(source: source, manga: model.manga) }
    private var record: MangaReadingRecord? { reading.record(title.id) }
    private var layout: SeriesDetailLayout { SeriesDetailLayout(page: .reader, saved: sectionOrder) }
    private var visibleSections: [SeriesDetailSection] {
        layout.visible.filter {
            if $0 == .synopsis { return !model.manga.description.isEmpty }
            if $0 == .genres { return !model.manga.genre.isEmpty }
            return true
        }
    }
    private var shownChapters: [SourceMangaChapter] {
        MangaChapterBrowsing.chapters(model.chapters, record: record, query: chapterQuery, filter: chapterFilter, newestFirst: newestFirst)
    }
    private var readCount: Int {
        let read = Set((record?.positions ?? []).filter(\.completed).map(\.chapterURL))
        return model.chapters.filter { read.contains($0.url) }.count
    }
    private var nextChapter: SourceMangaChapter? { MangaChapterSequence.nextToRead(model.chapters, record: record) }
    var body: some View {
        Group {
            if matureSource && !showMature { ContentUnavailableView("Collection hidden", systemImage: "eye.slash") }
            else if !sourceReady && !extensions.loading { unavailableSource }
            else { content }
        }.background(Theme.background).navigationBarTitleDisplayMode(.inline).tint(MangaStyle.accent)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { if showMature || !matureSource { seriesOptions } } }
            .sheet(isPresented: $sourceSettings) { MangaSourceSettingsView(source: source) { Task { await loadChapters(force: true) } } }
            .sheet(isPresented: $arranging) { AppNavigationStack { SeriesLayoutEditor(page: .reader) } }
            .confirmationDialog("Mark \(marking.count) chapters as read?", isPresented: $confirmMark, titleVisibility: .visible) {
                Button("Mark as read") {
                    let chapters = marking; updatingChapters = true
                    Task { await reading.mark(current, chapters: chapters, read: true); updatingChapters = false }
                }
                Button("Cancel", role: .cancel) {}
            } message: { Text("This changes read status. Your saved series and reading history are kept.") }
            .task(id: availabilityKey) {
                await extensions.load(refreshCatalog: false)
                guard !Task.isCancelled, sourceReady, showMature || !matureSource else { return }
                await reading.load()
                await loadChapters()
            }
            .fullScreenCover(item: $reader) { WebtoonReaderView(route: $0) }
            .sheet(isPresented: $showWebsite) {
                MangaSourceSessionView(source: source) {
                    Task { await loadChapters(force: true) }
                }
            }
            .sheet(isPresented: $manageExtensions) { MangaExtensionSheet() }
    }
    private var content: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    header
                    VStack(alignment: .leading, spacing: 14) {
                        readingAction
                        MangaSourceLinkControl(title: current, requestedTarget: linkingTo)
                    }.padding(.horizontal, 20).accessibilityIdentifier("manga-primary-actions")
                    if visibleSections.isEmpty {
                        Text("Details are hidden. Use Arrange sections in the options menu to show more.")
                            .font(.subheadline).foregroundStyle(.secondary).padding(.horizontal, 20)
                    }
                    ForEach(visibleSections) { section in detailSection(section).id(section.rawValue) }
                }.padding(.bottom, 100).frame(maxWidth: 1000).frame(maxWidth: .infinity)
            }.accessibilityIdentifier("manga-title-detail")
                .refreshable { await loadChapters(force: true) }
                .task(id: jumpToken) {
                    guard let jumpURL else { return }
                    do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
                    withAnimation { proxy.scrollTo("chapter:" + jumpURL, anchor: .center) }
                }
        }
    }
    @ViewBuilder private func detailSection(_ section: SeriesDetailSection) -> some View {
        switch section {
        case .synopsis: synopsis
        case .genres: genres
        case .chapters: chapterSection.padding(.horizontal, 20)
        default: EmptyView()
        }
    }
    @ViewBuilder private var synopsis: some View {
        if !model.manga.description.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Synopsis").font(.title3.bold())
                Text(model.manga.description).font(.subheadline).foregroundStyle(.secondary).lineLimit(expanded ? nil : 5)
                Button(expanded ? "Show less" : "Read more") { expanded.toggle() }.font(.caption.bold())
            }.padding(.horizontal, 20)
        }
    }
    @ViewBuilder private var genres: some View {
        if !model.manga.genre.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(Set(model.manga.genre.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })).sorted(), id: \.self) {
                        Text($0).font(.caption).padding(.horizontal, 12).padding(.vertical, 8)
                            .overlay(Capsule().stroke(.white.opacity(0.20)))
                    }
                }.padding(.horizontal, 20)
            }
        }
    }
    private var header: some View {
        HStack(alignment: .top, spacing: 18) {
            MangaCover(title: current, width: 126).frame(width: 126, height: 186).clipShape(RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 10) {
                Text(model.manga.title).font(.title2.bold()).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("manga-detail-title")
                if !model.manga.author.isEmpty { Text(model.manga.author).font(.subheadline).foregroundStyle(.secondary) }
                Text(status).font(.caption.weight(.medium)).foregroundStyle(MangaStyle.accent)
                Text(source.name).font(.caption).foregroundStyle(.secondary)
                Button {
                    Task { await reading.save(current, saved: record?.saved != true) }
                } label: { Label(record?.saved == true ? "Saved series" : "Save series", systemImage: record?.saved == true ? "bookmark.fill" : "bookmark") }
                    .font(.subheadline.bold()).buttonStyle(.bordered).buttonBorderShape(.capsule).disabled(reading.loading || reading.unreadable)
                    .accessibilityIdentifier("manga-save-title")
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(20).padding(.top, 12).frame(maxWidth: .infinity, alignment: .leading)
            .background {
                MangaCover(title: current, width: 500).blur(radius: 28).opacity(0.30)
                    .overlay(LinearGradient(colors: [Theme.background.opacity(0.35), Theme.background], startPoint: .top, endPoint: .bottom)).clipped()
            }
    }
    private var readingAction: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let chapter = nextChapter {
                Button { open(chapter) } label: {
                    Label(record?.position(for: chapter.url)?.completed == false ? "Continue \(chapter.name)" : "Read \(chapter.name)", systemImage: "play.fill")
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 12)
                }.buttonStyle(.borderedProminent).buttonBorderShape(.capsule).tint(MangaStyle.accent).foregroundStyle(.black).accessibilityIdentifier("manga-read")
            }
            if !model.chapters.isEmpty {
                HStack {
                    Label("\(readCount) / \(model.chapters.count) read", systemImage: "checkmark.circle")
                    Spacer()
                    if let latest = model.chapters.last {
                        Button("Read latest") { open(latest) }.fontWeight(.semibold).accessibilityIdentifier("manga-read-latest")
                    }
                }.font(.caption).foregroundStyle(.secondary)
                ProgressView(value: Double(readCount), total: Double(model.chapters.count)).tint(MangaStyle.accent)
                    .accessibilityLabel("Chapters read")
            }
            if let url = record?.lastChapterURL, let point = record?.position(for: url) {
                Text(point.chapterName + (point.completed ? " · Finished" : " · Page \(point.pageIndex + 1) of \(point.pageCount)"))
                    .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("manga-reading-progress")
            }
            if model.loading { ProgressView("Loading chapters…").font(.subheadline) }
            if let error = model.error {
                Text(error).font(.subheadline).foregroundStyle(.secondary)
                Button("Open source website / verify") { showWebsite = true }
                Button("Try again") { Task { await loadChapters(force: true) } }
            }
            if let error = reading.error { Text(error).font(.caption).foregroundStyle(.orange) }
        }
    }
    private var seriesOptions: some View {
        Menu {
            Button("Refresh chapters", systemImage: "arrow.clockwise") { Task { await loadChapters(force: true) } }.disabled(model.loading || !sourceReady)
            Button("Open source website", systemImage: "globe") { showWebsite = true }
            Button("Source settings", systemImage: "slider.horizontal.3") { sourceSettings = true }.disabled(!sourceReady)
            if let url = source.webURL(for: model.manga.url) { ShareLink(item: url) { Label("Share series", systemImage: "square.and.arrow.up") } }
            Divider()
            Button("Arrange sections", systemImage: "rectangle.3.group") { arranging = true }.accessibilityIdentifier("series-arrange-reader")
        } label: { Image(systemName: "ellipsis").frame(minWidth: 44, minHeight: 44) }
            .accessibilityLabel("Series options").accessibilityIdentifier("manga-series-options")
    }
    private var chapterSection: some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Chapters").font(.title3.bold())
                    Text("\(model.chapters.count) total · \(model.chapters.count - readCount) unread").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { searchChapters.toggle(); if !searchChapters { chapterQuery = "" } } label: { Image(systemName: "magnifyingglass").frame(width: 40, height: 44) }
                    .accessibilityLabel("Search chapters")
                Menu {
                    Toggle("Newest first", isOn: $newestFirst)
                    if let nextChapter { Button("Show current chapter", systemImage: "bookmark") { jump(to: nextChapter) } }
                    Button("Mark all as read", systemImage: "checkmark.circle") { confirmRead(model.chapters) }
                        .disabled(model.chapters.isEmpty || updatingChapters || reading.loading || reading.unreadable)
                } label: { Image(systemName: "line.3.horizontal.decrease").frame(width: 40, height: 44) }.accessibilityLabel("Chapter order and actions")
            }
            Picker("Chapter status", selection: $chapterFilter) {
                ForEach(MangaChapterFilter.allCases) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented).accessibilityIdentifier("manga-chapter-filter")
            if searchChapters {
                TextField("Chapter name or number", text: $chapterQuery).textFieldStyle(.roundedBorder).autocorrectionDisabled()
                    .accessibilityIdentifier("manga-chapter-search")
            }
            if !model.loading && shownChapters.isEmpty && model.error == nil {
                ContentUnavailableView("No chapters", systemImage: "text.book.closed", description: Text(model.chapters.isEmpty ? "This source returned no chapters." : "Try another search or read-status filter."))
            }
            ForEach(shownChapters) { chapter in
                chapterRow(chapter).id("chapter:" + chapter.url)
            }
        }
    }
    private func chapterRow(_ chapter: SourceMangaChapter) -> some View {
        let isRead = record?.position(for: chapter.url)?.completed == true
        let isCurrent = record?.lastChapterURL == chapter.url
        return HStack(spacing: 8) {
            Button { Task { await reading.mark(current, chapter: chapter, read: !isRead) } } label: {
                Image(systemName: isRead ? "checkmark.circle.fill" : "circle").font(.title3)
                    .foregroundStyle(isRead ? MangaStyle.accent : Color.secondary).frame(width: 44, height: 52)
            }.buttonStyle(.plain).disabled(updatingChapters || reading.loading || reading.unreadable)
                .accessibilityLabel((isRead ? "Mark unread: " : "Mark read: ") + chapter.name)
            Button { open(chapter) } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 8) {
                            Text(chapter.name.isEmpty ? "Chapter" : chapter.name).font(.subheadline.weight(.semibold))
                            if isCurrent { Text("Current").font(.caption2.weight(.semibold)).foregroundStyle(MangaStyle.accent) }
                        }
                        HStack(spacing: 6) {
                            if chapter.uploadedAt > 0 { Text(Date(timeIntervalSince1970: Double(chapter.uploadedAt) / 1000), style: .date) }
                            if let scanlator = MangaChapterBrowsing.scanlator(chapter.scanlator) { Text(scanlator).lineLimit(1) }
                        }.font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "play.fill").font(.caption).foregroundStyle(MangaStyle.accent)
                }.padding(.vertical, 14).padding(.trailing, 12).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("manga-chapter-\(model.chapters.firstIndex(of: chapter) ?? 0)")
        }.background(isCurrent ? MangaStyle.accent.opacity(0.09) : Theme.surface, in: RoundedRectangle(cornerRadius: 16))
            .contextMenu {
                Button("Read from beginning", systemImage: "backward.end") { open(chapter, fromBeginning: true) }
                Button(isRead ? "Mark unread" : "Mark read", systemImage: "checkmark.circle") {
                    Task { await reading.mark(current, chapter: chapter, read: !isRead) }
                }.disabled(updatingChapters || reading.loading || reading.unreadable)
                if let index = model.chapters.firstIndex(of: chapter) {
                    Button("Mark read through this chapter", systemImage: "checkmark.circle.fill") { confirmRead(Array(model.chapters.prefix(index + 1))) }
                        .disabled(updatingChapters || reading.loading || reading.unreadable)
                }
                if let url = source.webURL(for: chapter.url) { ShareLink(item: url) { Label("Share chapter", systemImage: "square.and.arrow.up") } }
            }
    }
    private func jump(to chapter: SourceMangaChapter) {
        chapterFilter = .all; chapterQuery = ""; jumpURL = chapter.url; jumpToken = UUID()
    }
    private func confirmRead(_ chapters: [SourceMangaChapter]) { marking = chapters; confirmMark = true }
    private var status: String {
        switch model.manga.status {
        case 1: return "Ongoing"
        case 2: return "Completed"
        case 3: return "Licensed"
        case 4: return "Finished"
        case 5: return "Cancelled"
        case 6: return "On hiatus"
        default: return "Manga & manhwa"
        }
    }
    private func open(_ chapter: SourceMangaChapter, fromBeginning: Bool = false) { reader = MangaReaderRoute(title: current, chapters: model.chapters, chapter: chapter, startAtBeginning: fromBeginning) }
    private func loadChapters(force: Bool = false) async {
        guard !Task.isCancelled, sourceReady, showMature || !matureSource else { return }
        await model.load(current, extensions: extensions, reading: reading, force: force || model.error != nil)
        guard !Task.isCancelled, resumeOnOpen, !resumed, model.error == nil,
              let chapter = MangaChapterSequence.nextToRead(model.chapters, record: record) else { return }
        resumed = true; open(chapter)
    }
    private var unavailableSource: some View {
        ContentUnavailableView {
            Label(installed?.enabled == false ? "Reading source disabled" : "Reading source unavailable", systemImage: "puzzlepiece.extension")
        } description: {
            Text("Saved source: " + title.source.name + ". Enable or install it to read again. You can change the source link from your library entry.")
        } actions: {
            if installed?.enabled == false {
                Button("Enable source") { Task { await extensions.setEnabled(title.source.extensionID, true) } }.disabled(extensions.busy)
            }
            Button("Manage extensions") { manageExtensions = true }.buttonStyle(.borderedProminent)
        }
    }
}
