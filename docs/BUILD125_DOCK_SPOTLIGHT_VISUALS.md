# Build 125 — glass selection, Spotlight logo and artwork loading

Version 0.57.3 (125) builds on 0.57.2, preserving playback, launch, reset, accounts, customization and navigation state.

## Requested changes

- Dock: use a real interactive Liquid Glass selection lens, a shared `GlassEffectContainer`, stable glass identity and a spring morph between icons. Reduce Motion retains a short fade. The compact dock sits 14 points lower than build 124, without changing the reserved browse inset or Spotlight height. Accessibility text sizes retain their clearance. The separate hosting surface and interactive back-navigation coordinator still prevent duplicate docks and preserve pane state.
- Spotlight: the English logo visible beneath the controls is embedded in Cinemeta's `tt15483602` poster. The replacement is the same forest key artwork without lettering, verified on TMDB's public no-language posters page. Only the known poster URL is corrected when selecting Spotlight artwork, including old cached URLs. The foreground title logo remains. `FeaturedAnimeCarousel.swift` is unchanged: all layout, controls, artwork alignment, gradients and animation code remain intact. Other Spotlight images and series-page posters are unchanged.
- Visuals: restore immediate AniList cover/banner images alongside LiveChart, with source labels intact. The persistent cache continues to hold only validated LiveChart URLs; AniList art comes from the current title metadata. Existing legacy mixed-source records remain rejected. No MAL/Jikan request is added.
- LiveChart reliability: show saved images before loading; coalesce cancellable requests across shelf/full-gallery viewers; release the web page when its last viewer leaves; preserve stale images and their original age after refresh failure; remember the failed refresh briefly across repeat visits/restarts. Retry old empty cache entries once after upgrading, retaining positive galleries and the new loader's negative-cache cooldown. Retry an interrupted connection or temporary 502/503/504 once, with a delay; denied/rate-limited requests retain their cooldown and are never routed through a workaround. The ephemeral WebKit profile is public-gallery-only, is reset with app data, uses a real viewport for responsive markup and briefly waits for lazy DOM cards. Block duplicate web image/media/font/stylesheet downloads: native views load the actual images.
- Scrolling: Explore's configurable row container is lazy, so offscreen shelves do not all start at once. Retained image tasks keep decoded bitmaps instead of clearing them on each appearance. A 768-pixel decode bucket reduces excess cover memory for intermediate sizes. The artwork shelf reserves its loading height.

## Source verification

- Original poster, inspected with embedded lettering: <https://images.metahub.space/poster/large/tt15483602/img>
- Verified same-scene textless artwork: <https://image.tmdb.org/t/p/original/gyWFWI2ks2OFaWYDS5hnZK4iVLG.jpg>
- Source catalog: <https://www.themoviedb.org/tv/134667/images/posters?image_language=xx>
- Exact AniList 159042 / MAL 53913 / LiveChart 11748 IDs verified in the public AnimeAPI TSV and Fribb mapping. No fuzzy-title selection is used.
- Current AnymeX source still uses `data-anime-visual-url-value`; the parser's existing contract matches it: <https://github.com/RyanYuuki/AnymeX/blob/main/lib/widgets/anime/visuals/visuals_popup.dart>.
- Glass APIs: <https://developer.apple.com/documentation/swiftui/glasseffectcontainer> and <https://developer.apple.com/documentation/swiftui/view/glasseffectid(_:in:)>.

## Validation

Pending CI at the initial commit. Local diff whitespace, all four privacy-guard tests, source credential scan and Safari bundle/version checks passed. Added regressions cover the exact poster substitution and exclusions, immediate AniList/no-network presentation, connection interruption with pagination, stale failure caching across return/restart without extending artwork age, and final-viewer cancellation without saving a negative result. Existing source isolation, pagination, ID conflict and cooldown regressions are retained with the requested AniList behavior.

Direct automated LiveChart requests from this workspace receive HTTP 403. This is not evidence that the live on-device WebKit gallery succeeds; that and the physical glass feel require a device check. No scrolling frame-rate benchmark is claimed. The full required IPA workflow remains enabled, with longer simulator suites opt-in as before.

## Quick device checks

1. Tap Home, Explore and My Library repeatedly: the glass lens should morph between icons, and the dock should sit lower. Open a title and swipe back, including canceling the swipe; only one dock should return, with previous scroll positions intact.
2. Open the reported Reincarnated as a Sword Spotlight: the forest image remains, with only the existing foreground logo. Check that controls, gradients, paging and title placement are unchanged.
3. Open a title's Artwork & covers / full Visuals gallery: AniList images should appear immediately, followed by separately labeled LiveChart visuals when allowed by the service. Refresh, briefly leave/reopen, and try offline after a successful load: saved images should remain.
4. Scroll Explore and artwork shelves up/down, open a series and return; check for placeholder flashes, content jumps and loss of position. Also check Reduce Motion and large text.
