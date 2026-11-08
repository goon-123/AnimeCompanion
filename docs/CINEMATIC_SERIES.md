# Cinematic series and transparent navigation — 0.49.0 (112)

Anime detail pages open with a larger edge-to-edge backdrop, cover and branded transparent title logo. Episodes is the initial tab; More Info contains information, related entries, artwork, news, reviews and links; You May Also Like has its own tab. Existing episode filters, default preferences, tracking/Undo, library state, source selection and all reading integrations remain in place.

## Artwork

- The client uses the public [Fribb ID map](https://github.com/Fribb/anime-lists) to resolve an exact AniList/MAL entry to one IMDb identity and the correct movie/series type.
- [Stremio Cinemeta](https://v3-cinemeta.strem.io/manifest.json) supplies `logo` and `background` through its documented [metadata contract](https://stremio.github.io/stremio-addon-sdk/api/responses/meta.html). This is an artwork integration; it does not install playback add-ons or replace TorBox.
- Missing artwork falls back to the exact AniList entry's ani.zip/TVDB Clearlogo and Fanart records, then the existing AniList banner/cover and native title. Failed image downloads also retain an AniList backdrop/title. No API keys are borrowed from another app and no user server is required.
- The old media-index endpoint referenced by Firefly returned 404 during research, so it is not a dependency. The implementation is native SwiftUI and uses the supplied screenshots as design references.
- Public metadata is coalesced and cached separately from account data; no account tokens or cookies are sent to these providers. Missing/ambiguous mappings and mismatched MAL/type/IMDb records cannot attach another title's artwork. Saved artwork remains available when a refresh fails.

## Series controls

- The Trailer button opens the official trailer in a native in-app browser only after a tap. It never searches for an anime episode and never starts during page loading.
- Watch Now uses the existing progress/resume-aware `WatchAnimeView` episode and source dialog. The adjacent plus/check opens the full status/progress editor. Saved state changes only through the existing confirmed tracking flow.
- The countdown appears only for a releasing/upcoming entry with a future announced episode time. Finished entries and elapsed timestamps have no countdown. Dates use device local time; seconds are updated only within the countdown view.
- Character portraits come from the series' AniList character connection. The floating left comment button opens Series Reviews / Episode Comments, preserving existing native comment readers, source controls and spoiler handling.
- Header sections retain existing visibility controls. More Info sections retain their saved order. Characters is a new independently hideable section.

## Explore and glass controls

- Trending is a numbered top-ten poster row with independent plus/check controls and a full catalog destination. Existing hidden Trending preferences still apply.
- The same Top 10 Trending widget is available in Home's Add widgets picker, initially hidden for existing layouts, and can also be added independently to Explore.
- Animation Studios uses a single batched AniList query for live studio names and representative non-adult covers. Cards open the existing paginated studio catalog.
- Anime Genres uses current public catalog artwork and opens the full genre-filtered catalog without a season restriction.
- All three rows can be hidden, restored and reordered in Customize Explore for Classic Anime, Discovery and the poster grid. Existing saved layouts and Home widgets are preserved; Home settings are independent.
- Floating format/search/filter controls use ultra-thin material instead of an opaque fill; the native bottom tab dock uses a translucent material. The system's Reduce Transparency accessibility setting retains a solid readable surface.

## Focused device acceptance

1. Scroll artwork behind the format/filter controls and bottom dock; content should show through their material.
2. Open a mapped series such as The Irregular at Magic High School. Check branded title/backdrop, then a title with no artwork mapping for the native fallback.
3. Tap Trailer, dismiss it, then tap Watch Now: only Watch Now should open episode/source selection, initialized from saved progress.
4. Open the plus/check status editor, save a status/progress change and revisit the entry. Check an airing entry's countdown and a finished entry's absence of a countdown.
5. Scroll to Episodes / More Info / You May Also Like; use the floating comments button to switch between reviews and episode comments.
6. Open Studio and Genre collections. Hide/reorder the new rows, relaunch and verify persistence on iPhone and iPad.

Validation: local whitespace and Safari resource/version checks; focused artwork identity, fallback/cache, studio batch and preference migration tests are included in Core CI. The Release workflow compiles and packages a universal iPhone/iPad IPA. Longer simulator suites remain opt-in.
