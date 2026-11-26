# AniNext: themes and guided source setup — 0.61.2 (147)

Settings → Appearance & layout now offers six accent palettes, a custom color picker,
five background/card palettes, and System/Light/Dark appearance. Colors update without
restarting or resetting navigation. Theme preferences join existing device sync.
Reader page backgrounds remain independent. Custom accent brightness is adjusted for
text contrast against both theme surfaces.

First launch and Settings → Setup Guide now have six steps. Watching explains two
routes: configure/install an anime-compatible AIOStreams/Stremio stream add-on, or
install/enable a Seanime torrent extension AND connect TorBox. Either route needs a
separately installed external player. Selecting a different player clears the user's
installation confirmation. Reading explains adding Keiyoushi, then installing/enabling
at least one actual manga source. Account connections are separate from content sources.

The final summary reports saved configuration, including missing sources. Skipping
setup leads to that summary before browsing; it does not claim playback is ready.
These checks do not validate provider availability or credentials with a live episode.
Safari → VidHub moved to the main Settings preferences section and stays searchable.

## Focused checks

- Change accent and background in light/dark modes. Return to Home, Explore, manga,
  and a pushed series page; colors should update and navigation should remain intact.
- Relaunch and sync to another configured device; appearance should persist.
- Run Setup Guide, select either video route, and open its setup screens. Return to
  see configuration status. A catalog-only/disabled add-on must not count as anime streams.
- For Seanime, an extension alone or TorBox alone must remain incomplete.
- Choose each external player. Confirm installed; changing the player clears confirmation.
- Add only the Keiyoushi repository: reading remains incomplete until a source is installed
  and enabled. Disabling all sources restores the incomplete status.
- Skip sources: the summary explains missing video/reading setup; browsing remains possible.
- Safari → VidHub is available in Settings and search, absent from Sources & playback.

This branch also carries forward the already-developed 0.61.1 manga/search/sync changes
that were present on development branches but missing from main, preserving the new README.

## AniNext rebrand

The display name is now AniNext on the Home Screen, in onboarding, Settings,
sidebar navigation, Safari extension and external-player handoff. The selected
purple book/play logo is packaged as a 1024 × 1024 opaque iOS app icon and as a
transparent launch mark on a warm ivory canvas. The existing maximum two-second
startup budget is unchanged. Bundle IDs, Keychain service names, sync formats,
iCloud container IDs, URL schemes and saved folder paths retain their existing
values so this release upgrades the current app without orphaning saved data.

Icon preparation prompt: extract the central purple open-book/play-arrow mark and
lavender turned page from the supplied 3A Page Turn concept, remove all labels and
the presentation tile, preserve the silhouette and negative space, then place the
mark on an opaque warm ivory square for the Home Screen icon. The image-generation
tool produced the assets; the app icon was resized to Apple's required 1024 pixels.

Check after installing: Home Screen name/icon, cold-launch logo/name, Settings,
Safari extension title, and that previous saved accounts and sources remain.
