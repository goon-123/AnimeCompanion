# AnimeCompanion experience redesign

Version 0.34.0 · build 88

## Baseline and audit

The implementation starts from the exact merged build-87 commit `04eb6eb1194d14729905423c5a93698d6dd5b657`. Its full source tree was verified before editing. This matters because earlier `main` history lagged the feature branches: this redesign includes the saved MangaBaka accounts, content ratings, linked reading sources, discovery feed repairs, swipe Back, reader scrolling improvements and guided setup.

This is a source and interaction audit. Native screenshot review, compilation and regression results are recorded in the verification section; no on-device performance measurements are implied by source inspection.

| Area | Finding | Design response |
| --- | --- | --- |
| App navigation | Five destinations, a hidden reading tab, and multiple independent catalog entry points (`AnimeCompanionApp`, `AppTabPreferences`) | Home, Explore and My Library form the default phone navigation. Other areas remain available from Home, Explore tools, the iPad sidebar and navigation settings. Explicitly saved tab choices retain their visible order. |
| Home | Discovery doubled as the starting page; resuming required browsing library or source screens | A personal dashboard prioritizes continuing anime, saved reader positions, tracked manga/novels and the next broadcasts from the watchlist. Empty sections are omitted. |
| Explore | A large hero, mixed trending, large format cards and several repeated shelves preceded catalog controls (`UnifiedExploreView`) | Smaller spotlight, compact format links before the feed, fewer repeated titles and shorter headings. Advanced catalog tools remain in one menu. Classic and mixed-grid layouts remain supported. |
| Search | Unified search existed, but always requested both providers and offered no media scope (`UnifiedExploreSearchView`) | All stories, Anime, Manga and Novels scopes. Anime-only skips MangaBaka; reading scopes skip AniList. Novels apply the provider's format filter. Existing cancellation, independent errors and pagination remain. |
| Libraries | Layout, sorting, direction and content controls consumed separate rows (`CombinedLibraryView`, `MangaBakaLibraryView`) | Compact display controls, sort/direction/default choices in one menu, content ratings in the toolbar, shared status chips, and locally saved views. |
| Anime detail | Playback, progress, large countdowns and dub information competed before the synopsis | Retain the primary watch action, adaptation links and tracking. Put the synopsis earlier; expand airing/dub details when wanted. Episodes and deeper information remain available. |
| Manga/novel detail | A centered 180–240 pt phone cover and seven jump links displaced actions; galleries and related requests started immediately | Compact side-by-side phone hero with an accessible stacked fallback. Four direct jump links. Publication/ratings, artwork and related recommendations expand on demand. Anime mappings, tags, progress and official links remain reachable. |
| Playback | Direct streams and torrents already shared one filter area and secure provider workflows | Retain episode/audio/source controls and provider behavior. Use consistent surfaces and lazy results; no new source-selection heuristics or automatic playback. |
| Reader | Recent builds already addressed momentum, image arrivals, tiled rendering and progress saves | Preserve the canvas and persistence logic. Replace blurred control backgrounds with legible opaque surfaces; retain every reader setting and gesture. |
| Schedules | Native airing/weekly modes already distinguished original and English dub dates | Retain both modes, filters, timezone handling, unknown dates and catch-up semantics. Add Home and sidebar entry points with shared visual styling. |
| News | Existing personalization, saved stories, unread controls and original-article browsing were valuable | Keep the news experience and preferences; correct surface foregrounds for light appearance and expose News through the new navigation. |
| Accounts/settings | Provider setup and personalization occupied many rows on the same settings page | Searchable Settings, a reusable Sources & playback directory, and Appearance & layout. Search can find individual services directly. Existing account screens, switching and secure storage are reused. |
| Onboarding | The new optional, resumable setup wizard was already present | Keep its lifecycle, migration guard, skip options and provider steps. Harmonize colors and remove its forced dark appearance. |
| iPad | Full-width and browse/detail split layouts existed; no app-wide sidebar | Add a native sidebar with adaptive content. Keep explicit full-width and legacy side-by-side preferences, with single-column behavior in compact windows. |
| Visual language | Forced dark appearance, global rounded fonts, multiple palettes and glass controls | Native typography, semantic light/dark surfaces, a restrained violet accent, consistent panels and 44 pt controls. Artwork overlays retain their own legible contrast. |

## Design direction

Content leads. Covers are visible without overwhelming text or primary actions. A quiet violet accent identifies interaction; backgrounds and borders adapt to appearance. Native navigation, sheets, menus and system typography supply the structure. Custom effects never compete with scrolling or reading.

Shared implementations live in `ExperienceStyle`, `DetailComponents`, `Components` and the existing library controls. This is an update to the actual application, with no parallel prototype or replacement backend.

The navigation and search choices follow Apple's [sidebar guidance](https://developer.apple.com/design/human-interface-guidelines/sidebars), [search guidance](https://developer.apple.com/design/human-interface-guidelines/search-fields), [layout guidance](https://developer.apple.com/design/human-interface-guidelines/layout) and [accessibility guidance](https://developer.apple.com/design/human-interface-guidelines/accessibility). Custom disclosure transitions respect Reduce Motion. System navigation continues to handle its own platform motion.

## Added capabilities

- Home sections can be reordered and hidden without changing saved data. Home resumes anime through the existing Watch/VidHub flow and local manga through the existing saved chapter/page flow. Tracked MangaBaka books open native series details. Exact source links prevent duplicate local/tracked reading cards.
- Saved Library views store search text, status, sort, direction and list/grid layout locally. Up to twelve views can be named, recalled and removed. They do not modify account entries.
- Search scopes constrain provider work and result types while retaining the original all-catalog search.
- Appearance supports System, Light and Dark. iPad offers sidebar navigation, single-column pages and the retained browse/detail presentation.
- Source/settings search finds Stremio/AIOStreams, torrent extensions, TorBox, VidHub, Safari and reading extensions without inspecting credentials.

## Workflow changes

| Task | Route |
| --- | --- |
| Continue watching or reading | Home → Continue; the original Library and source routes also remain |
| Find all formats | Explore → search → scope, or the format links |
| Find a hidden section | Home shortcuts / Explore discovery tools / iPad sidebar More |
| Manage playback and reading integrations | Settings → Sources & playback, or search Settings for the service |
| Change appearance, Home, Explore or navigation | Settings → Appearance & layout; Home and Explore also retain their local customization buttons |
| Save a library filter | My Library → All → bookmark → Save current view |
| Inspect airing/dub details | Anime detail → Airing & English dubs, or the existing Schedule action |
| Inspect manga publication/artwork/related titles | Open the clearly labeled disclosure on the same series page |

For an installation with explicitly saved navigation settings, the new Home tab is initially hidden so its existing visible order remains intact. Home is still accessible from Explore's tools and can be enabled in navigation settings. New default navigation uses three tabs. Enabling every destination can use the system's More overflow on iPhone.

## Preserved integrations and data

| Capability | Preservation |
| --- | --- |
| AniList authentication, sync, status, ratings and episode tracking | Existing client, OAuth, Keychain and tracking store retained |
| MangaBaka multiple accounts, libraries, recommendations and progress | Existing credentials, account identities, generation guards, clients and mutation paths retained |
| Anime streaming, torrent extensions and Stremio/AIOStreams | Existing extension runtimes, add-on manifests, catalogs, audio filters, source selection and playback retained |
| TorBox | Existing account key, cloud-file workflows, torrent receipts and playback handoff retained |
| VidHub and Safari | Existing playback/resume integration, Safari handler and resources retained; extension version advances with the app |
| Manga source installation, settings, search and readers | Existing runtime, source configuration, linked sources, bookmarks, chapter/page progress and canvas retained |
| Novels | Discovery, scoped search, detail pages, adaptation links and MangaBaka tracking retained |
| News, schedules, recommendations | Existing data sources, personalization, filters, saved/read state and original article links retained |
| Explicit-content preferences | Existing independent AniList, MangaBaka rating and mature-source settings enforced at the same data/view boundaries |
| Customization and library tools | Existing stored keys, account switching, sorts, defaults, filters, grid/list and poster options retained; new preferences use separate namespaces |

No existing preference or progress file is reset in Release. No credential schema, source runtime, library storage or authentication migration is introduced. Debug-only resets isolate deterministic simulator fixtures. No server dependency is added.

## Performance and accessibility

- Home reads the existing local library/reader state and synchronizes the connected reading library through its existing guarded client. It does not fetch discovery feeds. Lists are bounded for the dashboard and use lazy/adaptive containers.
- Combined Library sorts once for each body evaluation, reusing the result for counts and rendering.
- Poster decode dimensions share bounded size buckets, increasing cache reuse during resizing and grid changes. The existing bitmap/byte budgets and memory-warning eviction remain.
- Reading cards use the existing entry dictionary instead of scanning the complete account library for every poster.
- Collapsed manga galleries and related sections defer their own requests until expanded. Existing response caches, request coalescing, cancellation and generation checks remain.
- Reader canvas, tile preparation, scroll momentum, bounded page windows, ProMotion handling and batched/immediate progress saves are untouched.
- Shared controls keep 44 pt minimum targets, semantic foregrounds, Dynamic Type and selected/expanded accessibility states. Disclosure motion respects Reduce Motion. Reader controls use an opaque dark surface independently of the chosen reading background.

These are implementation improvements; device frame-time, energy and memory profiling are still required before making quantified performance claims.

## Verification

- Baseline commit and full source tree verified before editing.
- Local whitespace/diff checks and simulator script syntax checks.
- Safari resource/version validation: 13 resources verified.
- New Core regressions cover Home normalization and persistence, legacy navigation preservation, saved-view validation/bounds/round-trip, scope routing and bounded image sizing.
- New iPhone/iPad journeys cover Home, light/dark and large text, hidden schedule access, source management, scoped search/native details, Home persistence and saved Library views.
- Existing journeys were updated to navigate the consolidated Settings and new compact series layout.
- Swift/Xcode are unavailable on the editing host. The repository's existing macOS Actions workflow is used for compilation, iPhone/iPad simulator execution and unsigned IPA packaging. Results must be recorded against the final commit before this is described as verified.

## Remaining work and rollout

The first implementation delivers the app-wide navigation, visual foundation, personal dashboard, search/library improvements and detail/settings consolidation together. Classic Explore and the older browse/detail iPad option remain supported rather than being duplicated or discarded.

After native validation, a follow-up device pass should measure large real libraries and long webtoons, check right-to-left and extreme text sizes, review provider-specific connection/error screens with live accounts, and tune the remaining artwork-heavy surfaces. More advanced recommendation ranking or offline downloads are separate product changes and are not implied by this redesign. The preserved recommendation and caching systems continue to work as before.
