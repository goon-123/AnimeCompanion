# Build 121 — Quick cinematic launch, restored Catch Up and upcoming series

- Remove the optional website Community destination and its in-app panels,
  source menu and settings links. Old destination preferences resolve to AniList;
  This Season and My Shows remain available.
- Reduce the startup ceiling to two seconds. Cached launches can finish after
  0.2 seconds; the reveal fade is capped by the remaining deadline. Replace the
  calendar splash with a cinematic silver/lavender AC aperture mark, centered at
  the same size in the system storyboard and runtime loading view. The Home
  Screen app icon is unchanged.
- Restore the Catch Up shortcut to its earlier Airing Now release-status screen,
  with list/grid mode, behind-only filtering and original/dub comparison. Keep
  saved shortcut positions and display preferences. Remove the replacement
  plain-list destination.
- Show an episode-one premiere card for unreleased series, using the exact
  broadcast time when present, otherwise the announced date/month/season or a
  clear unannounced state. Do not infer episodes from the planned season total.
  Avoid episode provider requests, cache reads, retries and pagination until
  premiere, including manual refresh and repeated entry to the Episodes tab.
  The scheduled first-episode timestamp takes precedence over a stale status.
- For confirmed missing cinematic artwork, use the existing series cover as a
  blurred backdrop and use the name as text when no logo exists. Keep any real
  banner or logo. This is a missing-asset presentation, not a global re-enabling
  of AniList source fallbacks. Wait for cached/resolved metadata before choosing
  that presentation; preserve it during refresh.

## Focused device checks

1. Cold-launch online and offline: verify the cinematic mark and a logo wait of
   at most two seconds; resume should not replay it.
2. Open Catch Up from Quick Access. Verify the familiar release-status groups,
   list/grid choice, behind-only control and original/dub setting.
3. Open a next-season title with a future date, switch between its tabs and pull
   to refresh. Verify a premiere card with no episode spinner or Retry/Load More.
4. Open a title without cinematic assets and one with full artwork. Verify a
   blurred existing cover/text title only where needed, and unchanged real art.
5. Verify Community contains AniList's two categories and no website source.

Core regressions cover deadline behavior, removed-source preference migration,
premiere timing/partial dates, zero upcoming episode requests and missing-asset
presentation. Standard Release/privacy checks run; long UI journeys stay opt-in.

Launch artwork is a project asset created with the built-in image generator.
Prompt: cinematic original AC monogram fused with a play/aperture silhouette;
satin silver with restrained lavender/violet rim lighting, crisp at small sizes,
generous pure-black negative space, no calendar, tile, characters or extra text.
