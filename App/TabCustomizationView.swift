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
                            .disabled(tab == .home)
                            .accessibilityLabel(tab.title)
                            .accessibilityIdentifier("tab-visible-" + tab.rawValue)
                    }.accessibilityElement(children: .contain)
                }.onMove { from, to in preferences.order.move(fromOffsets: from, toOffset: to) }
            } header: { Text("Main destinations") }
            footer: { Text("Home brings together your calendar, Airing Now and News, so it stays available. Drag to reorder the other destinations or hide them. Changes apply when Settings closes.") }
            Section {
                Button("Show all tabs") { preferences = .init(order: preferences.order, hidden: []) }
                Button("Reset tab order") { preferences.order = AppTab.navigationTabs }
            }
        }.environment(\.editMode, .constant(.active))
            .navigationTitle("Navigation").navigationBarTitleDisplayMode(.inline)
            .onChange(of: preferences) { _, value in UserDefaults.standard.set(value.saved, forKey: AppTabPreferences.storageKey) }
    }
}
