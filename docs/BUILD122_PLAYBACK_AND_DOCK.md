# AnimeCompanion 0.57.0 (122)

This build includes the changes from PR #75 and addresses issue #76. It is based
on build 121 and retains its Catch Up, upcoming-premiere, artwork-fallback and
removed-community-source changes.

- Native anime playback automatically marks an episode watched when VidHub
  returns a valid position at or beyond 90% of the actual reported duration, or
  reports completion. The setting defaults on and the threshold is adjustable.
  An implausibly fast jump to the end does not satisfy the position heuristic.
- AniList sync runs after local completion; an unsuccessful sync keeps local
  progress and offers a manual retry in the player sheet. VidHub reports progress
  on return to AnimeCompanion, not continuously during external playback.
- Continue Watching uses the tracked next episode and its unfinished local
  resume position. Episode title and artwork load separately; the existing
  poster remains visible until the episode image has decoded. Both fresh and
  cached episode images crossfade. Missing images retain the poster.
- The cinematic launch mark fades in from black and the overlay fades out within
  the existing two-second app-controlled startup budget.
- On iOS/iPadOS 26, a persistent glass dock sits outside the navigation stacks.
  Each immersive destination reports its public view-controller lifecycle to
  the dock. The navigation transition coordinator drives its fade and short
  slide, including interactive back and cancellation. Safe-area reservation
  stays constant; immersive content can extend beneath it. Hidden docks do not
  intercept touches or appear to accessibility. Reduce Motion uses a short
  fade without translation. Earlier OS versions retain native tabs, and the
  optional iPad sidebar continues to own its navigation.
- Tab order, hidden tabs, selected tab and per-tab navigation stacks still use
  the existing preferences and navigation store.

## Focused device checks

1. Cold-launch with and without cached content. Confirm the cinematic mark fades
   in and out and does not hold the screen for more than two seconds.
2. Open an anime from Home, Explore and My Library. Tap Back, complete an edge
   swipe, then cancel an edge swipe. Confirm the dock follows the transition,
   stays hidden after cancellation, and does not resize Spotlight.
3. Repeat with a MangaBaka title, related titles, anime-to-manga links and a
   detail-to-browse link. Verify hidden-dock areas remain tappable and long pages
   reach their last row. Repeat on iPad, with its sidebar, and with Reduce Motion.
4. Watch part of a 24-minute episode and return before 21:36. It should remain
   resumable on Home. After normal playback beyond 21:36, return and verify local
   watched status and AniList progress. An immediate seek from 0:00 to 22:00
   should not qualify using the returned-position heuristic.
5. View Continue Watching with uncached, cached and missing episode art. Confirm
   there is always a poster or decoded image and that metadata arrives smoothly.

Device animation quality is a manual check; a successful Release compile does
not establish that an interactive gesture looks correct on a physical device.
