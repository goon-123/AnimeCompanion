# Compact series pages — 0.45.0 (106)

The anime header uses a smaller banner, cover and title while keeping the existing theme and image expansion. A pinned watchlist strip contains status, confirmed watched progress, +1 and Resume/Play. Its status/progress area opens the editor; the floating pencil opens that editor in one tap as well. Score, status, episode count, notes, rewatches and removal remain in the existing editor. Save feedback and Undo remain available. The overflow menu and a long press on the pencil retain secondary actions.

The pinned section picker has three tabs:

- **Info:** synopsis with Read more, information and compact aired/dubbed/watched counts, original broadcast, related titles, characters, staff, recommendations, visible artwork, trailer, dub details, schedule/news/gallery links, discussions, reviews and external links.
- **Episodes:** existing cached episode metadata, images, search/filters, Play/Replay and watched controls. Tapping an unwatched episode's check marks cumulative AniList progress through that episode. Tapping an already-watched check opens the editor; it does not rewind later episodes. Totals and auto-complete/rewatch preferences remain enforced, rating/notes are not overwritten, and progress updates only after server confirmation. Starting playback does not mark watched automatically.
- **Read:** source manga/novels and other written adaptations from the anime's relations, prioritized by source relationship. Exact written-media AniList IDs resolve MangaBaka listings; the anime ID and title similarity are never treated as proof of a match. Comic listings reuse linked reading sources, Continue reading and Chapters. Novel listings link to their series details/publisher links. Manual reading-source and MangaBaka search remain available when metadata has no match. Content filters and account-scoped source links are retained.

Only the selected tab is mounted. Existing public caches provide fast returns to episode/reading metadata; switching tabs alone does not repeatedly force a refresh after a previous pull-to-refresh. Tabs use buttons rather than a horizontal page gesture, preserving native edge-swipe back. Content has bottom clearance for the floating pencil and adapts to larger text and iPad windows.

## Focused device checks

1. Open anime details. Confirm Info is selected, the header is shorter, and the watchlist strip/section picker remain reachable while scrolling.
2. Tap the floating pencil and progress/status strip. Edit or cancel; check +1 and Undo, including saving/network-error states. Confirm score and notes are retained.
3. Switch to Episodes, play a chosen episode and mark an unwatched episode through its check button. Verify earlier entries dim after confirmation and already-watched checks open the editor.
4. Switch to Read for an anime with linked written media. Open the manga/novel, test an existing linked source or search installed sources, and verify chapter progress/reader navigation. Titles with no match should offer manual search without invented associations.
5. Check Info artwork, related/recommended cards, full synopsis, broadcast/dub information and native swipe-back in iPhone portrait, iPad landscape/narrow windows and larger text.

Core regressions cover cumulative tracking, duplicate/older selections, auto-completion and rewatches, invalid totals and exact written-media selection. Existing native navigation expectations are updated; longer simulator runs remain opt-in under the user's preference.
