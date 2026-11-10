# Build 119 — Spotlight scrolling and navigation sizing

Remove Spotlight's directionless drag recognizer. The native horizontal pager
handles sideways swipes; upward/downward drags on the artwork can reach Explore's
vertical scroll view. On iOS 18 and later, native scroll-phase notifications keep
logo changes deferred during paging without adding a competing gesture. On iOS
17, the existing visibility/selection checks protect visible titles.

Measure the Explore viewport above its navigation stack. Spotlight's automatic
height no longer follows temporary safe-area changes from the series navigation
bar. Real window resizing, rotation, iPad split-column sizing, accessibility type
and saved poster sizing still apply. Selected slides and prepared logos remain
in the existing carousel state.

## Device checks

1. In Anime Explore, drag up and down starting in the middle of the Spotlight
   artwork. The page should scroll without needing to start between widgets.
2. Swipe Spotlight sideways, including a slow diagonal swipe. Confirm paging
   and the dots still work, and prepared logos do not replace a visible title.
3. On a slide other than the first, open the series and return using Back and
   the edge swipe. Confirm the same slide and stable artwork height/crop.
4. Rotate the device and resize an iPad window. Confirm Spotlight adapts to the
   real viewport; also check the saved fixed-height and balanced-size options.

Standard Core, native Release and privacy checks run in CI. Longer simulator UI
journeys remain opt-in; these checks target the reported device behavior.
