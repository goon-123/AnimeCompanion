# Build 116 — Cinematic Home and Explore

Home and each Explore layout now have independent Cinematic / Original preferences.
Cinematic is the default. Original uses the previous screen components, including
the restored Classic Anime Spotlight. No widget reset is needed when switching.

## Controls

- Settings → Appearance & layout → Home & Explore appearance.
- Home → options → Screen appearance.
- Explore → options → Explore design → Screen appearance for the selected layout.
- Explore layout choices remain Classic sections, Mixed poster grid and Discovery
  shelves. Changing layout does not change any of the four appearance preferences.
- Series layout and artwork fallbacks remain separate settings.

## Cinematic presentation

- Home adds a removable, movable Cinematic Spotlight using active watching/reading
  entries and public discovery picks. Existing empty Home configurations stay empty.
- The three Explore layouts get wide artwork, strong readable gradients, a subtle
  artwork backdrop and poster cards with metadata below the artwork.
- Spotlight pages use matched anime artwork when available, with selected-page-only
  requests through the existing cached artwork client. Nothing autoplays.
- Watch/Continue opens the existing anime source selection. Linked manga opens its
  saved source with resume enabled. Read and Details open the series page.
- Plus/check opens the existing library editor or account setup.
- Widget order, hidden rows, studio/genre sizing, filters, content restrictions,
  reading links and progress use their existing stores. Public catalog responses
  use the existing clients and Home cache; no account data is bundled.

## Validation

Core regressions cover appearance defaults, independent preference scopes, widget
migration, an empty Home and saved Spotlight customization. The standard native
Release build and privacy gates also run. Simulator UI suites remain opt-in.

Device checks:

1. Choose Cinematic and Original independently for Home and all three Explore
   layouts; restart and confirm each choice stays saved. Original Classic Anime
   should show the previous portrait Spotlight.
2. Hide/move Cinematic Spotlight and another widget, switch styles and confirm
   their order, visibility and sizing stay saved. An empty Home should stay empty.
3. Try Watch, Details and plus/check; continue a manga with a linked source. Check
   long titles, large text and iPad width. Confirm filtered titles stay hidden.
