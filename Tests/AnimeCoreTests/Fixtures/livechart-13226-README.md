# LiveChart 13226 gallery regression

Source: https://www.livechart.me/anime/13226/visuals

Captured November 11, 2026 from the rendered public gallery. This fixture contains
its canonical link and the 31 original `data-controller="anime-visual"` cards;
site navigation, scripts and unrelated markup were omitted. Image bytes are not
bundled. Credits and source image URLs remain attached to each card.

The site uses `data-anime-visual-url`, `data-anime-visual-label`,
`data-anime-visual-anime-id` and `data-anime-visual-copyright-notices`.
The old parser searched only for `data-anime-visual-url-value`, found zero cards
and incorrectly treated the matching canonical URL as proof of an empty gallery.
