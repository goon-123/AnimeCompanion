import SwiftUI
import AnimeCore

/// A series title searches enabled sources together and keeps the library-link destination.
struct MangaTitleSearchView: View {
    let titles: [String]
    let linkingTo: MangaSourceLinkTarget?
    @State private var query: String
    @State private var manage = false
    @State private var refresh = 0
    @FocusState private var editing: Bool
    init(titles: [String], linkingTo: MangaSourceLinkTarget? = nil) {
        self.titles = titles; self.linkingTo = linkingTo
        _query = State(initialValue: titles.first ?? "")
    }
    private var search: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let linkingTo {
                    Label("Link a source for " + linkingTo.title, systemImage: "link").font(.subheadline).foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Series title", text: $query).submitLabel(.search).autocorrectionDisabled()
                        .focused($editing).onSubmit { editing = false }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .accessibilityIdentifier("manga-search-title")
                    Button { query = ""; editing = true } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary).frame(width: 44, height: 44)
                    }.buttonStyle(.plain).opacity(query.isEmpty ? 0 : 1).disabled(query.isEmpty)
                        .accessibilityHidden(query.isEmpty).accessibilityLabel("Clear series title")
                        .accessibilityIdentifier("manga-search-clear")
                }.padding(.horizontal, 12).background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
                if titles.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(Set(titles)).sorted(), id: \.self) { title in
                                CompanionFilterChip(title: title, selected: search == title) { query = title; editing = false }
                            }
                        }
                    }.accessibilityLabel("Alternative series titles")
                }
                InstalledMangaSearchView(query: search, compact: false, refresh: refresh, linkingTo: linkingTo, showAll: {})
                Text("Try the original or alternative title if a source has no matches. Tap a source's arrow for all its results and source settings.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(16).frame(maxWidth: 1180).frame(maxWidth: .infinity)
        }.background(Theme.background).navigationTitle("Find manga")
            .navigationBarTitleDisplayMode(.inline).tint(MangaStyle.accent)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { manage = true } label: { Image(systemName: "puzzlepiece.extension") }
                        .accessibilityLabel("Manage manga extensions")
                }
            }
            .sheet(isPresented: $manage) { MangaExtensionSheet() }
            .refreshable { refresh += 1 }
    }
}
