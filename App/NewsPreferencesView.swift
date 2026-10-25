import SwiftUI
import AnimeCore

struct NewsPreferencesView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var preferences: NewsPreferences
    @Binding var compact: Bool
    @State private var mutedText = ""
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(NewsTopic.allCases.filter { $0 != .all }, id: \.self) { topic in
                        Toggle(isOn: Binding(get: { preferences.followedTopics.contains(topic) }, set: { enabled in
                            if enabled { preferences.followedTopics.insert(topic) } else { preferences.followedTopics.remove(topic) }
                        })) { Label(topic.label, systemImage: topic.symbol) }.accessibilityIdentifier("news-follow-\(topic.rawValue)")
                    }
                } header: { Text("Your interests") } footer: {
                    Text("For You combines these topics with title matches from your loaded libraries. English dubs start followed. Topics are inferred from headlines and publisher categories.")
                }
                Section {
                    ForEach(NewsSource.allCases, id: \.self) { source in
                        Toggle(source.label, isOn: Binding(get: { preferences.enabledSources.contains(source) }, set: { enabled in
                            if enabled { preferences.enabledSources.insert(source) } else { preferences.enabledSources.remove(source) }
                        })).accessibilityIdentifier("news-enable-\(source.rawValue)")
                    }
                } header: { Text("Publishers") } footer: { Text("Applies to Latest and For You. Your saved stories and history remain available.") }
                Section {
                    TextField("Words or phrases, separated by commas", text: $mutedText, axis: .vertical)
                        .lineLimit(3...5).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("news-muted-keywords")
                } header: { Text("Mute keywords") } footer: { Text("Hide matching words or phrases from Latest and For You. Saved and History stay searchable. This cannot guarantee spoiler-free headlines.") }
                Section("Appearance") { Toggle("Compact story layout", isOn: $compact).accessibilityIdentifier("news-compact-layout") }
                Section {
                    Text("Bookmarks save the headline, excerpt and link on this device. Full articles open on the original website and need an internet connection. Reading history and interests stay on this device.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.navigationTitle("Customize News").navigationBarTitleDisplayMode(.inline)
                .onAppear { mutedText = preferences.mutedKeywords.joined(separator: ", ") }
                .onChange(of: mutedText) { _, value in
                    preferences.mutedKeywords = Array(value.components(separatedBy: CharacterSet(charactersIn: ",\n"))
                        .map { String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(100)) }.filter { !$0.isEmpty }.prefix(30))
                }
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("news-preferences-done") } }
        }.presentationDetents([.large])
    }
}
