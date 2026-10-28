import SwiftUI
import AnimeCore

struct MangaBakaLibraryTile: View {
    let entry: MangaBakaLibraryEntry
    let series: MangaBakaSeries
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geometry in
                MangaBakaCover(series: series, width: geometry.size.width)
            }.aspectRatio(1 / 1.45, contentMode: .fit)
                .overlay(alignment: .topLeading) { LibraryFormatBadge(title: series.formatLabel).padding(7) }
            Text(series.displayTitle).font(.subheadline.weight(.semibold)).lineLimit(2, reservesSpace: true)
            Text(MangaBakaReadingStatus(rawValue: entry.state)?.label ?? entry.state.capitalized)
                .font(.caption).foregroundStyle(.secondary)
            Text("Ch. " + (entry.chapter ?? 0).formatted()).font(.caption.monospacedDigit())
            MangaSourceLinkBadge(series: series)
            if let total = series.totalChapters, total > 0 {
                ProgressView(value: min(max(0, entry.chapter ?? 0), total), total: total).tint(.mint)
            }
        }.frame(maxWidth: .infinity, alignment: .topLeading).contentShape(Rectangle())
            .accessibilityIdentifier("reading-library-title-\(series.id)")
    }
}

struct LibraryFormatBadge: View {
    let title: String
    var body: some View {
        Text(title.uppercased()).font(.caption2.bold()).foregroundStyle(.white)
            .padding(.horizontal, 8).padding(.vertical, 5).background(.black.opacity(0.78), in: Capsule())
    }
}
