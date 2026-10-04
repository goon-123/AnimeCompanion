# Anime Companion

An iPhone-first SwiftUI app for seasonal anime discovery, AniList library tracking, English dub information and anime news. The name is a working title. Requires iOS 17 or newer.

## Features

- **Explore:** Trending first, Popular this season and Upcoming. Shelf cards and category lists/grids show English dub release counts or availability, your AniList library status, Completed/Watched before badges, the next original broadcast and the next listed dub date. Unknown counts and unverified or delayed dates are labeled. Every category opens a full paginated list with title search, genre/year/season/format/status filters, rating/popularity/trending/newest/title sorting and list/grid display.
- **Schedule:** weekly original broadcasts and English dub entries, local times, previous/next week, a graphical date picker and a watching-list filter. All/Sub/Dub and watching-only preferences are saved across launches. Week-navigation buttons have independent actions.
- **My Library:** saved list/grid display with one to four cards per row, title search, Watching/Planning/Completed/Dropped/Paused/Rewatching tabs, counts and sorting including AniList rating. Continue watching is removed; Coming up for you remains expandable. Both layouts show watched progress and dub release counts without opening details. Each entry has a menu for progress and status. Changes display after AniList confirms them; an unsuccessful write preserves saved progress.
- **News:** Anime News Network, Crunchyroll and Anime Corner, with publisher filters and thumbnails beside headlines. Feed thumbnails are used first; visible stories can retrieve the publisher's Open Graph image. Missing images show a neutral news icon. Articles open at their original source in Safari. The weekly/monthly Popular section uses reading counts saved on this device and is labeled accordingly; it does not claim publisher-wide readership statistics.
- **Anime details:** cover and banner, expandable synopsis, season/status, score, genres, release dates, episodes, duration, studio, popularity, favourites and rankings. Includes characters, staff, related titles, recommendations, a trailer, reviews, external links and AniList controls. Upcoming original broadcasts have a live countdown. Each title has its own English dub availability, recorded release history and upcoming schedule when the sources list dates.
- **Artwork viewer:** tap a cover or banner on the detail page to expand it, then pinch to zoom, drag while zoomed or double-tap to zoom/reset.

The application opens with real provider clients rather than the design prototype's sample data. Each provider can fail independently. AniList requests are spaced and public responses are cached briefly in memory. Login is not required for public browsing.

## AniList sign-in setup

1. Visit https://anilist.co/settings/developer and create an application.
2. Name it **Anime Companion** and set its redirect URL to **animecompanion://oauth/anilist**.
3. In the iPhone app, open Settings, enter the numeric **client ID**, and tap Connect AniList.

Only the client ID is needed. Do not paste a client secret or access token into the source. OAuth opens AniList's sign-in screen; the returned bearer token is stored in this device's Keychain. Expired credentials require signing in again. The sign-in request follows AniList's implicit mobile flow by sending only the client ID and response type; AniList uses the redirect URI saved in the developer application. The callback URI is validated before a token is accepted.

## Build an iPhone IPA with GitHub

The project is hosted at [goon-123/AnimeCompanion](https://github.com/goon-123/AnimeCompanion). The included **iOS unsigned IPA** workflow runs when main is updated and can also be started from Actions → iOS unsigned IPA → Run workflow.

On a successful run, download **AnimeCompanion-unsigned-IPA** from the run's Artifacts section. Extract the ZIP to get **AnimeCompanion-unsigned.ipa**. This is an unsigned build and needs signing through your chosen installation method before it can run on an iPhone. It is not a TestFlight upload.

The workflow uses a macOS Xcode runner, runs core unit tests, generates the project with XcodeGen, compiles the app and packages the IPA. No credentials or signing keys are required for an unsigned build.

After packaging, the workflow also checks the public AniList, dub and news providers. Six iPhone simulator tests cover all four tabs, account settings, library search, list/grid preferences, dub labels, rating sorting, expanded category filters, Explore dub/library/completed/airing indicators in shelves and both layouts, week navigation, date-picker access, persistent Dub selection, entry details and cover expansion. Simulator screenshots and the test result bundle are uploaded separately. Public-provider diagnostics can fail during a service outage; check that step's logs for the result.

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

Tests cover season rollover, local dates, unknown episode totals, real-vs-estimated dub date priority, indefinite delays, dub counts versus original releases and planned totals, missing/partial/complete dub listings, RSS dates/CDATA/unsafe links, thumbnail metadata, partial news-source failures, local reading windows, discovery filter variables, OAuth callback validation, request headers, public response caching, custom-list deduplication, mutation IDs, error responses and airing pagination.

An optional `LIVE_FIXTURE_DIR` environment variable lets tests read externally captured source responses. Captured upstream datasets are not bundled into this source package.

For opt-in checks of the live public clients, run `ANIMECOMPANION_LIVE_SERVICES=1 swift test --filter LiveServiceTests`. These checks do not log in or write to an AniList account. Run the simulator smoke test with `bash scripts/check-simulator.sh` after generating the Xcode project. Simulator builds use local ad-hoc signing so Keychain access can be checked; the downloadable device IPA remains unsigned.

The library UI tests use the Debug-only `--ui-library-preview` launch argument: real public metadata with synthetic local progress. This fixture does not authenticate or write to AniList and is excluded from Release builds.

## Data sources and attribution

- AniList: https://anilist.co — metadata, seasons, original broadcasts, login and library.
- AniSchedule by Bas1874: https://github.com/Bas1874/AniSchedule — English dub dates and recorded episodes. The app reads the original raw JSON URLs.
- Dub data © MyDubList — https://mydublist.com — CC BY 4.0: https://creativecommons.org/licenses/by/4.0/. Data is matched by IDs and formatted for display; source records are not edited.
- Anime News Network: https://www.animenewsnetwork.com — news RSS headlines, publisher thumbnails and original article links.
- Crunchyroll: https://www.crunchyroll.com/news — English news RSS and publisher thumbnails.
- Anime Corner: https://animecorner.me — news RSS, publisher thumbnails and original article links.

Dub availability is matched by MAL ID; releases are matched by AniList ID. “Dub 6/12 released” means the source reports dub progress through episode 6 while 12 original episodes have broadcast, rather than 12 being the planned season total. Completed titles in a complete-dub listing use their episode total when the recent release feed no longer includes them. Partial listings, absent announcements and source errors do not become invented counts or release dates.

Seanime plugins were inspected to locate upstream sources and understand their schemas. This app does not run Seanime plugins or redistribute their marketplace database.

## Current verification

See `BUILD_STATUS.md` for the completed checks and remaining signed-device verification. Download a compiled IPA only from a successful workflow run; the source ZIP is not an installable app.
