# Anime Companion

### Schedule and details refresh (0.4.1)

Schedule opens on **Airing Now** for your watching/rewatching lists. Green means caught up, yellow means behind, and unconfirmed counts stay neutral. Choose Original broadcast or English dub, tap the yellow count to filter behind titles, or open **Weekly Schedule** to browse sub/dub releases in either week direction. My Library keeps its list/grid controls and per-title progress.

Weekly Schedule opens at the highlighted local **Today** section in the current week, including days without releases. A compact weekday strip jumps to any day; the full week remains freely scrollable. Previous/next weeks and the date picker remain available. Manual browsing is not reset by incoming releases, and other weeks never jump back to today. Foregrounding or reopening refreshes the local day, including week and daylight-saving boundaries.

Anime genres appear as a single horizontally scrolling row of buttons. Tap one to open Explore with that genre selected across the whole catalog; saved dub preferences still apply. Your library and confirmed AniList progress are preserved when switching tabs.

The details page has a cinematic fading banner, poster and compact status/rating/dub summary, a progress-aware VidHub resume button and an airing countdown. Full dub counts, release history and schedules, tracking and library management, synopsis/metadata, related titles, characters, staff, recommendations, trailers, reviews and external links remain available. Build 17 validation is recorded in `BUILD_STATUS.md`.

A universal iPhone and iPad SwiftUI app for seasonal anime discovery, AniList library tracking, English dub information and anime news. The name is a working title. Requires iOS/iPadOS 17 or newer. iPad supports portrait, upside-down portrait and both landscape orientations.

## Features

- **Airing catch-up:** Schedule's Airing Now view shows green Caught up or yellow episodes behind, watched/aired episode numbers and the next episode's local airing time. Compare with original broadcasts or reported English-dub releases using the saved Schedule/Settings choice. Missing, expired or estimated release counts stay neutral. Finished originals do not receive broadcast catch-up badges; an ongoing dub can still have its own status. My Library no longer repeats these panels, poster markers or next-airing lines; it retains watched counts, dub counts, sorting, display preferences and its independent expandable Coming up for you section. AniList refreshes preserve Undo only when confirmed tracking is unchanged.
- **Progress-aware Watch:** Library cards have a direct VidHub action, and the detail Watch button appears before longer metadata. Tracked titles automatically search the next unwatched AniList episode; an older or later local resume record cannot rewind or skip that selection. The selected episode's local resume position still applies. Untracked titles can use their valid local resume episode, movies always use episode 1, and known totals bound the selection. Manual episode changes remain available.
- **Metadata source switch:** AniList native details or LiveChart.me's actual web listings inside the app. Choose a default in Settings, switch from Explore's globe menu or the detail source picker, and browse LiveChart seasons/search. LiveChart has no public metadata API; web pages are clearly labeled and can open in the system browser if verification blocks loading. AniList progress, ratings, notes and playback controls remain native for a uniquely matched title. ID matching is bidirectional and rejects ambiguous split entries; unmatched titles stay unlinked rather than guessing from names. Switching back to AniList details uses the last matched title.
- **Content settings:** Show adult anime (18+) is saved on this device and starts off. Enabling it includes regular and adult titles; disabling it filters catalog previews, category search, details, related titles/recommendations, library entries and schedules without deleting AniList records. Adult and non-adult Explore caches are separate. LiveChart's web pages retain LiveChart's own website content preferences.
- **Tracking controls:** One-tap next-episode controls in library list/grid cards and details; tap the episode count to set progress directly. The full editor supports status, rating, notes, rewatch count, and confirmed removal. Quick actions preserve other tracking fields. Saves display after AniList confirms them, with Undo for the most recent per-title save. A library banner keeps Undo reachable when completion moves a title out of the current list. Finishing a known episode total can move the title to Completed and finish a rewatch; this behavior can be disabled. Ratings display out of ten and are submitted as AniList's canonical 100-point score so account formats remain compatible.
- **Explore:** Trending first, Popular this season and Upcoming, on a neutral dark shelf background. Featured titles, shelves and category lists/grids use a green dot only for currently airing original broadcasts, your signed-in AniList list status and a short English-dub badge. Dub available and Partial dub are green; estimates/unconfirmed reports are amber, announcements yellow and missing information neutral. Upcoming premieres do not receive an airing dot merely because they have a scheduled episode. Detailed dub counts, next-airing dates and countdowns stay in My Library, Schedule and details, not Explore; title/format/season totals, ratings and genres remain available. Every category opens a full paginated list with title search, genre/year/season/format/status filters, rating/popularity/trending/newest/title sorting and list/grid display. Genres remain visible in every layout.
- **Featured posters:** Explore starts with five swipeable, edge-to-edge featured titles. Artwork fills most of the screen, extends behind the top controls and fades through its poster-derived accent into the neutral page background. There is no framed card or separate iPad poster panel. Wide windows use banner artwork when available. Genres, ratings, compact list/dub badges, details and artwork expansion remain accessible. Automatic screen-filling height refits after rotation; Display options also offers a custom height. Cover colors come from AniList, with local image sampling when missing, and are shaded to keep white text readable.
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
3. Tap the play button on a library card, or open details and tap **Watch in VidHub**. Sources load automatically for the next unwatched AniList episode (four episodes watched selects episode five). An untracked title can resume its local episode. Choosing another episode reloads the sources and stays selected during synchronization. **Tap a source to open VidHub directly**—there is no separate confirmation screen. Touch and hold a source for optional external subtitles or to play from the beginning. The reload icon retries the current episode.

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

The workflow selects Xcode 26.0.1 and the iOS 26 SDK on a macOS runner, runs core unit tests, generates the project with XcodeGen, compiles the app and packages the IPA. iPhone and 11-inch iPad Pro UI checks run in parallel on separate fresh macOS runners, preferring the supported iOS/iPadOS 18 runtime when available because hosted iOS 26 simulators have repeatedly stalled at startup. The app still builds with the iOS 26 SDK. No credentials or signing keys are required for an unsigned build.

After packaging, the workflow also checks the public AniList, dub, news and LiveChart providers. Seven iPhone smoke tests cover all four tabs, account settings, library search, display controls and persistence, list/grid preferences, dub labels and grid genres, rating sorting, expanded category filters, Explore dub/library/completed/airing indicators, week navigation, date-picker access, persistent Dub selection, entry details and cover expansion. Three iPad layout tests check artwork growth, Coming-up sizing, two/three/eight-column grids and genres, independent preferences, rotation, all tabs, details and full-screen artwork. Shared checks cover repeated category detail/back and swipe-back journeys with retained pagination and filters; featured paging and artwork expansion; saved dub/completed filters; source switching and tracking validation; playback setup and AniList-first episode selection; Library cleanup with Schedule catch-up retained; cinematic details; genre taps/swipes in list, grid, featured and every shelf; compact presentation; and today/week navigation including late-arriving and empty releases. The full suites contain **29 iPhone** and **25 iPad** cases; **17 shared cases** also run as focused checks with a 30-minute budget for cold startup and a retained retry. Two weekly cases run independently on each device. Screenshots and result bundles are uploaded separately. Public-provider diagnostics can fail during an outage; check their actual logs. See `BUILD_STATUS.md` for the verified source and any outstanding CI-only rerun.

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

Focused iPhone/iPad checks verify featured artwork, source switching, content preferences, airing catch-up in both layouts, behind filtering, progress-aware source loading and one-tap player handoff. Run `bash scripts/check-simulator.sh iphone focused` (or `ipad focused`). Playback uses an opt-in Debug-only `--ui-playback-preview` transport and launch recorder; it exercises the real URL builder without installing a personal add-on, saving progress or opening VidHub. `--ui-airing-preview` supplies labeled synthetic airing records and `--ui-playback-stale-resume` supplies an old episode-one resume. These arguments and fixtures are excluded from Release. Full regression suites remain enabled separately.

## Data sources and attribution

- AniList: https://anilist.co — metadata, seasons, original broadcasts, login and library.
- AniSchedule by RockinChaos: https://github.com/RockinChaos/AniSchedule — maintained English dub dates and recorded episodes, derived from AnimeSchedule.net. Feed update timestamps detect stale data. The Bas1874 mirror (https://github.com/Bas1874/AniSchedule) is an alternate for endpoint failures, or when its timestamp is newer than a stalled primary endpoint. Each endpoint is chosen separately, with a visible fallback notice. The app consumes JSON; it does not embed the provider's scripts.
- Dub data © MyDubList — https://mydublist.com — CC BY 4.0: https://creativecommons.org/licenses/by/4.0/. Data is matched by IDs and formatted for display; source records are not edited.
- Anime News Network: https://www.animenewsnetwork.com — news RSS headlines, publisher thumbnails and original article links.
- Crunchyroll: https://www.crunchyroll.com/news — English news RSS and publisher thumbnails.
- Anime Corner: https://animecorner.me — news RSS, publisher thumbnails and original article links.

Dub availability is matched by MAL ID; releases use AniList IDs, with a matching MAL ID as a mapping fallback and contradictory IDs rejected. “Dub 6/12 released” means reported dub progress through episode 6 while 12 original episodes have broadcast; the planned season total appears in details. MyDubList source counts show how many sources report a dub, not how many episodes exist. Details show the count basis, source agreement, latest reported release, feed update time and upcoming dates.

Recorded episodes take priority over estimates. If history is missing, a next dub episode within two weeks can supply an explicitly labeled estimate of earlier releases, capped by original episodes already aired. Delayed, distant, past and not-yet-released schedules never supply that estimate. Completed dub listings without history or an ongoing dub schedule use their total as a labeled estimate. The app never invents a weekly recurrence. A failed endpoint preserves the other endpoint's useful data, and pull to refresh rechecks both releases and availability.

Dub data refreshes on every return to the foreground and every ten minutes while the app is active, without blocking Explore. Failed requests retry after one minute. Discovery, details, library counts and the visible dub schedule observe the same updates; switching tabs does not stop the timer. Requests bypass the device HTTP cache, while concurrent views share requests and reuse the ten-minute release cache between automatic checks. Backgrounding cancels the timer; returning starts a fresh check. The app cannot make an upstream provider publish faster: feeds older than three days, missing update timestamps and unsuccessful checks remain visible instead of looking current.

Seanime plugins were inspected to locate upstream sources and understand their schemas. This app does not run Seanime plugins or redistribute their marketplace database.

## Current verification

See `BUILD_STATUS.md` for the completed checks and remaining signed-device verification. Download a compiled IPA only from a successful workflow run; the source ZIP is not an installable app.
