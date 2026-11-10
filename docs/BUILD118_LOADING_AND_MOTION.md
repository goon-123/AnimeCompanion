# Build 118 — Stable Spotlight titles and smoother loading

## Spotlight

- Center the branding across the full Spotlight width, including iPad. Use one
  reserved title slot for both the transparent logo and readable fallback.
- Probe metadata and decoded/HTTP image caches before choosing the first title.
  The probe never starts a network request and never flashes a text placeholder
  ahead of a usable cached logo.
- A cold slide uses its readable title for that visit. Fresh logos are prepared
  and decoded in advance for up to five slides, two requests at a time. A visible
  title never changes into a logo. Partly visible pages and drag gestures are
  protected; a prepared logo is committed only when its page is out of view.
- Returning to Explore reuses prepared/cached logos. Native horizontal paging
  gives page geometry a reliable viewport for visibility checks.
- Logo requests return once the matched logo is available; they do not wait for
  a missing backdrop fallback. Full series artwork still resolves its fallback.
  Provider lookups are shared, with bounded metadata and bitmap caches.

## Motion and Home

- Native bottom-tab navigation stacks stay intact. Their content has a short
  arrival fade, and Anime/Manga switching uses shared transition timing.
- Keep the small media switch in one stable header location during replacement.
- Use the same light transition for series tabs, episode expansion, Home widget
  arrival, loading replacements and widget edits. Reduce Motion removes travel
  and staggering, keeping only a brief fade. Reader scrolling and native back/
  sheet gestures keep their existing behavior.
- Decode usable cached images immediately instead of replaying a loading fade.
- Start selected Home Headlines/Community requests at utility priority while
  the greeting and local data display. Reuse the existing coalescing clients.
- Restore reading/source-link data in parallel. AniList refresh and dub updates
  also start independently. Restoring flags prevent a signed-in user's Home
  from briefly showing guest/empty-library messages.
- Reserve row placeholders while libraries, headlines and conversations load;
  animate content/height changes. No artificial wait is added for Home content.

## Watched episodes

Replace the tiny thumbnail-only check with a visible Watched capsule and accent
outline. The action becomes a replay icon. Keep the normal artwork, metadata,
long-press tracking actions and default episode filter.

## Verification

Core regressions cover first cached presentation, protection during swipes,
offscreen promotion, returning to Explore, cache-only image reads, logo-first
requests, full-detail fallback and shared provider lookups. Standard Core,
Release and privacy gates run; longer simulator journeys remain opt-in.

Focused device checks:

1. Open Explore with cached logos, swipe slowly between pages, and return to a
   title after it finishes downloading. Confirm centered logos and no visible
   text-to-logo replacement. Try an uncached/offline title as well.
2. Switch Anime/Manga and bottom tabs, including returning to a scrolled page
   or series detail. Confirm navigation and source selection remain intact.
3. Launch Home with saved accounts, then try a slow/offline connection. Confirm
   placeholders/fades instead of guest-message flashes and sharp layout jumps.
4. View All/Watched episodes, expand a synopsis and replay a watched episode.
   Check the badge in light/dark mode and with Reduce Motion enabled.
