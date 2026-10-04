# Build verification

Verified implementation: `4bdd36f313740b0939748953b6df94d3d0246f7f`.

[Successful macOS/Xcode workflow](https://github.com/goon-123/AnimeCompanion/actions/runs/37217762663), October 4, 2026.

## Completed

- Compiled and type-checked the complete SwiftUI app for iPhone in Release configuration.
- Packaged and checked an unsigned ARM64 IPA for iOS 17 or newer. Its SHA-256 is `0fce2a6617387ffa6e66bc1c3879e7c0ef525ebc4eade26c84339ad8d672bb32`. The Debug-only sample-library launch argument is excluded from the device binary.
- Passed **21 offline core tests**. The optional captured-source test was skipped because captures are not bundled. Three live checks are gated during the offline step and run separately below.
- Passed **3 live public-client checks** covering AniList browsing, filters, details and airings; AniSchedule/MyDubList dub information and partial listings; and all three news publishers, including thumbnail retrieval.
- Passed **6 iPhone simulator UI tests** covering Explore shelf/list/grid dub, library and Completed indicators; complete visible next-airing dates; category navigation and format filtering; all four tabs and settings; persistent library grid density and AniList-rating sorting; switching from Grid back to List after reopening; library search, details and cover expansion; schedule week navigation, date-picker access and saved Dub selection.
- Reviewed the final simulator screenshots, including Watching and Completed badges alongside dub counts, next-episode dates in Explore, the restored library list, three-column library grid, news images, entry details, expanded artwork and schedule controls.
- Removed the mature-story settings, categories and associated native manga browsing routes.
- Removed Continue watching. Coming up for you remains an expandable section in My Library. Explore shows Trending first, Popular this season and Upcoming, with full filtered category pages.
- Dub counts distinguish already broadcast original episodes from planned season totals. Missing counts remain unknown; unreported dubs and unverified or delayed dates are labeled.
- News combines Anime News Network, Crunchyroll and Anime Corner with images where available. Weekly/monthly Popular uses reading history on this device and is labeled accordingly.
- Preserved the existing AniList implicit sign-in flow, callback validation and confirmed-server-write behavior for library changes.

Simulator preview progress is a Debug-only fixture using public metadata. It does not authenticate or write to an AniList account. Simulator builds use local ad-hoc signing to exercise Keychain access.

## Remaining device verification

- Sign and install the IPA through the existing sideloading method, or configure a development-signed device build in Xcode.
- Verify personal-account sign-in, token persistence and library mutations on the signed device using the existing AniList client setup. The automated public-client checks do not authenticate or change an account.

## Repository and artifacts

The source is available at [goon-123/AnimeCompanion](https://github.com/goon-123/AnimeCompanion). Source pushes to main start the iOS unsigned IPA workflow. Public-provider diagnostics are checked separately because that step allows temporary provider outages.

The verified run provides **AnimeCompanion-unsigned-IPA**, **AnimeCompanion-simulator-screenshots** and **AnimeCompanion-simulator-check** artifacts. Screenshot export also runs after a test failure; the smaller screenshot artifact contains PNGs, text diagnostics and the attachment manifest.
