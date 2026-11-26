import SwiftUI
import AnimeCore

enum MangaReadingDestination: String, Hashable {
    case sources, saved, history
    var title: String {
        switch self { case .sources: return "Installed sources"; case .saved: return "Saved series"; case .history: return "Reading history" }
    }
}

private struct MangaReadingNavigation: ViewModifier {
    func body(content: Content) -> some View {
        content.navigationDestination(for: MangaReadingDestination.self) { destination in
            MangaHubView(destination: destination).toolbar(.visible, for: .navigationBar)
        }.navigationDestination(for: MangaSearchRoute.self) { route in
            MangaTitleSearchView(titles: route.titles, linkingTo: route.linkingTo).id(route.id)
                .toolbar(.visible, for: .navigationBar)
        }.navigationDestination(for: LinkedMangaRoute.self) { route in
            MangaTitleDetailView(title: route.link.title, linkingTo: route.link.library, resumeOnOpen: true).id(route.id)
                .toolbar(.visible, for: .navigationBar)
        }
    }
}
extension View { func mangaReadingNavigation() -> some View { modifier(MangaReadingNavigation()) } }

/// A small, local-only entry point beside discovery. No source search or
/// extension catalog refresh is performed merely to show these counts.
struct MangaReadingTiles: View {
    @EnvironmentObject private var extensions: MangaExtensionStore
    @EnvironmentObject private var reading: MangaReadingStore
    @EnvironmentObject private var preferences: AppStore
    @Environment(\.dynamicTypeSize) private var textSize
    private var mature: Bool { preferences.mangaBakaContent.allowsMatureSources }
    private var sourceCount: Int {
        extensions.state.installations.filter { $0.enabled && (mature || !$0.descriptor.adult) }.reduce(0) { $0 + $1.sources.count }
    }
    private var records: [MangaReadingRecord] { reading.state.records.filter { mature || !$0.title.source.adult } }
    private var savedCount: Int { records.filter(\.saved).count }
    private var recentCount: Int { records.filter { $0.lastReadAt != nil }.count }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your reading").font(.headline)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: textSize.isAccessibilitySize ? 1 : 2), spacing: 12) {
                tile(.sources, symbol: "square.stack.3d.up", detail: extensions.loading ? "Loading…" : extensions.unreadableState ? "Could not load sources" : "\(sourceCount) available")
                tile(.saved, symbol: "books.vertical", detail: reading.loading ? "Loading…" : reading.unreadable ? "Could not load saved series" : "\(savedCount) saved · \(recentCount) recent")
            }
        }.accessibilityIdentifier("explore-your-reading")
            .task {
                async let sources: Void = extensions.load(refreshCatalog: false)
                async let saved: Void = reading.load()
                _ = await (sources, saved)
            }
    }
    private func tile(_ destination: MangaReadingDestination, symbol: String, detail: String) -> some View {
        NavigationLink(value: destination) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: symbol).font(.title3).foregroundStyle(Theme.accent)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
                Text(destination.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, minHeight: 92, alignment: .leading).padding(14)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.border, lineWidth: 0.75))
                .contentShape(RoundedRectangle(cornerRadius: 18))
        }.buttonStyle(.plain).accessibilityIdentifier("explore-reading-" + destination.rawValue)
    }
}
