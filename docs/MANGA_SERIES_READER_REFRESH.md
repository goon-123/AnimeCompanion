# Manga series and reader refresh

Version 0.60.9 / build 144 builds on the Manga Explore consolidation from #86.

Read/Continue and Link to My Library are always directly below the source-series header. They cannot be moved below chapters or hidden by an older section layout. Optional synopsis, genres and chapter sections retain their saved relative order and visibility. The local bookmark is labelled Save series / Saved series to distinguish it from linking a MangaBaka account library entry. Removing a library link requires confirmation and keeps saved titles and reading progress.

The series page adds a chapter-progress summary, Read latest, separate play and read-status buttons, All/Unread/Read filtering, chapter-name/number search, newest-first sorting and Show current chapter. Long-press a chapter for Read from beginning, mark read/unread, mark read through this chapter, or share its web URL. Mark all/through read requires confirmation and uses one atomic storage update while preserving history and the resume selection. Placeholder scanlator values such as Unknown are omitted. Series options provide refresh, source website, source settings, sharing and section arrangement.

The continuous reader keeps its existing reusable image canvas, image retry, zoom, source session, progress saves and automatic chapter loading. Its bottom panel groups page jumping/scrubbing, previous/next chapter controls, auto-scroll and speed. Reader actions offer read from beginning (confirmed), mark read and advance, source website and chapter sharing. The chapter picker supports search, read-status filtering, resume details and Current. Opening reader sheets/page prompts pauses auto-scroll; page-jump/restart prompts also suspend automatic chapter advancement. Settings group Display, Chapter flow, Scrolling and Comfort. Large accessibility text uses stacked scrolling controls.

No reading-state schema, source-link schema or iCloud payload format changes. Bulk marks retain unselected positions, saved flags and history. Sharing only resolves HTTP(S) URLs/paths and excludes opaque IDs and credential-bearing URLs.

Device review: open an installed-source title without scrolling and check Link to My Library; link/change/remove a library entry; try chapter filters and confirm/cancel a bulk mark; resume and jump to a page; open/search Chapters and use Current; check that opening settings pauses scrolling; close/relaunch and verify the original series, source link and position remain available. Reader UI checks remain opt-in in the existing workflow.
