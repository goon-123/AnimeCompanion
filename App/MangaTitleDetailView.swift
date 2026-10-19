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
}

struct MangaTitleDetailView: View {
    @EnvironmentObject private var extensions: MangaExtensionStore
    @EnvironmentObject private var reading: MangaReadingStore
    @AppStorage("manga.showMatureSources") private var showMature = false
    @AppStorage("manga.chaptersNewestFirst") private var newestFirst = false
    let title: MangaTitleReference
    @StateObject private var model: MangaBookModel
    @State private var expanded = false
    @State private var searchChapters = false
    @State private var chapterQuery = ""
    @State private var unreadOnly = false
    @State private var reader: MangaReaderRoute?
    @State private var showWebsite = false
    init(title: MangaTitleReference) { self.title = title; _model = StateObject(wrappedValue: MangaBookModel(title)) }
    private var current: MangaTitleReference { MangaTitleReference(source: title.source, manga: model.manga) }
    private var record: MangaReadingRecord? { reading.record(title.id) }
    private var shownChapters: [SourceMangaChapter] {
        let filtered = model.chapters.filter {
            (chapterQuery.isEmpty || $0.name.localizedCaseInsensitiveContains(chapterQuery)) &&
            (!unreadOnly || record?.position(for: $0.url)?.completed != true)
        }
        return newestFirst ? Array(filtered.reversed()) : filtered
    }
    var body: some View {
        Group {
            if title.source.adult && !showMature { ContentUnavailableView("Collection hidden", systemImage: "eye.slash") }
            else { content }
        }.background(Color.black).navigationBarTitleDisplayMode(.inline).tint(MangaStyle.accent)
            .task {
                guard showMature || !title.source.adult else { return }
                await reading.load()
                await model.load(title, extensions: extensions, reading: reading)
            }
            .fullScreenCover(item: $reader) { WebtoonReaderView(route: $0) }
            .sheet(isPresented: $showWebsite) {
                MangaSourceSessionView(source: title.source) {
                    Task { await model.load(title, extensions: extensions, reading: reading, force: true) }
                }
            }
    }
    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                header
                if !model.manga.description.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(model.manga.description).font(.subheadline).foregroundStyle(.secondary).lineLimit(expanded ? nil : 3)
                        Button(expanded ? "Show less" : "Read more") { expanded.toggle() }.font(.caption.bold())
                    }.padding(.horizontal, 20)
                }
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
                readingAction.padding(.horizontal, 20)
                chapterSection.padding(.horizontal, 20)
            }.padding(.bottom, 32)
        }.accessibilityIdentifier("manga-title-detail")
            .refreshable { await model.load(title, extensions: extensions, reading: reading, force: true) }
    }
    private var header: some View {
        HStack(alignment: .top, spacing: 18) {
            MangaCover(title: current, width: 126).frame(width: 126, height: 186).clipShape(RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 10) {
                Text(model.manga.title).font(.title2.bold()).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("manga-detail-title")
                if !model.manga.author.isEmpty { Text(model.manga.author).font(.subheadline).foregroundStyle(.secondary) }
                Text(status).font(.caption.weight(.medium)).foregroundStyle(MangaStyle.accent)
                Text(title.source.name).font(.caption).foregroundStyle(.secondary)
                Button {
                    Task { await reading.save(current, saved: record?.saved != true) }
                } label: { Label(record?.saved == true ? "In library" : "Add to library", systemImage: record?.saved == true ? "bookmark.fill" : "bookmark") }
                    .font(.subheadline.bold()).buttonStyle(.bordered).buttonBorderShape(.capsule).disabled(reading.loading || reading.unreadable)
                    .accessibilityIdentifier("manga-save-title")
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(20).padding(.top, 12).frame(maxWidth: .infinity, alignment: .leading)
            .background {
                MangaCover(title: current, width: 500).blur(radius: 28).opacity(0.30)
                    .overlay(LinearGradient(colors: [.black.opacity(0.15), .black], startPoint: .top, endPoint: .bottom)).clipped()
            }
    }
    private var readingAction: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let chapter = MangaChapterSequence.nextToRead(model.chapters, record: record) {
                Button { open(chapter) } label: {
                    Label(record?.position(for: chapter.url)?.completed == false ? "Continue \(chapter.name)" : "Read \(chapter.name)", systemImage: "play.fill")
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 9)
                }.buttonStyle(.borderedProminent).buttonBorderShape(.capsule).tint(MangaStyle.accent).foregroundStyle(.black).accessibilityIdentifier("manga-read")
            }
            if let url = record?.lastChapterURL, let point = record?.position(for: url) {
                Text(point.chapterName + (point.completed ? " · Finished" : " · Page \(point.pageIndex + 1) of \(point.pageCount)"))
                    .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("manga-reading-progress")
            }
            if model.loading { ProgressView("Loading chapters…").font(.subheadline) }
            if let error = model.error {
                Text(error).font(.subheadline).foregroundStyle(.secondary)
                Button("Open source website / verify") { showWebsite = true }
                Button("Try again") { Task { await model.load(title, extensions: extensions, reading: reading, force: true) } }
            }
        }
    }
    private var chapterSection: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("\(model.chapters.count) chapters").font(.title3.bold())
                Spacer()
                Button { searchChapters.toggle(); if !searchChapters { chapterQuery = "" } } label: { Image(systemName: "magnifyingglass") }
                    .accessibilityLabel("Search chapters")
                Menu {
                    Toggle("Newest first", isOn: $newestFirst)
                    Toggle("Unread only", isOn: $unreadOnly)
                } label: { Image(systemName: "line.3.horizontal.decrease") }.accessibilityLabel("Chapter order and filters")
            }.padding(.bottom, 16)
            if searchChapters {
                TextField("Find a chapter", text: $chapterQuery).textFieldStyle(.roundedBorder).padding(.bottom, 14).autocorrectionDisabled()
            }
            if !model.loading && shownChapters.isEmpty && model.error == nil {
                Text(model.chapters.isEmpty ? "This source returned no chapters." : "No chapters match these filters.")
                    .font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 20)
            }
            ForEach(shownChapters) { chapter in
                Button { open(chapter) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: record?.position(for: chapter.url)?.completed == true ? "checkmark.circle.fill" : "circle")
                            .font(.subheadline).foregroundStyle(record?.position(for: chapter.url)?.completed == true ? MangaStyle.accent : .secondary)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(chapter.name.isEmpty ? "Chapter" : chapter.name).font(.subheadline.weight(.medium))
                            HStack(spacing: 6) {
                                if chapter.uploadedAt > 0 { Text(Date(timeIntervalSince1970: Double(chapter.uploadedAt) / 1000), style: .date) }
                                if !chapter.scanlator.isEmpty { Text(chapter.scanlator).lineLimit(1) }
                            }.font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 16).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("manga-chapter-\(model.chapters.firstIndex(of: chapter) ?? 0)")
                    .contextMenu {
                        Button(record?.position(for: chapter.url)?.completed == true ? "Mark unread" : "Mark read") {
                            Task { await reading.mark(current, chapter: chapter, read: record?.position(for: chapter.url)?.completed != true) }
                        }
                    }
                Divider().overlay(.white.opacity(0.05))
            }
        }
    }
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
    private func open(_ chapter: SourceMangaChapter) { reader = MangaReaderRoute(title: current, chapters: model.chapters, chapter: chapter) }
}
