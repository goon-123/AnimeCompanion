# Explore widgets and series links — 0.48.1 (111)

0.48.1 fixes two regressions from 0.48.0. The Add a Home widget and Customize shortcuts actions use explicit button-driven navigation, so native List reorder mode cannot disable them; their destination pages use normal non-editing controls. When Spotlight leads Classic Anime, its artwork once again extends to the top behind the format controls. Empty catalog notices no longer reserve a row of spacing. When Spotlight is hidden, moved below another row or preceded by an actual notice, normal content stays clear of the fixed header. Saved widget choices and row order are preserved.

Explore now has a visible Customize control. Choose **Add a Home widget**, then return to the row list and drag its handle between catalog shelves. Toggle any row or added widget off, or use its context menu to move it up/down or hide it. Restore Explore layout returns that layout to its catalog defaults. Hide all retains the customization entry point.

Discovery shelves, Mixed poster grid, Classic Anime and Classic Manga/Novels each save their own order and widget options. Adding copies that widget's current Home layout, preview size and shortcut choices; subsequent edits stay local to Explore. Home's saved layout is never written. All Home widgets use the same rendering components and account stores on both pages. iPad widget artwork uses the existing adaptive Home metrics, with narrow panes fitting their measured width.

Anime discovery adds **Previous season** (relative to the selected season, including Winter → Fall of the preceding year) and **Top anime of all time** (AniList scores without a season limit). Both are horizontal shelves with full paginated See all routes. Original adult/dub/score/completed filters still apply. New Explore snapshots use cache version 2 so an older three-shelf snapshot cannot suppress these rows after upgrading. Widgets remain available even if the anime catalog fails to load.

Information keeps its compact Aired/Dubbed/Watched counts. Dubbed now has an accent background, a **Dub schedule** label and a chevron. It opens the existing English dub schedule. Each studio name has a chevron and opens a native, paginated studio anime page with Popular, Top rated and Newest sorting. Studio results use AniList's documented `Studio.media` relationship, then enforce anime/adult visibility locally because that relationship has no adult argument. A filtered page with more results retains Load more.

The large separate discussion card is replaced with a single compact **Discussions** link in the Reviews header. It opens the existing discussion page and preserves its watched-episode starting point and episode/source controls. The layout editor calls the merged section **Reviews & discussions**. Old section orders migrate to one merged position; it remains visible if either old section was visible, and remains hidden if both were hidden.

Focused verification covers mixed row/widget persistence, hidden rows, independent Home options and shortcuts, malformed preferences, season rollover, all-time filters, new query variables, studio identity/pagination/content filtering and merged discussion visibility. Two offline iPhone UI regressions exercise adding a widget and editing its shortcuts while reorder handles are active, persistence after relaunch, the Spotlight top edge, and the safe header position with Spotlight hidden. CI checks the three new live AniList routes and builds the universal Release IPA. Longer simulator suites remain opt-in.

## Quick device checks

1. In Explore, open Customize → Add a Home widget. Add Airing this week or Headlines. Return, drag it above Trending, hide another row and reopen the app. Confirm the arrangement persists and Home's arrangement stays the same.
2. Open Previous season → See all; verify its season/year. Open Top anime of all time → See all; verify there is no season/year restriction. Repeat in Classic Anime if you use that layout.
3. Try the same widget on an iPhone and iPad (including narrow Split View). Tap an Airing this week title; it should open its anime in the current tab/presentation after the day chooser closes.
4. On an anime's Info page, tap the visibly accented Dub schedule count. Go back and tap a studio; sort its anime and load more, then open a title and return normally.
5. Find Reviews. Confirm there is only one compact Discussions link, that it opens the discussion page, and that the merged section can be moved/hidden with Arrange sections.

API references: [Studio](https://github.com/AniList/docs/blob/master/docs/reference/object/studio.md), [MediaConnection](https://github.com/AniList/docs/blob/master/docs/reference/object/mediaconnection.md).
