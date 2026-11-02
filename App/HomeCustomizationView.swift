import SwiftUI
import UIKit
import AnimeCore

/// Shares the same live preference as Home and the inline editing controls.
struct HomeCustomizationView: View {
    @AppStorage(HomePreferences.storageKey) private var saved = ""
    @AppStorage(HomeArtworkSize.storageKey) private var artworkSize = HomeArtworkSize.large.rawValue
    @State private var confirmReset = false
    private var preferences: HomePreferences { HomePreferences(saved: saved) }

    var body: some View {
        List {
            if UIDevice.current.userInterfaceIdiom == .pad {
                Section {
                    Picker("Artwork size", selection: $artworkSize) {
                        ForEach(HomeArtworkSize.allCases) { size in Text(size.title).tag(size.rawValue) }
                    }.accessibilityIdentifier("home-ipad-artwork-size")
                } header: { Text("iPad appearance") }
                footer: { Text("Large is the default. Changes apply immediately to Home posters, thumbnails, banners and icons. Narrow Split View windows adapt to fit.") }
            }
            Section {
                ForEach(preferences.order) { section in
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle(isOn: Binding(get: { !preferences.hidden.contains(section) }, set: { shown in
                            update { $0.setVisible(section, shown) }
                        })) {
                            Label(section.title, systemImage: section.symbol).font(.subheadline.weight(.semibold))
                        }.accessibilityIdentifier("home-visible-" + section.rawValue)
                        Text(section.detail).font(.caption).foregroundStyle(.secondary)
                        if section == .featureLinks {
                            NavigationLink("Customize the three shortcuts") { HomeShortcutCustomizationView() }
                                .font(.caption).accessibilityIdentifier("home-manage-shortcuts")
                        }
                        if section.supportsItemLimit && !preferences.hidden.contains(section) {
                            Picker("Preview items", selection: Binding(get: { preferences.size(for: section) }, set: { size in
                                update { $0.setSize(size, for: section) }
                            })) {
                                ForEach(HomeWidgetSize.allCases) { size in Text("\(size.title) · \(size.itemLimit)").tag(size) }
                            }.font(.caption).accessibilityIdentifier("home-size-" + section.rawValue)
                        }
                    }.padding(.vertical, 4)
                }.onMove { offsets, destination in update { $0.order.move(fromOffsets: offsets, toOffset: destination) } }
            } header: { Text("Your widgets") }
            footer: { Text("Changes save immediately. Drag the handles to reorder. Every widget can be hidden, including search and shortcuts. Empty libraries appear when you connect an account or add titles.") }
            Section {
                Button("Show all widgets") { update { $0.setAllVisible(true) } }
                Button("Hide all widgets") { update { $0.setAllVisible(false) } }.accessibilityIdentifier("home-hide-all")
                Button("Restore Home layout") { confirmReset = true }
            }
        }.environment(\.editMode, .constant(.active))
            .navigationTitle("Customize Home").navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("Restore the default Home layout?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Restore layout") { saved = HomePreferences().saved }
            } message: { Text("This resets widget order, visibility, preview sizes and quick-access shortcuts.") }
    }
    private func update(_ change: (inout HomePreferences) -> Void) { var value = preferences; change(&value); saved = value.saved }
}

struct HomeWidgetPicker: View {
    @Environment(\.homeVisuals) private var visuals
    @AppStorage(HomePreferences.storageKey) private var saved = ""
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    private var preferences: HomePreferences { HomePreferences(saved: saved) }
    private var matches: [HomeSection] {
        preferences.order.filter { query.isEmpty || ($0.title + " " + $0.detail).localizedCaseInsensitiveContains(query) }
    }
    var body: some View {
        List {
            Section {
                Text("Add a widget, then drag its handle on Home to place it. Everything saves as you go.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(matches) { section in
                HStack(spacing: 14) {
                    Image(systemName: section.symbol).font(visuals.circleIconFont).foregroundStyle(Theme.accent).frame(width: visuals.value(30, 44))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(section.title).font(.subheadline.weight(.semibold))
                        Text(section.detail).font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    if preferences.hidden.contains(section) {
                        Button {
                            var value = preferences; value.setVisible(section, true); saved = value.saved
                        } label: { Image(systemName: "plus.circle.fill").font(visuals.circleIconFont).frame(minWidth: 44, minHeight: 44) }
                            .buttonStyle(.borderless).accessibilityLabel("Add \(section.title)")
                            .accessibilityIdentifier("home-add-" + section.rawValue)
                    } else {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
                            .frame(width: 44).accessibilityLabel("Already on Home")
                    }
                }.padding(.vertical, 6)
            }
            if matches.isEmpty { Text("No widgets match your search.").foregroundStyle(.secondary) }
        }.searchable(text: $query, prompt: "Find a widget")
            .navigationTitle("Add widgets").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
}

struct HomeShortcutCustomizationView: View {
    @AppStorage(HomePreferences.storageKey) private var saved = ""
    private var preferences: HomePreferences { HomePreferences(saved: saved) }
    var body: some View {
        Form {
            Section {
                ForEach(0..<3, id: \.self) { index in
                    Picker("Slot \(index + 1)", selection: Binding<HomeShortcut?>(get: { preferences.shortcuts[index] }, set: { shortcut in
                        var value = preferences; value.setShortcut(shortcut, at: index); saved = value.saved
                    })) {
                        Text("Hidden").tag(Optional<HomeShortcut>.none)
                        ForEach(HomeShortcut.allCases) { item in Label(item.title, systemImage: item.symbol).tag(Optional(item)) }
                    }.accessibilityIdentifier("home-shortcut-slot-\(index)")
                }
            } header: { Text("Quick access") }
            footer: { Text("Replace any section instantly. Choosing a shortcut already in another slot swaps them. Hidden slots stay hidden after relaunch.") }
            Section {
                Button("Restore Calendar, Airing Now & News") {
                    var value = preferences
                    for (index, shortcut) in [HomeShortcut.calendar, .airing, .news].enumerated() { value.setShortcut(shortcut, at: index) }
                    saved = value.saved
                }
            }
        }.navigationTitle("Customize shortcuts").navigationBarTitleDisplayMode(.inline)
    }
}
