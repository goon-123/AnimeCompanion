# Series details, visibility and episode actions — 0.47.0 (109)

Anime retains Info and Episodes. The Read tab, character/staff rows and their
unused detail-query fields are removed. Find manga/manhwa remains in the
series options menu, and related written entries retain their destinations.

## Layout and visibility

Use the toolbar up/down arrows (Arrange sections) on anime, manga/novel and
source-reader detail pages. Drag row handles to reorder; switch rows off to
hide sections. Show all preserves the chosen order, Hide all is supported, and
Restore default layout restores order and visibility. All-hidden pages keep
their header and toolbar, with a recovery message rather than a blank screen.

The three page types have independent, device-local preferences shared across
their titles. Original array-only orders migrate to the order/visibility
snapshot. Unknown/removed and cross-page values are ignored; new sections
append without discarding existing choices. Empty sections are skipped without
forgetting their position. Manga jump links follow visible sections.

The compact watchlist card retains its design, Edit, +1, Play/Resume, confirmed
saves and Undo in Info, where it can be arranged or hidden. It scrolls naturally
and is absent from Episodes. Neither the card nor tab picker is pinned. There
is no floating edit overlay.

Related/recommendation posters remain 128 points on a normal iPhone and 200
on a roomy iPad, with narrow-window adaptation. Reading positions, chapter
filters, source links, account handling and content settings are preserved.

## Episodes

Unwatched is the initial default. Episode filters has two distinct choices:
Show episodes changes the current visit; Default on opening saves All,
Unwatched or Watched for future visits (and applies the chosen default now).

Touch and hold an aired episode for the native context menu. Mark watched
updates progress through that episode; Mark unwatched sets progress to N-1
and therefore also unmarks later episodes. The menu states the resulting
progress before selection. Completed entries return to Watching when reduced;
paused/dropped/rewatching status is preserved otherwise. Rating, notes and
rewatch count are not overwritten. Writes remain server-confirmed, failures
retain prior progress, and compact save feedback/Undo stays available.

Watched rows keep normal colors, artwork and text; the checkmark is their only
persistent watched styling. Remove inline watched-toggle buttons. Playback
remains one tap, and future rows cannot play or mutate progress.

The main list shows aired episodes. Unaired rows are collapsed behind actual
next-release information and expand on request. Original broadcast evidence
takes precedence over dub dates or metadata reruns; no weekly dates are
invented. Number-only rows fill confirmed aired gaps in paginated metadata,
so a long series still shows the next unwatched episode. Unknown release
counts do not turn unloaded planned rows into confirmed releases. Metadata
pagination remains available independently of Show more rows.

## Information, broadcast and news

Information keeps its existing layout and Aired / Dubbed / Watched counts.
The Dubbed field is a plain navigation link to a dedicated English dub page,
with the existing release history, dates and sources expanded. This replaces
the separate English dub section in Info. Pull to refresh and the weekly
schedule remain available on that page.

Original broadcast is shown only for AniList RELEASING titles. Finished,
not-yet-released, cancelled, hiatus and unknown-status titles omit the widget.

Replace the old schedule/visuals/headlines shortcut strip with a compact Series
news shelf. It scrolls horizontally through all available matching headlines
from the existing recent feeds plus title-specific archive, newest first,
deduplicated and honoring publisher/muted-keyword preferences. There is no
artificial preview cutoff and no unrelated-story fallback. Stories open in
the existing in-app publisher browser and update shared reading history;
saving/sharing is available in the context menu. View all opens the full series
news feed. Cached stories survive refresh failures, and partial/stale responses
show a retry notice. No new providers or full-article scraping are introduced.
The redundant Visuals shortcut is removed; inline artwork and its full-gallery
control remain.

## Focused device checks

1. Arrange sections: hide Synopsis and Artwork, move another row, close and
   relaunch. Order/visibility should persist. Check Show all preserves the
   order; Hide all leaves a recovery path; Restore default layout resets both.
   Repeat on manga/novel and reader pages to check independent settings.
2. Episodes opens at Unwatched with no watchlist card. Use Show episodes to
   temporarily choose All, then set Default on opening to Watched and reopen.
   Long-press rows to mark watched/unwatched; check confirmed progress and Undo.
   Unwatching N also changes later rows, as stated in the menu.
3. Watched episode stills should keep full color and normal contrast, with a
   checkmark. Confirm upcoming rows remain collapsed and cannot be marked or
   played. For a long series, confirm the next unwatched number is available
   even before all metadata pages have loaded.
4. In Info, tap Dubbed: open English dub with its history expanded, then return
   using Back/swipe. The original broadcast widget should appear only on
   currently releasing titles, not finished or upcoming shows.
5. Swipe the Series news shelf, open a story, save one, and use View all. Check
   the story appears in shared history/saved news and publisher preferences are
   honored. Hide the news section and confirm its shelf disappears. Artwork
   should remain accessible without the old Visuals chip.

Core regressions cover legacy visibility migration, hidden/moved sections,
defaults, cumulative unwatched edits, broadcast status and paginated episode
gaps. Existing optional UI expectations follow the new routes. The normal
workflow checks Core/runtime contracts and compiles the universal Release IPA;
longer simulator journeys remain opt-in.
