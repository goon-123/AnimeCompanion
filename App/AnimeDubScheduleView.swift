import SwiftUI
import AnimeCore

struct AnimeDubScheduleView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var dubs: ExploreDubStore
    @EnvironmentObject private var navigation: AppNavigationStore
    let anime: Anime
    private var events: [ReleaseEvent] {
        dubs.snapshot?.events(knownMedia: [anime.id: anime]).filter { $0.anime.id == anime.id } ?? []
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if store.isVisible(anime) {
                    Text(anime.displayTitle).font(.title2.bold())
                    AnimeDubSchedule(anime: anime, progress: dubs.progress(for: anime), snapshot: dubs.snapshot,
                        events: events, loading: dubs.loading, error: dubs.notice, showExpandedDetails: true)
                    Button { navigation.openSchedule() } label: {
                        Label("Open the weekly schedule", systemImage: "calendar")
                    }.buttonStyle(.bordered).accessibilityIdentifier("detail-weekly-schedule")
                } else {
                    ContentUnavailableView("Adult content is hidden", systemImage: "eye.slash")
                }
            }.padding(18).readableContent(width: 940)
        }.background(Theme.background).navigationTitle("English dub").navigationBarTitleDisplayMode(.inline)
            .companionDockHidden()
            .accessibilityIdentifier("anime-dub-schedule")
            .task(id: "\(anime.id)-\(store.includeAdult)") {
                if store.isVisible(anime) { await dubs.load(using: store.dubs) }
            }
            .refreshable { if store.isVisible(anime) { await dubs.load(using: store.dubs, refresh: true) } }
    }
}
