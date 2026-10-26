import SwiftUI
import AnimeCore

struct MangaBakaSeriesTags: View {
    @EnvironmentObject private var account: MangaBakaStore
    let series: MangaBakaSeries
    @State private var expanded = true
    @State private var spoilers = true
    @State private var implied = true
    @State private var information: String?
    private var tags: [MangaBakaTag] {
        var seen = Set<String>()
        return series.tags.map(account.resolvedTag).filter {
            (spoilers || !$0.isSpoiler) && (implied || !$0.isImplied) && seen.insert($0.name).inserted
        }.sorted {
            let order = ["core", "defining", "recurrent", "incidental"]
            let left = order.firstIndex(of: $0.weightLabel ?? "") ?? 4
            let right = order.firstIndex(of: $1.weightLabel ?? "") ?? 4
            return left == right ? $0.path < $1.path : left < right
        }
    }
    private var visibleTags: [MangaBakaTag] { expanded ? tags : Array(tags.prefix(36)) }
    private var groups: [String: [MangaBakaTag]] { Dictionary(grouping: visibleTags, by: \.category) }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !series.genres.isEmpty {
                Text("Genres").font(.title2.bold())
                MangaBakaFlowLayout {
                    ForEach(series.genres, id: \.self) { genre in
                        let value = account.catalogGenres.first { $0.value == genre.name } ?? MangaBakaGenre(value: genre.name, label: genre.label)
                        NavigationLink(value: MangaBakaBrowseRoute(query: .init(genres: [value]))) {
                            tagText(value.label, color: .mint)
                        }.buttonStyle(.plain)
                    }
                }
            }
            HStack {
                Text("Tags").font(.title2.bold())
                Spacer()
                Menu {
                    Toggle("Show spoiler tags", isOn: $spoilers)
                    Toggle("Include implied tags", isOn: $implied)
                } label: { Label("Display", systemImage: "line.3.horizontal.decrease") }.font(.subheadline)
            }
            ForEach(groups.keys.sorted(), id: \.self) { category in
                VStack(alignment: .leading, spacing: 10) {
                    Text(category.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    MangaBakaFlowLayout(spacing: 7) {
                        ForEach(groups[category] ?? [], id: \.self) { tag in tagLink(tag) }
                    }
                }
            }
            if tags.isEmpty { Text("No tags are available with these display options.").font(.subheadline).foregroundStyle(.secondary) }
            if tags.count > 36 {
                Button(expanded ? "Show fewer tags" : "Show all \(tags.count) tags") { expanded.toggle() }.font(.subheadline.bold())
            }
            NavigationLink { MangaBakaTaxonomyView() } label: { Label("Explore every genre & tag", systemImage: "tag") }
                .font(.subheadline)
        }.task { await account.loadTaxonomy() }
            .alert("Tag details", isPresented: Binding(get: { information != nil }, set: { if !$0 { information = nil } })) {
                Button("Done", role: .cancel) { information = nil }
            } message: { Text(information ?? "") }
    }
    @ViewBuilder private func tagLink(_ tag: MangaBakaTag) -> some View {
        if tag.id != nil {
            NavigationLink(value: MangaBakaBrowseRoute(query: .init(tags: [tag]))) { tagContent(tag) }
                .buttonStyle(.plain).contextMenu {
                    Button("About this tag") { information = tag.path + (tag.description.isEmpty ? "" : "\n\n" + tag.description) }
                }
        } else { tagContent(tag) }
    }
    private func tagContent(_ tag: MangaBakaTag) -> some View {
        HStack(spacing: 5) {
            Text(tag.label).lineLimit(2)
            if let weight = tag.weightLabel { Text(weight.capitalized).font(.caption2.weight(.semibold)).foregroundStyle(.secondary) }
            if tag.isSpoiler { Image(systemName: "eye.slash").foregroundStyle(.orange) }
            if tag.isImplied { Image(systemName: "sparkles").foregroundStyle(.cyan) }
        }.font(.caption.weight(.medium)).padding(.horizontal, 10).padding(.vertical, 8)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.1)))
    }
    private func tagText(_ title: String, color: Color) -> some View {
        Text(title).font(.caption.weight(.semibold)).foregroundStyle(color).padding(.horizontal, 12).padding(.vertical, 8)
            .background(color.opacity(0.1), in: Capsule())
    }
}

struct MangaBakaCoverGallery: View {
    @EnvironmentObject private var account: MangaBakaStore
    @EnvironmentObject private var preferences: AppStore
    let series: MangaBakaSeries
    var refreshToken = 0
    @State private var covers: [MangaBakaCoverImage] = []
    @State private var loading = false
    @State private var error: String?
    @State private var page = 0
    @State private var hasMore = false
    @State private var retry = 0
    @State private var generation = UUID()
    @State private var preview: AnimeImagePreview?
    private var visible: [MangaBakaCoverImage] { covers.filter { $0.isVisible(contentFilter: preferences.mangaBakaContent) && $0.thumbnailURL != nil } }
    private var gallery: [AnimeImagePreview] {
        visible.compactMap { cover in
            cover.fullURL.map { AnimeImagePreview(url: $0, title: series.displayTitle + " · " + cover.caption, credit: cover.note, source: "MangaBaka") }
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text("Covers").font(.title2.bold()); Spacer(); Text(visible.count.formatted()).font(.caption).foregroundStyle(.secondary) }
            if !visible.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 14) { ForEach(visible) { cover in coverButton(cover) } }
                }
            }
            if loading { ProgressView("Loading covers…") }
            if let error { NoticeView(message: error) { retry += 1 } }
            if !loading && visible.isEmpty && error == nil { Text("No additional covers are available for this title and content setting.").font(.subheadline).foregroundStyle(.secondary) }
            if hasMore && !loading { Button("Load more covers") { Task { await load(next: true) } }.buttonStyle(.bordered) }
        }.task(id: "\(series.id)-\(preferences.mangaBakaContent)-\(retry)-\(refreshToken)") { await load() }
            .fullScreenCover(item: $preview) { item in AnimeImageViewer(preview: item, gallery: gallery) }
            .onChange(of: preferences.mangaBakaContent) { _, _ in preview = nil }
    }
    private func coverButton(_ cover: MangaBakaCoverImage) -> some View {
        Button {
            if let url = cover.fullURL { preview = AnimeImagePreview(url: url, title: series.displayTitle + " · " + cover.caption, credit: cover.note, source: "MangaBaka") }
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                ArtworkImage(url: cover.thumbnailURL, pointSize: 142) { $0.resizable().scaledToFill() } placeholder: { Theme.surface }
                    .frame(width: 142, height: 206).clipped().clipShape(RoundedRectangle(cornerRadius: 13))
                Text(cover.caption).font(.caption).lineLimit(2)
                if let note = cover.note, !note.isEmpty { Text(note).font(.caption2).foregroundStyle(.secondary).lineLimit(2) }
            }.frame(width: 142, alignment: .leading)
        }.buttonStyle(.plain).accessibilityLabel("Enlarge " + cover.caption)
    }
    private func load(next: Bool = false) async {
        if next && loading { return }
        if !next { generation = UUID(); covers = []; page = 0; hasMore = false }
        let request = generation, targetPage = next ? page + 1 : 1
        loading = true; error = nil
        defer { if generation == request { loading = false } }
        do {
            let result = try await account.api.covers(id: series.id, page: targetPage, refresh: retry > 0 || refreshToken > 0)
            try Task.checkCancellation(); guard request == generation else { return }
            var seen = Set(covers.map(\.id))
            let additions = result.items.filter { seen.insert($0.id).inserted }
            if next && additions.isEmpty && result.hasNext { throw MangaBakaError.message("No new covers were returned. Refresh this series to try again.") }
            covers += additions; page = targetPage; hasMore = result.hasNext
        } catch is CancellationError {} catch { if generation == request { self.error = error.localizedDescription } }
    }
}

struct MangaBakaRelatedSection: View {
    @EnvironmentObject private var account: MangaBakaStore
    @EnvironmentObject private var preferences: AppStore
    let series: MangaBakaSeries
    let kind: MangaBakaRelatedKind
    var refreshToken = 0
    @State private var items: [MangaBakaRelatedSeries] = []
    @State private var loading = false
    @State private var error: String?
    @State private var retry = 0
    @State private var generation = UUID()
    private var visible: [MangaBakaRelatedSeries] { items.filter { $0.series.isVisible(contentFilter: preferences.mangaBakaContent) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(kind.label).font(.title2.bold())
            Text(kind.explanation).font(.caption).foregroundStyle(.secondary)
            if !visible.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(visible) { item in
                            NavigationLink(value: MangaBakaSeriesRoute(series: item.series)) {
                                VStack(alignment: .leading, spacing: 8) {
                                    if let label = context(item) { Text(label).font(.caption2.weight(.semibold)).foregroundStyle(.mint).lineLimit(1) }
                                    MangaBakaCard(series: item.series, width: 156)
                                }.frame(width: 156, alignment: .leading)
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
            if loading { ProgressView("Loading " + kind.label.lowercased() + "…") }
            if let error { NoticeView(message: error) { retry += 1 } }
            if !loading && visible.isEmpty && error == nil { Text("MangaBaka has no matching titles for this section yet.").font(.subheadline).foregroundStyle(.secondary) }
        }.task(id: "\(series.id)-\(preferences.mangaBakaContent)-\(retry)-\(refreshToken)") { await load() }
    }
    private func context(_ item: MangaBakaRelatedSeries) -> String? {
        if kind == .readers, let count = item.sharedReaders { return count.formatted() + " readers" }
        if kind == .similar, item.matchedRelated { return "Related series" }
        if kind == .similar, let count = item.sharedTags { return count.formatted() + " shared tags" }
        return item.relationship?.replacingOccurrences(of: "_", with: " ").capitalized
    }
    private func load() async {
        let request = UUID(); generation = request; loading = true; error = nil
        defer { if generation == request { loading = false } }
        do {
            let result = try await account.api.related(id: series.id, kind: kind, contentFilter: preferences.mangaBakaContent, refresh: retry > 0 || refreshToken > 0)
            try Task.checkCancellation(); guard request == generation else { return }; items = result
        } catch is CancellationError {} catch { if generation == request { self.error = error.localizedDescription } }
    }
}
