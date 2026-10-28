import SwiftUI
import AnimeCore

struct LibrarySavedViewsMenu: View {
    @Binding var query: String
    @Binding var status: CombinedLibraryStatus
    @Binding var sort: String
    @Binding var ascending: Bool
    @Binding var layout: String
    @AppStorage(LibraryViewPresets.storageKey) private var saved = ""
    @State private var naming = false
    @State private var managing = false
    @State private var name = ""
    private var presets: LibraryViewPresets { LibraryViewPresets(saved: saved) }
    var body: some View {
        Menu {
            if !presets.items.isEmpty {
                Section("Saved views") {
                    ForEach(presets.items) { preset in Button(preset.name) { apply(preset) } }
                }
            }
            Button("Save current view", systemImage: "bookmark.badge.plus") { name = ""; naming = true }
                .disabled(presets.items.count >= LibraryViewPresets.limit)
            if !presets.items.isEmpty { Button("Manage saved views", systemImage: "slider.horizontal.3") { managing = true } }
        } label: { Image(systemName: "bookmark").frame(width: 44, height: 44) }
            .accessibilityLabel("Saved library views").accessibilityIdentifier("library-saved-views")
            .alert("Save library view", isPresented: $naming) {
                TextField("View name", text: $name)
                Button("Save") {
                    var value = presets
                    if value.add(.init(name: name, query: query, status: status.rawValue, sort: sort, ascending: ascending, layout: layout)) { saved = value.saved }
                }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Cancel", role: .cancel) {}
            } message: { Text("Remembers your search, status, sorting and layout. It doesn’t change any library entries.") }
            .sheet(isPresented: $managing) {
                AppNavigationStack {
                    List {
                        ForEach(presets.items) { preset in
                            Button { apply(preset); managing = false } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(preset.name).foregroundStyle(.primary)
                                    Text((CombinedLibraryStatus(rawValue: preset.status)?.label ?? "All") + " · " + preset.sort)
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }.onDelete { offsets in
                            var value = presets
                            for index in offsets { value.remove(presets.items[index].id) }
                            saved = value.saved
                        }
                    }.navigationTitle("Saved views").toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("Done") { managing = false } }
                        ToolbarItem(placement: .topBarLeading) { EditButton() }
                    }
                }
            }
    }
    private func apply(_ value: LibraryViewPreset) {
        query = value.query; status = CombinedLibraryStatus(rawValue: value.status) ?? .active
        sort = value.sort; ascending = value.ascending; layout = value.layout
    }
}
