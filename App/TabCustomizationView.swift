import SwiftUI
import AnimeCore

struct TabCustomizationView: View {
    @State private var preferences = AppTabPreferences(saved: UserDefaults.standard.string(forKey: AppTabPreferences.storageKey))
    var body: some View {
        List {
            Section {
                ForEach(preferences.order) { tab in
                    HStack {
                        Label(tab.title, systemImage: tab.symbol).accessibilityHidden(true)
                        Spacer()
                        Toggle(tab.title, isOn: Binding(get: { !preferences.hidden.contains(tab) }, set: { preferences.setVisible(tab, $0) }))
                            .labelsHidden().fixedSize()
                            .disabled(preferences.visible.count == 1 && !preferences.hidden.contains(tab))
                            .accessibilityLabel(tab.title)
                            .accessibilityIdentifier("tab-visible-" + tab.rawValue)
                    }.accessibilityElement(children: .contain)
                }.onMove { from, to in preferences.order.move(fromOffsets: from, toOffset: to) }
            } header: { Text("Bottom tabs") }
            footer: { Text("Drag the handles to change the order. Turn off a tab to hide its whole section. Keep at least one visible. Your library, sources and reading progress are kept. Changes apply when you close Settings.") }
            Section {
                Button("Show all tabs") { preferences = .init(order: preferences.order, hidden: []) }
                Button("Reset tab order") { preferences.order = AppTab.allCases }
            }
        }.environment(\.editMode, .constant(.active))
            .navigationTitle("Bottom tabs").navigationBarTitleDisplayMode(.inline)
            .onChange(of: preferences) { _, value in UserDefaults.standard.set(value.saved, forKey: AppTabPreferences.storageKey) }
    }
}
