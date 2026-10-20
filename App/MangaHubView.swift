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
                if let recent = history.first {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Continue reading").font(.title3.bold())
                        NavigationLink { MangaTitleDetailView(title: recent.title) } label: { continueCard(recent) }.buttonStyle(.plain)
                    }
                }
                HStack {
                    Text("Your library").font(.title3.bold())
                    Spacer(); Text("\(saved.count) titles").font(.subheadline).foregroundStyle(.secondary)
                }
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
            }.padding(18)
        }.accessibilityIdentifier("manga-library")
    }
    private func continueCard(_ record: MangaReadingRecord) -> some View {
        HStack(spacing: 16) {
            MangaCover(title: record.title, width: 96).frame(width: 96, height: 138).clipShape(RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 8) {
                Text(record.title.manga.title).font(.headline).lineLimit(2)
                Text(record.title.source.name).font(.caption).foregroundStyle(.secondary)
                if let url = record.lastChapterURL, let point = record.position(for: url) {
                    Text(point.chapterName).font(.subheadline).foregroundStyle(MangaStyle.accent)
                    Text(point.completed ? "Chapter finished" : "Page \(point.pageIndex + 1) of \(point.pageCount)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Label("Continue", systemImage: "arrow.right").font(.subheadline.bold())
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(12).background(MangaStyle.surface, in: RoundedRectangle(cornerRadius: 18))
    }
    private var historyList: some View {
        List {
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
                    }.padding(.vertical, 4)
                }
            }
        }.scrollContentBackground(.hidden).accessibilityIdentifier("manga-history")
    }
    private var sourceList: some View {
        List {
            Section {
                HStack {
                    Label("Read on your terms", systemImage: "rectangle.portrait.on.rectangle.portrait")
                    Spacer(); Text("WEBTOON").font(.caption2.bold()).foregroundStyle(MangaStyle.accent)
                }
                Text("Choose an installed source, find a story, and keep scrolling.").font(.subheadline).foregroundStyle(.secondary)
                Picker("Language", selection: $language) {
                    Text("All languages").tag("")
                    ForEach(Array(Set(extensions.state.installations.flatMap(\.sources).map(\.language) + ["en"])).filter { $0 != "all" }.sorted(), id: \.self) {
                        Text(Locale.current.localizedString(forLanguageCode: $0) ?? $0.uppercased()).tag($0)
                    }
                }
            }
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
                if !pinned.isEmpty { Section("Pinned") { ForEach(pinned) { sourceRow($0) } } }
                if !recent.isEmpty { Section("Recently used") { ForEach(recent) { sourceRow($0) } } }
                if !others.isEmpty { Section("Sources") { ForEach(others) { sourceRow($0) } } }
            }
            Section {
                Button { manage = true } label: { Label("Manage extensions", systemImage: "puzzlepiece.extension") }
            } footer: { Text("Source compatibility is experimental. Mature source collections follow the setting in Extensions.") }
        }.scrollContentBackground(.hidden).accessibilityIdentifier("manga-sources")
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
                }.padding(.vertical, 6)
            }.accessibilityIdentifier("manga-source-\(source.sourceID)")
            Button { Task { await reading.pin(source) } } label: {
                Image(systemName: reading.state.pinnedSources.contains(source.id) ? "pin.fill" : "pin")
                    .foregroundStyle(reading.state.pinnedSources.contains(source.id) ? MangaStyle.accent : .secondary)
            }.buttonStyle(.borderless).accessibilityLabel(reading.state.pinnedSources.contains(source.id) ? "Unpin source" : "Pin source")
        }
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
