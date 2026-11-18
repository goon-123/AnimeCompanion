# AnimeCompanion extension services

This Flutter add-to-app module runs AnymeX's source APIs behind AnimeCompanion's
SwiftUI extension hub. The existing app, AniList/MangaBaka integration, Keiyoushi
reader, Seanime providers, TorBox and iCloud features remain available.

## Included systems

CloudStream, Aniyomi, Kotatsu, Tsundoku, iReader, Mangayomi, Sora, Legado,
LNReader, Stremio and Nuvio are registered from the pinned upstream framework.
Repositories and source packages are managed by that framework; adding a system
does not silently install all of a repository's packages. Each provider's website
and its upstream implementation determine its compatibility.

The native hub supports repository addition/removal, installed/available sources,
language and mature-source filters, individual updates and update-all, browsing,
search, pagination, source preferences where exposed, saved titles, image/novel
reading and video selection. Provider-specific media and episode payloads are
retained intact across the native boundary. Separate source systems and content
types use namespaced identities.

Manga and novel content use one shared Content preferences editor. Mature
reading collections follow the saved MangaBaka ratings, including on Home,
without a separate extension switch or an anime adult-content requirement.
Discovery uses those same ratings instead of a second set of checkboxes.

## Runtime and builds

Use Flutter **3.38.5**, macOS and Xcode, then run `bash scripts/build-anymex.sh`.
The script checks out upstream commit `98402444842f5bc1ad85ac381401640af486fa2b`,
stages its committed OpenJDK Zero framework and verifies the SHA-256 of the
v2.7.4 backend JAR. It builds the Flutter module and generates the framework
manifest consumed by `xcodegen generate --spec project-anymex.yml`.

The engine is lazy: app launch does not initialize Flutter, Java or source
repositories. iOS uses the embedded interpreter with no JIT or external server.
The upstream simulator OpenJDK slice is a stub; JVM source execution must be
tested on a signed physical iPhone/iPad. Ordinary existing native regression
jobs use `project.yml`; device releases use `project-anymex.yml` and fail when
extension frameworks are missing.

The native on-device player preserves source HTTP headers. Plain direct links
can also use the user's configured external player. Torrent links are offered
to TorBox using the existing secure account; the AnymeX TorrServer engine is
excluded by the explicit patch in `scripts/prepare-anymex.py`. Video playback
from unlinked extension titles does not guess an AniList identity or mark an
unrelated show watched. Source-provided external subtitles currently accompany
external-player handoffs; the in-app player uses embedded subtitle support.

Source errors are surfaced without printing request URLs/credentials. Source
log callbacks are suppressed. Reset closes the extension engine before local
data is erased. Existing iCloud sync continues to cover its original settings
and library; the new extension runtime's private Isar/configuration is local.
Nuvio's optional TMDB fallback uses a user-entered source preference rather
than upstream's bundled shared API key. Cinemeta remains its primary lookup.

## Current validation

Direct Dart analysis: no issues. Four extension contract tests and ten content
and library preference tests pass,
covering opaque episode payloads, source identity separation and preserved
video headers/subtitles. New native source files pass Swift syntax parsing;
source credential checks and script syntax checks pass. Flutter's widget test,
the full Xcode device build, IPA bundle validation and physical-device source
execution remain pending. Publishing the branch and running GitHub Actions
will run the remaining build checks before an IPA is delivered.

## Licensing

Upstream's custom Unabandon Public License incorporates GPLv3 and adds a public
source requirement. OpenJDK and other included components retain their upstream
licenses. The source URL, revision, patch script and runtime notices are bundled
as `ExtensionRuntimeNotices.txt`. The local integration and exact upstream
modifications are public alongside the app source.

## Device check

1. Open Settings → Sources & playback → All extension systems.
2. Add a repository for the desired system and content type, install a source,
   then browse/search and open a title. Repeat with a script-based system and
   a JVM-based system.
3. Open a manga chapter and a novel chapter; save titles and reopen the app.
4. Resolve a video, test Play here and the configured external player, then
   return to the app. Try a TorBox magnet separately if your source provides one.
5. Update/remove a source, reinstall it, and confirm the saved title is retained.
