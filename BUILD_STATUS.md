# Build checkpoint

## Completed

- Implemented 15 Swift source files across the app and its shared data layer.
- Swift 6.1.3 compiled the AnimeCore package and XCTest targets on Linux.
- Executed **14 tests with 0 failures**, including parsing captured current AniSchedule data, dub episode history, the MyDubList English index and ANN RSS.
- Passed Swift parser checks for all SwiftUI application source files.
- Parsed the XcodeGen project specification, GitHub workflow and asset JSON, and passed shell syntax validation for the build script.
- Included XcodeGen project generation and a GitHub Actions macOS workflow that builds and packages an unsigned IPA after its checks succeed.

## Still required

- Compile and type-check the complete SwiftUI app with Xcode, then check the actual screens in the iPhone simulator. Linux syntax checks do not validate SwiftUI type compatibility or rendering.
- Verify live AniList metadata requests on that build. Direct AniList requests returned HTTP 403 from this workspace; API definitions were checked against the official documentation.
- Register an AniList OAuth client and verify the complete sign-in, cancellation, token persistence and list-mutation flow on device.
- Sign the IPA for installation or configure a development-signed device build. No IPA has been produced at this checkpoint.

## Repository and build

The source is being uploaded to [goon-123/AnimeCompanion](https://github.com/goon-123/AnimeCompanion). A push to main starts the included **iOS unsigned IPA** workflow. The complete Xcode build is pending; consult the latest Actions run for its result.
