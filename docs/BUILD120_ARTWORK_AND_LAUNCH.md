# Build 120 — Sharper Spotlight and calm transitions

## The six requested changes

1. **Spotlight artwork:** phone Spotlight now resolves the same identity-matched
   Stremio/Cinemeta and ani.zip/TVDB artwork as cinematic series details. It uses
   portrait posters on phones and backdrops in wide layouts. Supported Metahub
   poster/background URLs use the large variant. AniList covers/banners require
   their existing, separate fallback settings. Mapped images cannot silently
   reintroduce AniList covers. Older cached records without posters are repaired.
2. **Continuous background:** the dark app canvas is black. Spotlight's final
   gradient, page dots, spacing and shelves share Theme.background. Light mode
   retains its matching semantic background rather than acquiring a black seam.
3. **Anime/Manga switching:** remove the parent layout animation and overlapping
   outgoing/incoming screens. The incoming page has a simple opacity fade over
   one persistent canvas. Library media switching follows the same approach.
4. **Bottom tabs:** remove PageArrival entirely. Retain native tab navigation and
   its stacks; there is no added screen translation, scale or bounce. Content
   and catalog arrival also use opacity without vertical offsets.
5. **Startup logo:** a system launch storyboard and the runtime loading view
   show the existing app icon on black at the same fixed size and position. Home
   mounts underneath while local records, account restoration, selected Home
   feeds and the first two Spotlight entries prepare. Cached data can reveal
   after 0.35 seconds; a six-second deadline prevents an offline service from
   trapping the user. Requests can finish in the background after that deadline.
   The logo does not reappear on foregrounding or ordinary navigation. New-user
   setup does not wait for optional discovery calls.
6. **Spotlight paging:** retain native horizontal paging and the prior vertical
   scrolling/navigation-height fixes. Preload the current and next artwork,
   gently fade pages during a swipe, and retain a decoded image until its
   replacement is ready. Cached images appear without another loading fade.
   Logo/text presentation still changes only while its title is offscreen.

Artwork and feed caches stay bounded/device-local. No new service credentials,
personal defaults, server dependency or authentication flow is introduced.

## Verification

Core regressions cover source selection, opt-in fallback, safe large-image URL
selection, legacy poster-cache repair and the startup deadline. Standard Core,
native Release and privacy checks run; long simulator journeys remain opt-in.

The existing Black Clover example was checked against the public provider:
Metahub's medium poster was 500×750 and its large poster was 780×1170. Source
artwork can still vary by series; this does not invent detail or upscale a small
AniList cover. Requests retain the app's image byte/decode/memory limits.

Focused device checks:

1. Compare Black Clover and two other Spotlight entries with their series page.
   Swipe both directions, use a page dot and drag vertically from the image.
   Confirm prepared logos remain stable and return navigation keeps its height.
2. Scroll past the poster into Trending. Confirm no horizontal color seam at
   the dots or between shelves. Repeat in Light appearance.
3. Switch Anime/Manga and each bottom tab repeatedly. Check for an incoming fade
   on media changes and no added bounce, scale or fragmented black background.
4. Cold-launch online, with a warm cache, and offline. Confirm the icon on black
   gives way to the app and an unavailable service cannot hold it indefinitely.
   Resume the app and check that the boot logo does not replay.
