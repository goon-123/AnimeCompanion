# Build verification

Verified implementation: `aaa52a3f185acd170f9fa8e6447f0c95788034fc`.

[Successful macOS/Xcode workflow](https://github.com/goon-123/AnimeCompanion/actions/runs/37177831116), October 4, 2026.

## Completed

- Compiled and type-checked the complete SwiftUI app with Xcode for iPhone, in Release configuration.
- Packaged a real unsigned ARM64 IPA with minimum iOS version 17.0. The downloadable artifact is **AnimeCompanion-unsigned-IPA**.
- Passed **13 offline core unit tests**. The optional captured-source test was skipped because external captures are not bundled. The three live tests are gated during this offline step and run separately below.
- Passed **3 live public-client checks**: AniList seasonal/trending browsing, pagination, search, expanded details, ID lookup and weekly airings; AniSchedule and MyDubList English dub data; Anime News Network RSS. The expanded detail check validates release dates, popularity, staff, recommendations and external links.
- Passed **2 iPhone simulator UI tests**. The first covers Explore, Schedule, My Library, News and account settings, including Keychain access on a fresh installation. The second covers library search and status controls, opening an entry, expanding/closing its cover and reaching its English dub schedule.
- Reviewed the simulator screenshots for the reference-style library, detailed entry page, full-screen cover and title-specific dub section. Library preview progress is a Debug-only test fixture with real public metadata; it is excluded from the Release IPA and does not write to an AniList account.
- Moved Continue watching and Coming up for you to expandable sections in My Library. Explore contains discovery sections.
- Preserved the AniList implicit sign-in update: authorization sends the client ID and response type, and AniList uses the registered redirect URI. Callback URI, token type, expiry and duplicate parameters are validated.

Simulator builds use local ad-hoc signing to exercise Keychain access. The device IPA is unsigned and still needs signing before installation.

## Remaining device verification

- Sign and install the updated IPA through the chosen sideloading method, or configure a development-signed device build in Xcode.
- Verify the full personal-account flow on a signed device using the existing AniList client setup: sign-in, cancellation, token persistence, reconnecting and library mutations. The public-client checks do not authenticate or change an AniList account.

## Repository

The current source is available at [goon-123/AnimeCompanion](https://github.com/goon-123/AnimeCompanion). A source push to main starts the included **iOS unsigned IPA** workflow. Public-provider checks are diagnostic so a temporary service outage does not prevent packaging the app; inspect their step result separately. Simulator screenshots and the XCTest result bundle are uploaded as **AnimeCompanion-simulator-check**.
