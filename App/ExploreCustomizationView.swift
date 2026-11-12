import SwiftUI
import UIKit
import AnimeCore

struct ExploreCustomizationView: View {
    let surface: ExploreSurface
    @AppStorage private var saved: String
    @State private var confirmReset = false
    @State private var pickingWidgets = false
    @State private var customizingShortcuts = false
    init(surface: ExploreSurface) {
        self.surface = surface; _saved = AppStorage(wrappedValue: "", surface.storageKey)
    }
    private var preferences: ExplorePreferences { ExplorePreferences(surface: surface, saved: saved) }
    private var widgetOptions: Binding<String> {
        Binding(get: { preferences.widgetOptions.saved }, set: { json in update { $0.widgetOptions = HomePreferences(saved: json) } })
    }
    var body: some View {
        List {
            Section {
                // List edit mode disables NavigationLink rows. Keep the reorder
                // handles active and push destinations with explicit buttons.
                Button { pickingWidgets = true } label: {
                    HStack {
                        Label("Add a Home widget", systemImage: "plus.circle.fill")
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                    }.foregroundStyle(Theme.accent).frame(minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("explore-add-widgets")
                    .accessibilityHint("Open the Home widget picker")
            } footer: { Text("Add any Home widget here. Explore keeps its own order, visibility, layouts and preview sizes.") }
            Section {
                ForEach(preferences.order) { row in
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle(isOn: Binding(get: { !preferences.hidden.contains(row) }, set: { shown in update { $0.setVisible(row, shown) } })) {
                            Text(row.title).font(.subheadline.weight(.semibold))
                        }.accessibilityIdentifier("explore-visible-" + row.id)
                        if case .catalog(let catalog) = row, catalog.supportsCardSize {
                            Picker("Card size", selection: Binding(get: { preferences.cardSize(for: catalog) }, set: { size in update { $0.setCardSize(size, for: catalog) } })) {
                                ForEach(ExploreCollectionSize.allCases) { size in Text(size.title).tag(size) }
                            }.pickerStyle(.segmented).accessibilityIdentifier("explore-card-size-" + catalog.rawValue)
                        }
                        if case .widget(let section) = row {
                            Text(section.detail).font(.caption).foregroundStyle(.secondary)
                            if section == .featureLinks {
                                Button("Customize shortcuts") { customizingShortcuts = true }.font(.caption)
                                    .frame(minHeight: 44).accessibilityIdentifier("explore-widget-shortcuts")
                            }
                            if section.supportsLayout {
                                Picker("Widget layout", selection: Binding(get: { preferences.widgetOptions.layout(for: section) }, set: { value in update { $0.widgetOptions.setLayout(value, for: section) } })) {
                                    ForEach(HomeWidgetLayout.allCases) { value in Text(value.title).tag(value) }
                                }
                            }
                            if section.supportsItemLimit {
                                Picker("Preview items", selection: Binding(get: { preferences.widgetOptions.size(for: section) }, set: { value in update { $0.widgetOptions.setSize(value, for: section) } })) {
                                    ForEach(HomeWidgetSize.allCases) { value in Text("\(value.title) · \(value.itemLimit)").tag(value) }
                                }
                            }
                        }
                    }.padding(.vertical, 4)
                        .accessibilityAction(named: "Move up") { update { $0.move(row, by: -1) } }
                        .accessibilityAction(named: "Move down") { update { $0.move(row, by: 1) } }
                }.onMove { offsets, destination in update { $0.move(fromOffsets: offsets, toOffset: destination) } }
            } header: { Text("Rows & widgets") }
            footer: { Text("Drag the handles to rearrange catalog rows and widgets together. Changes save immediately for this Explore layout.") }
            Section {
                Button("Show all rows") { update { $0.setAllVisible(true) } }
                Button("Hide all rows") { update { $0.setAllVisible(false) } }
                Button("Restore Explore layout") { confirmReset = true }
            }
        }.environment(\.editMode, .constant(.active))
            .navigationTitle("Customize Explore").navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $pickingWidgets) {
                ExploreWidgetPicker(surface: surface).environment(\.editMode, .constant(.inactive))
            }
            .navigationDestination(isPresented: $customizingShortcuts) {
                HomeShortcutCustomizationView(savedOverride: widgetOptions).environment(\.editMode, .constant(.inactive))
            }
            .confirmationDialog("Restore this Explore layout?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Restore layout") { saved = ExplorePreferences(surface: surface).saved }
            } message: { Text("This restores the default order, visibility and widget sizes for this Explore layout.") }
    }
    private func update(_ change: (inout ExplorePreferences) -> Void) { var value = preferences; change(&value); saved = value.saved }
}

private struct ExploreWidgetPicker: View {
    let surface: ExploreSurface
    @AppStorage private var saved: String
    @AppStorage(HomePreferences.storageKey) private var home = ""
    @State private var query = ""
    init(surface: ExploreSurface) { self.surface = surface; _saved = AppStorage(wrappedValue: "", surface.storageKey) }
    private var preferences: ExplorePreferences { ExplorePreferences(surface: surface, saved: saved) }
    private var matches: [HomeSection] { HomeSection.allCases.filter { query.isEmpty || ($0.title + " " + $0.detail).localizedCaseInsensitiveContains(query) } }
    var body: some View {
        List {
            Section {
                Text("Choose a widget, then go back to drag it into place among your Explore rows.").font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(matches) { section in
                HStack(spacing: 12) {
                    Image(systemName: section.symbol).font(.title3).foregroundStyle(Theme.accent).frame(width: 30)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(section.title).font(.subheadline.weight(.semibold))
                        Text(section.detail).font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    if preferences.visible.contains(.widget(section)) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent).frame(width: 44).accessibilityLabel("Already on Explore")
                    } else {
                        Button {
                            var value = preferences; value.addWidget(section, copying: HomePreferences(saved: home)); saved = value.saved
                        } label: { Image(systemName: "plus.circle.fill").font(.title2).frame(width: 44, height: 44) }
                            .buttonStyle(.borderless).accessibilityLabel("Add \(section.title) to Explore").accessibilityIdentifier("explore-add-" + section.rawValue)
                    }
                }.padding(.vertical, 6)
            }
            if matches.isEmpty { Text("No widgets match your search.").foregroundStyle(.secondary) }
        }.navigationTitle("Add widgets").navigationBarTitleDisplayMode(.inline).searchable(text: $query, prompt: "Find a Home widget")
    }
}

/// Catalog rows and Home widgets share a single saved order on each surface.
struct ExploreRows<Content: View>: View {
    let surface: ExploreSurface
    @AppStorage private var saved: String
    @Environment(\.exploreWidgetActivation) private var activationID
    let refreshID: Int
    let widgetInset: CGFloat
    let content: (ExploreCatalogRow) -> Content
    init(surface: ExploreSurface, refreshID: Int, widgetInset: CGFloat = 0, @ViewBuilder content: @escaping (ExploreCatalogRow) -> Content) {
        self.surface = surface; self.refreshID = refreshID; self.widgetInset = widgetInset; self.content = content
        _saved = AppStorage(wrappedValue: "", surface.storageKey)
    }
    private var preferences: ExplorePreferences { ExplorePreferences(surface: surface, saved: saved) }
    private var widgetOptions: Binding<String> {
        Binding(get: { preferences.widgetOptions.saved }, set: { json in update { $0.widgetOptions = HomePreferences(saved: json) } })
    }
    var body: some View {
        LazyVStack(alignment: .leading, spacing: 26) {
            ForEach(preferences.visible) { row in
                rowContent(row).contextMenu {
                    if case .catalog(let catalog) = row, catalog.supportsCardSize {
                        Picker("Card size", selection: Binding(get: { preferences.cardSize(for: catalog) }, set: { size in update { $0.setCardSize(size, for: catalog) } })) {
                            ForEach(ExploreCollectionSize.allCases) { size in Text(size.title).tag(size) }
                        }
                    }
                    Button("Move up", systemImage: "arrow.up") { update { $0.move(row, by: -1) } }.disabled(preferences.visible.first == row)
                    Button("Move down", systemImage: "arrow.down") { update { $0.move(row, by: 1) } }.disabled(preferences.visible.last == row)
                    Button("Hide row", systemImage: "eye.slash") { update { $0.setVisible(row, false) } }
                }.accessibilityIdentifier("explore-row-" + row.id)
            }
            if preferences.visible.isEmpty {
                ContentUnavailableView("Make Explore yours", systemImage: "rectangle.stack.badge.plus",
                    description: Text("Use Customize Explore above to show catalog rows or add Home widgets."))
                    .accessibilityIdentifier("explore-empty-layout")
            }
        }
    }
    @ViewBuilder private func rowContent(_ row: ExploreRow) -> some View {
        switch row {
        case .catalog(let row): content(row).environment(\.exploreCollectionSize, preferences.cardSize(for: row))
        case .widget(let section):
            HomeWidgetContent(section: section, saved: widgetOptions, refreshID: refreshID, activationID: activationID)
                .environment(\.homeWidgetLayout, preferences.widgetOptions.layout(for: section))
                .padding(.horizontal, widgetInset)
        }
    }
    private func update(_ change: (inout ExplorePreferences) -> Void) { var value = preferences; change(&value); saved = value.saved }
}

private struct ExploreWidgetActivationKey: EnvironmentKey { static let defaultValue = 0 }
private struct ExploreCollectionSizeKey: EnvironmentKey { static let defaultValue = ExploreCollectionSize.small }
extension EnvironmentValues {
    var exploreCollectionSize: ExploreCollectionSize {
        get { self[ExploreCollectionSizeKey.self] }
        set { self[ExploreCollectionSizeKey.self] = newValue }
    }
}
extension EnvironmentValues {
    var exploreWidgetActivation: Int { get { self[ExploreWidgetActivationKey.self] } set { self[ExploreWidgetActivationKey.self] = newValue } }
}

/// Shared stores are loaded once per Explore page, even when several widgets use them.
struct ExploreWidgetSupport: ViewModifier {
    let surface: ExploreSurface
    let refreshID: Int
    @AppStorage private var saved: String
    @AppStorage(HomeArtworkSize.storageKey) private var artworkSize = HomeArtworkSize.large.rawValue
    @EnvironmentObject private var anime: AppStore
    @EnvironmentObject private var books: MangaBakaStore
    @EnvironmentObject private var reading: MangaReadingStore
    @EnvironmentObject private var links: MangaSourceLinkStore
    @EnvironmentObject private var extensions: MangaExtensionStore
    @EnvironmentObject private var week: WeeklyScheduleStore
    @EnvironmentObject private var dubs: ExploreDubStore
    @Environment(\.scenePhase) private var scene
    @State private var width: CGFloat = 380
    @State private var activation = 0
    @State private var appeared = false
    init(surface: ExploreSurface, refreshID: Int) { self.surface = surface; self.refreshID = refreshID; _saved = AppStorage(wrappedValue: "", surface.storageKey) }
    private var hasWidgets: Bool { ExplorePreferences(surface: surface, saved: saved).hasWidgets }
    func body(content: Content) -> some View {
        content.environment(\.homeVisuals, HomeVisualMetrics(isPad: UIDevice.current.userInterfaceIdiom == .pad,
                    availableWidth: max(0, min(width, 1180) - 40), artworkSize: HomeArtworkSize(rawValue: artworkSize) ?? .large))
            .environment(\.exploreWidgetActivation, activation)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .onAppear { if appeared { activation += 1 }; appeared = true }
            .onChange(of: scene) { previous, current in if current == .active && previous != .active { activation += 1 } }
            .task(id: "\(hasWidgets)-\(books.connected)-\(books.connectionID)-\(books.revision)") {
                guard hasWidgets else { return }
                await reading.load(); await links.load()
                if !reading.state.records.isEmpty { await extensions.load() }
                if books.connected { await books.loadLibrary(state: nil) }
                await anime.refreshLibraryIfNeeded()
            }
            .task(id: refreshID) {
                guard hasWidgets, refreshID > 0 else { return }
                async let shows: Void = refreshAnime()
                async let titles: Void = refreshBooks()
                async let releases: Void = refreshWeek()
                _ = await (shows, titles, releases)
            }
    }
    private func refreshAnime() async { if anime.isSignedIn { await anime.reloadLibrary() } }
    private func refreshBooks() async { if books.connected { await books.loadLibrary(state: nil, refresh: true) } }
    private func refreshWeek() async {
        let rows = ExplorePreferences(surface: surface, saved: saved).visible
        guard anime.isSignedIn, rows.contains(.widget(.weekly)) || rows.contains(.widget(.today)) else { return }
        async let original: Void = week.load(in: ScheduleWeek(containing: ScheduleClock.now, firstWeekday: 1).window, using: anime.aniList, refresh: true)
        async let dubbed: Void = dubs.load(using: anime.dubs, refresh: true)
        _ = await (original, dubbed)
    }
}
