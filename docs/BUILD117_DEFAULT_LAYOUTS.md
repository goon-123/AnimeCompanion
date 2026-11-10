# Build 117 — Clean defaults and simpler Community

Home and Explore use the original presentation. The cinematic screen variants,
their appearance settings and the cinematic Home Spotlight are removed. Cinematic
anime and MangaBaka series pages remain, together with the existing series-style
choice and independently disabled AniList artwork fallbacks.

Home's toolbar explicitly uses the same semantic background as its scroll content.
Home has only Customize and Settings in its options menu. Classic Explore keeps
Search, Customize and Settings; the other layouts already have their search field.
Explore layout choices, seasons, filters and poster options are under Settings →
Appearance & layout → Explore settings. The Classic layout has one small button
that switches Anime / Manga & Novels, rather than the large category pill.

## Shipped Home layout

1. Greeting & date
2. Search
3. Quick access: Calendar / Catch up / News
4. Welcome & setup
5. Library sync status
6. Airing this week
7. Headlines
8. Community
9. Continue watching
10. Continue reading
11. Up next
12. Your companion

Welcome and sync status continue to appear only when relevant. Catch up opens
confirmed aired episodes behind your AniList progress, rather than Airing Now.
Old stock shortcut slots migrate; custom shortcuts and hidden sections stay saved.

## Shipped Anime layout

Spotlight → Trending → Popular this season → Previous season → Top anime of all
time → Next season countdown (Large / Banner) → Coming soon.

Classic sections is the default Explore layout. Existing explicit design choices
stay saved. Fresh installs and Restore layout use this preset; an untouched stock
Anime arrangement upgrades automatically. Custom arrangements stay saved.
Top 10, studios and genres remain optional rows with independent visibility/sizes.

Spotlight keeps its previous portrait layout and controls, and resolves a transparent
series logo through the existing cached Stremio/Cinemeta artwork client. Only the
selected title requests matched artwork. If unavailable or offline, its readable
title remains. Wide layouts can use the matched backdrop.

## Community

- AniList is the only native discussion provider. Its feed and Home widget expose
  This Season and My Shows. Existing series/episode comment reading, spoiler gates,
  identity checks, episode numbering, paging and replies remain.
- Reddit and MyAnimeList selection, browser panels, app requests and MAL key setup
  are removed. Legacy Core source identifiers remain decodable for cached records.
- Fapservice is an optional, remembered website destination, selectable from Home,
  Community or Settings. It opens only after tapping Open Fapservice, using the
  existing in-app browser. No site images/posts are fetched into the native feed.
- Home previews now request threads scoped to actual seasonal or library anime IDs.
  Empty scopes never request General Anime. Scoped cache keys include media IDs
  and content preferences; old general-feed snapshots are not read.

## Checks and device validation

Core regressions cover defaults, migration/customization, provider/filter choices,
cache isolation and empty-scope behavior. Standard Release/privacy gates run;
longer simulator journeys stay opt-in.

On device, check Home's top bar while scrolling, the two-item menus, the small
Anime/Manga switch, Spotlight logos, and Settings → Restore layout. Try both
Community filters, switch to Fapservice and back, and open episode comments.
