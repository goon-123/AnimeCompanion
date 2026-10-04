# Build verification

Verified implementation: `dae598d9727bca30f21bcc40d4351225227a918c`.

[Successful macOS/Xcode workflow](https://github.com/goon-123/AnimeCompanion/actions/runs/37225358120), October 4, 2026.

## Completed

- Compiled and type-checked the complete SwiftUI app as a universal iPhone/iPad Release build. The IPA declares both device families and all four iPad orientations; iPhone portrait behavior is preserved.
- Packaged and checked an unsigned ARM64 IPA, build 2, for iOS/iPadOS 17 or newer. Its SHA-256 is `13cafd2df87d906c19baf53fb388a4f406a448278b5f6b742d1f9d4ed1a22eec`. The existing bundle identifier is unchanged. Debug-only library and layout preview launch arguments are excluded from the device binary.
- Passed **25 offline core tests**, including poster sizing, phone/iPad grid fitting, temporary narrow-window and accessibility constraints, and extreme-value bounds. The optional captured-source test was skipped because captures are not bundled. Three live checks are gated during the offline step and run separately below.
- Passed **7 iPhone simulator UI tests** covering Explore shelf/list/grid dub, library and Completed indicators; next-airing dates; category navigation and format filtering; all four tabs and settings; persistent display options, library grid density and AniList-rating sorting; switching from Grid back to List after reopening; library search, details and cover expansion; schedule week navigation, date-picker access and saved Dub selection.
- Passed **3 native 11-inch iPad Pro (M4) simulator UI tests** covering all tabs, details and full-screen artwork in portrait and landscape; independently adjustable Explore shelf, list and grid artwork; two-, three- and eight-column layouts; larger library list and Coming up for you artwork; full-width section-header touch targets; saved preferences across relaunch; and artwork refitting after rotation.
- Reviewed **38 final simulator screenshots**, 19 each for iPhone and iPad, including enlarged artwork, aligned grid cards, metadata readability, tablet portrait/landscape layouts, library badges, dub counts, next-episode dates, details and schedule controls.
- Added independent, automatically saved Display options for Explore and My Library: list poster width, grid entries per row (1–8), maximum grid poster width, Explore shelf poster width and library Coming up for you poster width. Defaults are larger on iPad. Narrow windows temporarily reduce fitting columns without overwriting the saved choice. Each tab can reset its sizes without resetting account or progress data.
- Centered readable content on wide displays, enlarged tablet detail and news artwork, retained poster aspect ratios and constrained grid touch bounds. Narrow-window fitting is unit-tested; actual physical-device and iPad multitasking-window verification remain separate from the simulator rotation checks.
- Removed the mature-story settings, categories and associated native manga browsing routes.
- Removed Continue watching. Coming up for you remains an expandable section in My Library. Explore shows Trending first, Popular this season and Upcoming, with full filtered category pages.
- Dub counts distinguish already broadcast original episodes from planned season totals. Missing counts remain unknown; unreported dubs and unverified or delayed dates are labeled.
- News combines Anime News Network, Crunchyroll and Anime Corner with images where available. Weekly/monthly Popular uses reading history on this device and is labeled accordingly.
- Preserved the existing AniList implicit sign-in flow, callback validation and confirmed-server-write behavior for library changes.

## Public-provider diagnostics

The final run passed the dub-provider and news-provider live checks. The separate AniList diagnostic returned HTTP 500, so this run did **not** pass all three standalone live checks. Subsequent iPhone and iPad UI tests successfully loaded real AniList browsing, search, details and airings. [The preceding run](https://github.com/goon-123/AnimeCompanion/actions/runs/37223487585) passed all three live checks. Provider diagnostics allow temporary outages and do not hide layout or build failures.

Simulator preview progress is a Debug-only fixture using public metadata. A synthetic future release is used only to exercise Coming up for you resizing; it is not a provider-verified release date and is excluded from the Release app. Preview fixtures do not authenticate or write to an AniList account. Simulator builds use local ad-hoc signing to exercise Keychain access.

## Remaining device verification

- Sign and install the IPA through the existing sideloading method, or configure a development-signed device build in Xcode.
- Verify personal-account sign-in, token persistence and library mutations on the signed device using the existing AniList client setup. The automated public-client checks do not authenticate or change an account.

## Repository and artifacts

The source is available at [goon-123/AnimeCompanion](https://github.com/goon-123/AnimeCompanion). Source pushes to main start the universal unsigned IPA workflow and native iPhone plus 11-inch iPad Pro UI tests. Public-provider diagnostics are checked separately because that step allows temporary provider outages.

The verified run provides **AnimeCompanion-unsigned-IPA**, **AnimeCompanion-iPad-screenshots**, **AnimeCompanion-simulator-screenshots** and **AnimeCompanion-simulator-check** artifacts. Screenshot export also runs after a test failure; the screenshot artifacts contain PNGs, text diagnostics and attachment manifests.
