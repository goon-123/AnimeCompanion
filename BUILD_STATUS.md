# Build verification

Verified implementation: `0aa37edca5663c021316ac206d5e83d36c56c1ce`.

[Successful macOS/Xcode workflow](https://github.com/goon-123/AnimeCompanion/actions/runs/37257803775), October 5, 2026 (UTC).

## Completed

- Compiled and type-checked the complete SwiftUI app as a universal iPhone/iPad Release build. The IPA declares both device families and all four iPad orientations; iPhone portrait behavior is preserved.
- Packaged and checked an unsigned ARM64 IPA, build 3, for iOS/iPadOS 17 or newer. Its SHA-256 is `7479489d867a7abef802c94ae6ede1ba8aaecc74c1c12ea3ecff1ffd1d3d55c6`. The existing bundle identifier is unchanged. Debug-only library and layout preview launch arguments are excluded from the device binary.
- Passed **25 offline core tests**, including poster sizing, phone/iPad grid fitting, temporary narrow-window and accessibility constraints, and extreme-value bounds. The optional captured-source test was skipped because captures are not bundled. Three live checks are gated during the offline step and run separately below.
- Passed **8 iPhone simulator UI tests** covering Explore shelf/list/grid dub, library and Completed indicators; next-airing dates; category navigation and format filtering; all four tabs and settings; persistent display options, library grid density and AniList-rating sorting; switching from Grid back to List after reopening; library search, details and cover expansion; schedule week navigation, date-picker access and saved Dub selection; and repeated category returns through Back and edge-swipe navigation.
- Passed **4 native 11-inch iPad Pro (M4) simulator UI tests** covering all tabs, details and full-screen artwork in portrait and landscape; independently adjustable Explore shelf, list and grid artwork; two-, three- and eight-column layouts; larger library list and Coming up for you artwork; full-width section-header touch targets; saved preferences across relaunch; artwork refitting after rotation; and repeated category returns through Back and edge-swipe navigation.
- The shared navigation test passed on both devices in list and grid layouts, with three detail-return cycles per layout. It verified that the selected scrolled entry remained hittable, the loaded result count stayed unchanged, genre and rating filters and grid density were retained, and an additional page actually loaded before a further detail-return check.
- Reviewed **46 final simulator screenshots**, 23 each for iPhone and iPad, including populated category returns, enlarged artwork, aligned grid cards, wrapping genres, metadata readability, tablet portrait/landscape layouts, library badges, dub counts, next-episode dates, details and schedule controls.
- Fixed category pages becoming blank after returning from details. Loaded results and pagination are retained when the same filters resume; explicit refresh replaces results only after a successful response, and changed filters start a new result set. Cancelled or stale requests cannot overwrite the current selection.
- Added every reported genre to Explore and My Library grid cards, and to Explore shelf cards. Genre text wraps without truncation so it remains readable at different grid densities.
- Kept category and library layout controls mounted above their lazy results. Replaced nested layout, column and sorting pickers with checked menu buttons that dismiss after selection. Both device suites verify menu dismissal and the selected row count; iPad checks also verify saved density after relaunch.
- Added independent, automatically saved Display options for Explore and My Library: list poster width, grid entries per row (1–8), maximum grid poster width, Explore shelf poster width and library Coming up for you poster width. Defaults are larger on iPad. Narrow windows temporarily reduce fitting columns without overwriting the saved choice. Each tab can reset its sizes without resetting account or progress data.
- Centered readable content on wide displays, enlarged tablet detail and news artwork, retained poster aspect ratios and constrained grid touch bounds. Narrow-window fitting is unit-tested; actual physical-device and iPad multitasking-window verification remain separate from the simulator rotation checks.
- Removed the mature-story settings, categories and associated native manga browsing routes.
- Removed Continue watching. Coming up for you remains an expandable section in My Library. Explore shows Trending first, Popular this season and Upcoming, with full filtered category pages.
- Dub counts distinguish already broadcast original episodes from planned season totals. Missing counts remain unknown; unreported dubs and unverified or delayed dates are labeled.
- News combines Anime News Network, Crunchyroll and Anime Corner with images where available. Weekly/monthly Popular uses reading history on this device and is labeled accordingly.
- Preserved the existing AniList implicit sign-in flow, callback validation and confirmed-server-write behavior for library changes.

## Public-provider diagnostics

The final run passed **all three standalone live checks**: AniList public browsing, the Anime News Network feed, and English dub providers. The iPhone and iPad UI tests also loaded real AniList browsing, search, details and airings. Provider diagnostics allow temporary outages and do not hide layout or build failures; their actual passing results were checked in this run's logs.

Simulator preview progress is a Debug-only fixture using public metadata. A synthetic future release is used only to exercise Coming up for you resizing; it is not a provider-verified release date and is excluded from the Release app. Preview fixtures do not authenticate or write to an AniList account. Simulator builds use local ad-hoc signing to exercise Keychain access.

## Remaining device verification

- Sign and install the IPA through the existing sideloading method, or configure a development-signed device build in Xcode.
- Verify personal-account sign-in, token persistence and library mutations on the signed device using the existing AniList client setup. The automated public-client checks do not authenticate or change an account.

## Repository and artifacts

The source is available at [goon-123/AnimeCompanion](https://github.com/goon-123/AnimeCompanion). Source pushes to main start the universal unsigned IPA workflow and native iPhone plus 11-inch iPad Pro UI tests. The build and the two simulator suites run as three independent jobs on fresh macOS machines, with iPhone and iPad checks in parallel. Native UI checks are required and retain Back and real edge-swipe coverage. Public-provider diagnostics are checked separately because that step allows temporary provider outages.

The verified run provides **AnimeCompanion-unsigned-IPA**, **AnimeCompanion-iPad-screenshots**, **AnimeCompanion-simulator-screenshots**, **AnimeCompanion-simulator-check** and **AnimeCompanion-iPad-simulator-check** artifacts. Screenshot export also runs after a test failure; the screenshot artifacts contain PNGs, text diagnostics and attachment manifests.
