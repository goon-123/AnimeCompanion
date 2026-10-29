# Integrated Community — 0.40.0 (99)

Built on `codex/home-schedule-news-hub` / PR #68, preserving the combined Home, Calendar and News work. No new server, social account, scraping proxy, or synthetic discussion data.

## Provider behavior and access

| Source | Reader shipped | Actual content | Access requirements |
| --- | --- | --- | --- |
| AniList | Native SwiftUI | Thread body, paginated comments, nested replies from the `childComments` JSON scalar, users, dates and likes | Public GraphQL queries; no additional user sign-in. Shares the app’s existing AniList client, request queue, response cache and 429 cooldown. |
| Reddit r/anime | Official site in `SFSafariViewController` | Official live feed/search, threads, comments and replies in the browser | Native data access requires Reddit approval plus registered OAuth. No Reddit API credentials/approval are configured here. The official page may require a Reddit login. |
| MyAnimeList | Official browser by default; native SwiftUI adapter with a registered client ID | Official v2 topic posts, authors, dates and offset pagination | Add your registered client ID in Settings → Community sources, or provide `MyAnimeListClientID` in the build configuration. No user sign-in for public reads. Live credential acceptance has not been checked. |

MAL’s API exposes chronological posts, including quoted responses, rather than a structured nested reply tree. The reader preserves quote text and does not invent parent relationships, scores, or unsupported sorting. AniList supports oldest/newest comment order and active/newest/most-replied thread order. Posting is available through original pages; there is no native posting mutation or voting flow in this change.

## Capability and terms research (October 29, 2026)

- AniList’s [official Thread reference](https://docs.anilist.co/reference/object/thread), [ThreadComment reference](https://github.com/AniList/docs/blob/master/docs/reference/object/threadcomment.md), [Page reference](https://docs.anilist.co/reference/object/page) and [comment sort enum](https://github.com/AniList/docs/blob/master/docs/reference/enum/threadcommentsort.md) confirm actual comment bodies and raw JSON child replies. The raw scalar is queried without a sub-selection.
- AniList’s [API terms](https://docs.anilist.co/guide/terms-of-use) apply to the existing complementary/synced integration, prohibit mass collection and backup/storage uses, and have commercial licensing conditions. No broad collection or new content persistence is added here.
- Reddit’s [Responsible Builder Policy](https://support.reddithelp.com/hc/en-us/articles/42728983564564-Responsible-Builder-Policy), [Data API Wiki](https://support.reddithelp.com/hc/en-us/articles/16160319875092-Reddit-Data-API-Wiki), and [Data API terms](https://redditinc.com/policies/data-api-terms) require authorized API access and registered OAuth. Unauthenticated `.json`, RSS extraction, mirrors and scraping are not used as workarounds. Browser routes point directly to `www.reddit.com/r/anime/`.
- MAL’s official [API reference](https://myanimelist.net/apiconfig/references/api/v2), [registration](https://myanimelist.net/apiconfig) and [API agreement](https://myanimelist.net/static/apiagreement.html) could not be retrieved by the research environment. **Current MAL license wording could not be independently verified.** Review it when registering/enabling the client, particularly before distribution or monetization. The adapter is disabled without a supplied registered ID and never borrows another app’s credentials.
- MAL’s `GET /forum/topics` and `GET /forum/topic/{id}` request/response shapes were corroborated against the [AtiinLabs Swift SDK’s original forum models](https://github.com/AtiinLabs/mal-sdk/blob/main/Sources/mal/Models/Forum.swift) and [requests](https://github.com/AtiinLabs/mal-sdk/blob/main/Sources/mal/Requests/UserAndForumRequests.swift). This confirms post bodies rather than a titles-only endpoint; it is not a substitute for MAL’s license review or live credential validation.

Related GitHub projects researched: [TheEnigmaBlade/holo](https://github.com/TheEnigmaBlade/holo) demonstrates explicit internal/display episode mapping; [Grinv/anilist-mcp-server](https://github.com/Grinv/anilist-mcp-server/blob/main/src/clients/anilist/thread.ts) confirms raw JSON nested replies and checking that a thread exists rather than treating a missing thread as an empty success; [AtiinLabs/mal-sdk](https://github.com/AtiinLabs/mal-sdk) corroborates MAL’s chronological forum-post API. The implementation is original; these are research references, not added dependencies. An older Hayase forum example was unavailable and was not used.

## Navigation and matching

- Home has a compact, reorderable/hideable Community widget with live AniList thread titles, activity/count metadata, four feed filters and prominent r/anime access. Home pull-to-refresh refreshes it. A Community shortcut is also available in the Home shortcuts section.
- Community has General Anime, This Season, My Shows and Episode Discussions filters. Seasonal/library scopes batch up to eight exact AniList media IDs per request, cycling through batches before older pages. More seasonal titles can be loaded explicitly. Reddit and MAL scopes let the user choose a series rather than claiming an unverified cross-series match.
- Anime details have a Discussions section, a series route and a latest-watched episode route. Find Streams has a visible Discuss Episode action. Calendar list and grid entries expose Discuss Episode through long-press and VoiceOver actions, retaining the existing poster appearance and primary series tap.
- Episode selection defaults to the latest episode actually marked watched on AniList. With no marked progress it starts at general series conversations. Episode and series modes, direct number entry and stepping remain available.
- AniList episode matches require exactly one anime category with the current media ID and one explicit matching episode number. Different seasons, missing IDs, ranges, specials and ambiguous numbering are not silently substituted. Title/episode identity is checked again before displaying newly fetched comments.
- MAL topic searches do not return an authoritative anime association. English/Romaji/preferred names and synonyms are offered, full season/cour names are retained, and episode results require an exact normalized title prefix plus episode number. Reading additionally requires an explicit identity confirmation. Unmatched general search results remain visibly unverified.
- Community numbering can be adjusted explicitly per provider and series. The saved offset and mapped episode are displayed; there is no inferred season/cour offset. Reddit search results are always browser searches, never advertised as exact verified matches.
- No body previews appear in feeds. Unwatched/unknown episode titles are replaced with neutral labels; opening posts and comments are gated before any comment request. Provider website previews follow that website’s spoiler behavior, which is stated before browser entry. Native spoilers support AniList, BBCode, HTML spoiler containers and Reddit-style delimiters; malformed delimiters hide the whole comment.

MAL uses an ephemeral URL session and bounded five-minute memory cache. Its credential stays in Keychain; only layout choices and explicit numbering offsets are saved by the new UI. Pagination URLs from MAL are not followed: requests reconstruct the next offset on the official API host. Loading, 401/403/404/429, removed threads, empty results, cancellation and source/episode changes have explicit handling.

## Short device checklist

1. Open Home → Community; try all four filters, then reorder/hide the widget in Customize Home. Existing Calendar and News should still open normally.
2. On AniList, open an active real thread. Expand multiple reply levels, reveal/hide a spoiler, switch oldest/newest, load another comment page and open the original.
3. Set a show’s watched progress to 3. Its Discussions action should start at episode 3. Select episode 4: its preview stays hidden and the reader asks before loading comments.
4. Compare two seasons with restarted episode numbering. The wrong season/episode should not appear. Try a known numbering offset and verify its displayed mapping survives reopening the app.
5. Open Find Streams → Discuss Episode; long-press Calendar entries in list and grid. Both should select the exact chosen episode and support Back/Done.
6. Select Reddit and browse a real r/anime thread/replies inside Safari. Check the full season name and episode in browser search results; any Reddit login is handled by Reddit.
7. With no MAL ID, confirm the official-browser fallback. Add your registered ID in Community sources, confirm a series/episode match, then read actual chronological posts and load more. A bad ID should show an access error and an original-page option.
8. Switch sources/episodes quickly and try refreshing offline. Old requests should not replace the current context, and failures should not create fake discussions.

## Checks

Focused source/whitespace, version and YAML checks only; no simulator runs, interactive app testing or live credential tests were requested or run. Added focused Core regression cases for exact episode identity, explicit offsets, spoiler isolation, raw AniList reply decoding, missing threads, public/no-token requests, official MAL host pagination and Reddit fallback URLs. Updated the existing Home migration expectations for the new optional section. Hosted build/check status belongs to the PR; do not treat source checks as device validation.
