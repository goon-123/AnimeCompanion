# Build verification

Verified implementation: `9c5352cec319530703dd2e89fe79bf0855d93c7a`.

[Successful macOS/Xcode workflow](https://github.com/goon-123/AnimeCompanion/actions/runs/37175654375), October 4, 2026.

## Completed

- Compiled and type-checked the complete SwiftUI app with Xcode for iPhone, in Release configuration.
- Packaged a real unsigned ARM64 IPA with minimum iOS version 17.0. The downloadable artifact is **AnimeCompanion-unsigned-IPA**.
- Passed **13 offline core unit tests**. The optional captured-source test was skipped because external captures are not bundled. The three live tests are gated during this offline step and run separately below.
- Passed **3 live public-client checks**: AniList seasonal/trending browsing, seasonal pagination, search, details, ID lookup and weekly airings; AniSchedule and MyDubList English dub data; Anime News Network RSS.
- Passed **1 iPhone simulator UI test** covering Explore, Schedule, My Library, News and account settings. It waits for loading indicators to disappear and checks that a fresh installation can read its Keychain without a saved-login warning.
- Reviewed the simulator screenshots. Anime covers, weekly releases and news headlines display real source data. The signed simulator starts with a clean guest library and settings screen.
- Preserved the AniList implicit sign-in update that landed during the build: the authorization request sends the client ID and response type, and AniList uses the redirect URI registered for that client. Callback URI, token type, expiry and duplicate parameters are validated.

Simulator builds use local ad-hoc signing to exercise Keychain access. The device IPA is unsigned and still needs signing before installation.

## Remaining device setup and verification

- Register an AniList application with redirect **animecompanion://oauth/anilist**, then enter its numeric client ID in the app's Settings.
- Sign and install the IPA through the chosen sideloading method, or configure a development-signed device build in Xcode.
- Verify the full personal-account flow on a signed device: sign-in, cancellation, token persistence, reconnecting and library mutations. The public-client checks do not authenticate or change an AniList account.

## Repository

The current source is available at [goon-123/AnimeCompanion](https://github.com/goon-123/AnimeCompanion). A source push to main starts the included **iOS unsigned IPA** workflow. Public-provider checks are diagnostic so a temporary service outage does not prevent packaging the app; inspect their step result separately. Simulator screenshots and the XCTest result bundle are uploaded as **AnimeCompanion-simulator-check**.
