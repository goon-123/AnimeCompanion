# Unified manga source search and optional progress updates

Version 0.61.0 / build 145 extends #87 with items 3 and 8 from the improvement list.

## One search query

Search stories includes an Installed sources preview in All stories and Manga, plus a Sources filter with grouped cover rows. Version 0.61.1 / build 146 searches all enabled installed sources by default, replacing the former five-source choice. Only pinned sources uses the existing source pins; the toggle is remembered and included in portable/iCloud preferences. The previous source-selection preference remains readable for older backups but no longer limits searches.

The same grouped search is used by Find a reading source from a series, prefilled with its title and alternative names. Selecting a cover preserves the MangaBaka library-link target. Source arrows open the complete source browser with the query and link target intact.

Queries debounce for 500 ms. The scheduler submits at most two source requests at once, streams completed first pages independently, deduplicates source IDs and result URLs, and distinguishes waiting, searching, empty and failed sources. The existing native interpreter retains its serial execution queue and timeout/cancellation handling. This change does not alter interpreter threading. A failure does not stop the remaining sources; open that source to retry or verify its website session. Refresh searches again. Query changes, clearing, source changes and leaving the screen cancel prior work; cancellation/generation checks discard late results. Disabled, removed and hidden adult sources are excluded using existing content preferences. No AnymeX components are restored.

The full list uses lazy source sections and horizontal cover rows. All stories/Manga retain compact interleaved previews with See all to avoid filling catalog searches with empty source sections. With no enabled pinned sources, pinned-only search shows a clear empty state and an action to search all installed sources instead.

## MangaBaka chapter progress

On an already-linked source series, open MangaBaka progress beneath the library link. The same control is in the reader's actions menu. Manual updates accept a completed chapter number. Automatic updates are off by default and require consent for that exact account, source and link revision on this device. Relinking/replacing a source requires new consent. Consent is not copied to another device through iCloud.

The reader reports actual completed chapters and explicit Mark read & next actions. Automatic candidates use clear whole chapter numbers and exclude extras, specials, fractional/part chapters, missing numbers and conflicts between names and source metadata. Ambiguous chapters can be updated manually. Enabling a target switches off automatic updates for other entries using that source/account. Automatic writes require exactly one opted-in target; ambiguous/corrupt multiple selections are skipped. Local bulk read-status changes do not perform account writes.

Updates verify the active account/session and current source link around asynchronous work, read the existing remote entry, and send a PATCH containing only `progress_chapter` when the proposed chapter exceeds the value just read. They do not create missing library entries, lower the value observed, or send status, ratings, notes, volumes, privacy or lists. Account switches and revoked/replaced links stop queued writes before dispatch. The API does not advertise a conditional/atomic maximum update, so simultaneous writers on other devices can still race between read and PATCH. Failures retain local progress and provide retry; pending automatic writes are coalesced in memory, not replayed as an unbounded background queue.

Contract checked against the official [OpenAPI specification](https://mangabaka.org/api.json), `PATCH /v1/my/library/{series_id}`, and [OAuth scope documentation](https://mangabaka.org/developers/concepts/oauth-scopes). Existing account authentication is reused. No real account writes are performed by the development checks.

Device review: search a title in Explore, open Sources/See all, and compare the grouped cover rows. Toggle Only pinned sources; pin or unpin a source and confirm the same pins appear in Installed sources. Change or clear the query during loading, refresh, and open a source arrow without retyping. From a MangaBaka series, use Find a reading source, select a cover directly and verify Link to My Library still targets that series. Source availability and website verification require device review. On a linked source series, check manual progress first; enable automatic updates only for a source whose chapter numbering matches your MangaBaka title, then finish a chapter. Confirm the chapter changes while notes/rating/status stay unchanged. Test disconnecting/switching accounts and a failed update; local reading should continue.
