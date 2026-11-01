import SwiftUI
import AnimeCore

/// Shares the same live preference as Home and the inline editing controls.
struct HomeCustomizationView: View {
    @AppStorage(HomePreferences.storageKey) private var saved = ""
    @State private var confirmReset = false
    private var preferences: HomePreferences { HomePreferences(saved: saved) }

    var body: some View {
        List {
            Section {
                ForEach(preferences.order) { section in
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle(isOn: Binding(get: { !preferences.hidden.contains(section) }, set: { shown in
                            update { $0.setVisible(section, shown) }
                        })) {
                            Label(section.title, systemImage: section.symbol).font(.subheadline.weight(.semibold))
                        }.accessibilityIdentifier("home-visible-" + section.rawValue)
                        Text(section.detail).font(.caption).foregroundStyle(.secondary)
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
            } message: { Text("This resets widget order, visibility and preview sizes.") }
    }
    private func update(_ change: (inout HomePreferences) -> Void) { var value = preferences; change(&value); saved = value.saved }
}

struct HomeWidgetPicker: View {
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
                    Image(systemName: section.symbol).font(.title2).foregroundStyle(Theme.accent).frame(width: 30)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(section.title).font(.subheadline.weight(.semibold))
                        Text(section.detail).font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    if preferences.hidden.contains(section) {
                        Button {
                            var value = preferences; value.setVisible(section, true); saved = value.saved
                        } label: { Image(systemName: "plus.circle.fill").font(.title2).frame(minWidth: 44, minHeight: 44) }
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
