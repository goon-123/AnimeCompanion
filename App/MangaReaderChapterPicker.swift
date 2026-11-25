import SwiftUI
import AnimeCore

struct MangaReaderChapterPicker: View {
    let title: String
    let chapters: [SourceMangaChapter]
    let current: SourceMangaChapter
    let record: MangaReadingRecord?
    let onSelect: (SourceMangaChapter) -> Void
    let onDone: () -> Void
    @State private var query = ""
    @State private var filter = MangaChapterFilter.all
    @State private var jump = 0
    private var shown: [SourceMangaChapter] {
        MangaChapterBrowsing.chapters(chapters, record: record, query: query, filter: filter)
    }
    var body: some View {
        AppNavigationStack {
            ScrollViewReader { proxy in
                List {
                    Section {
                        Text(title).font(.headline)
                        Text(current.name + " · \(chapters.count) chapters").font(.caption).foregroundStyle(.secondary)
                        Picker("Chapter status", selection: $filter) {
                            ForEach(MangaChapterFilter.allCases) { Text($0.title).tag($0) }
                        }.pickerStyle(.segmented).listRowSeparator(.hidden)
                    }
                    Section {
                        ForEach(shown) { chapter in
                            chapterRow(chapter).id(chapter.url)
                        }
                        if shown.isEmpty { Text("No chapters match. Try another search or read-status filter.").foregroundStyle(.secondary) }
                    }
                }.searchable(text: $query, prompt: "Chapter name or number")
                    .task(id: jump) {
                        // Wait for the List to include the current chapter after clearing filters.
                        do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
                        proxy.scrollTo(current.url, anchor: .center)
                    }
            }.navigationTitle("Chapters").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Current") { query = ""; filter = .all; jump += 1 }
                            .accessibilityIdentifier("webtoon-current-chapter")
                    }
                    ToolbarItem(placement: .confirmationAction) { Button("Done", action: onDone) }
                }
        }.tint(MangaStyle.accent).preferredColorScheme(.dark)
    }
    private func chapterRow(_ chapter: SourceMangaChapter) -> some View {
        let selected = chapter.url == current.url
        let point = record?.position(for: chapter.url)
        return Button { onSelect(chapter) } label: {
            HStack(spacing: 12) {
                Image(systemName: selected ? "book.fill" : point?.completed == true ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected || point?.completed == true ? MangaStyle.accent : Color.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(chapter.name).font(.subheadline.weight(selected ? .bold : .regular))
                    if selected { Text("Reading now").font(.caption).foregroundStyle(MangaStyle.accent) }
                    else if let point, !point.completed, point.pageCount > 0 {
                        Text("Page \(point.pageIndex + 1) of \(point.pageCount)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }.padding(.vertical, 6).foregroundStyle(.primary)
        }.accessibilityIdentifier("webtoon-choose-chapter-\(chapters.firstIndex(of: chapter) ?? 0)")
    }
}
