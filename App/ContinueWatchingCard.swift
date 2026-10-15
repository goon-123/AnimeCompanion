import SwiftUI
import AnimeCore

struct ContinueWatchingCard: View {
    @EnvironmentObject private var store: AppStore
    let item: ContinueWatchingItem
    @State private var watching = false
    var body: some View {
        if let anime = item.entry.media {
            VStack(alignment: .leading, spacing: 12) {
                AnimeLink(id: anime.id) {
                    HStack(alignment: .top, spacing: 12) {
                        AnimeCover(anime: anime, width: 64, cornerRadius: 8)
                        VStack(alignment: .leading, spacing: 7) {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(anime.displayTitle).font(.headline).lineLimit(2)
                                DiscoveryAiringDot(anime: anime, identifierPrefix: "continue")
                            }
                            Text(anime.format == "MOVIE" ? "Movie" : "Episode \(item.episode)").font(.subheadline.bold())
                                .accessibilityIdentifier("continue-episode-\(anime.id)")
                            Text("\(item.entry.progressValue) watched on AniList").font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.foregroundStyle(.primary).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("continue-details-\(anime.id)")
                if let resume = item.resume {
                    Text("Resume at \(Int(resume.position) / 60):\(String(format: "%02d", Int(resume.position) % 60))")
                        .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("continue-resume-\(anime.id)")
                    if let duration = resume.duration, duration.isFinite, duration > 0 {
                        ProgressView(value: min(resume.position, duration), total: duration).tint(.white)
                    }
                }
                Button { watching = true } label: {
                    Label(item.resume == nil ? "Watch in VidHub" : "Resume in VidHub", systemImage: "play.fill")
                        .font(.subheadline.bold()).frame(maxWidth: .infinity, minHeight: 44)
                }.buttonStyle(.borderedProminent).tint(.white).foregroundStyle(.black)
                    .disabled(store.loadingLibrary)
                    .accessibilityIdentifier("continue-watch-\(anime.id)")
            }.padding(14).background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
                .sheet(isPresented: $watching) { WatchAnimeView(anime: anime) }
        }
    }
}
