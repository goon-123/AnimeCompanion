import SwiftUI
import UIKit
import AnimeCore

enum DisplayScope: String {
    case explore, library
    var title: String { self == .explore ? "Explore" : "My Library" }
}

/// Each tab has independent preferences; narrow windows only constrain rendering.
struct PosterPreferences: DynamicProperty {
    @AppStorage var listWidth: Double
    @AppStorage var gridWidth: Double
    @AppStorage var shelfWidth: Double
    @AppStorage var columns: Int
    @AppStorage var featuredHeight: Double
    @AppStorage("explore.poster.fillScreen") var fillFeaturedScreen = true
    @AppStorage("explore.poster.balanced") var balancedFeatured = false
    let scope: DisplayScope

    init(_ scope: DisplayScope) {
        self.scope = scope
        let pad = UIDevice.current.userInterfaceIdiom == .pad
        let listKey = "\(scope.rawValue).poster.list"
        let listDefault = PosterLayout.defaultListWidth(isTablet: pad)
        let migrationKey = listKey + ".fullHeight.v1"
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: migrationKey) {
            let legacyDefault: Double = pad ? 140 : (scope == .library ? 76 : 90)
            // Upgrade the old thumbnail default once; retain other custom sizes.
            if let saved = defaults.object(forKey: listKey) as? NSNumber, saved.doubleValue == legacyDefault {
                defaults.set(listDefault, forKey: listKey)
            }
            defaults.set(true, forKey: migrationKey)
        }
        _listWidth = AppStorage(wrappedValue: listDefault, listKey)
        _gridWidth = AppStorage(wrappedValue: pad ? 360 : 280, "\(scope.rawValue).poster.grid")
        _shelfWidth = AppStorage(wrappedValue: pad ? 230 : 150, "\(scope.rawValue).poster.shelf")
        _featuredHeight = AppStorage(wrappedValue: pad ? 700 : 620, "\(scope.rawValue).poster.featured")
        // Preserve the previously saved library density.
        _columns = AppStorage(wrappedValue: pad ? 4 : 2, scope == .library ? "library.columns" : "discovery.columns")
    }

    var preferredColumns: Int { min(8, max(1, columns)) }
    var gridPosterWidth: CGFloat { CGFloat(min(480, max(120, gridWidth))) }
    func listPosterWidth(in width: CGFloat) -> CGFloat {
        CGFloat(PosterLayout.listWidth(preferred: listWidth, availableWidth: Double(width)))
    }
    func fittingColumns(in width: CGFloat, accessible: Bool = false, split: Bool = false) -> Int {
        PosterLayout.columns(requested: preferredColumns, availableWidth: Double(width), minimumWidth: accessible || split ? 160 : 80)
    }
    func reset() {
        let pad = UIDevice.current.userInterfaceIdiom == .pad
        listWidth = PosterLayout.defaultListWidth(isTablet: pad)
        gridWidth = pad ? 360 : 280; shelfWidth = pad ? 230 : 150
        columns = pad ? 4 : 2
        featuredHeight = pad ? 700 : 620
        if scope == .explore { fillFeaturedScreen = true; balancedFeatured = false }
    }
}

struct DisplayOptionsView: View {
    @Environment(\.dismiss) private var dismiss
    private var preferences: PosterPreferences
    init(scope: DisplayScope) { preferences = PosterPreferences(scope) }

    var body: some View {
        AppNavigationStack {
            Form {
                Section {
                    Text("Customize \(preferences.scope.title). Changes are saved automatically on this device, separately from the other tab.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Section("List view") {
                    sizeControl("List poster width", value: preferences.$listWidth, range: 60...240, key: "list-size")
                    Text("Larger covers leave less room for text. Narrow windows keep enough space to read episode and dub information.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Grid view") {
                    Picker("Entries per row", selection: preferences.$columns) {
                        ForEach(1...8, id: \.self) { Text("\($0) per row").tag($0) }
                    }.accessibilityIdentifier("\(preferences.scope.rawValue)-display-columns")
                    sizeControl("Maximum grid poster width", value: preferences.$gridWidth, range: 120...480, key: "grid-size")
                    Text("Choose fewer entries per row for bigger images. Covers grow up to your maximum width. Narrow windows may temporarily fit fewer entries; your chosen density is remembered.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if preferences.scope == .explore {
                    Section("Featured poster") {
                        Toggle("Size to this window", isOn: preferences.$fillFeaturedScreen)
                            .accessibilityIdentifier("explore-featured-fill-screen")
                        Toggle("Balanced preview", isOn: preferences.$balancedFeatured)
                            .disabled(!preferences.fillFeaturedScreen)
                            .accessibilityIdentifier("explore-featured-balanced")
                        sizeControl("Featured poster height", value: preferences.$featuredHeight, range: 400...950, key: "featured-size")
                            .disabled(preferences.fillFeaturedScreen)
                        Text("Balanced preview uses about 60% of this pane so browsing stays close. Turn it off for immersive artwork, or turn off Size to this window for your saved custom height. Existing poster sizes are kept.").font(.caption).foregroundStyle(.secondary)
                    }
                    Section("Explore shelves") {
                        sizeControl("Shelf poster width", value: preferences.$shelfWidth, range: 120...360, key: "shelf-size")
                        Text("Applies to Trending, Popular this season and Upcoming.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section {
                    Button("Reset \(preferences.scope.title) display sizes") { preferences.reset() }
                        .accessibilityIdentifier("\(preferences.scope.rawValue)-display-reset")
                }
            }.navigationTitle("Display options").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
    private func sizeControl(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, key: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text(title); Spacer(); Text("\(Int(value.wrappedValue)) pt").monospacedDigit().foregroundStyle(.secondary) }
            Slider(value: value, in: range, step: 10).accessibilityLabel(title)
                .accessibilityValue("\(Int(value.wrappedValue)) points")
                .accessibilityIdentifier("\(preferences.scope.rawValue)-\(key)")
        }.padding(.vertical, 5)
    }
}

extension View {
    /// Keep long-form text readable without stretching it across a landscape iPad.
    func readableContent(width: CGFloat = 940) -> some View {
        frame(maxWidth: width).frame(maxWidth: .infinity)
    }
}
