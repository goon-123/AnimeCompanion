import SwiftUI
import AnimeCore

struct LibraryPreferencesView: View {
    var body: some View {
        Form {
            ForEach(LibraryScope.allCases) { scope in
                Section(scope.label) { LibraryDefaultPicker(scope: scope) }
            }
            Section {
                Text("Each library opens on its default status. You can browse another status at any time. Sort order and direction are saved separately for Anime, MangaBaka and All stories.")
            }.font(.subheadline).foregroundStyle(.secondary)
        }.navigationTitle("Library defaults").navigationBarTitleDisplayMode(.inline)
    }
}

struct LibraryDefaultPicker: View {
    let scope: LibraryScope
    @AppStorage private var saved: String
    init(scope: LibraryScope) {
        self.scope = scope
        _saved = AppStorage(wrappedValue: scope.initialStatus, scope.defaultStatusKey)
    }
    var body: some View {
        Picker("Open library on", selection: $saved) {
            ForEach(scope.statuses) { Text($0.label).tag($0.id) }
        }.accessibilityIdentifier("library-default-" + scope.rawValue)
    }
}

struct LibraryDefaultMenu: View {
    let scope: LibraryScope
    @AppStorage private var saved: String
    init(scope: LibraryScope) {
        self.scope = scope
        _saved = AppStorage(wrappedValue: scope.initialStatus, scope.defaultStatusKey)
    }
    var body: some View {
        Menu("Open library on") {
            ForEach(scope.statuses) { status in
                MenuChoice(title: status.label, selected: saved == status.id) { saved = status.id }
            }
        }.accessibilityIdentifier("library-default-" + scope.rawValue)
    }
}

struct ReadingLibrarySortControls: View {
    let scope: LibraryScope
    @Binding var sortValue: String
    @Binding var ascending: Bool
    private var sort: ReadingLibrarySort { ReadingLibrarySort(rawValue: sortValue) ?? .updated }
    private var choices: [ReadingLibrarySort] { ReadingLibrarySort.allCases.filter { scope != .combined || $0 != .volumes } }
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack { sortMenu; Spacer(minLength: 8); directionMenu }
            VStack(alignment: .leading, spacing: 8) { sortMenu; directionMenu }
        }
    }
    private var sortMenu: some View {
        Menu {
            ForEach(choices) { order in
                MenuChoice(title: order.rawValue, selected: sort == order) {
                    sortValue = order.rawValue; ascending = order.defaultAscending
                }
            }
            Section("Default view") { LibraryDefaultMenu(scope: scope) }
        } label: { Label(sort.rawValue, systemImage: "arrow.up.arrow.down") }
            .accessibilityIdentifier(scope.rawValue + "-library-sort")
    }
    private var directionMenu: some View {
        Menu {
            MenuChoice(title: sort.directionLabel(ascending: true), selected: ascending) { ascending = true }
            MenuChoice(title: sort.directionLabel(ascending: false), selected: !ascending) { ascending = false }
        } label: { Label(sort.directionLabel(ascending: ascending), systemImage: ascending ? "arrow.up" : "arrow.down") }
            .accessibilityIdentifier(scope.rawValue + "-library-direction")
    }
}
