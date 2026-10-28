import SwiftUI
import AnimeCore

struct StreamPickerCard<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .frame(maxWidth: .infinity, alignment: .leading).padding(16)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
    }
}

/// One filter area for direct streams and torrent releases. Audio selection is
/// shared, so switching source types never silently changes the language.
struct StreamPickerFilters: View {
    var kind: Binding<String>? = nil
    @Binding var audio: String
    @Binding var query: String
    var englishSummary: String? = nil
    var hasEnglish = false
    var showsSearch = true
    var audioID = "playback-audio-filter"
    @FocusState private var editing: Bool
    var body: some View {
        StreamPickerCard {
            if let kind {
                Picker("Source type", selection: kind) {
                    Text("All").tag("all")
                    Text("Streaming").tag("streaming")
                    Text("Torrents").tag("torrents")
                }.pickerStyle(.segmented).accessibilityIdentifier("playback-source-kind")
            }
            if showsSearch {
                HStack(spacing: 9) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
                    TextField("Filter releases", text: $query).autocorrectionDisabled().textInputAutocapitalization(.never)
                        .focused($editing).submitLabel(.done).onSubmit { editing = false }
                        .accessibilityIdentifier("playback-source-search")
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                            .accessibilityLabel("Clear release filter")
                    }
                }.padding(10).background(Theme.secondarySurface, in: RoundedRectangle(cornerRadius: 10))
            }
            Picker("Audio language", selection: $audio) {
                ForEach(StreamAudioFilter.allCases, id: \.self) { Text($0.label).tag($0.rawValue) }
            }.pickerStyle(.segmented).accessibilityIdentifier(audioID)
            if let englishSummary {
                Text(englishSummary).font(.caption.weight(.medium)).foregroundStyle(hasEnglish ? Color.green : .secondary)
                    .accessibilityIdentifier("playback-english-availability")
            }
        }
    }
}

struct StreamPickerHeading: View {
    let title: String
    let count: Int
    var loading = false
    var countID = "stream-picker-count"
    var body: some View {
        HStack(spacing: 8) {
            Text(title).font(.headline)
            Text("\(count)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .padding(.horizontal, 7).padding(.vertical, 3).background(Theme.secondarySurface, in: Capsule())
                .accessibilityLabel("\(count) \(title)").accessibilityIdentifier(countID)
            Spacer()
            if loading { ProgressView().controlSize(.small) }
        }.padding(.horizontal, 3).padding(.top, 4)
    }
}

struct StreamPickerEmptyState: View {
    let title: String
    let message: String
    let symbol: String
    var body: some View {
        StreamPickerCard {
            Label(title, systemImage: symbol).font(.subheadline.weight(.semibold))
            Text(message).font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct StreamPickerHelpView: View {
    var body: some View {
        Form {
            Section("Choose a release") {
                Text("Streaming sources open directly in VidHub. Torrent releases expand here to show their TorBox status and video files.")
                Text("English audio appears first. EN/JA badges come from provider descriptions and filenames, not verified audio tracks. English subtitles alone do not mean an English dub.")
            }
            Section("Playback") {
                Text("Open source information for the complete original description. Touch and hold a direct stream for available subtitles or to play from the beginning.")
                Text("Choose the correct episode’s file in a batch. Adding or downloading a release requires your action and may use TorBox account limits. Status checks never add it again.")
            }
            Section("Tracking & privacy") {
                Text("AniList watched progress changes only when you explicitly update it. Supported VidHub versions return resume position for native anime playback; catalog and independent playback remain untracked.")
                Text("Playing a TorBox file shares its private playback address with VidHub. Keep that address private.")
            }
        }.font(.subheadline).navigationTitle("Playback help").navigationBarTitleDisplayMode(.inline)
    }
}
