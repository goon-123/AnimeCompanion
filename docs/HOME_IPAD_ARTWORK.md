# Larger iPad Home artwork — 0.43.1 (103)

Home defaults to **Large** artwork on iPad. Change it immediately with the top-right Customize button → **Artwork size**, or **Manage widgets → iPad appearance**. Standard keeps the previous compact presentation; Extra large increases artwork further. The choice survives relaunch and is independent of widget visibility, order, item counts and quick-access destinations.

## Presentation

- Weekly posters can fill their seven equal-width columns instead of stopping at 72 points. All seven days and the existing Today outline, empty-day action and additional-title counts remain visible.
- At a wide iPad Home column, the Large defaults use 112-point watching covers, 80-point reading covers, 76-point Up next covers and 84-point Community thumbnails. Planned and Catch up rows use 80-point covers.
- News banners grow from 160 to 240 points tall. Anime banners grow from 210 to 280, with larger inset posters. Their horizontal card widths also increase.
- Quick access, companion shortcuts, navigation arrows, toolbar icons, editor controls, empty-state icons and the season emblem are larger. Shortcut and media grids use wider minimum columns to keep titles readable beside the artwork.
- Size follows the actual Home column width, capped by the existing 1180-point layout, rather than screen orientation or screen bounds. Narrow Split View/Stage Manager panes taper back toward compact sizes. iPhone retains its compact presentation.
- Artwork requests use the displayed dimensions so larger posters can reuse or decode appropriately sized images. No new feeds, metadata requests or background refresh loops are introduced.

## Short device check

1. Open Home on iPad in portrait and landscape. Weekly posters should use their columns, with all seven days visible and Today still highlighted. Open a day to verify the existing calendar destination.
2. Check Community, Continue watching/reading, Up next, Headlines and any optional banner widgets. Images and icons should be larger while text remains readable. Resume and detail taps should still open their existing destinations.
3. Tap Customize → Artwork size; switch Standard / Large / Extra large. Changes should be immediate. Relaunch and confirm the choice is kept, along with your widget layout and shortcut slots.
4. Resize Split View or Stage Manager down to a narrow column, then widen it again. Cards should reflow without horizontal overflow or compressed text columns. Check a larger accessibility text size as well.
5. On iPhone, confirm the compact Home card sizes remain familiar. Cached startup, manual refresh and all existing widgets remain available.

Compilation and the existing core checks run in CI. Broad simulator journeys remain manual per the user's preference; no UI snapshot suite was added for these reversible sizing changes.
