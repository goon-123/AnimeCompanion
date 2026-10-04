# Anime Companion

An iPhone-first SwiftUI app for seasonal anime discovery, AniList library tracking, English dub information and anime news. The name is a working title. Requires iOS 17 or newer.

## First implementation

- **Explore:** season/year browsing, airing titles, popularity, trending, upcoming season, title search, and more seasonal results. Connected users see continue watching and upcoming releases.
- **Schedule:** weekly original broadcasts and English dub entries, All/Sub/Dub filters, local times, previous/next week, and a watching-list filter.
- **My Library:** AniList Watching, Planning, Completed, Paused, Dropped and Rewatching. Change progress or list status. Changes display after AniList confirms them; an unsuccessful write preserves saved progress.
- **News:** Anime News Network RSS headlines and dates. Articles open at their original source with an in-app Safari view. Feed artwork is optional.
- **Anime details:** synopsis, cover/banner, score, genres, studio, characters, related titles, trailer, next broadcast, dub status, release history and upcoming dub dates, plus AniList controls.

The application opens with real provider clients rather than the design prototype's sample data. Each provider can fail independently. AniList requests are spaced and public responses are cached briefly in memory. Login is not required for public browsing.

## AniList sign-in setup

1. Visit https://anilist.co/settings/developer and create an application.
2. Name it **Anime Companion** and set its redirect URL to **animecompanion://oauth/anilist**.
3. In the iPhone app, open Settings, enter the numeric **client ID**, and tap Connect AniList.

Only the client ID is needed. Do not paste a client secret or access token into the source. OAuth opens AniList's sign-in screen; the returned bearer token is stored in this device's Keychain. Expired credentials require signing in again. Callback state and redirect are checked before a token is accepted.

## Build an iPhone IPA with GitHub

The project is hosted at [goon-123/AnimeCompanion](https://github.com/goon-123/AnimeCompanion). The included **iOS unsigned IPA** workflow runs when main is updated and can also be started from Actions → iOS unsigned IPA → Run workflow.

On a successful run, download **AnimeCompanion-unsigned-IPA** from the run's Artifacts section. Extract the ZIP to get **AnimeCompanion-unsigned.ipa**. This is an unsigned build and needs signing through your chosen installation method before it can run on an iPhone. It is not a TestFlight upload.

The workflow uses a macOS Xcode runner, runs core unit tests, generates the project with XcodeGen, compiles the app and packages the IPA. No credentials or signing keys are required for an unsigned build.

## Build on a Mac

Install Xcode and XcodeGen (`brew install xcodegen`), then run:

```sh
bash scripts/build-ios.sh
```

For simulator testing, run `xcodegen generate`, open `AnimeCompanion.xcodeproj`, select an iPhone simulator and run the AnimeCompanion scheme. For a development-signed device build, configure your Apple development team in Xcode.

## Check the data layer

```sh
swift test -j 2
```

Tests cover season rollover, local dates, unknown episode totals, real-vs-estimated dub date priority, indefinite delays, missing dub IDs, RSS dates/CDATA/unsafe links, OAuth callback validation, request headers, public response caching, custom-list deduplication, mutation IDs, error responses and airing pagination.

An optional `LIVE_FIXTURE_DIR` environment variable lets tests read externally captured source responses. Captured upstream datasets are not bundled into this source package.

## Data sources and attribution

- AniList: https://anilist.co — metadata, seasons, original broadcasts, login and library.
- AniSchedule by Bas1874: https://github.com/Bas1874/AniSchedule — English dub dates and recorded episodes. The app reads the original raw JSON URLs.
- Dub data © MyDubList — https://mydublist.com — CC BY 4.0: https://creativecommons.org/licenses/by/4.0/. Data is matched by IDs and formatted for display; source records are not edited.
- Anime News Network: https://www.animenewsnetwork.com — news RSS headlines and original article links.

Seanime plugins were inspected to locate upstream sources and understand their schemas. This app does not run Seanime plugins or redistribute their marketplace database.

## Current verification

See `BUILD_STATUS.md` for the completed checks and remaining iPhone build steps. Download a compiled IPA only from a successful workflow run; the source ZIP is not an installable app.
