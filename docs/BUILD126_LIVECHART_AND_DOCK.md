# Build 126 — current LiveChart markup and clear dock labels

Version 0.57.4 (126) corrects two failures reported after build 125.

## LiveChart: proven parser mismatch

The user's exact page, <https://www.livechart.me/anime/13226/visuals>, was
successfully inspected in a browser. It contains **31 visual cards**. All use
`data-anime-visual-url`, whereas our parser recognized only the older
`data-anime-visual-url-value`. Because the page had a matching canonical link,
the old code then incorrectly classified the missing matches as an empty gallery.

The parser and WebKit readiness check now recognize both contracts. Modern
attributes supply full-size URLs, labels, copyright notices and the owning
LiveChart anime ID. Native thumbnails still use the actual smaller image URL.
Mismatched anime IDs and unsafe image hosts remain rejected. The exact public
IDs were verified: AniList 195516, MAL 61987, LiveChart 13226.

The captured 31-card HTML fixture is exercised both directly and through the
production gallery client; two current AniList images remain alongside those
visuals when supplied by title metadata. The native preview transport now uses
the current HTML contract too.

An unrecognized document is no longer called an empty gallery merely because
its canonical link matches. Empty classification requires an explicit provider
message. Cache v3 imports only real LiveChart images from v2, so build 125's
false-empty records cannot suppress new requests for six hours. Existing good
galleries, new failure cooldowns, URL validation, cancellation and source labels
are preserved. No app reset or account logout is required.

## Dock: foreground above glass

The selected label was inside `GlassEffectContainer`, allowing the glass
compositor to blur/refract the icon and text themselves. The container now owns
only the selection lens; all buttons, symbols and labels are a separate final
foreground overlay. The lens identity/spring transition, lower placement,
single-dock navigation coordinator, retained page state and Reduce Motion path
remain. Spotlight, its artwork correction and its rendering code are untouched.

## Focused verification

Core regressions cover the actual 31-card page, full production client flow,
modern ownership checks, explicit-empty versus changed markup, positive v2
migration and retrying build 125's false-empty results. Existing cancellation,
retry, pagination, stale gallery and credential isolation checks remain.

Only dock/gallery source changes trigger the two additional iPhone simulator
checks. They switch through selected tabs, capture the complete dock and label
crops, and open the native gallery using the current markup contract. The broad
iPhone/iPad suites remain opt-in. Screenshot evidence must be inspected; an
accessibility assertion alone cannot establish that selected text is sharp.

Build and focused-rendering results are tracked in PR #78. Browser verification
of the actual LiveChart page and captured-page parser verification are distinct
from the native gallery's offline preview transport. The latter uses owned test
images, not the site's artwork bytes.
