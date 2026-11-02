# Series page arrangement — 0.46.0 (108)

Anime retains Info and Episodes. Remove the Read tab, the floating pencil,
and the character/staff sections, including their unused detail-query fields.
Find manga/manhwa remains in the series options menu. Related written entries
still open their existing MangaBaka destinations.

The compact tracking card retains Edit, +1, Play/Resume, server-confirmed saves
and Undo. It is now ordinary scrolling content, including on Episodes. Info
also allows moving it with the other sections. Neither the card nor tab picker
is pinned, and there is no floating action overlay.

Use the toolbar's up/down arrows (Arrange sections) on anime, manga/novel and
source-reader detail pages. Drag row handles; changes save immediately on this
device. Restore default order resets that page type. The three page types have
separate preferences, shared across their titles. Empty sections are skipped
without forgetting their position; unknown/removed entries and malformed old
preferences recover safely, while newly introduced sections append.

Anime Info can arrange progress, synopsis, information, original broadcast,
related entries, recommendations, dub information, news, discussions, reviews,
artwork, trailer and links. Manga/novel pages can arrange library progress,
reading source, story, publication/ratings, tags, related anime, chapter
coverage, recommendations, covers and links. Reader pages can arrange resume,
synopsis, chapters, genres and source/library linking. Manga jump links follow
the saved section order. Library status, account handling, source links and
reading positions are unchanged.

Related/recommendation posters use a measured window width: 128 points on a
normal iPhone, 200 on a roomy iPad (preserving the anime detail iPad size), and
smaller in narrow windows. Manga recommendation shelves share these metrics.

## Episodes

The main list shows released episodes. Unaired episodes live in a collapsed
next-release card; expand to inspect them, with bounded Show more controls.
Use an actual AniList next-airing timestamp where present, otherwise a listed
future episode date. Never invent a date or weekly recurrence. Original
broadcast counts take precedence over metadata rerun dates or dub availability.
Undated episodes with unknown broadcast counts stay available rather than
being guessed unaired. Upcoming rows disable playback and watched actions.
A minute-based update moves the confirmed next episode into the released list
when its airing time passes; it does not infer later broadcasts.

## Validation and device checks

Core regressions cover saved orders, independent page keys, invalid/legacy
settings, multi-row moves, artwork sizing and evidence-based release grouping.
The normal workflow compiles the universal Release IPA and checks the existing
core/runtime contracts. Longer simulator journeys remain opt-in.

1. Open anime Info: only Info/Episodes tabs; no floating pencil or people rows.
   Scroll down and confirm the progress card scrolls away. Edit through the
   card or toolbar; +1, save feedback, Undo and playback should still work.
2. Tap the toolbar up/down arrows. Drag Synopsis above progress, then move
   Related higher. Done, revisit another anime, and relaunch: keep that order.
   Restore default order and confirm it resets.
3. On a manga/novel series, arrange Story, Reading source and Publication to
   taste. Its order should persist independently of anime; jump links should
   follow it. On a reading-source title, move Chapters before Synopsis and
   confirm saved reading progress, source links and chapter filters still work.
4. Compare related/recommended cards on iPhone and iPad, then rotate or resize
   an iPad window. Check poster proportions, title wrapping and title taps.
5. Open Episodes for an airing show: unaired rows should be collapsed beneath
   the actual next date. Expand/collapse; upcoming play/watched controls stay
   disabled. Finished shows retain their aired episodes; no dates are guessed
   for unavailable schedules.
