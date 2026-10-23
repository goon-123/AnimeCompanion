import SwiftUI
import AnimeCore

struct MangaHubView: View {
    @EnvironmentObject private var extensions: MangaExtensionStore
    @EnvironmentObject private var reading: MangaReadingStore
    @AppStorage("manga.showMatureSources") private var showMature = false
    @State private var section = "Library"
    @State private var query = ""
    @State private var language = "en"
    @State private var manage = false
    @State private var choseInitialSection = false
    @State private var confirmClearHistory = false
    @State private var clearingHistory = false
    private var sources: [MangaSourceReference] {
        extensions.state.installations.filter { $0.enabled && (showMature || !$0.descriptor.adult) }.flatMap { entry in
            entry.sources.map { MangaSourceReference(installation: entry, source: $0) }
        }.filter { (language.isEmpty || $0.language == language || $0.language == "all") &&
            (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    private var records: [MangaReadingRecord] {
        reading.state.records.filter { (showMature || !$0.title.source.adult) &&
            (query.isEmpty || $0.title.manga.title.localizedCaseInsensitiveContains(query)) }
    }
    private var history: [MangaReadingRecord] { records.filter { $0.lastReadAt != nil }.sorted { $0.lastReadAt! > $1.lastReadAt! } }
    private var saved: [MangaReadingRecord] {
        records.filter(\.saved).sorted { ($0.lastReadAt ?? $0.addedAt) > ($1.lastReadAt ?? $1.addedAt) }
    }
    var body: some View {
        VStack(spacing: 0) {
            Picker("Manga area", selection: $section) {
                ForEach(["Library", "Sources", "History"], id: \.self) { Text($0) }
            }.pickerStyle(.segmented).padding(.horizontal, 18).padding(.vertical, 12)
                .accessibilityIdentifier("manga-hub-sections")
            if reading.loading { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
            else if section == "Sources" { sourceList }
            else if section == "History" { historyList }
            else { library }
        }.background(Color.black).navigationTitle("Manga").tint(MangaStyle.accent)
            .searchable(text: $query, prompt: section == "Sources" ? "Find a source" : "Find a title")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(value: MangaSearchRoute(titles: [])) { Image(systemName: "magnifyingglass") }
                        .accessibilityLabel("Search manga in installed sources").accessibilityIdentifier("manga-search-sources")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { manage = true } label: { Image(systemName: "puzzlepiece.extension") }
                        .accessibilityLabel("Manage manga extensions").accessibilityIdentifier("manga-manage-extensions")
                }
            }
            .sheet(isPresented: $manage) { MangaExtensionSheet() }
            .confirmationDialog("Clear manga history?", isPresented: $confirmClearHistory, titleVisibility: .visible) {
                Button("Clear history", role: .destructive) {
                    clearingHistory = true
                    Task { await reading.clearHistory(); clearingHistory = false }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Removes all titles from History and Continue reading, including hidden titles. Saved stories and chapter progress are kept.")
            }
            .task {
                await reading.load()
                if !choseInitialSection {
                    choseInitialSection = true
                    if reading.state.records.isEmpty { section = "Sources" }
                }
                await extensions.load()
            }
            .onChange(of: section) { _, _ in query = "" }
            .alert("Manga", isPresented: Binding(get: { reading.error != nil }, set: { if !$0 { reading.error = nil } })) {
                Button("OK") { reading.error = nil }
            } message: { Text(reading.error ?? "") }
    }
    private var library: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                pageHeading("Your next chapter", subtitle: "Keep the stories you love close.")
                if !history.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        sectionHeading("Continue reading", count: min(history.count, 8))
                        ScrollView(.horizontal) {
                            LazyHStack(spacing: 14) {
                                ForEach(history.prefix(8)) { recent in
                                    NavigationLink { MangaTitleDetailView(title: recent.title) } label: {
                                        continueCard(recent).frame(width: 310)
                                    }.buttonStyle(.plain)
                                }
                            }.scrollTargetLayout()
                        }.scrollIndicators(.hidden).scrollTargetBehavior(.viewAligned)
                    }
                }
                sectionHeading("Saved stories", count: saved.count)
                if saved.isEmpty {
                    ContentUnavailableView {
                        Label(query.isEmpty ? "Your next story belongs here" : "No matching titles", systemImage: "books.vertical")
                    } description: { Text("Save titles from a source to keep their covers and reading progress together.") }
                    actions: { Button("Browse sources") { section = "Sources" }.buttonStyle(.borderedProminent) }
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 240), spacing: 12)], spacing: 12) {
                        ForEach(Array(saved.enumerated()), id: \.element.id) { index, entry in
                            NavigationLink { MangaTitleDetailView(title: entry.title) } label: {
                                MangaTitleCard(title: entry.title, saved: true)
                            }.buttonStyle(.plain).accessibilityIdentifier("manga-saved-title-\(index)")
                        }
                    }
                }
                discoverCard
            }.padding(18).frame(maxWidth: 1100).frame(maxWidth: .infinity)
        }.accessibilityIdentifier("manga-library")
    }
    private func pageHeading(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.title2.bold()).foregroundStyle(.white)
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
        }.padding(.top, 4)
    }
    private func sectionHeading(_ title: String, count: Int) -> some View {
        HStack {
            Text(title).font(.headline)
            Spacer()
            Text("\(count)").font(.caption.weight(.semibold)).monospacedDigit()
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(.white.opacity(0.08), in: Capsule()).foregroundStyle(.secondary)
        }
    }
    private var discoverCard: some View {
        NavigationLink(value: MangaSearchRoute(titles: [])) {
            HStack(spacing: 14) {
                Image(systemName: "sparkle.magnifyingglass").font(.title2)
                    .frame(width: 48, height: 48).background(MangaStyle.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Find your next story").font(.headline)
                    Text("Search across your installed sources").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right").font(.subheadline.bold())
            }.foregroundStyle(MangaStyle.accent).padding(16)
                .background(MangaStyle.surface, in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(MangaStyle.accent.opacity(0.18)))
        }.buttonStyle(.plain).accessibilityIdentifier("manga-discover-stories")
    }
    private func continueCard(_ record: MangaReadingRecord) -> some View {
        HStack(spacing: 16) {
            MangaCover(title: record.title, width: 84).frame(width: 84, height: 126).clipShape(RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 8) {
                Text(record.title.manga.title).font(.headline).lineLimit(2)
                Text(record.title.source.name).font(.caption).foregroundStyle(.secondary)
                if let url = record.lastChapterURL, let point = record.position(for: url) {
                    Text(point.chapterName).font(.subheadline).foregroundStyle(MangaStyle.accent)
                    Text(point.completed ? "Chapter finished" : "Page \(point.pageIndex + 1) of \(point.pageCount)")
                        .font(.caption).foregroundStyle(.secondary)
                    ProgressView(value: point.completed ? 1 : Double(point.pageIndex + 1) / Double(max(point.pageCount, 1)))
                        .tint(MangaStyle.accent).accessibilityLabel("Chapter progress")
                }
                Label("Continue", systemImage: "arrow.right").font(.subheadline.bold())
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(14).background(MangaStyle.surface, in: RoundedRectangle(cornerRadius: 20))
    }
    private var historyList: some View {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 16) {
            pageHeading("Recently read", subtitle: "Pick up where you left off, in any source.")
            Button(role: .destructive) { confirmClearHistory = true } label: {
                Label(clearingHistory ? "Clearing history…" : "Clear manga history", systemImage: "trash")
                    .font(.subheadline.weight(.medium)).frame(minHeight: 44)
            }.disabled(clearingHistory || reading.unreadable || !reading.state.records.contains { $0.lastReadAt != nil })
                .accessibilityIdentifier("manga-clear-history")
                .accessibilityHint("Asks for confirmation. Saved titles and reading progress are kept.")
            if history.isEmpty { ContentUnavailableView("No reading history yet", systemImage: "clock", description: Text("The chapters you read will appear here.")) }
            ForEach(history) { record in
                NavigationLink { MangaTitleDetailView(title: record.title) } label: {
                    HStack(spacing: 14) {
                        MangaCover(title: record.title, width: 60).frame(width: 60, height: 86).clipShape(RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 5) {
                            Text(record.title.manga.title).font(.headline).lineLimit(2)
                            if let url = record.lastChapterURL, let point = record.position(for: url) {
                                Text(point.chapterName + (point.completed ? " · Finished" : " · Page \(point.pageIndex + 1)"))
                                    .font(.caption).foregroundStyle(MangaStyle.accent)
                            }
                            if let date = record.lastReadAt { Text(date, style: .relative).font(.caption).foregroundStyle(.secondary) }
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.secondary)
                    }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        .background(MangaStyle.surface, in: RoundedRectangle(cornerRadius: 18))
                }.buttonStyle(.plain)
            }
          }.padding(18).frame(maxWidth: 1100).frame(maxWidth: .infinity)
        }.accessibilityIdentifier("manga-history")
    }
    private var sourceList: some View {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 24) {
            pageHeading("Explore your sources", subtitle: "Browse a favorite or discover something new.")
            discoverCard
            HStack {
                Label("\(sources.count) available", systemImage: "square.stack.3d.up")
                    .font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Picker("Language", selection: $language) {
                    Text("All languages").tag("")
                    ForEach(Array(Set(extensions.state.installations.flatMap(\.sources).map(\.language) + ["en"])).filter { $0 != "all" }.sorted(), id: \.self) {
                        Text(Locale.current.localizedString(forLanguageCode: $0) ?? $0.uppercased()).tag($0)
                    }
                }.pickerStyle(.menu).tint(MangaStyle.accent)
                    .accessibilityIdentifier("manga-source-language")
            }.padding(12).background(MangaStyle.surface, in: RoundedRectangle(cornerRadius: 14))
            if extensions.loading { ProgressView("Loading sources…") }
            else if extensions.state.installations.isEmpty {
                ContentUnavailableView {
                    Label("Add your first source", systemImage: "puzzlepiece.extension")
                } description: { Text("Connect Keiyoushi and install a manga or manhwa extension.") }
                actions: { Button("Add extensions") { manage = true }.buttonStyle(.borderedProminent) }
            } else if sources.isEmpty {
                ContentUnavailableView("No matching sources", systemImage: "magnifyingglass",
                    description: Text("Try another language or enable a source in Extensions."))
            } else {
                let pinned = sources.filter { reading.state.pinnedSources.contains($0.id) }
                let recent = reading.state.recentSources.compactMap { id in sources.first { $0.id == id && !reading.state.pinnedSources.contains(id) } }
                let others = sources.filter { !reading.state.pinnedSources.contains($0.id) && !recent.contains($0) }
                if !pinned.isEmpty { sourceGroup("Pinned", items: pinned) }
                if !recent.isEmpty { sourceGroup("Recently used", items: recent) }
                if !others.isEmpty { sourceGroup("All sources", items: others) }
            }
            Button { manage = true } label: {
                Label("Manage extensions", systemImage: "puzzlepiece.extension")
                    .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(14)
            }.buttonStyle(.bordered).clipShape(RoundedRectangle(cornerRadius: 14))
          }.padding(18).frame(maxWidth: 1100).frame(maxWidth: .infinity)
        }.accessibilityIdentifier("manga-sources")
    }
    private func sourceGroup(_ title: String, items: [MangaSourceReference]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeading(title, count: items.count)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 270, maximum: 520), spacing: 12)], spacing: 12) {
                ForEach(items) { sourceRow($0) }
            }
        }
    }
    private func sourceRow(_ source: MangaSourceReference) -> some View {
        HStack(spacing: 12) {
            NavigationLink { MangaSourceBrowseView(source: source) } label: {
                HStack(spacing: 13) {
                    if let entry = extensions.installed(source.extensionID)?.descriptor { MangaExtensionIcon(entry: entry) }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(source.name).font(.headline)
                        Text(source.language == "all" ? "Multilingual" : Locale.current.localizedString(forLanguageCode: source.language) ?? source.language)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.secondary)
                }.padding(.vertical, 8).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("manga-source-\(source.sourceID)")
            Button { Task { await reading.pin(source) } } label: {
                Image(systemName: reading.state.pinnedSources.contains(source.id) ? "pin.fill" : "pin")
                    .foregroundStyle(reading.state.pinnedSources.contains(source.id) ? MangaStyle.accent : .secondary)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel(reading.state.pinnedSources.contains(source.id) ? "Unpin source" : "Pin source")
        }.padding(.leading, 14).padding(.trailing, 6)
            .background(MangaStyle.surface, in: RoundedRectangle(cornerRadius: 18))
    }
}

struct MangaExtensionSheet: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            MangaExtensionsView().toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }.tint(MangaStyle.accent)
    }
}

struct MangaTitleCard: View {
    let title: MangaTitleReference
    let saved: Bool
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomLeading) {
                MangaCover(title: title, width: geometry.size.width)
                LinearGradient(colors: [.clear, .black.opacity(0.90)], startPoint: .center, endPoint: .bottom)
                Text(title.manga.title).font(.subheadline.weight(.semibold)).lineLimit(2).foregroundStyle(.white).padding(12)
            }.overlay(alignment: .topLeading) {
                if saved { Image(systemName: "bookmark.fill").font(.caption).padding(8).background(MangaStyle.accent, in: Capsule()).foregroundStyle(.black).padding(8) }
            }
        }.aspectRatio(2.0 / 3, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 14))
            .accessibilityElement(children: .ignore).accessibilityLabel(title.manga.title + (saved ? ", in library" : ""))
    }
}
