# Series and library refinements — 0.50.0 (113)

## Artwork and series appearance

- Cinematic remains the default. Series options → Series appearance (also in Settings → Appearance & layout) can switch to Classic AniList, restoring the previous compact AniList header and Info-first, two-tab layout.
- Title/logo, banner and poster fallback are three separate switches, initially off. Missing cinematic artwork uses a neutral placeholder; the poster now prefers the matched external poster. An image-download failure also respects the switches. Choosing Classic explicitly uses the original AniList artwork without changing the cinematic fallback settings.
- Existing accounts, progress, provider settings and legacy section customization are preserved. Classic and cinematic More Info arrangements use different saved preferences.
- The cinematic scroll and its outer sizing container extend through the top safe area; scroll-content top margins are zero. This removes the black strip above the Tomb Raider King banner while leaving native back navigation available.

## Series content

- Tabs are Episodes / More Info / Similar. The underline and content crossfade animate together and respect Reduce Motion. Selecting a tab no longer forces the whole page to jump to the tab header.
- Related and Similar are bounded horizontal shelves aligned at the top, preventing the large blank space before posters.
- More Info initially shows Information, Related, Series news, Artwork & covers and External links, in that order. Reviews and Trailer are optional extras in Customize sections; the floating community page is still available.
- Information has a compact summary, studio links and aired/dub/watched counts. Dates, popularity and rankings expand on demand.

## Episode metadata

- ani.zip and the exact MAL entry's episode listing load concurrently. A partial result no longer prevents another provider from supplying titles, dates, scores or plots.
- Missing stills can come from explicitly numbered AniList streaming-episode metadata and Jikan's episode-video artwork endpoint. Array positions, video IDs and guessed cour offsets are never used as episode numbers. Mapped movie/series identity and conflicting TVDB-number checks remain in place.
- Requests use a reserved rate-limit slot and shorter timeouts. Cached metadata from the previous version remains usable offline; failed refreshes keep saved details.
- Episodes without images get a decorative numbered episode card, clearly distinct from a real still. Numbered episodes remain playable and tracking/filter preferences are unchanged. Missing-provider feedback is a compact retry row.

## Discovery, controls and libraries

- Classic Explore's format selector and one options menu occupy their own header, rather than covering artwork. Search, seasons, filters, display, customization, design and account switching are in that menu; the floating search button is removed. Unified Explore also uses one labeled options menu.
- Featured Watch/Save controls, genres and metadata sit below the image. The redundant information icon is removed; tapping the artwork opens details. Trending's plus/check is below its poster. Discovery badges move off the artwork; rating, dub and airing text is available below the posters. Library poster badges are retained.
- Series, Home and library controls use one main options menu. Editing Home still provides explicit Add and Done actions. Manga/reader section controls use a recognizable customization symbol.
- Studios use a bounded Page.studios query instead of multiple root aliases. Schema failures can fall back to individual Studio reads. Network failures and rate limits do not trigger an eight-request retry cascade. Public studio artwork is cached, with compact retry feedback.
- All/Anime/Reading use the same adaptive grid minimum (140 pt by default), spacing and content widths. All-list covers now use the same saved poster width as Anime-list covers. Library display options affect all three media views.

## Validation and focused device checks

Core checks cover fallback independence, saved layouts, metadata enrichment, strict episode numbering, cache compatibility and batched studio decoding. The live studio contract checks that the actual directory returns illustrated collections. Native Release compilation and IPA packaging cover iPhone and iPad. Simulator suites are opt-in, following the preference for testing UI changes on the user's devices.

1. Open Tomb Raider King at the top, then a title without matched artwork. Test the three fallback switches independently and switch Classic → Cinematic; fallback choices and library progress should stay saved.
2. Switch Episodes / More Info / Similar: no forced jump or large gap. Check the five initial More Info sections and compact Information expansion.
3. Inspect a previously blank episode list, use Retry, and play a numbered episode with a decorative placeholder. Confirm watched/unwatched and default filters still work.
4. Scroll Classic Explore: controls and quick library buttons should not cover posters. Open Studio collections and verify artwork and catalog navigation.
5. Compare the same entries in All and Anime library list/grid views, including after changing Library display options on iPhone and iPad.
