# Home seasons and cached startup — 0.43.0 (102)

Add the new widgets from **Home → Customize → Add widgets**. They start hidden so existing layouts, hidden sections, preview sizes and shortcut slots are preserved.

- **Next season countdown**: seasonal tint, real lineup artwork when available, day/hour/minute clock, current-season progress and a link to the correct season browser. The calendar marker is January 1 / April 1 / July 1 / October 1 in the device timezone. These are season boundaries; anime premiere dates vary. The clock works without an account or network and rolls over automatically.
- **Next season premieres**: artwork-led popular lineup with announced full or partial premiere dates; missing dates stay unannounced.
- **Returning favorites**: matches the next-season popular lineup to saved AniList IDs and explicit anime PREQUEL relations. Does not infer franchises from similar names. This is limited to the loaded popular lineup, not every announced sequel.
- **Tonight’s pick**: a stable daily selection from Watching, Rewatching and Plan to Watch with a confirmed available unwatched original episode. Shuffle chooses another eligible title.
- **Your hall of fame**: completed titles ordered by personal AniList scores, displayed on wide banners.

## Startup and freshness

AniList restores its saved viewer and library before making network requests. The snapshot is encrypted with a key derived from the existing Keychain credential, bounded in size, stored in the app cache and deleted for that credential on disconnect. Credential changes cannot restore another account’s data. Confirmed tracking edits, removals and undo update the snapshot. Snapshots older than 30 days are ignored.

Library snapshots less than five minutes old avoid a redundant startup request. Older usable snapshots remain interactive while a silent refresh runs. App activation, returning to Home and tab changes check freshness; automatic failures back off for one minute. Pull to refresh explicitly requests fresh data. A progress mutation invalidates earlier in-flight reads so a slower refresh cannot revert a confirmed edit. Cached tracking is display-only: writes still require AniList confirmation.

Home and the default native Community feed share an off-main-actor public disk snapshot and one coalesced request. Community previews and seasonal banners restore immediately, revalidate after five minutes, and remain visible on failure. Public Home snapshots expire after seven days and have hard file/count/memory bounds. Content filters and spoiler/progress checks are applied again at display time. Seasonal widgets share one next-season query; adding several does not request one lineup per widget. Countdown clock updates do not trigger network requests. Existing News cache behavior is retained.

## Short device acceptance checklist

1. Add all five widgets; hide/reorder them and relaunch. Verify your previous shortcuts and other widgets retain their positions.
2. Tap the countdown and premiere banners. The season browser and individual series should match the card.
3. Connect AniList, wait for one successful load, force quit, then launch offline. Continue Watching, the library and cached Community should display; the countdown should work. An installation that has never loaded data still needs its first connection.
4. Reconnect and pull to refresh. Leave Home and return; existing content should stay visible without recurring sync banners. After five minutes or a background/foreground return, confirm new progress made elsewhere updates.
5. Mark an episode watched while a background refresh is running; verify it stays updated and survives relaunch. Sign out and verify private data disappears.
6. Check a large text size, iPhone portrait and iPad. Countdown text should remain readable; the clock must not clip. Check that changing the adult-content setting still filters artwork and discussions and that unwatched discussion previews remain protected.

Validation: core regression suite plus Apple-platform encrypted snapshot tests and universal iPhone/iPad Release compilation. Longer simulator journeys intentionally remain manual per the user’s testing preference.
