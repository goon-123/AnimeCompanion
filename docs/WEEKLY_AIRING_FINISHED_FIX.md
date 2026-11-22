# Weekly airing widget — 0.60.4 (139)

The Home/Explore weekly widget now excludes series explicitly marked FINISHED or CANCELLED by library, broadcast, or dub-source metadata. A terminal status wins over an older copy of the same AniList ID. This prevents remaining dub episodes, dub estimates, and stale next-airing metadata from keeping an ended broadcast in the widget. Unknown status alone does not hide a dated release.

The full calendar retains its original broadcast/dub events and history. Library tracking status and watched progress do not determine whether a series is still broadcasting.

Device checks:

1. Install over the existing app and open Home. Confirm the finished Bleach season no longer appears in Airing this week, even if it remains Watching with unwatched/dub episodes.
2. Confirm an ongoing tracked series still appears on the correct local weekday. If multiple titles share a day, open the chooser and confirm finished series are absent there too.
3. Check the widget in Explore if enabled, and open the full calendar to confirm dub release information remains available.

This build is based on the existing AnymeX/iCloud branch to retain the current app features. No settings reset or account logout is needed.
