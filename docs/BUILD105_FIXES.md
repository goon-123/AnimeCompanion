# Anime details and extension management — 0.44.1 (105)

Anime detail order is Story → Information → Original broadcast → Watchlist controls → Episodes, followed by dub details, links, discussions and visible galleries. Section jump links follow that order. Synopsis HTML is normalized to at most one blank line between paragraphs. Original broadcasts use a compact local-date/episode/countdown row, updated once a minute; finished and unannounced broadcasts remain visible.

Artwork has stable reserved bounds while loading. The horizontal shelf has an explicit height, and the shared gallery card reserves its poster aspect ratio. Failed thumbnails try the original; failed originals show a retry action. The full title gallery no longer waits behind an entrance animation. Empty or malformed preferred cover URLs fall back to the next supplied size. The hero uses one responsive poster layout, and lower detail sections load when scrolled into view.

Keiyoushi's live release-assets.json currently maps package names directly to SHA-256 strings. The client now accepts this and the earlier nested APK inventory. Older inventory entries still require an exact filename match. APK bytes and inspected package/version remain verified before storage; failed updates retain the prior installation. Malformed verification feeds produce a repository-specific error instead of a generic decoder message. CI includes the app client's focused live Keiyoushi index/checksum contract.

Manga extension management has a repository status card, Available/Installed/Updates views, language/content controls, direct install/update buttons and an Update all action for eligible installed packages. Progress, cancellation and partial failures are explicit; one failure does not undo completed updates or replace the failed package. Disabled installations retain their disabled state when updated. Catalog refresh and checking updates do not install packages automatically. Extension details show installed and available versions and a refresh action.

Seanime settings and search share an availability policy. Installed, disabled and enabled-but-content-restricted states are distinct. The visible source section synchronizes directly with saved settings rather than depending on a cancellable parent initialization task. Its key guard prevents scrolling from restarting workers. Settings show when an enabled provider is hidden; search links directly to its configuration. Mentioning NSFW exclusions in a description no longer marks a newly installed general provider as adult-only. Existing explicit adult flags remain unchanged and can be reviewed in Configure.

## Focused device checks

1. Open an anime in light/dark mode on iPhone/iPad. Verify the cover, Story/Information/Original broadcast order, compact timing and paragraph spacing before Episodes.
2. Scroll to Artwork, open the full Visuals gallery and tap a poster. Missing images should have an identifiable placeholder/retry action. Check narrow iPad windows and larger text.
3. Add or refresh Keiyoushi. Confirm real sources appear, search a known source, install it and reopen the extension page. Check the Installed and Updates views.
4. Update one package, then use Update all when updates are available. Verify progress and retained enabled/disabled state. A failed update should retain its previous version and appear in the error summary.
5. Toggle a Seanime provider on and open torrent search immediately. It should appear as searchable, or be explicitly labeled hidden by the content setting with a Configure link. Test two providers together, change settings and return without relaunching.

Normal Core/runtime/Release checks run; the longer simulator journeys remain opt-in as requested. A successful catalog contract verifies current repository decoding and checksums, not live compatibility of every manga website or torrent provider.
