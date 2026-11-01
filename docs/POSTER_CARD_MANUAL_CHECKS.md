# Anime poster cards — quick device check

Version 0.37.1, build 94. These are manual checks for the poster sizing adjustments; broad app retesting is unnecessary.

1. **Compare the same anime.** My Library Grid should look the same as build 93. In Library List, Explore Trending / Popular this season and search (List and Grid), rating and DUB badges should be noticeably smaller, with less padding. They stay at bottom right, with DUB above the rating, while the airing dot stays at top left. Nothing should extend beyond the image or appear twice below it.
2. **Check applicable badges.** Compare a currently airing title, a finished title, a known English dub, and an undubbed or unconfirmed title. Finished titles have no green airing dot; unknown, announced-only and estimated-only dubs have no DUB badge. A missing rating leaves no empty rating badge. Detailed dub information remains on the series page.
3. **Check tracking and taps.** Open a poster, go back, and tap a genre. Long-press a Library card to confirm Watch, mark-next and Edit still work. Change a title's AniList status in the tracking editor and confirm Explore shows that status after returning; restore it if desired. Library watched progress and the yellow/green original-broadcast countdown must remain visible.
4. **Check schedules.** Open Schedule daily / weekly and Airing Now List / Grid. These posters should have no rating, DUB or airing-dot overlays. Episode/source/time and catch-up information still appear beside or below the art. The small upcoming-airings preview on Home should also have clean artwork.
5. **Check larger series cards.** Open an anime and compare its main header: larger poster, taller banner and larger title. Related and You May Also Like posters are now 160 points wide on iPhone and 200 on iPad, with larger title text and smaller badges. Tap a card and a genre to confirm both still open their own destinations. Try larger text and iPad rotation/Split View if you use them; the main header should stack when needed, with no clipping. The cover's expand icon remains at top right.

If something looks wrong, send the screen name, List/Grid setting, column count and a screenshot. Include whether it happened on iPhone or iPad.

The longer simulator suites can still be run manually in GitHub Actions by dispatching **iOS unsigned IPA** with **run_ui_tests** enabled. Normal pushes and pull requests prioritize the build and IPA.
