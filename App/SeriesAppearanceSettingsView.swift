import SwiftUI
import AnimeCore

struct SeriesAppearanceSettingsView: View {
    @AppStorage(AnimeSeriesStyle.storageKey) private var style = AnimeSeriesStyle.cinematic.rawValue
    @AppStorage(SeriesArtworkPreferences.logoKey) private var logo = false
    @AppStorage(SeriesArtworkPreferences.bannerKey) private var banner = false
    @AppStorage(SeriesArtworkPreferences.posterKey) private var poster = false
    var body: some View {
        Form {
            Section {
                Picker("Series view", selection: $style) {
                    ForEach(AnimeSeriesStyle.allCases) { Text($0.title).tag($0.rawValue) }
                }.accessibilityIdentifier("series-style-picker")
            } header: { Text("Layout") } footer: {
                Text("Cinematic is the default. Classic AniList restores the previous header and Info-first layout. Switching layouts keeps your section settings and library progress.")
            }
            Section {
                Toggle("AniList title fallback", isOn: $logo).accessibilityIdentifier("series-logo-fallback")
                Toggle("AniList banner fallback", isOn: $banner).accessibilityIdentifier("series-banner-fallback")
                Toggle("AniList poster fallback", isOn: $poster).accessibilityIdentifier("series-poster-fallback")
            } header: { Text("Optional cinematic artwork fallback") } footer: {
                Text("All three are off by default. Enable each independently if you want AniList to fill a missing artwork asset. These switches apply to Cinematic; choosing Classic AniList explicitly uses its original artwork. Series information and tracking still come from AniList.")
            }
        }.navigationTitle("Series appearance").navigationBarTitleDisplayMode(.inline)
    }
}
