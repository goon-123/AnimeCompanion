# Unified manga source search and optional progress updates

Version 0.61.0 / build 145 extends #87 with items 3 and 8 from the improvement list.

## One search query

Search stories now includes an Installed sources section in All stories and Manga, plus a Sources filter. Choose up to five enabled installed sources once; the selected IDs are saved and included in the existing portable/iCloud preferences. No sources are selected implicitly. The same title query searches those sources with debouncing, up to two concurrent source searches per query, independent error handling and generation/cancellation checks. Disabled, removed and hidden adult sources are excluded. Source matches show provider names and open the native series/reader flow; More results retains the query in the source browser. Catalog search/pagination and the separate contextual Find manga flow remain available.

## MangaBaka chapter progress

On an already-linked source series, open MangaBaka progress beneath the library link. The same control is in the reader's actions menu. Manual updates accept a completed chapter number. Automatic updates are off by default and require consent for that exact account, source and link revision on this device. Relinking/replacing a source requires new consent. Consent is not copied to another device through iCloud.

The reader reports actual completed chapters and explicit Mark read & next actions. Automatic candidates use clear whole chapter numbers and exclude extras, specials, fractional/part chapters, missing numbers and conflicts between names and source metadata. Ambiguous chapters can be updated manually. Enabling a target switches off automatic updates for other entries using that source/account. Automatic writes require exactly one opted-in target; ambiguous/corrupt multiple selections are skipped. Local bulk read-status changes do not perform account writes.

Updates verify the active account/session and current source link around asynchronous work, read the existing remote entry, and send a PATCH containing only `progress_chapter` when the proposed chapter exceeds the value just read. They do not create missing library entries, lower the value observed, or send status, ratings, notes, volumes, privacy or lists. Account switches and revoked/replaced links stop queued writes before dispatch. The API does not advertise a conditional/atomic maximum update, so simultaneous writers on other devices can still race between read and PATCH. Failures retain local progress and provide retry; pending automatic writes are coalesced in memory, not replayed as an unbounded background queue.

Contract checked against the official [OpenAPI specification](https://mangabaka.org/api.json), `PATCH /v1/my/library/{series_id}`, and [OAuth scope documentation](https://mangabaka.org/developers/concepts/oauth-scopes). Existing account authentication is reused. No real account writes are performed by the development checks.

Device review: search a title in Explore, choose sources, compare catalog/source matches, change the query, and open More results without retyping. On a linked source series, check manual progress first; enable automatic updates only for a source whose chapter numbering matches your MangaBaka title, then finish a chapter. Confirm the chapter changes while notes/rating/status stay unchanged. Test disconnecting/switching accounts and a failed update; local reading should continue.
