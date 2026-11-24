# Anime extensions in Find streams

Version 0.60.6 / build 141 queries installed anime extensions alongside Stremio and Seanime when opening an AniList episode. This includes Sora/Jormungandr and the other installed anime source systems; adding a repository alone does not install its sources.

- Extension sources publish independently as each finishes, with at most three source lookups in flight. AniList English/romaji titles and aliases are used for exact normalized matching. Season numbers are retained. Ambiguous titles, duplicate episode numbers, multi-season lists and missing numbers require an explicit title/episode choice in the picker.
- Source errors do not block other sources. Reload and episode changes cancel old work and reject old results. Sources and adult visibility are re-read for each lookup.
- All, Streaming and Torrents, release text and explicit audio filters include extension results. Source language and subtitle language never imply dubbed audio.
- Direct videos use the selected external player with AniList episode/resume context and optional subtitles. Header-dependent videos use the existing in-app extension player; that player does not report AniList playback progress. Magnet releases use the existing explicit TorBox cache/download flow and preserve the selected anime/episode for resolved-file playback.
- Choose title or episode searches the provider and returns selected videos to Find streams. Manage extensions reloads the picker on return.

Focused validation covers title aliases, season/episode ambiguity, opaque payload preservation, cancellation, headers/subtitles and audio evidence. The IPA workflow also compiles the full iPhone/iPad application and runs the existing required checks. Live third-party provider availability and actual playback depend on the installed sources.
