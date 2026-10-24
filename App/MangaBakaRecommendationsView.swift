import SwiftUI
import AnimeCore

/// Browses the same account-owned result as Explore. Opening this screen never
/// routes a private recommendation query through the public catalog client.
struct MangaBakaRecommendationsView: View {
    @EnvironmentObject private var account: MangaBakaStore
    @EnvironmentObject private var preferences: AppStore
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("mangabaka.browseLayout") private var layout = "grid"
    @State private var search = ""
    private var visible: [MangaBakaSeries] {
        let text = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return account.recommendationState.items.filter { series in
            series.isVisible(includeAdult: preferences.includeAdult)
                && (text.isEmpty || series.searchTitles.contains { $0.localizedStandardContains(text) })
        }
    }
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if account.connected {
                        header
                        if let error = account.recommendationState.error { NoticeView(message: error) { refresh() } }
                        if let notice = account.recommendationCacheNotice { Text(notice).font(.caption).foregroundStyle(.orange) }
                        results(width: geometry.size.width)
                        if account.recommendationState.loading { ProgressView("Loading recommendations…").frame(maxWidth: .infinity).padding() }
                        if visible.isEmpty && !account.recommendationState.loading {
                            if !search.isEmpty { ContentUnavailableView.search(text: search) }
                            else {
                                Text(account.recommendationState.emptyMessage).foregroundStyle(.secondary)
                                Link("View recommendations on MangaBaka", destination: URL(string: "https://mangabaka.org/my/recommendations")!)
                            }
                        }
                        MangaBakaAttribution().padding(.top, 12)
                    } else {
                        ContentUnavailableView("Connect MangaBaka", systemImage: "person.crop.circle",
                            description: Text("Connect your account in Settings to see your recommendations."))
                    }
                }.padding(20).frame(maxWidth: 1180).frame(maxWidth: .infinity)
            }.refreshable { await account.loadRecommendations(includeAdult: preferences.includeAdult, refresh: true) }
        }.background(Theme.background).navigationTitle("For you").navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, prompt: "Search your recommendations")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { refresh() } label: { Image(systemName: "arrow.clockwise") }
                        .disabled(!account.connected || account.recommendationState.loading)
                        .accessibilityLabel("Refresh manga recommendations")
                }
            }
            .task(id: "\(account.connected)-\(preferences.includeAdult)") {
                await account.loadRecommendations(includeAdult: preferences.includeAdult)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await account.loadRecommendations(includeAdult: preferences.includeAdult) } }
            }
    }
    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(visible.count) recommendations").font(.subheadline.weight(.semibold))
                Spacer()
                Picker("Results layout", selection: $layout) {
                    Image(systemName: "square.grid.2x2").accessibilityLabel("Poster grid").tag("grid")
                    Image(systemName: "list.bullet.rectangle").accessibilityLabel("Detailed list").tag("list")
                }.pickerStyle(.segmented).frame(width: 100)
            }
            Text("Selected by MangaBaka from your library. Refreshes weekly, or whenever you tap Refresh.")
                .font(.subheadline).foregroundStyle(.secondary)
            if let date = account.recommendationState.fetchedAt {
                Text("Updated \(date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let date = account.recommendationState.refreshAt {
                Text("Next refresh: \(date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    @ViewBuilder private func results(width: CGFloat) -> some View {
        if layout == "list" {
            LazyVStack(spacing: 14) {
                ForEach(visible) { series in
                    NavigationLink(value: MangaBakaSeriesRoute(series: series)) { MangaBakaBrowseRow(series: series) }.buttonStyle(.plain)
                }
            }
        } else {
            let minimum: CGFloat = textSize.isAccessibilitySize ? 180 : 140
            let available = max(140, min(1180, width) - 40)
            let count = max(1, Int((available + 14) / (minimum + 14)))
            let cardWidth = max(1, (available - CGFloat(count - 1) * 14) / CGFloat(count))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: count), alignment: .leading, spacing: 24) {
                ForEach(visible) { series in
                    NavigationLink(value: MangaBakaSeriesRoute(series: series)) { MangaBakaCard(series: series, width: cardWidth) }.buttonStyle(.plain)
                }
            }
        }
    }
    private func refresh() { Task { await account.loadRecommendations(includeAdult: preferences.includeAdult, refresh: true) } }
}
