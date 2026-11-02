# Home and Community — 0.42.0 (101)

1. On Home, use **Quick access → Customize**. Replace Airing Now with Community, then choose Calendar in another slot to swap. Hide a slot, relaunch, and verify all choices persist. You can also long-press a shortcut, use the widget's edit menu, or open Manage widgets → Quick access.
2. Add **Seasonal spotlight**, **Next episode countdown**, and **From your watchlist** from the widget picker. Swipe banners and open a series. Reorder/hide them; check that existing widget order and hidden choices survive the upgrade. New banners start hidden. Try large text and iPad split view.
3. In Community → This Season, verify episode cards show the anime's name, poster and episode number. Unwatched plot previews remain protected; open a card and choose Read anyway to view the post and comments. Watched/general threads show available text previews.
4. Open the AWC seasonal challenge from the screenshot. SVG/PNG images should render in the reader rather than showing img150(...) or img80%(...) text. Test an image in a reply and tap a spoiler to reveal its image. Broken images have a visible fallback and Open image.
5. Scroll far down the feed; change filter/source/show, open a thread, and go Back. Pull to refresh and briefly disconnect networking. Controls should remain visible; refresh preserves existing results and failed requests offer Retry. No empty black screen.

## Provider reference

The AniList Thread.body and ThreadComment.comment fields support asHtml; Media supplies coverImage and bannerImage. Images and previews are requested with each thread page rather than issuing per-row metadata requests. Raw JSON nested replies still pass through the local HTML/Markdown/AniList-image parser. Reddit and MAL access behavior is unchanged.

- https://docs.anilist.co/reference/object/thread
- https://docs.anilist.co/reference/object/threadcomment
- https://docs.anilist.co/reference/object/media
