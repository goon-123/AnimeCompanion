# Build verification

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
