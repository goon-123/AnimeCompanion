import SwiftUI
import AnimeCore

struct MangaBakaTaxonomyView: View {
    @EnvironmentObject private var account: MangaBakaStore
    @EnvironmentObject private var preferences: AppStore
    @Binding private var selection: MangaBakaQuery
    private let selecting: Bool
    @State private var mode = "genres"
    @State private var search = ""
    @State private var category = "All categories"
    init(selection: Binding<MangaBakaQuery>? = nil) {
        _selection = selection ?? .constant(.init()); selecting = selection != nil
    }
    private var categories: [String] { Array(Set(account.catalogTags.map(\.category))).sorted() }
    private var genres: [MangaBakaGenre] {
        account.catalogGenres.filter { search.isEmpty || $0.label.localizedCaseInsensitiveContains(search) }
    }
    private var tags: [MangaBakaTag] {
        account.catalogTags.filter {
            (category == "All categories" || $0.category == category) &&
            (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.path.localizedCaseInsensitiveContains(search))
        }
    }
    var body: some View {
        List {
            if !selecting && search.isEmpty { ratings }
            Section {
                Picker("Browse", selection: $mode) {
                    Text("Genres (\(account.catalogGenres.count))").tag("genres")
                    Text("Tags (\(account.catalogTags.count))").tag("tags")
                }.pickerStyle(.segmented)
                if mode == "tags" {
                    Picker("Category", selection: $category) {
                        Text("All categories").tag("All categories")
                        ForEach(categories, id: \.self) { Text($0).tag($0) }
                    }
                }
            }
            if account.loadingTaxonomy && account.catalogTags.isEmpty { ProgressView("Loading MangaBaka's taxonomy…") }
            if let error = account.taxonomyError {
                NoticeView(message: error) { Task { await account.loadTaxonomy(refresh: true) } }
            }
            if mode == "genres" {
                Section("Genres") { ForEach(genres) { genre in genreRow(genre) } }
            } else {
                Section("\(tags.count.formatted()) tags") { ForEach(tags, id: \.id) { tag in tagRow(tag) } }
            }
        }.navigationTitle(selecting ? "Choose genres & tags" : "Explore genres & tags")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, prompt: "Search names and tag paths")
            .task { await account.loadTaxonomy() }
            .refreshable { await account.loadTaxonomy(refresh: true) }
    }
    private var ratings: some View {
        Section {
            Toggle("Include mature titles", isOn: $preferences.includeAdult)
            ForEach(MangaBakaContentRating.allCases, id: \.self) { rating in
                NavigationLink(value: MangaBakaBrowseRoute(query: .init(contentRatings: [rating]))) {
                    Label(rating.label, systemImage: rating.isMature ? "eye" : "books.vertical")
                }.disabled(rating.isMature && !preferences.includeAdult)
            }
        } header: { Text("Content ratings") }
        footer: { Text("Content ratings and genres are separate filters. Enable mature titles to browse every rating.") }
    }
    @ViewBuilder private func genreRow(_ genre: MangaBakaGenre) -> some View {
        if selecting {
            Button {
                if selection.genres.contains(where: { $0.value == genre.value }) { selection.genres.removeAll { $0.value == genre.value } }
                else { selection.genres.append(genre) }
                regularQuery()
            } label: {
                HStack { Text(genre.label); Spacer(); if selection.genres.contains(where: { $0.value == genre.value }) { Image(systemName: "checkmark.circle.fill").foregroundStyle(.mint) } }
            }.foregroundStyle(.primary)
        } else {
            NavigationLink(genre.label, value: MangaBakaBrowseRoute(query: .init(genres: [genre])))
        }
    }
    @ViewBuilder private func tagRow(_ tag: MangaBakaTag) -> some View {
        if selecting {
            HStack {
                Button { include(tag) } label: { tagLabel(tag) }.foregroundStyle(.primary)
                Spacer(minLength: 8)
                if selection.tags.contains(where: { $0.id == tag.id }) { Image(systemName: "checkmark.circle.fill").foregroundStyle(.mint) }
                if selection.excludedTags.contains(where: { $0.id == tag.id }) { Image(systemName: "minus.circle.fill").foregroundStyle(.orange) }
                Menu {
                    Button("Include tag") { include(tag) }
                    Button("Exclude tag") {
                        selection.tags.removeAll { $0.id == tag.id }
                        selection.excludedTags.removeAll { $0.id == tag.id }
                        selection.excludedTags.append(tag); regularQuery()
                    }
                    Button("Clear tag") {
                        selection.tags.removeAll { $0.id == tag.id }; selection.excludedTags.removeAll { $0.id == tag.id }
                    }
                } label: { Image(systemName: "ellipsis.circle").frame(minWidth: 32, minHeight: 36) }
            }
        } else {
            NavigationLink(value: MangaBakaBrowseRoute(query: .init(tags: [tag]))) { tagLabel(tag) }
        }
    }
    private func tagLabel(_ tag: MangaBakaTag) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(tag.label).font(.subheadline.weight(.medium))
            Text(tag.path).font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func include(_ tag: MangaBakaTag) {
        if selection.tags.contains(where: { $0.id == tag.id }) { selection.tags.removeAll { $0.id == tag.id } }
        else { selection.tags.append(tag) }
        selection.excludedTags.removeAll { $0.id == tag.id }; regularQuery()
    }
    private func regularQuery() { if selection.shelf.isCurated { selection.shelf = .popular } }
}

struct MangaBakaFilterSheet: View {
    @EnvironmentObject private var preferences: AppStore
    @Environment(\.dismiss) private var dismiss
    @Binding private var query: MangaBakaQuery
    @State private var draft: MangaBakaQuery
    @State private var allowMature = false
    @State private var initialized = false
    init(query: Binding<MangaBakaQuery>) { _query = query; _draft = State(initialValue: query.wrappedValue) }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Include mature titles", isOn: $allowMature)
                    ForEach(MangaBakaContentRating.allCases, id: \.self) { rating in
                        Toggle(rating.label, isOn: Binding(get: { draft.contentRatings.contains(rating) }, set: { selected in
                            if selected { draft.contentRatings.insert(rating) } else { draft.contentRatings.remove(rating) }
                            regularQuery()
                        })).disabled(rating.isMature && !allowMature)
                    }
                } header: { Text("Content ratings") }
                footer: { Text("With no ratings selected, results use all ratings allowed by your content setting.") }
                Section("Genres & tags") {
                    NavigationLink { MangaBakaTaxonomyView(selection: $draft) } label: {
                        Label("Browse all genres & tags", systemImage: "tag")
                    }
                    ForEach(draft.genres) { genre in
                        selectedRow(genre.label, excluded: false) { draft.genres.removeAll { $0.value == genre.value } }
                    }
                    ForEach(draft.tags, id: \.self) { tag in selectedRow(tag.label, excluded: false) { draft.tags.removeAll { $0.id == tag.id } } }
                    ForEach(draft.excludedTags, id: \.self) { tag in selectedRow(tag.label, excluded: true) { draft.excludedTags.removeAll { $0.id == tag.id } } }
                }
                Section("Format & publication") {
                    Picker("Format", selection: $draft.format) {
                        Text("All formats").tag(MangaBakaFormat?.none)
                        ForEach(MangaBakaFormat.allCases, id: \.self) { Text($0.label).tag(Optional($0)) }
                    }
                    Picker("Status", selection: $draft.status) {
                        Text("Any status").tag(String?.none)
                        ForEach(["releasing", "completed", "hiatus", "cancelled", "upcoming"], id: \.self) { Text($0.capitalized).tag(Optional($0)) }
                    }
                }
                Button("Reset filters", role: .destructive) { draft = .init(shelf: query.shelf.isCurated ? .popular : query.shelf, text: query.text) }
            }.navigationTitle("Discovery filters").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Show results") {
                            regularQuery(); preferences.includeAdult = allowMature; query = draft; dismiss()
                        }.fontWeight(.semibold)
                    }
                }
        }.onAppear { if !initialized { initialized = true; allowMature = preferences.includeAdult } }
            .onChange(of: allowMature) { _, value in if !value { draft.contentRatings = Set(draft.contentRatings.filter { !$0.isMature }) } }
    }
    private func regularQuery() {
        if draft.shelf.isCurated && (draft.format != nil || draft.status != nil || draft.hasFacets) { draft.shelf = .popular }
    }
    private func selectedRow(_ title: String, excluded: Bool, remove: @escaping () -> Void) -> some View {
        HStack {
            Label((excluded ? "Exclude: " : "") + title, systemImage: excluded ? "minus.circle" : "checkmark.circle")
                .foregroundStyle(excluded ? Color.orange : Color.mint)
            Spacer()
            Button(action: remove) { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.borderless).accessibilityLabel("Remove " + title)
        }.font(.subheadline)
    }
}

struct MangaBakaBadges: View {
    let series: MangaBakaSeries
    var body: some View {
        MangaBakaFlowLayout(spacing: 7) {
            badge(series.formatLabel, symbol: "book.closed")
            badge(series.status.capitalized, symbol: series.status == "releasing" ? "dot.radiowaves.left.and.right" : "checkmark.circle")
            if let year = series.year { badge(String(year), symbol: "calendar") }
            if let rating = series.contentRating { badge(rating.capitalized, symbol: "eye") }
            if let count = series.totalChapters { badge(count.formatted() + " ch.", symbol: "list.number") }
            if let count = series.finalVolume { badge(count.formatted() + " vol.", symbol: "books.vertical") }
            if series.isLicensed { badge("Licensed", symbol: "checkmark.seal") }
        }
    }
    private func badge(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol).font(.caption).lineLimit(1).padding(.horizontal, 9).padding(.vertical, 6)
            .background(.white.opacity(0.07), in: Capsule())
    }
}

struct MangaBakaBrowseRow: View {
    let series: MangaBakaSeries
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            MangaBakaCover(series: series, width: 94)
            VStack(alignment: .leading, spacing: 8) {
                Text(series.displayTitle).font(.headline).lineLimit(3)
                MangaBakaBadges(series: series)
                if let rating = series.rating { Label(rating.formatted(.number.precision(.fractionLength(0...1))) + "%", systemImage: "star.fill").font(.caption).foregroundStyle(.yellow) }
                if !series.synopsis.isEmpty { Text(series.synopsis).font(.caption).foregroundStyle(.secondary).lineLimit(3) }
                let labels = series.genres.prefix(4).map(\.label).joined(separator: " · ")
                if !labels.isEmpty { Text(labels).font(.caption2).foregroundStyle(.mint).lineLimit(2) }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(13).background(Theme.surface, in: RoundedRectangle(cornerRadius: 20))
    }
}

struct MangaBakaFlowLayout: Layout {
    var spacing: CGFloat = 8
    private func arrange(_ subviews: Subviews, width: CGFloat) -> (CGSize, [CGPoint], [CGSize]) {
        var positions: [CGPoint] = [], sizes: [CGSize] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for item in subviews {
            let ideal = item.sizeThatFits(.unspecified)
            let size = item.sizeThatFits(.init(width: min(width, ideal.width), height: nil))
            if x > 0 && x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            positions.append(.init(x: x, y: y)); sizes.append(size)
            x += size.width + spacing; rowHeight = max(rowHeight, size.height)
        }
        return (.init(width: width, height: y + rowHeight), positions, sizes)
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(subviews, width: max(1, proposal.width ?? 360)).0
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let (_, positions, sizes) = arrange(subviews, width: max(1, bounds.width))
        for index in subviews.indices {
            subviews[index].place(at: .init(x: bounds.minX + positions[index].x, y: bounds.minY + positions[index].y),
                proposal: .init(width: sizes[index].width, height: sizes[index].height))
        }
    }
}
