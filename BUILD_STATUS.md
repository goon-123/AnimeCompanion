## Today positioning, focused Library and genre fixes — build 17

Version 0.4.1 on `fix/schedule-today-library-genres`, based on merged PR #7.

- Weekly Schedule keeps all seven local calendar days, highlights Today and initially positions its releases below fixed week/filter/day controls. Day shortcuts and free scrolling remain available. A chosen day stays in view as releases arrive; freely scrolling cancels pending positioning, including while releases are loading. Previous/upcoming weeks do not jump back to the current week. Day/foreground notifications refresh today and follow a week boundary only when already browsing the current week.
- My Library list/grid cards no longer repeat catch-up panels, green/yellow poster markers or associated next-airing lines. Watched progress, dub availability/counts, Watch/+1/edit actions, sorting, saved display controls and the independent expandable Coming up for you section are retained. Schedule's full Airing Now comparison and detail progress remain unchanged.
- Genre destinations now have explicit route identity so replacing an Explore path cannot retain an earlier category's State filters. Repeated taps, including the same genre, open fresh all-catalog results. Normal anime detail/back navigation retains category state. Compact horizontal scroll views keep independent genre buttons outside anime links; list-card blank areas now share the link's hit shape.
- Added seven local-calendar unit cases (including timezone, next-day, week boundary, first-weekday and both daylight-saving changes), two deterministic native weekly cases, and list/grid/featured/all-shelf tap and swipe checks. Existing Library badge checks now assert their absence only in My Library and their continued presence in Schedule. All preview clocks/releases are DEBUG only, with no credentials or account writes.
- Local whitespace and shell syntax checks pass. This Linux workspace has no Swift/Xcode; application validation was performed on hosted runners as recorded below.

Earlier build-17 candidates exposed competing scroll-reader scopes and selected-day displacement as late release rows arrived. The corrected implementation isolates the vertical reader and keeps the requested day in place until a free scroll clears it. Dedicated weekly iPhone/iPad jobs supplement every existing suite. Test scroll helpers use shorter, direction-aware gestures; genre menu choices have distinct identifiers to avoid matching clickable tags.

### Verified application source: `df95b5f28f80f77f234af96940a0ce533e5be84a`

[Validation run 38067191016](https://github.com/goon-123/AnimeCompanion/actions/runs/38067191016):

- All **117 active core tests** passed (122 total, five gated/optional skips), including all seven calendar/timezone/DST cases.
- Universal Release compilation and all **four public-provider checks** passed. The unsigned ARM64 IPA is version 0.4.1/build 17, supports device families 1 and 2, retains iOS 17 minimum support and all four iPad orientations, and contains no DEBUG preview flags. IPA SHA-256: `245b05b533d448dc0e345b62bcd8552ac5ffe4f582fcfba3463f86ea0e9b4e25`.
- All **29 full iPhone** and **25 full iPad** UI cases passed on their first attempts on iOS/iPadOS 18.5 simulators built with Xcode 26.0.1/the iOS 26 SDK. This includes repeated category detail/back navigation and pagination, genre menu selection, list/grid/featured/every-shelf genre shortcuts and swipe-only behavior, Library cleanup with Schedule indicators retained, saved filters/custom sizing/rotation, dub counts, tracking validation, AniList-first resume selection and the previewed player flow.
- Both dedicated weekly jobs passed their two cases on the first attempt. All **17 focused iPhone** cases also passed on the first attempt.
- The duplicate focused iPad job hit its old 20-minute budget after an XCTest snapshot-query timeout; that case passed on retry, and the complete full iPad suite independently passed every case. The workflow as a whole therefore is **not** reported as green. The documentation/CI-only follow-up raises the focused budget to 30 minutes without disabling or changing any test assertion; its fresh run is pending.
- Reviewed weekly opening/manual-day/landscape captures and Library/genre-result layouts. Personal AniList sign-in/server writes, a signed installation and an actual installed VidHub handoff remain device checks; these suites use no account credentials or external writes.

The final follow-up changes only documentation and the focused-job deadline; application code, tests, project settings and simulator scripts are identical to the validated source above.

## Schedule, genre navigation and cinematic details — build 16

Version 0.4.0 on `design/schedule-genres-details`, based on PR #6's build-15 polish; PR #6 is left untouched.

- Schedule opens with the user's airing watchlist, behind-first ordering, green/yellow/neutral progress, original/dub comparison, next-airing times, direct playback and tracking actions. The weekly sub/dub calendar, saved filters, date picker and both week directions remain behind Weekly Schedule.
- Shared single-row genre buttons work in Explore, list/grid library entries, releases, details, related titles and recommendations. A tap switches to Explore and opens a fresh all-season genre query; genre buttons are outside the anime's navigation link.
- Details now use a larger fading banner, overlapping poster and clear status/rating/dub summary, a progress-aware resume button, four-part broadcast countdown, and consistent cards. AniList/LiveChart switching, tracking editor, image expansion, full dub evidence/history/dates, supporting metadata, trailers and external links remain.
- Added two core genre/model regressions and four native design/navigation regressions to the existing iPhone/iPad suites; moved the Airing Now filter assertions to Schedule and retained the library badge checks. UI fixtures are DEBUG only and contain no credentials or account writes.
- [Merged-source run 38014110089](https://github.com/goon-123/AnimeCompanion/actions/runs/38014110089) passed all 110 active core tests, universal Release compilation and public-provider checks. Native iPhone/iPad suites failed: genre navigation retained old filter state, and the full discovery-navigation case also reported a detail-opening failure. Build 17 addresses the genre identity bug and list-link hit shape and reruns the existing assertions. This earlier workflow was not a native validation pass.

# Build verification

## Version 0.3.2 / build 15

Simplifies native Explore featured titles, shelves, search and category list/grid cards to a green currently-airing dot, AniList list status and compact English-dub availability. Next-sub/next-dub episode numbers, dates and countdown rows no longer appear in Explore. Original broadcasts marked RELEASING receive the dot; a scheduled premiere alone does not. Reported/listed availability, partial dubs, estimates, announcements, unconfirmed reports and unknown data remain distinct. Full dub counts, catch-up progress and schedules remain in My Library, Schedule and anime details.

Explore shelves now use a neutral dark background; featured artwork retains its cover-derived accent and fades into that background. Poster sizing, grid-density preferences, metadata switching and tracking are retained. List rows wrap all reported genres instead of showing only the first three.

Adds nine core presentation cases and two native iPhone/iPad cases, included in both focused and full regression suites. Existing discovery checks now assert the requested compact badges and absence of schedule rows; library/detail count assertions remain.

[Build 13 / run 38010174866](https://github.com/goon-123/AnimeCompanion/actions/runs/38010174866), source `a7bb039fbfc28a09ad8ed5b87782a5edb5940e31`, compiled successfully. All 108 active core tests (113 enumerated, five optional/live skips) and all four separately executed live-provider checks passed. Its inspected universal ARM64 IPA is intact, unsigned and has no Debug fixtures; SHA-256: `ea4fdc4186e7d576cdfd95be18b577a72569dd5e7a71e539fa43f8d75671708a`. The focused iPhone suite passed eight of nine unique cases, but the new detail-dub-count lookup failed twice before the positive airing-dot portion of that case could run. The other new presentation case passed. Other native jobs were still running when this record was written; the workflow did not pass.

Build 14 removes the details panel's inherited container identifier, which overwrote child identifiers, and scrolls the existing count assertion into view before waiting for it. The failed build 13 accessibility hierarchy confirms that the visible label "Dub ~26/26 · estimated" inherited "anime-dub-schedule" instead of its child identifier. The count and positive airing-dot assertions remain enabled. [Build 14 / run 38011518553](https://github.com/goon-123/AnimeCompanion/actions/runs/38011518553), source `6fc066f2c99a1a92c58347129aaa3f9226f74a39`, compiled with all 108 active core tests and all four live-provider checks passing. Native jobs were still running when this record was written.

Reviewed three build 13 iPhone screenshots of the unchanged featured/shelf/list design. They showed the requested compact badges and no episode dates, and also revealed shelf controls showing through the always-transparent navigation bar. Build 15 restores native automatic navigation-background behavior as Explore scrolls and fixes singular episode wording. Final build 15 compilation, native regression results, screenshot review and IPA inspection are pending. Earlier results do not validate these final changes.

## Version 0.3.1 / build 12

Adds currently-airing library catch-up cards: green Caught up, yellow episodes behind, watched/aired episode numbers, the next airing time, a behind-only filter and Behind first sorting. Original broadcast and English dub comparisons are separately selectable and labeled. Unknown/stale original schedules and estimated dub counts cannot create a confirmed green/yellow status.

VidHub searches the next unwatched AniList episode for tracked titles, ignoring stale local episode-one resumes while preserving the selected episode's resume position. Library cards provide a direct Watch button; details place Watch before longer metadata. Active-library refreshes preserve Undo only if confirmed tracking fields remain unchanged. This version also fixes inherited LiveChart control identifiers and Debug preference reset persistence discovered in the build 9 native results.

### Completed build 12 verification

[Run 37943034223](https://github.com/goon-123/AnimeCompanion/actions/runs/37943034223) completed successfully on October 9, 2026 UTC. The built and tested source is `df62a903ae99bbd75bc592b8f057c33d7cc1038a` (tree `fd5e3d1a086074002a7df44f5b6a1ec700177908`). Subsequent verification-document updates do not change the app, package, tests or workflow.

- All 99 active core tests passed: 104 enumerated, five optional/live checks skipped, zero failures. All four separately executed live-provider checks passed, including AniList and LiveChart matching; their actual results were checked rather than relying on the step's continue-on-error setting.
- All seven focused native UI cases passed on each device family: airing catch-up/playback, immersive artwork/source launch, metadata matching, tracking controls and adult-setting persistence.
- All 19 full iPhone 16 simulator UI cases passed, with zero failures and no test retries.
- All 15 full 11-inch iPad Pro (M4) simulator UI cases passed, with zero failures and no test retries. These include portrait/landscape layout, saved display preferences, airing indicators, playback, filters, repeated detail returns and real pagination.
- Xcode 26.0.1 and the iOS 26 SDK compiled the universal ARM64 Release app. Native UI tests used iOS/iPadOS 18.5; this is not a claim that build 12 was natively tested on iOS 26. The simulator script prefers the available iOS 18 runtime to avoid hosted iOS 26 first-boot stalls and does not pause simulator system services. All navigation, scroll-retention, pagination, filter-reset and layout assertions remained enabled.
- Reviewed 11 build 12 screenshots: caught-up and behind list cards, grid poster markers and complete airing panels, automatically selected VidHub episode 9 for eight watched episodes, iPad rotation, reachable Reset and retained populated discovery results.
- Inspected both archive ZIP layers and the delivered IPA. It is version 0.3.1/build 12, minimum OS 17, iPhone/iPad families, all four iPad orientations, with an executable ARM64 app, no signature or embedded provisioning profile, and no Debug fixtures or preview launch strings. IPA SHA-256: `07d695310c8befa5a66f090345b5e9501678b5881a0ba25a3763a857ed835a70`. GitHub artifact ZIP SHA-256: `37fd5edc60104d267c21e372a002a0f9023bb28804c19193733a7e973f150772`.

The native airing tests use Debug-only synthetic progress/schedules and a safe player-launch recorder. They exercise the real episode selection and URL builder, but do not sign in, mutate a personal AniList library or launch the installed VidHub app. Actual account writes, player handoff and signed physical-device behavior still require the user's device. Opening Watch does not itself mark an episode watched. The unsigned IPA needs the existing signing/sideloading method; it is not a TestFlight build.

### Earlier candidates and fixes

The first candidate, [build 10 / run 37939078512](https://github.com/goon-123/AnimeCompanion/actions/runs/37939078512), compiled successfully. All 99 active core tests (104 enumerated, five skipped), all four live-provider checks and all seven focused native cases on each device family passed. Screenshot review found an unavailable SF Symbol rendering the library next-episode button blank. Build 11 replaces it with an explicit +1 label and adds a colored catch-up marker on grid posters. Its native grid check also reveals the full airing panel, and playback screenshots capture the automatically selected episode before manual override.

Build 10's full iPad suite passed all 15 cases. Its full iPhone suite passed 17 of 19 unique cases, but the discovery edge-swipe case failed twice and the saved-dub-filter case failed twice; the workflow did not pass. The failure hierarchy retained active filters after the bottom Reset button was tapped, and the retry inherited those filters. Build 12 moves Reset into the always-reachable toolbar and adds explicit reset-state assertions. The automated edge swipe is slower, with every original return/scroll/pagination assertion retained. Full jobs have a 35-minute limit so startup and artifact export do not cut off the larger suites.

[Build 11 / run 37941696936](https://github.com/goon-123/AnimeCompanion/actions/runs/37941696936), source `ae81ce87192d286d59f04afef141771ad794c17a`, compiled with all 99 active core tests and all four live-provider checks passing. Its inspected universal ARM64 IPA is intact and unsigned with no Debug fixtures, version 0.3.1/build 11, minimum OS 17 and all iPad orientations. IPA SHA-256: `e02387ae6b4a105de9a3d418665b615974ca848e3ae520d419543bf9c9958e18`. All seven focused native cases on each family and all 15 full iPad cases passed. The full iPhone suite again passed 17 of 19 unique cases, with discovery edge-swipe and saved-dub-filter cases each failing twice (21 executions, four failures). That workflow failed; build 12's successful results above validate the subsequent fixes.

Whitespace and shell syntax checks passed locally. The earlier temporary local Swift toolchain is no longer available, so the final Swift compilation and native verification were performed on the hosted macOS runners.

## Version 0.3.0 / build 9

Adds LiveChart web metadata switching with ID-matched AniList tracking, a persistent adult-content setting, an episode/rating/notes editor, next-episode actions, optional completion, and confirmed-save Undo. Native adult filtering and discovery caches are connected throughout the app.

Local validation on October 9, 2026 UTC:

- Swift 6.2 core suite: 93 tests enumerated, 88 active tests passed, five optional/live checks skipped, zero failures. New tests cover bidirectional ID matching and ambiguous seasons, shared mapping downloads, every adult-query filter, separate discovery caches, tracking bounds/completion/rewatches, preservation and explicit clearing of tracking fields, confirmed deletion, and metadata refresh.
- Direct Swift frontend type checking of AnimeCore and syntax parsing of all App/UI-test sources passed. Shell syntax and patch whitespace checks passed.
- Live checks: LiveChart ID matching and news passed. AniList public requests returned HTTP 403 in this environment, also preventing the dub test's AniList metadata probe. This is not a claim that AniList is unavailable on devices; repeat those checks from the hosted build runner.
- [Published run 37880226775](https://github.com/goon-123/AnimeCompanion/actions/runs/37880226775), source commit `c9cfce4f92d85968d11471bd258d751efb28128f`: universal ARM64 Release compiled with Xcode 26.0.1/iOS 26 SDK. All 88 active core tests and all four live-provider checks passed on GitHub, including AniList and LiveChart matching. The inspected IPA has intact ZIP layers, version 0.3.0/build 9, iPhone/iPad families, minimum OS 17, all four iPad orientations, an executable ARM64 app, no signature and no Debug preview strings. IPA SHA-256: `e7b8efddc3b6d745c64537c633516379265d9d1982954f4883ad0f2f2b3d8063`.
- Native checks ran on iOS/iPadOS 18.5. Immersive artwork/source-launch checks, adult-setting persistence and invalid-episode rejection passed on both families. The overall native workflow failed: the LiveChart edit-button test could not locate its identifier because the parent identifier overwrote child identifiers; its reset also did not persist the source choice and affected later playback tests. Some full iPhone discovery/filter checks also failed. Version 0.3.1 fixes the identified identifier/reset issues and reruns the assertions rather than treating that failed workflow as a pass.

## Earlier build verification

Verified app implementation: `470380ee4fbe00450faaa3d0794c19d8fd688914`.

[Successful universal build and native iPhone/iPad workflow](https://github.com/goon-123/AnimeCompanion/actions/runs/37328305383), October 5, 2026 (UTC).

The archive inspected before the workspace disconnected was built from `c4e8c0465c202d1ef0f395df9382a15ca6aba572`. The subsequent commit changes only CI scripts; App and AnimeCore sources are identical. [Download that validated build 4 archive](https://github.com/goon-123/AnimeCompanion/actions/runs/37326188379/artifacts/11352576849). Extract AnimeCompanion-unsigned.ipa and use the existing signing method.

## Build 4 changes

- Added saved English-dub filters: All anime, Dub available, Airing dubs, Scheduled dubs and No dub reported. Explore previews, full categories and search share these choices, a minimum AniList rating and Hide completed setting.
- Missing provider data stays unknown. No dub reported describes an index record without a dub listing, release or announcement; it does not predict whether a dub will ever be made. Scheduled dubs requires a verified future date and excludes estimates and indefinite delays. Known complete or partial dubs with unknown episode counts remain eligible for Dub available.
- Added large swipeable featured posters with every reported genre, rating, library status, current dub availability, next dub/sub airing, synopsis, View details and full-screen artwork expansion. Wide iPad windows show the complete cover beside its information. Narrow windows show information over a faded portrait cover. The selected poster remains selected after returning from details.
- Added an independent, automatically saved featured-poster height control. Existing Explore shelf/list/grid sizes and library list/grid/Coming up for you sizes remain independent. Requested grid density stays saved from one to eight columns, with temporary fitting limits for narrow windows.
- Adopted silver native Liquid Glass navigation on iOS/iPadOS 26. Bottom tabs remain accessible on iPad in portrait and landscape. Earlier supported systems use material styling for custom controls. Reduce Transparency uses opaque controls; Reduce Motion avoids animated poster selection.

## Completed validation

- Compiled the universal ARM64 Release app with Xcode 26.0.1 and the iOS 26.0 SDK. The minimum remains iOS/iPadOS 17. The IPA declares both iPhone and iPad families and all four iPad orientations, retaining the existing bundle identifier and build number 4.
- Inspected the delivered archive and IPA before the workspace disconnected. The ZIP is intact, the app executable is ARM64 and executable, signing is absent, and Debug-only preview launch arguments are excluded. IPA SHA-256: `feda96d82014c2a1da1413c539ddd014d2ea45cade8f3a4a8aedd826cc164905`. GitHub artifact ZIP SHA-256: `53a75926ef62acb109345939ab96935fe4e9b81bcf6301a83481652ecb54bef8`.
- Passed **30 offline core tests**, including missing-provider filter matching, verified versus estimated dub dates, inclusive rating thresholds, completed-library filtering, saved preferences and existing poster-fitting bounds. The optional captured-source test was skipped because captures are not bundled. Three live checks are gated during the offline step.
- Passed **all three separately executed live checks**: AniList public browsing, Anime News Network and English dub providers. Their actual passing results were checked even though the workflow permits that diagnostic step to tolerate temporary provider outages.
- Passed **all 10 native iPhone simulator UI cases**: all tabs/settings, dub/library/Completed/next-airing indicators, category filters, display options and density, library rating sorting, details and expanded artwork, schedule/date navigation and saved Dub selection, repeated category Back/edge-swipe returns with real pagination, featured-poster paging/expansion/return retention, and shared dub/rating/completed filters across search, categories and relaunch.
- Passed **all six native 11-inch iPad Pro simulator UI cases**: both new Explore feature cases, repeated list/grid category returns and real pagination, every tab and details/full-screen artwork in both orientations, independently enlarged Explore shelf/list/grid artwork, two-/three-/eight-column layouts, larger library and Coming up for you posters, and saved independent preferences across rotation and relaunch.
- The iPad Explore sizing case needed one test retry after a drag selected 411 points against the test's 420–480 point setup range. The retry passed the complete original growth, shrink, density, bounds, genre and persistence assertions. The initial failed attempt is retained in the result bundle. This run contains seven iPad test executions for six unique cases; the workflow concluded successfully.
- Reviewed **52 screenshots of the unchanged app implementation** before the workspace disconnected: 27 iPhone and 25 iPad images from [the earlier verification run](https://github.com/goon-123/AnimeCompanion/actions/runs/37319567520), including large featured artwork, silver tabs, saved filters, populated detail returns, wrapping genres, enlarged shelves/library posters, details, schedule and tablet rotation. Later changes concern only UI-test gestures and CI startup; the final simulator run also provides screenshots and result bundles.

## Retained behavior and verification scope

Category pages reuse loaded results and pagination for unchanged filters. Canceled or stale requests cannot overwrite the current selection, and explicit refresh replaces results after a successful response. The shared navigation case checks three detail-return cycles in each of List and Grid, retained scroll/filters/density/count, and another actual page before a further return.

Every reported genre remains visible in Explore and My Library grid cards and Explore shelf cards. Continue watching and mature-story browsing remain removed. Coming up for you remains in My Library. News retains multiple sources, optional thumbnails and clearly labeled on-device weekly/monthly reading-history popularity.

Native checks use iOS/iPadOS 26 simulators. Earlier OS material fallbacks, physical devices and actual multitasking windows are separate device checks; narrow-window fitting is covered by core tests. Preview library progress and the future release used for Coming up for you resizing are Debug-only fixtures, excluded from the device app. They do not authenticate or write to an AniList account.

The existing AniList implicit sign-in, callback validation and confirmed-server-write behavior remain unchanged. Personal-account sign-in, token persistence and actual library mutations require the signed device and its existing AniList client setup.

## CI and artifacts

Hosted iOS 26 simulators can stall at first boot. Startup is bounded separately. Spotlight indexing is disabled on the disposable runner, and a runtime-path-guarded watcher pauses known simulator wallpaper/background push processes and resumes them on cleanup. Push-delivery tests must run separately without that watcher. Every UI assertion remains enabled, and XCTest permits one retry while retaining both attempts.

The successful run provides AnimeCompanion-unsigned-IPA, AnimeCompanion-simulator-screenshots, AnimeCompanion-iPad-screenshots, AnimeCompanion-simulator-check and AnimeCompanion-iPad-simulator-check artifacts. Screenshot export also runs after a failure.

The local workspace disconnected during delivery, so the direct IPA attachment could not be saved. The validated GitHub artifact above is the delivery fallback. Repository source and this verification record remain available at [goon-123/AnimeCompanion](https://github.com/goon-123/AnimeCompanion).
