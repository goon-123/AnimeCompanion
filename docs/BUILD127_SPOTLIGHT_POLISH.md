# Build 127 — Spotlight artwork, logo sizing and continuous paging

Version 0.58.0 (127) retains the build 126 dock and LiveChart repairs. This change
is limited to Spotlight's clean artwork, optical logo size, looping and motion,
with source attribution in the existing About screen.

## Confirmed causes and source selection

The app already retrieves transparent title logos independently from Cinemeta /
Metahub. Its portrait Spotlight preferred ordinary posters, which can have an
additional title printed into their pixels. The earlier single-poster correction
could not fix other series. The reference screenshots demonstrate the desired
separation; they do not establish the reference app's internal provider.

Spotlight now resolves the existing exact AniList/MAL/IMDb mapping's TMDB TV or
movie ID and optional season. It reads TMDB's public No Language poster and
backdrop collections. Both the canonical collection and each image card's language
must match. There is no title search, embedded API key, account session or server.
A mapped season without a textless poster can use its exactly mapped series-level
collection. Other series' collections, ordinary language-tagged posters, unrelated
hosts and source redirects are rejected.

The three reported collections were inspected: One Piece (TMDB 37854, 49 clean
posters), Mage (313346, 6), and Returner (230050, 2). The same Mage and Returner
scenes exist without lettering. The Mage counterpart is preferred while it remains
listed. Returner's matching old scene is only 550 pixels wide, so its sharper
900-pixel clean key visual is preferred. Resolution groups retain provider order;
small uploads are still available if no larger clean variant exists. One Piece gets actual clean character artwork from its collection instead
of the branded Metahub poster. Captured cards exercise the production parser.

Clean URLs live in independent Spotlight fields/cache. Series posters and existing
logo URLs are unchanged. A new mapping cache version supplies TMDB IDs immediately
after upgrading. Good cached clean art survives provider failure; failed empty
lookups retry after five minutes. Existing provider background and explicit AniList
fallback preferences remain available when a clean collection cannot load. Normal
posters are no longer the default fallback behind a separate Spotlight logo.

## Logo sizing without moving the interface

Metahub's 800-by-310 logo canvas includes substantial transparent side margins on
the reported Mage/Returner logos. A background actor removes only transparent
padding and retains the painted logo and a small edge allowance. The logo fits a
larger envelope above the same fixed 92-point title slot (150 for accessibility
text). Its lower edge remains anchored to the same slot. Existing metadata,
buttons, badges, horizontal padding, gradients, top alignment and hero height are
unchanged. Cropping is Spotlight-only; other screens retain their original logos.

## Loop and motion

The native horizontal pager gets an identical last-title copy before the first
page and first-title copy after the last. Native idle callbacks rebase to the
matching real page without animation; iOS 17 uses exact page alignment. Logical
selection and page dots stay the same. Zero/one-title cases do not create boundary
copies. All copies share the same decoded asset snapshots, so recentering does not
start a new image task, reveal a placeholder, or reset the data source.

Remove the previous per-panel opacity effect. Background, logo and controls move
together in the native pager; no added zoom, parallax or spring is introduced.
At most two title preparations run together. Current/previous/next titles are
prioritized with wraparound, images are decoded off the main actor, and snapshots
are not promoted during a swipe. Cold ready background/logo pairs fade in together
while idle, within fixed layout bounds. Reduce Motion retains a short fade.

## Verification scope

Core checks cover the three captured public collections, identity/language/host
rejection, cache upgrade without changing series posters/logos, wraparound and
title-presentation rules. Focused native checks use an owned metadata/image
transport through the production clean-artwork and decode pipeline, inspect logo
rendering, exercise both loop boundaries repeatedly, and assert unchanged control
frames after wrapping. Transparent/asymmetric bitmap tests check trimming. Existing
dock/gallery regressions and required IPA validation remain enabled; broad UI
suites remain opt-in. Actual image content was inspected separately from the
owned native preview. Physical-device gesture feel remains a user check.
