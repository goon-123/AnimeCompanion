# Series, episode cards and torrent sources — 0.44.0 (104)

## Home and calendar

- Weekly Schedule contains the calendar controls only. The existing Home **Airing Now · Catch up** shortcut opens its own destination.
- A single tracked title in Airing this week opens that anime. A day with several titles opens a poster chooser; choosing a poster opens that anime. The widget header arrow still opens the full calendar. Empty days show a brief empty state.
- Long-press a large banner widget, choose **Widget layout**, or use **Customize**. Small is a compact row, Medium emphasizes the cover, Large keeps cinematic artwork. This applies separately to both countdowns, seasonal spotlight, watchlist banners, next-season premieres, returning favorites, tonight's pick, hall of fame and headlines. Preview-item counts, visibility, order and iPad artwork size remain separate settings.
- Layout selections persist through relaunch, retain previous widget order/visibility/shortcut choices and default to the previous large design.

## Series and episodes

Anime details put the watchlist and episode cards near the top, with jump links to story, artwork, related titles and discussions. Manga/novel details use a larger cover header, reading controls and visible artwork/connections ahead of publication details. No disclosure controls hide those galleries. Existing tracking, reading source and chapter flows remain available.

Episode metadata is fetched without credentials from exact AniList mappings at ani.zip, with an exact MAL-ID Jikan fallback. The bounded public cache renders saved entries first, coalesces requests and retains saved metadata on refresh failure. Lists are paginated and reveal more rows on request. Canonical entry-local episode numbers exclude specials and guessed season offsets. Conflicting TVDB numbers suppress that record's still/overview; missing metadata uses a neutral thumbnail and episode number. The UI never invents titles, images, dates or plots. Source attribution appears under the list.

Watched state follows confirmed AniList cumulative progress. Watched thumbnails become desaturated with a checkmark, titles become subdued and Play becomes Replay. Starting an external player does not mark progress watched. Cards include available title, date, runtime, score, filler/recap and expandable synopsis, with search, watched filters and ordering. Announced future episodes do not enable playback.

## Seanime repairs

- The inert DOM adapter supports the documented callable `length()` and traversal methods used by torrent-table providers.
- Public GET metadata headers and response metadata are supported; native validation still rejects authentication, cookies, writes, private targets, unapproved hosts and redirects.
- Named/default TypeScript exports work. Malformed entries are reported without discarding valid siblings; all-invalid responses fail rather than looking empty.
- Native decoding accepts numeric strings and ignores empty hash/magnet fields. Different releases with empty hashes no longer share one identity.
- Provider workers, preferences, request bridges, result identities and failure states remain independent; up to two searches run concurrently. The picker is always visible when multiple providers are enabled. Each provider reports waiting, searching, result count, failure or cancellation separately.
- Background suspension preserves completed results and resumes only interrupted providers when the visible screen returns. Temporary inactive states do not cancel searches. Explicit cancellation and leaving the search do cancel it, and generations reject late callbacks.
- Reviewed inline source is stored once rather than duplicated inside the saved manifest. Updating a reviewed provider retains its ID, enabled/disabled state and matching preference values. Enable toggles edit the latest saved installation.

## Focused device checks

1. On iPad, use the existing Airing Now shortcut, return, then open Calendar. Confirm no Airing Now tab remains in Calendar.
2. Tap a one-title day and a multi-title day in Home. Verify the correct series opens and the multi-title picker dismisses.
3. Select all three layouts for both countdowns and another banner. Relaunch and rotate; confirm layout, order, visibility and item counts persist independently.
4. Open anime and manga/novel series in light/dark mode. Artwork and related/recommendation shelves should already be visible. Verify chapter/source links and tracking still work.
5. Open an anime with public episode metadata and one without. Check images/titles/date/synopsis when supplied, neutral fallbacks when absent, metadata attribution, watched/replay state, filters, pagination and offline cached reopen.
6. Install two trusted compatible providers with distinct configuration. Test individually and together; one failure must leave the other's results usable. Check the provider picker and status rows, audio filters, cancellation, background/return and saved configuration after relaunch.
7. If a provider reports a blocked hostname, review and approve that provider's intended public host in Configure. Unsupported Smart Search, browser-challenge or authenticated providers still report compatibility failures; this runtime is not the complete Seanime server.
8. Verify the selected torrent/episode/file through the existing native TorBox confirmation and playback flow. These changes do not submit torrents automatically.

Automated coverage adds canonical mapping/fallback/cache/coalescing cases, torrent normalization, public header validation, compact storage/reviewed updates and widget-layout migrations. The built-worker tests exercise two independent providers, including one failing alongside one succeeding. Normal CI runs Core, runtime contracts, Apple encrypted-cache checks and the universal Release build. The longer simulator suites remain opt-in as requested; live third-party provider availability and visual/device verification are separate from owned-fixture tests.
