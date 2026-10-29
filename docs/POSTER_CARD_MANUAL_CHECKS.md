# Anime poster cards — quick device check

Version 0.37.0, build 93. These are manual checks for the new poster presentation; broad app retesting is unnecessary.

1. **Compare the same anime.** In My Library (Grid and List), Explore Trending / Popular this season, and a search result, check the top-left airing dot and bottom-right star/rating. English DUB should sit directly above the rating. Ratings use the same 10-point scale. Nothing should extend beyond the image or appear twice below it.
2. **Check applicable badges.** Compare a currently airing title, a finished title, a known English dub, and an undubbed or unconfirmed title. Finished titles have no green airing dot; unknown, announced-only and estimated-only dubs have no DUB badge. A missing rating leaves no empty rating badge. Detailed dub information remains on the series page.
3. **Check tracking and taps.** Open a poster, go back, and tap a genre. Long-press a Library card to confirm Watch, mark-next and Edit still work. Change a title's AniList status in the tracking editor and confirm Explore shows that status after returning; restore it if desired. Library watched progress and the yellow/green original-broadcast countdown must remain visible.
4. **Check the other layouts.** Open an Explore seasonal catalog, a series' Related / Recommendations, a manga's Related anime, Schedule daily / weekly and Airing Now List / Grid. Also check combined Anime + Manga & Novels Library/Explore if you use them. Badges stay on anime posters; schedule episode/source/time information and manga posters remain intact.
5. **Check sizing.** Try two and three grid columns, a narrow list-cover setting and larger text. On iPad, rotate and try Split View if enabled. Posters should fill their allotted space, and the badges should stay separated and inside the image. The cover's expand icon belongs at the top right on series details.

If something looks wrong, send the screen name, List/Grid setting, column count and a screenshot. Include whether it happened on iPhone or iPad.

The longer simulator suites can still be run manually in GitHub Actions by dispatching **iOS unsigned IPA** with **run_ui_tests** enabled. Normal pushes and pull requests prioritize the build and IPA.
