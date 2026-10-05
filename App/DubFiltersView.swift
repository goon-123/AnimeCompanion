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
        NavigationStack {
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
                    }.accessibilityIdentifier("dub-filter-rating")
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
                Section {
                    Button("Reset dub filters") { filters.selection = DiscoveryPreferences() }.accessibilityIdentifier("dub-filter-reset")
                }
            }.navigationTitle("Dub filters").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

struct DubFilterButton: View {
    @EnvironmentObject private var filters: DiscoveryFilterStore
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(filters.selection.isActive ? filters.selection.summary : "Dub filters", systemImage: "line.3.horizontal.decrease")
                .font(.subheadline.weight(.semibold)).lineLimit(2).padding(.horizontal, 15).padding(.vertical, 11)
                .silverGlass(in: Capsule())
        }.buttonStyle(.plain).accessibilityIdentifier("explore-dub-filters")
            .accessibilityValue(filters.selection.summary)
    }
}
