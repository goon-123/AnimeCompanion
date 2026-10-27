import SwiftUI
import AnimeCore

@MainActor
final class DiscoveryFilterStore: ObservableObject {
    @Published var selection: DiscoveryPreferences {
        didSet { if let data = try? JSONEncoder().encode(selection) { defaults.set(data, forKey: Self.key) } }
    }
    private let defaults: UserDefaults
    private static let key = "discovery.dub.preferences.v1"
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        selection = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(DiscoveryPreferences.self, from: $0) } ?? DiscoveryPreferences()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-phase2-preview") { selection = DiscoveryPreferences() }
        #endif
    }
    func includes(_ anime: Anime, dubs: ExploreDubStore, library: AppStore) -> Bool {
        selection.matches(anime: anime, progress: dubs.progress(for: anime), next: dubs.nextDub(for: anime.id), entry: library.entry(for: anime.id))
    }
}

struct DubFiltersView: View {
    @EnvironmentObject private var filters: DiscoveryFilterStore
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var dubs: ExploreDubStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        AppNavigationStack {
            Form {
                Section {
                    ForEach(DiscoveryDubFilter.allCases, id: \.self) { option in
                        Button { filters.selection.dub = option } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(option.label).foregroundStyle(.primary)
                                    Text(option.explanation).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 12)
                                if filters.selection.dub == option { Image(systemName: "checkmark.circle.fill").foregroundStyle(.mint) }
                            }.padding(.vertical, 3)
                        }.accessibilityIdentifier("dub-filter-\(option.rawValue)")
                            .accessibilityValue(filters.selection.dub == option ? "Selected" : "")
                    }
                } header: { Text("English dub availability") } footer: {
                    Text("Your choices are saved and apply to Explore, search and every category. Missing provider data is kept unknown.")
                }
                Section("Refine results") {
                    Picker("Minimum AniList rating", selection: $filters.selection.minimumScore) {
                        Text("Any rating").tag(0)
                        ForEach([50, 60, 70, 80, 90], id: \.self) { Text("\(Double($0) / 10, specifier: "%.1f") or higher").tag($0) }
                    }.pickerStyle(.menu).accessibilityIdentifier("dub-filter-rating")
                    Toggle("Hide completed anime", isOn: $filters.selection.hideCompleted).accessibilityIdentifier("dub-filter-hide-completed")
                    if !store.isSignedIn {
                        Text("Connect AniList in Settings to hide titles you have completed.").font(.caption).foregroundStyle(.secondary)
                    } else if store.libraryError != nil {
                        Text("Completed-title filtering uses the last synced library. Refresh My Library to update it.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if dubs.unavailable {
                    Section {
                        Text("Some dub information is temporarily unavailable. You can still browse all anime.").font(.subheadline)
                        Button("Retry dub information") { Task { await dubs.load(using: store.dubs, refresh: true) } }.disabled(dubs.loading)
                    }
                }
            }.navigationTitle("Dub filters").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Reset") { filters.selection = DiscoveryPreferences() }
                            .accessibilityLabel("Reset dub filters").accessibilityIdentifier("dub-filter-reset")
                    }
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
        }
    }
}

struct DubFilterButton: View {
    @EnvironmentObject private var filters: DiscoveryFilterStore
    var compact = false
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: filters.selection.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease")
                if !compact { Text(filters.selection.isActive ? filters.selection.summary : "Dub filters").lineLimit(2) }
            }.font(.subheadline.weight(.semibold)).padding(.horizontal, compact ? 0 : 15)
                .frame(minWidth: 44, minHeight: 44)
                .silverGlass(in: Capsule())
        }.buttonStyle(.plain).accessibilityIdentifier(compact ? "explore-dub-filter-toolbar" : "explore-dub-filters")
            .accessibilityLabel("Dub filters")
            .accessibilityValue(filters.selection.summary)
    }
}
