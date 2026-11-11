# AnimeCompanion 0.57.1 (123)

Build 123 retains build 122's playback and artwork changes and corrects its
duplicated dock and abrupt startup handoff. It also adds a complete local reset.

## Dock

The iOS/iPadOS 26 custom dock no longer sits over a native TabView. Its panes use
a lazy retained stack, so there is only one tab surface. Visited panes retain
their navigation/search/scroll state, and inactive panes receive an inactive
scene phase and cannot receive touches or accessibility focus. The optional
iPad sidebar uses the same panes without a bottom dock. Earlier OS versions
retain native tabs. The existing transition-coordinated dock fade is preserved.

## Launch

The splash timer begins when the session view mounts, after store construction,
so initialization cannot spend the crossfade budget before the logo appears.
Startup reserves up to 400 ms for an explicit crossfade of the mounted logo and
app content within the two-second visible splash budget. The logo layer is
removed only after the animation completes. Reduce Motion uses a shorter fade.

## Reset

Settings → Reset App & Sign Out of Everything opens a destructive confirmation.
Nothing is erased until the user confirms. Reset clears app-owned Keychain
connections (including all saved MangaBaka profiles and source credentials),
Stremio/Seanime/TorBox setup, installed manga extensions, local downloads,
reading progress and source links, preferences, snapshots, HTTP/browser caches
and source cookies. AniList and MangaBaka online libraries are not deleted.

The old view session is removed and all stores are recreated, returning directly
to first-run onboarding. A session generation barrier prevents old file and
secure-storage writers from restoring erased data after late callbacks. Network
tasks and native manga browser sessions are canceled; pending AniList sign-in
and MangaBaka refresh work are invalidated. Reset failures stay on a retry screen
and an interrupted reset resumes before stores load on the next launch.

## Validation

Focused Core regressions cover blocked stale writers, new-session writes,
protected secure-writer closures, hidden/nested file removal, sandbox boundaries,
symlink escape rejection, idempotent missing storage, and startup fade timing.
Required repository checks and the universal Release build run in CI. Physical
iOS/iPadOS appearance checks remain manual.

## Device checklist

1. Confirm only one dock appears on iOS/iPadOS 26. Switch tabs, return to a
   scrolled/search-filtered page, open anime/manga details, and complete/cancel a
   back swipe. Check the optional iPad sidebar as well.
2. Cold launch with cached data and offline. Confirm a visible logo-to-content
   fade, including Reduce Motion, without an extra two-second wait after fading.
3. Open the reset confirmation and cancel: accounts and preferences must stay.
4. On a test setup whose local data can be discarded, confirm reset. Verify the
   welcome/setup page appears, no accounts or extensions remain installed, and
   closing/reopening the app does not restore old credentials or reading data.
   The same online accounts should still retain their remote libraries.
