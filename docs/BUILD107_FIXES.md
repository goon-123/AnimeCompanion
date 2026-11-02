# Weekly anime navigation and Keiyoushi updates — 0.45.1 (107)

Home always uses a full-width navigation stack. The weekly widget previously
called the split-column selection method, so its single-title and day-chooser
taps changed an unused detail ID without showing a page. Single-title days now
use the shared AnimeLink. A selection from a multi-title day dismisses the
chooser before pushing an AnimeRoute onto Home, retaining normal Back behavior.

Keiyoushi's current release-assets.json values are build content hashes, not
the SHA-256 of the APK file. Upstream publish-repo.py explicitly uses
info["contentHash"] for this inventory, independent of version and signature.
The earlier flat-inventory fix incorrectly compared that value with APK bytes.

Catalog loading now decodes the current index without this build inventory.
Before every installation/update, including entries cached by older builds,
the client gets the exact GitHub release asset's SHA-256 using its tag,
filename and download URL. Missing/invalid digests, drafts, other repositories
and ambiguous assets fail before package inspection or installation. Release
metadata is cached for five minutes per client so a batch shares requests for
the same tag. One checksum mismatch triggers a fresh metadata/download retry;
the expected digest is never replaced with a locally observed hash.

The store still hashes the downloaded APK bytes, inspects package/version and
commits atomically. A failed update keeps the previous installation, enabled
state and settings. Cached build hashes are replaced during installation;
there is no need to remove the repository or reinstall sources. Install/update
controls resolve verification when selected instead of requiring a digest in
the catalog. GitHub API availability and its unauthenticated rate limit apply;
there is no fallback that skips package verification.

Source: https://github.com/keiyoushi/extensions-source/blob/main/.github/scripts/publish-repo.py

## Verification

Focused Core regressions cover cached bad hashes, exact release matching,
missing/invalid/ambiguous digests, untrusted download URLs and batch caching
with a fresh retry. The opt-in live Keiyoushi check now downloads Hiperdex,
Toonily and Weeb Central through the actual client and compares each APK's
SHA-256 with its verified descriptor. The normal workflow runs this check and
the universal iPhone/iPad Release build. Longer simulator suites remain opt-in.

## Device checks

1. On Home, tap a weekly day with one anime. Its series page should open;
   Back or an edge swipe should return to Home.
2. Tap a day with several titles, choose one, and confirm that the chooser
   closes and that title opens. Dismissing without a choice should keep Home.
3. In Manga extensions, tap Check for updates, then Update all. Confirm
   Hiperdex, Toonily and Weeb Central update without checksum mismatch errors.
4. Open a title from an updated source and confirm its saved source settings,
   enabled state and reading progress remain available.

Release compilation and live checks are recorded in the linked PR/build run.
