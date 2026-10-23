# Requested sources and hold scrolling — build 62

Version 0.25.15. This change fixes runtime blockers found while executing the
published Omega Scans, Toonily and MangaBall APKs, refreshes the native manga hub,
and adds press-and-hold reader scrolling with saved speed controls.

## Source fixes

| Source | Exact package version | Source index | Confirmed fix |
| --- | --- | --- | --- |
| Omega Scans | `en.omegascans` 1.6.52 | 0 | Preserve its title format metadata between catalog and refresh calls. |
| Toonily | `en.toonily` 1.6.72 | 0 | Preserve its title path; compare separate OkHttp URL objects by value, preventing an incorrect fallback to `?p=7`. |
| MangaBall | `all.mangaball` 1.6.5 | 8 (English) | Preserve title IDs, send the JSON chapter-list body with the source's bare content type, resolve ISO local dates, and load its actual view-update callback. |

The manga bridge now reads metadata from each actual guest title object and
restores it to the next operation's guest object. It retains author, description,
cover and other existing fields too. Metadata is an opaque JSON object, limited
to 64 KiB and 32 nesting levels; invalid and overflowing values are rejected
before source requests. Saved Swift titles and refresh merges retain it, while
older saved titles without it still decode.

The shared Kotlin ByteArray request-body default mask now uses the extension
receiver's parameter positions. Explicit offsets/counts are checked, binary data
is preserved, and `application/json` remains unchanged. ISO_LOCAL_DATE_TIME
retains nanosecond precision and rejects offsets, regions, invalid dates and leap
seconds. Existing ISO_DATE_TIME behavior remains covered by earlier regressions.

## Manga page and reader

The manga hub has a continue-reading rail with progress, saved cover cards,
dedicated history cards, a source-search action, and responsive pinned/recent/all
source groups. Language selection, mature-source filtering, source pinning,
extension management and existing navigation identifiers remain available.

Hold a loaded page for 0.35 seconds to start scrolling; release to stop. A small
indicator displays the selected speed. Reader controls provide slower/faster
buttons and a continuous-scroll play/pause button. Settings provide a speed slider
(15–240 points per second) and a hold-to-scroll switch. Existing preferences
migrate with their previous appearance and speed intact. Dragging, zooming,
chapter changes, leaving the app, unloaded pages and chapter end stop motion.
VoiceOver users retain the accessible continuous-scroll control.

## Evidence and limits

All three exact APKs complete owned-response catalog, details, dated chapters,
ordered pages and source image-byte flows in fresh VMs. Toonily's chapter memo is
restored for page requests; MangaBall's POST body/content type and English chapter
filter are asserted. Omega's paid chapter is filtered by the extension's default
preference. Paid access and browser verification are not bypassed.

Regression fixtures contain neutral synthetic stories and images. The checksum
manifest and download script pin all three packages. Native Swift/C/Rust tests
reuse the same responses and the app's actual command builders; a reader UI test
checks hold movement, release, speed adjustment and disabling the gesture.
Native iPhone/iPad execution requires hosted Xcode CI; local checks do not certify
live website availability or all 42 MangaBall language identities.

A separate live C-ABI check on 2026-10-23 UTC reached MangaBall's catalog (24
entries), title/chapter refresh (352 chapters) and page list (9 pages). The first
image request returned HTTP 403 from its image host. Toonily's catalog returned
HTTP 403. Omega's homepage and API returned an HTML “Site Unavailable” response,
including HTTP 200 for the API instead of JSON. These are observations from this
environment, not a claim that the sites are globally down. Complete live reading
for the three sources is therefore still unverified. The app's existing source
website/session controls remain available for user-completed verification.

The broader shared Java/Kotlin roadmap is approximately **94% complete**
(engineering estimate, previously 93%). The extra date formatter closes a shared
gap; the UI work does not count toward that percentage. Broader coroutine,
reflection and collection/date edge cases remain, so this is not a 100% claim.
