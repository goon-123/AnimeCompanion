import SwiftUI
import AnimeCore

struct MangaBakaContentSettingsView: View {
    @EnvironmentObject private var preferences: AppStore
    var body: some View {
        Form {
            MangaBakaRatingSection(filter: $preferences.mangaBakaContent)
            Section {
                Toggle("Show unrated titles", isOn: $preferences.mangaBakaContent.includeUnrated)
                    .accessibilityIdentifier("mangabaka-rating-unrated")
            } footer: {
                Text("Unrated titles have no recognized content rating and may contain adult content.")
            }
            Section {
                Text("Applies to MangaBaka in Explore, search, recommendations, libraries, related series and cover galleries. Hidden entries stay in your online library. AniList and external reading websites have separate settings.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }.navigationTitle("MangaBaka content").navigationBarTitleDisplayMode(.inline)
    }
}

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
        } header: { Text("Content rating") } footer: {
            Text("Enable each rating independently. For example, allow Suggestive while keeping Erotica and Pornographic hidden.")
        }
    }
}

struct MangaBakaContentButton: View {
    @EnvironmentObject private var preferences: AppStore
    @State private var presented = false
    var body: some View {
        Button { presented = true } label: { Label("Content rating", systemImage: "eye") }
            .accessibilityLabel("MangaBaka content rating").accessibilityValue(preferences.mangaBakaContent.summary)
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
