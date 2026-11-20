import SwiftUI
import AnimeCore

struct ContentPreferencesView: View {
    @EnvironmentObject private var preferences: AppStore
    var body: some View {
        Form {
            Section {
                Toggle("Show adult anime (18+)", isOn: $preferences.includeAdult)
                    .accessibilityIdentifier("settings-adult-content")
            } header: { Text("Anime & video sources") }
            MangaBakaRatingSection(filter: $preferences.mangaBakaContent)
            Section {
                Toggle("Show unrated titles", isOn: $preferences.mangaBakaContent.includeUnrated)
                    .accessibilityIdentifier("mangabaka-rating-unrated")
            } footer: {
                Text("Unrated titles have no recognized content rating and may contain adult content.")
            }
            Section {
                Text("One choice for manga and novels across Explore, search, libraries and extensions. Mature extension collections appear when Erotica or Pornographic is enabled. Hidden entries stay in your online library.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }.navigationTitle("Content preferences").navigationBarTitleDisplayMode(.inline)
    }
}

// Existing manga shortcuts all open the same shared preference editor.
typealias MangaBakaContentSettingsView = ContentPreferencesView

struct MangaBakaRatingSection: View {
    @Binding var filter: MangaBakaContentFilter
    var body: some View {
        Section {
            ForEach(MangaBakaContentRating.allCases, id: \.self) { rating in
                Toggle(isOn: Binding(get: { filter.ratings.contains(rating) }, set: { enabled in
                    if enabled { filter.ratings.insert(rating) } else { filter.ratings.remove(rating) }
                })) {
                    Label(rating.label, systemImage: rating == .safe ? "checkmark.shield" : rating == .suggestive ? "sparkles" : "eye")
                        .foregroundStyle(rating == .safe ? Color.mint : rating == .suggestive ? .yellow : rating == .erotica ? .orange : .pink)
                }.accessibilityIdentifier("mangabaka-rating-" + rating.rawValue)
            }
        } header: { Text("Manga & novel ratings") } footer: {
            Text("These are your saved preferences everywhere in the app.")
        }
    }
}

struct MangaBakaContentButton: View {
    @EnvironmentObject private var preferences: AppStore
    @State private var presented = false
    var body: some View {
        Button { presented = true } label: { Label("Content preferences", systemImage: "eye") }
            .accessibilityLabel("Content preferences").accessibilityValue(preferences.mangaBakaContent.summary)
            .accessibilityIdentifier("mangabaka-content-settings")
            .sheet(isPresented: $presented) {
                AppNavigationStack {
                    MangaBakaContentSettingsView().toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("Done") { presented = false } }
                    }
                }
            }
    }
}
