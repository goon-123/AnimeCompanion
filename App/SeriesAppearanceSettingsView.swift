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
                Toggle("Show title while logo loads", isOn: $logo).accessibilityIdentifier("series-logo-fallback")
                Toggle("AniList banner fallback", isOn: $banner).accessibilityIdentifier("series-banner-fallback")
                Toggle("AniList poster fallback", isOn: $poster).accessibilityIdentifier("series-poster-fallback")
            } header: { Text("Optional cinematic artwork fallback") } footer: {
                Text("Source fallbacks are off by default and can be enabled independently. When cinematic artwork is unavailable, the series cover supplies a blurred backdrop and a missing logo uses the title as text. Existing banners and logos are preserved. Classic AniList uses its original artwork.")
            }
        }.navigationTitle("Series appearance").navigationBarTitleDisplayMode(.inline)
    }
}
