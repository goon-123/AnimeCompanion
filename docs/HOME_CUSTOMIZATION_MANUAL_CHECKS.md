# Live Home customization — 0.41.0 (100)

Home uses one saved layout for the inline editor, widget picker and Settings → Appearance & navigation → Home sections. Changes save immediately. The six new widgets start hidden; the existing layout, section order and visibility migrate from build 99.

## Short device check

1. On Home, tap the sliders. Each widget gets a hide button, options menu and drag handle. Drag a widget above/below another. Check Move up/down and Move to top/bottom in the options menu, including with VoiceOver. Open Manage widgets for native list drag handles when moving across a long page.
2. Hide Greeting & date, Search, Calendar/Airing Now/News shortcuts, and any existing content widget. Tap Done; verify only your selected content remains. Long-press a widget's heading/background to hide it or edit Home without opening Settings.
3. Tap + in the editor and add Airing today, Catch up, Library snapshot, Plan to watch, Pick something for me, or Saved stories. Search the picker; added widgets show a checkmark. Add back a hidden widget and confirm its saved position and preview limit are retained.
4. In a supported widget's menu, set Preview items to Compact (3), Standard (6), or Expanded (10). Continue reading shares that limit across saved reading records and MangaBaka entries. Verify chapter/page/source resume and existing playback actions still work after leaving Edit mode.
5. Manage widgets → Hide all widgets, then Done. Confirm the empty Home retains its toolbar. Relaunch: the layout must stay empty. Use Home actions (•••) to open Search, Calendar, Airing Now, News, Community, My Library, Sources or Settings. Use + / Add widgets to restore only what you want.
6. Connect AniList: Catch up counts confirmed originally broadcast episodes regardless of dub preference, skips unknown release counts and titles not yet aired, and handles completed/rewatching titles. Shuffle only chooses released titles on Plan to watch. Changing accounts or adult-content filters must update candidates immediately.
7. Airing today uses the same library scope, local-day boundaries, original/dub data and uncertainty labels as the weekly widget. Open its Calendar link, pull to refresh, background/foreground at midnight, and check that hidden schedule widgets do not start fresh requests. Saved stories uses existing News bookmarks and read history; opening/removing a story must agree with the full News screen.
8. Check iPhone and iPad portrait/landscape, light/dark, and large text. After relaunch verify order, hidden choices and preview limits. Restore Home layout asks once before resetting those choices.

## Validation scope

Core regressions cover preference migration, a fully hidden Home, relative moves, preview limits, malformed/unknown settings, original-broadcast catch-up, duplicate library entries and shuffle eligibility. Routine CI compiles the universal iPhone/iPad Release app and packages the unsigned IPA. Longer simulator and device journeys remain opt-in; use the checks above for visual review.
