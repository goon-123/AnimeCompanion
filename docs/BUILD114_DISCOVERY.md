# Discovery refinements — 0.51.0 (114)

- Restore the build-112 Spotlight component: full artwork with its original gradient, title, year/format, genre chips, library status, synopsis and Watch / Info / Library actions over the lower image. When Spotlight is first in Classic Explore, artwork extends behind the glass format controls. Other first rows keep a reserved header. Preserve the consolidated options menu and protection against taps passing through the header.
- Restore the original unnumbered Trending shelf. Top 10 is a separate catalog row with small rank badges in the card footer, below unobstructed artwork. Each row can be hidden and reordered independently. Both versions are also available as optional Home widgets and through Explore's Home widget picker.
- Add Small / Medium / Large card sizes to Animation Studios and Anime Genres independently. Both start Small. Small studio cards are shorter; genre cards use compact landscape artwork. Size choices save per Explore design and are available in Customize Explore and each row's long-press menu.
- Keep saved row order, visibility, Home choices, reading widgets, series appearance and artwork-fallback settings. A previously hidden ranked Trending row also hides the new Top 10 row on migration; subsequent toggles stay independent.

## Focused device checks

1. Open Classic Explore with Spotlight first: compare it with the Overgeared reference. Try Watch, Info and Library, change carousel pages, and switch Anime / Manga without opening the poster underneath.
2. In Customize Explore, hide Trending while keeping Top 10, then reverse the choice. Rearrange them and reopen the app. Check that every ranking badge stays below its image.
3. Change Studios to Large and Genres to Small, then reopen Explore. Test Medium as well, including iPad / Split View. Open a studio and a genre to confirm their catalogs still navigate.
4. Add the plain Trending and Top 10 widgets to Home separately. Hide either one and verify the other remains visible.

Core checks cover independent saved visibility, legacy layout migration and per-row/per-design sizes. Native iPhone/iPad Release compilation and IPA packaging are required; longer simulator UI journeys remain opt-in for device testing.
