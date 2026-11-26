# Manga reading inside Explore

Version 0.60.8 / build 143 consolidates the previous Manga tab into Explore. The existing MangaBaka discovery layout is retained, with a small **Your reading** row beneath Spotlight containing **Installed sources** and **Saved series**. The row can be rearranged/hidden through the existing Explore customization. Explore's menu keeps both destinations reachable even with all rows hidden; alternate discovery/grid designs also include the row.

Installed sources opens the existing native source browser with all languages initially visible, pinned/recent source groups, source search and Manage sources. Saved series opens the existing local collection and Continue Reading; its menu retains reading history and the confirmed Clear History action. These titles are distinct from the account-backed My Library. The storage formats, reading positions, source links and iCloud payloads are unchanged.

The two tile counts load local stores only: opening Explore does not refresh the extension catalog or search installed providers. Counts respect the existing manga content preferences. Disabled sources are excluded from the available-source count.

Older tab preferences map Manga to Explore, remove the duplicate destination and retain a visible reading entry if Manga had been enabled while Explore was hidden. Old shortcuts, Find manga actions and linked-source resumes now open the written Explore stack. A deliberately hidden Explore still supports the existing supplementary-sheet fallback.

The classic Manga/Anime switch renders its glass as a non-hit-testing background so the real button owns the full rectangular target, including the corners that failed the previous UI check. Back navigation and iPad reading pages use the shared Explore stack.

Device review: open Explore → Manga & Novels, try both tiles and Back, open a source/title and resume a chapter, inspect Reading history, and check Manage sources. Existing saved stories should appear without importing them. Try the header switch's corners and confirm it switches catalogs without opening the poster beneath it.
