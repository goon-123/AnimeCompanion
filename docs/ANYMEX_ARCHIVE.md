# AnymeX integration paused

The complete implementation is retained on [`archive/anymex-0.60.6-build141`](https://github.com/goon-123/AnimeCompanion/tree/archive/anymex-0.60.6-build141), commit `9bdab22031d3049cd2bac0ac5b66b11b1009abae`. This includes all source managers, repository setup fixes, the stream-picker integration, tests, pinned SDK/backend inputs and rebuild scripts. The former IPA is retained as version 0.60.6 / build 141.

The active application returns to Stremio/Seanime watching sources and the original Keiyoushi reading runtime. Flutter, the AnymeX source hub, its playback search, native frameworks and CI jobs are removed from the active build. Existing manga rating simplification, iCloud sync and the finished-series weekly-widget correction are retained.

This is a code/build rollback. It does not reset preferences or delete existing app-support databases during an update. Archived source data remains on the device until an explicit reset or uninstall; it is not exposed by the active UI.

## Resuming the work

1. Create a feature branch from the then-current app. Use the archive as a reference rather than resetting the whole app to that branch.
2. Read `Tools/ExtensionBridge/README.md` on the archive for pinned revisions, patches, native assets and licensing/build requirements. Framework caches can expire; the source and rebuild inputs are retained.
3. Restore the bridge, native runtime/models, build scripts and tests from the archive. Reapply the integration changes to source settings, reader shortcuts and `WatchAnimeView` after deciding the revised product flow.
4. The completed native implementation is in `App/AnymeXRuntime.swift`, `UnifiedExtensionsView.swift`, `ExtensionAddRepositorySheet.swift`, `ExtensionSourcePreferencesView.swift`, `ExtensionReadingAndPlayback.swift` and `ExtensionStreamSources.swift`; shared types/matching are in `Sources/AnimeCore/UnifiedExtensions.swift` and `ExtensionStreamLookup.swift`.
5. Preserve newer series scrolling and episode-filter changes in `AnimeDetailView` and `AnimeEpisodesSection`. Keep the single manga content-preferences editor. Do not restore duplicate rating switches or replace the whole Settings directory with an older snapshot.
6. Rebuild and validate repository paste/add/relaunch, source lookup, physical-device native assets and player handoff. Header-dependent inline playback did not report AniList progress, and provider stream playback still requires live device verification.

Reference PRs: #81 (source hub), #83 (repository setup), #84 (Find streams integration). They remain available alongside the archive branch.
