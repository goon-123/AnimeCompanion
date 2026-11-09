import SwiftUI
import UIKit
import AnimeCore

struct SeriesLayoutButton: View {
    let page: SeriesDetailPage
    @State private var arranging = false
    var body: some View {
        Button("Arrange sections", systemImage: "slider.horizontal.3") { arranging = true }
            .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
            .accessibilityIdentifier("series-arrange-" + page.rawValue)
            .sheet(isPresented: $arranging) { AppNavigationStack { SeriesLayoutEditor(page: page) } }
    }
}

struct SeriesLayoutEditor: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage private var saved: String
    @AppStorage(AnimeSeriesStyle.storageKey) private var style = AnimeSeriesStyle.cinematic.rawValue
    let page: SeriesDetailPage
    init(page: SeriesDetailPage) {
        self.page = page
        _saved = AppStorage(wrappedValue: "", page.storageKey)
    }
    private var preferences: SeriesDetailLayout { SeriesDetailLayout(page: page, saved: saved) }
    var body: some View {
        Group {
            if page == .anime && AnimeSeriesStyle(preference: style) == .cinematic { CinematicSeriesSectionsEditor() }
            else { legacyEditor }
        }.navigationTitle(page.title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
    private var legacyEditor: some View {
        List {
            Section {
                ForEach(preferences.order) { section in
                    Toggle(isOn: Binding(get: { !preferences.hidden.contains(section) }, set: { visible in
                        var value = preferences; value.setVisible(section, visible); saved = value.saved
                    })) {
                        Text(section.title(on: page))
                    }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .accessibilityIdentifier("series-visible-" + section.rawValue)
                        .accessibilityAction(named: Text("Move up")) { move(section, down: false) }
                        .accessibilityAction(named: Text("Move down")) { move(section, down: true) }
                }.onMove { offsets, destination in
                    var value = preferences
                    value.move(fromOffsets: offsets, toOffset: destination)
                    saved = value.saved
                }
            } footer: {
                Text(page.explanation + " Switch sections off to hide them. Changes save immediately on this device; empty sections appear when content is available.")
            }
            Section {
                Button("Show all sections") { var value = preferences; value.setAllVisible(true); saved = value.saved }
                Button("Hide all sections") { var value = preferences; value.setAllVisible(false); saved = value.saved }
                Button("Restore default layout") { saved = "" }.accessibilityIdentifier("series-arrange-reset")
            }
        }.environment(\.editMode, .constant(.active))

    }
    private func move(_ section: SeriesDetailSection, down: Bool) {
        var value = preferences
        guard let index = value.order.firstIndex(of: section),
              (down ? index + 1 < value.order.count : index > 0) else { return }
        value.move(fromOffsets: IndexSet(integer: index), toOffset: down ? index + 2 : index - 1)
        saved = value.saved
    }
}

private struct CinematicSeriesSectionsEditor: View {
    @AppStorage(SeriesMoreInfoPreferences.storageKey) private var infoSaved = ""
    @AppStorage("series.layout.anime.v1") private var headerSaved = ""
    private var info: SeriesMoreInfoPreferences { .init(saved: infoSaved) }
    private var header: SeriesDetailLayout { .init(page: .anime, saved: headerSaved) }
    var body: some View {
        List {
            Section("Series header") {
                ForEach([SeriesDetailSection.watchlist, .synopsis, .characters, .broadcast, .recommendations]) { section in
                    Toggle(section.title(on: .anime), isOn: Binding(get: { !header.hidden.contains(section) }, set: { shown in
                        var value = header; value.setVisible(section, shown); headerSaved = value.saved
                    })).accessibilityIdentifier("series-visible-" + section.rawValue)
                }
            }
            Section {
                ForEach(info.order) { section in
                    Toggle(section.title(on: .anime), isOn: Binding(get: { !info.hidden.contains(section) }, set: { shown in
                        var value = info; value.setVisible(section, shown); infoSaved = value.saved
                    })).accessibilityIdentifier("series-visible-" + section.rawValue)
                }.onMove { offsets, target in var value = info; value.move(fromOffsets: offsets, toOffset: target); infoSaved = value.saved }
            } header: { Text("More Info") } footer: { Text("Drag to reorder. Information, Related, Series news, Artwork & covers, and Links are visible by default. Reviews and Trailer remain available here if enabled.") }
            Section { Button("Restore More Info defaults") { infoSaved = "" } }
        }.environment(\.editMode, .constant(.active))
    }
}

private struct SeriesPosterWidthKey: EnvironmentKey { static let defaultValue: CGFloat = 128 }
extension EnvironmentValues {
    var seriesPosterWidth: CGFloat {
        get { self[SeriesPosterWidthKey.self] }
        set { self[SeriesPosterWidthKey.self] = newValue }
    }
}
private struct SeriesPosterSizing: ViewModifier {
    func body(content: Content) -> some View {
        GeometryReader { geometry in
            content.environment(\.seriesPosterWidth, CGFloat(SeriesDetailSizing.posterWidth(
                availableWidth: Double(max(0, min(geometry.size.width, 940) - 32)),
                isTablet: UIDevice.current.userInterfaceIdiom == .pad)))
        }
    }
}
extension View {
    func seriesPosterSizing() -> some View { modifier(SeriesPosterSizing()) }
}
