# Anime Companion

A universal iPhone and iPad SwiftUI app for seasonal anime discovery, AniList library tracking, English dub information and anime news. The name is a working title. Requires iOS/iPadOS 17 or newer. iPad supports portrait, upside-down portrait and both landscape orientations.

## Features

- **Explore:** Trending first, Popular this season and Upcoming. Shelf cards and category lists/grids show English dub release counts or availability, your AniList library status, Completed/Watched before badges, the next original broadcast and the next listed dub date. Dub badges are green for reported releases/availability, amber for estimated counts and yellow for announcements. Every category opens a full paginated list with title search, genre/year/season/format/status filters, rating/popularity/trending/newest/title sorting and list/grid display.
- **Featured posters:** Explore starts with five swipeable, edge-to-edge featured titles. Artwork fills most of the screen, extends behind the top controls and fades into a poster-derived color that continues down the page. There is no framed card or separate iPad poster panel. Wide windows use banner artwork when available. Genres, ratings, dub information, details and artwork expansion remain accessible. Automatic screen-filling height refits after rotation; Display options also offers a custom height. Cover colors come from AniList, with local image sampling when missing, and are shaded to keep white text readable.
- **Saved dub filters:** automatically remembered English-dub availability filters for All anime, Dub available, Airing dubs, verified Scheduled dubs and No dub reported. Combine them with a minimum AniList rating and Hide completed anime. The same choices apply to featured posters, Explore shelves, search and expanded categories. Counts distinguish matches from loaded titles; a filtered category can load additional pages. Provider failures remain unknown rather than evidence that a dub does not exist.
- **Silver glass controls:** native floating bottom tab navigation and Liquid Glass controls on iOS/iPadOS 26. Older systems use material surfaces for the custom controls. Reduce Transparency replaces those custom surfaces with a readable opaque background.
- **Schedule:** weekly original broadcasts and English dub entries, local times, previous/next week, a graphical date picker and a watching-list filter. All/Sub/Dub and watching-only preferences are saved across launches. Week-navigation buttons have independent actions.
- **My Library:** saved list/grid display with one to eight entries per row, adjustable list/grid artwork, title search, Watching/Planning/Completed/Dropped/Paused/Rewatching tabs, counts and sorting including AniList rating. Continue watching is removed; Coming up for you remains expandable with its own poster-size control. Both layouts show watched progress and dub release counts without opening details. Each entry has a menu for progress and status. Changes display after AniList confirms them; an unsuccessful write preserves saved progress.
- **News:** Anime News Network, Crunchyroll and Anime Corner, with publisher filters and thumbnails beside headlines. Feed thumbnails are used first; visible stories can retrieve the publisher's Open Graph image. Missing images show a neutral news icon. Articles open at their original source in Safari. The weekly/monthly Popular section uses reading counts saved on this device and is labeled accordingly; it does not claim publisher-wide readership statistics.
- **Anime details:** cover and banner, expandable synopsis, season/status, score, genres, release dates, episodes, duration, studio, popularity, favourites and rankings. Includes characters, staff, related titles, recommendations, a trailer, reviews, external links and AniList controls. Upcoming original broadcasts have a live countdown. Each title has its own English dub availability, recorded release history and upcoming schedule when the sources list dates.
- **Artwork viewer:** tap a cover or banner on the detail page to expand it, then pinch to zoom, drag while zoomed or double-tap to zoom/reset. Rotation/window resizing refits the image instead of retaining an offscreen pan.
- **Display options:** the sliders icon in Explore, expanded categories and My Library opens independent, automatically saved image-size controls. Choose list-poster width, maximum grid-poster width and one to eight entries per row. Explore has featured-height and shelf-poster controls; My Library has a Coming-up poster control. Defaults are larger on iPad. Fewer grid entries give covers more room to grow, while a maximum width prevents enormous single-column images on wide screens. Narrow windows and accessibility-size text can temporarily reduce columns without losing the saved choice. Long-form detail, news and schedule content stays centered at a readable width.

Grid cards in Explore and My Library, plus Explore shelf cards, show all reported genres as wrapping text. Returning from an anime's details keeps the expanded category's loaded pages, selected filters and scroll position. Changing filters starts a new result set at the top; pull to refresh still reloads the current category.

Layout, grid-density and sorting menus use single-action choices that dismiss after selection. Native UI checks verify that the density menu closes and the selected row count persists after relaunch.

The application opens with real provider clients rather than the design prototype's sample data. Each provider can fail independently. AniList requests are spaced and public responses are cached briefly in memory. Login is not required for public browsing.

Version 0.2.2 also saves the public Explore catalog on the device, separately for each season. On later launches, saved titles appear before a network refresh; snapshots under five minutes old avoid an unnecessary request. Older snapshots refresh in the background and remain visible if the request fails. Snapshots expire after seven days, at most six seasons are retained, and pull to refresh always requests fresh data. The first launch still needs an internet connection. Explore fetches only the seasonal titles shown in its shelf and defers offscreen shelves. Search and category genre menus now include **Ecchi**.

## AIOStreams and VidHub playback

Version 0.2 adds **Settings → Add-ons & playback** and **Watch in VidHub** on released anime pages.

1. Install a current VidHub version on the same iPhone or iPad.
2. Open **Settings → Add-ons & playback**, paste your personal AIOStreams install link and tap **Connect add-on**. Both a base install link and a URL ending in `/manifest.json` work; `stremio://` links are normalized to HTTPS.
3. Open an anime and tap **Watch in VidHub**. Sources load automatically for the next or resumed episode; choosing another episode reloads them. **Tap a source to open VidHub directly**—there is no separate confirmation screen. Touch and hold a source for optional external subtitles or to play from the beginning. The reload icon retries the current episode.

The full add-on URL is stored only in this device's Keychain, never bundled in the app, committed to this repository, or written to request logs. Add-on requests use an ephemeral network session. Returned video URLs remain in memory and are passed only to the chosen player. Replacing an add-on validates it before changing the saved connection.

The client honors the manifest's stream resource types and ID prefixes. It requests the anime's AniList ID and entry-relative episode number, then tries its MyAnimeList ID if the first response is empty or the identifier is rejected. Movies use movie IDs without a fabricated season or episode suffix. AIOStreams remains responsible for matching those IDs to provider content, source ordering, and reported quality/language details. The app does not infer that every stream is dubbed from the title's general dub availability.

Direct HTTP(S) video links are supported. Torrent-only results, webpage links and streams requiring custom playback headers are labeled unavailable; enable a streaming service or playback proxy in AIOStreams for these. This version supports one active Stremio streaming add-on accepting AniList/MAL IDs. It does not run Nuvio JavaScript plugins or import add-on catalogs.

VidHub's `/play` interface supports external subtitles and resume. A random per-play request ID associates its callback with the selected episode. Stopped playback saves a local position; finished playback clears that episode's resume point and marks it finished locally. Errors and cancellation preserve existing progress. Missing callbacks (for example, after force-quitting VidHub) cannot update the saved position. Callbacks never change AniList automatically; use the watched-progress controls or **Mark episode watched on AniList** after a finished playback.

References: [VidHub integration](https://vidhub.okaapps.com/3rd-party-app-integration/), [Stremio stream protocol](https://github.com/Stremio/stremio-addon-sdk/blob/master/docs/api/responses/stream.md), [AIOStreams ID parser](https://github.com/Viren070/AIOStreams/blob/main/packages/core/src/utils/id-parser.ts).

## AniList sign-in setup

1. Visit https://anilist.co/settings/developer and create an application.
2. Name it **Anime Companion** and set its redirect URL to **animecompanion://oauth/anilist**.
3. In the app, open Settings, enter the numeric **client ID**, and tap Connect AniList. Existing users can keep their configured client ID; no new AniList developer registration is needed for this update.

Only the client ID is needed. Do not paste a client secret or access token into the source. OAuth opens AniList's sign-in screen; the returned bearer token is stored in this device's Keychain. Expired credentials require signing in again. The sign-in request follows AniList's implicit mobile flow by sending only the client ID and response type; AniList uses the redirect URI saved in the developer application. The callback URI is validated before a token is accepted.

## Build a universal iPhone/iPad IPA with GitHub

The project is hosted at [goon-123/AnimeCompanion](https://github.com/goon-123/AnimeCompanion). The included **iOS unsigned IPA** workflow runs when main is updated and can also be started from Actions → iOS unsigned IPA → Run workflow.

On a successful run, download **AnimeCompanion-unsigned-IPA** from the run's Artifacts section. Extract the ZIP to get **AnimeCompanion-unsigned.ipa**. The same unsigned build supports iPhone and iPad and needs signing through your chosen installation method before installation. It is not a TestFlight upload.

The workflow selects Xcode 26.0.1 and the iOS 26 SDK on a macOS runner, runs core unit tests, generates the project with XcodeGen, compiles the app and packages the IPA. iPhone and 11-inch iPad Pro UI checks run on iOS 26 in parallel on separate fresh macOS runners, so one simulator does not interfere with the other. No credentials or signing keys are required for an unsigned build.

After packaging, the workflow also checks the public AniList, dub and news providers. Seven iPhone smoke tests cover all four tabs, account settings, library search, display controls and persistence, list/grid preferences, dub labels and grid genres, rating sorting, expanded category filters, Explore dub/library/completed/airing indicators, week navigation, date-picker access, persistent Dub selection, entry details and cover expansion. Three iPad layout tests select an actual 11-inch iPad Pro simulator and check artwork growth, Coming-up sizing, two/three/eight-column grids and genres, independent saved preferences, portrait/landscape rotation, all four tabs, details and full-screen artwork. An additional navigation regression runs on both devices: repeated detail/back and swipe-back journeys from Popular this season in list and grid views, retaining scrolled results, appended pages when available, selected genre/sort filters and grid density. Two more shared tests cover featured paging, artwork expansion, detail returns and tablet rotation, plus available-dub filtering, hiding a completed movie, retained grid genres and saved choices after relaunch. That makes ten iPhone and six iPad UI tests. Screenshots and test result bundles are uploaded separately. Public-provider diagnostics can fail during a service outage; check that step's logs for the result.

## Build on a Mac

Install Xcode 26 or newer and XcodeGen (`brew install xcodegen`), then run:

```sh
bash scripts/build-ios.sh
```

For simulator testing, run `xcodegen generate`, open `AnimeCompanion.xcodeproj`, select an iPhone or iPad simulator and run the AnimeCompanion scheme. For a development-signed device build, configure your Apple development team in Xcode.

## Check the data layer

```sh
swift test -j 2
```

Tests cover season rollover, local dates, unknown episode totals, real-vs-estimated dub date priority, indefinite delays, dub counts versus original releases and planned totals, missing/partial/complete dub listings, RSS dates/CDATA/unsafe links, thumbnail metadata, partial news-source failures, local reading windows, discovery filter variables, OAuth callback validation, request headers, public response caching, custom-list deduplication, mutation IDs, error responses and airing pagination.

An optional `LIVE_FIXTURE_DIR` environment variable lets tests read externally captured source responses. Captured upstream datasets are not bundled into this source package.

For opt-in checks of the live public clients, run `ANIMECOMPANION_LIVE_SERVICES=1 swift test --filter LiveServiceTests`. These checks do not log in or write to an AniList account. After generating the Xcode project, run `bash scripts/check-simulator.sh iphone` or `bash scripts/check-simulator.sh ipad`. The iPad command requires an available 11-inch Pro simulator and fails clearly if none exists. Simulator builds use local ad-hoc signing so Keychain access can be checked; the downloadable device IPA remains unsigned.

The library UI tests use the Debug-only `--ui-library-preview` launch argument: real public metadata with synthetic local progress. Only the Coming-up artwork-sizing test also uses `--ui-layout-preview` to add a deterministic synthetic future release. That date is a test fixture, not a provider claim. Neither fixture authenticates or writes to AniList, and both are excluded from Release builds.

Focused iPhone/iPad checks verify edge-to-edge featured artwork, paging, shelf screenshots, automatic source loading and one-tap player handoff without a confirmation sheet. Run `bash scripts/check-simulator.sh iphone focused` (or `ipad focused`). Playback uses an opt-in Debug-only `--ui-playback-preview` transport and launch recorder; it exercises the real URL builder without installing a personal add-on, saving progress or opening VidHub. The full regression suites remain enabled separately.

## Data sources and attribution

- AniList: https://anilist.co — metadata, seasons, original broadcasts, login and library.
- AniSchedule by RockinChaos: https://github.com/RockinChaos/AniSchedule — maintained English dub dates and recorded episodes, derived from AnimeSchedule.net. Feed update timestamps detect stale data. The older Bas1874 mirror (https://github.com/Bas1874/AniSchedule) is used only when an endpoint fails, with a visible fallback notice. The app consumes JSON; it does not embed the provider's scripts.
- Dub data © MyDubList — https://mydublist.com — CC BY 4.0: https://creativecommons.org/licenses/by/4.0/. Data is matched by IDs and formatted for display; source records are not edited.
- Anime News Network: https://www.animenewsnetwork.com — news RSS headlines, publisher thumbnails and original article links.
- Crunchyroll: https://www.crunchyroll.com/news — English news RSS and publisher thumbnails.
- Anime Corner: https://animecorner.me — news RSS, publisher thumbnails and original article links.

Dub availability is matched by MAL ID; releases use AniList IDs, with a matching MAL ID as a mapping fallback and contradictory IDs rejected. “Dub 6/12 released” means reported dub progress through episode 6 while 12 original episodes have broadcast; the planned season total appears in details. MyDubList source counts show how many sources report a dub, not how many episodes exist. Details show the count basis, source agreement, latest reported release, feed update time and upcoming dates.

Recorded episodes take priority over estimates. If history is missing, a next dub episode within two weeks can supply an explicitly labeled estimate of earlier releases, capped by original episodes already aired. Delayed, distant, past and not-yet-released schedules never supply that estimate. Completed dub listings without history or an ongoing dub schedule use their total as a labeled estimate. The app never invents a weekly recurrence. A failed endpoint preserves the other endpoint's useful data, and pull to refresh rechecks both releases and availability. Concurrent views share network requests; the release cache lasts ten minutes.

Seanime plugins were inspected to locate upstream sources and understand their schemas. This app does not run Seanime plugins or redistribute their marketplace database.

## Current verification

See `BUILD_STATUS.md` for the completed checks and remaining signed-device verification. Download a compiled IPA only from a successful workflow run; the source ZIP is not an installable app.
