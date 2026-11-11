# Build 124 — compact dock and LiveChart gallery

Version 0.57.2 (124) corrects regressions after the build-123 tab container replacement.

- Restore compact, centered dock proportions and 25-point filled symbols. The selected capsule moves with a short ease-in-out transition; retained tab pages crossfade, including their first visit. Reduce Motion uses fades without capsule travel. Each visited pane keeps its navigation, search and scroll state.
- Preserve the single app-owned dock, constant bottom inset, interactive series-return visibility handling, launch handoff and complete local reset. The series subpage and artwork-arrival animations were already present and remain in place.
- Use LiveChart alone for the anime Artwork & covers shelf and title gallery. Do not append AniList posters/banners or query Jikan/MyAnimeList. Start a new gallery cache namespace and reject cached records containing another source. Preserve a previously successful LiveChart gallery when refresh fails.
- Load the public LiveChart gallery document with system WebKit in a separate ephemeral profile. ID mapping remains the exact AniList/MAL-to-LiveChart mapping, with no title-based guesses. No account credentials or source/browser cookies are supplied. Denied responses retain the request cooldown; no alternate transport, challenge solver or automatic denial retry is used. Requests have a deadline, cancellation and app-reset cleanup.
- Accept same-title canonical host/trailing-slash redirects, while rejecting another host, anime or page. Support lazy thumbnail attributes and preserve original full-size image URLs, captions and credits. Show request failures separately from confirmed empty galleries.

## Validation

The source privacy scan and Safari resource/version check pass locally. Focused gallery regressions cover pagination/coalescing, source exclusivity, denied requests/cooldowns, split mapping/page transports, redirect validation, lazy thumbnails, cache migration and stale refresh. The existing optional native gallery journey now expects only LiveChart images and a source-specific failure message.

Release compilation and Core regressions run through the PR workflow. See the PR for current results. The longer simulator suites remain opt-in.

The current public mapping dataset was inspected successfully, including AniList 178789 / MAL 59193 → LiveChart 12735. Direct automated LiveChart requests from this environment return HTTP 403; a live gallery success has not been verified here. The WebKit path and visual transitions still need device verification.

## Device checks

1. Home / Explore / My Library: confirm the compact dock, filled icons, smoothly moving highlight and page fade. Switch quickly and revisit a search/scroll position.
2. Open anime and MangaBaka entries, return with Back and with an interactive swipe, and cancel a back swipe. Confirm only one dock returns and the browsing viewport stays stable.
3. Open a title with a known LiveChart gallery. Confirm only LiveChart cards appear, thumbnails expand to full-size images, and refresh keeps saved artwork when offline.
4. Enable Reduce Motion and larger text. Confirm the dock remains readable and transitions use short fades.
5. Confirm reset during a gallery request stops the page load and returns to first-run setup.
