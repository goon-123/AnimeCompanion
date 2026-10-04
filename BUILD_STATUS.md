# Build checkpoint

## Completed

- Implemented 15 Swift source files across the app and its shared data layer.
- Swift 6.1.3 compiled the AnimeCore package and XCTest targets on Linux.
- Executed **14 tests with 0 failures**, including parsing captured current AniSchedule data, dub episode history, the MyDubList English index and ANN RSS.
- Passed Swift parser checks for all SwiftUI application source files.
- Parsed the XcodeGen project specification, GitHub workflow and asset JSON, and passed shell syntax validation for the build script.
- Included XcodeGen project generation and a GitHub Actions macOS workflow that builds and packages an unsigned IPA after its checks succeed.
- [First macOS workflow](https://github.com/goon-123/AnimeCompanion/actions/runs/37174795255) passed: 13 core tests, Xcode project generation, the complete iPhone Release build and IPA packaging. The captured-source test was skipped because external captures are not bundled.

## Still required

- Check the actual screens in the iPhone simulator. The complete SwiftUI app has compiled successfully with Xcode.
- Verify live AniList metadata requests on that build. Direct AniList requests returned HTTP 403 from this workspace; API definitions were checked against the official documentation.
- Register an AniList OAuth client and verify the complete sign-in, cancellation, token persistence and list-mutation flow on device.
- Sign the compiled IPA for installation or configure a development-signed device build.

## Repository and build

The source is available at [goon-123/AnimeCompanion](https://github.com/goon-123/AnimeCompanion). A push to main starts the included **iOS unsigned IPA** workflow. Public-provider checks and a simulator tab/settings smoke test have been added; their first results are pending. Provider checks are diagnostic so a temporary service outage does not prevent packaging the app.
