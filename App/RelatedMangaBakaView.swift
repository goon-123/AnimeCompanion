import SwiftUI
import AnimeCore

/// Stays on the anime's navigation stack, including an iPad detail column.
/// Opening a written adaptation does not depend on the Manga tab being visible.
struct RelatedMangaBakaView: View {
    @EnvironmentObject private var account: MangaBakaStore
    @EnvironmentObject private var preferences: AppStore
    let media: RelatedAnime
    @State private var matches: [MangaBakaSeries]?
    @State private var error: String?
    @State private var attempt = UUID()

    private var visible: [MangaBakaSeries] {
        (matches ?? []).filter { $0.isVisible(includeAdult: preferences.includeAdult) }
    }

    var body: some View {
        Group {
            if let series = visible.first, visible.count == 1 {
                MangaBakaDetailView(series: series).id(series.id)
            } else if !visible.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        Text("Choose a MangaBaka listing for \(media.displayTitle)").font(.headline)
                        ForEach(visible) { series in
                            NavigationLink(value: MangaBakaSeriesRoute(series: series)) {
                                MangaBakaBrowseRow(series: series)
                            }.buttonStyle(.plain).accessibilityIdentifier("related-mangabaka-choice-\(series.id)")
                        }
                    }.padding().frame(maxWidth: 1000).frame(maxWidth: .infinity)
                }
            } else if let matches, !matches.isEmpty {
                ContentUnavailableView("Hidden by content settings", systemImage: "eye.slash",
                    description: Text("This MangaBaka listing is hidden by your current content settings."))
            } else if let error {
                VStack(spacing: 20) {
                    NoticeView(message: error) { Task { await load(refresh: true) } }
                    searchLink
                }.padding()
            } else if matches != nil {
                ContentUnavailableView {
                    Label("No linked MangaBaka listing", systemImage: "book.closed")
                } description: {
                    Text("MangaBaka has no linked listing for \(media.displayTitle). You can search its catalog for this title.")
                } actions: { searchLink }
            } else {
                ProgressView("Finding on MangaBaka…").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.background(Theme.background).navigationTitle("Series").navigationBarTitleDisplayMode(.inline)
            .mangaBakaNavigation()
            .task(id: "\(media.id)-\(preferences.includeAdult)") { await load() }
    }

    private var searchLink: some View {
        NavigationLink(value: MangaBakaBrowseRoute(query: .init(text: media.displayTitle))) {
            Label("Search MangaBaka", systemImage: "magnifyingglass")
        }.accessibilityIdentifier("related-mangabaka-search")
    }

    @MainActor private func load(refresh: Bool = false) async {
        let request = UUID(); attempt = request
        matches = nil; error = nil
        do {
            let records = try await account.api.series(anilistID: media.id, refresh: refresh)
            try Task.checkCancellation()
            guard request == attempt else { return }
            matches = records
        } catch is CancellationError { return }
        catch {
            guard request == attempt, !Task.isCancelled else { return }
            self.error = error.localizedDescription
        }
    }
}
