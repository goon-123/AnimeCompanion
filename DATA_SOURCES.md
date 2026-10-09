# Verified integration references

Sources inspected during implementation on October 4–8, 2026 UTC:

- AniList official authentication guide: https://github.com/AniList/docs/blob/master/docs/guide/auth/index.md
- AniList implicit grant: https://github.com/AniList/docs/blob/master/docs/guide/auth/implicit.md
- AniList media-list guidance: https://github.com/AniList/docs/blob/master/docs/guide/graphql/queries/media-list.md
- AniList page fields: https://github.com/AniList/docs/blob/master/docs/reference/object/page.md
- AniList mutations: https://github.com/AniList/docs/blob/master/docs/reference/mutation.md
- AniList rate limiting: https://github.com/AniList/docs/blob/master/docs/guide/rate-limiting.md
- MyDubList schema and attribution: https://github.com/Joelis57/MyDubList/blob/main/README.md
- MyDubList English index: https://raw.githubusercontent.com/Joelis57/MyDubList/refs/heads/main/dubs/confidence/normal/dubbed_english.json
- MyDubList corroborating source counts: https://raw.githubusercontent.com/Joelis57/MyDubList/refs/heads/main/dubs/counts/dubbed_english.json
- Maintained AniSchedule dates: https://raw.githubusercontent.com/RockinChaos/AniSchedule/refs/heads/master/raw/dub-schedule.json
- Maintained AniSchedule history: https://raw.githubusercontent.com/RockinChaos/AniSchedule/refs/heads/master/raw/dub-episode-feed.json
- AniSchedule update timestamps: https://raw.githubusercontent.com/RockinChaos/AniSchedule/refs/heads/master/raw/last-updated.json
- Alternate AniSchedule repository: https://github.com/Bas1874/AniSchedule
- Magical Explorer official English dub announcement: https://www.crunchyroll.com/news/latest/2026/10/5/magical-explorer-anime-english-dub-now-streaming-on-crunchyroll
- ANN feed: https://www.animenewsnetwork.com/news/rss.xml
- XcodeGen package specification: https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md

## Important schema findings

AniSchedule uses nested `media.media.id` AniList identifiers. Upcoming node dates can span multiple weeks; dates are not extrapolated. Some records use an indefinite delay with a placeholder year of 2032. Such dates are suppressed and shown as delayed. `verified: false` remains visibly unverified. Recorded history overrides an estimate for the same media and episode, and future records are not presented as already released.

MyDubList uses MAL identifiers. Its object has separate `dubbed` and `partial` arrays; the legacy array form is also supported. Its supplemental numbers count agreeing sources, never released episodes. At least two agreeing sources can fill a lagging availability index; one uncorroborated source remains unconfirmed. Partial listings retain their status. A missing MAL ID or source failure remains unknown. An absent ID in the loaded dataset is displayed as no dub reported, which is not a definitive claim about all services or regions.

The Bas1874 release feed stopped updating in early September. RockinChaos is the maintained primary and reports Magical Explorer episodes 1 and 2, matching Crunchyroll's announcement. Its next listed episode 3 date is October 10 at 16:30 UTC, marked unverified. Availability agreement does not establish an episode count. Manifest timestamps detect a stalled feed even when HTTP requests succeed; an alternate replaces a stale endpoint only when newer data loads successfully. The app checks on every foreground return and every ten minutes while active, retries failed requests after one minute, and shows source freshness or failure notices across its shared dub views.

The ANN RSS response verified in this workspace has titles, canonical links and timestamps, and does not include an image field in every item. The app does not scrape article pages to manufacture thumbnails.

AniList's official documentation supports mobile custom URI redirects and the implicit grant. The app supplies a nonce in `state`, verifies it at callback, and never includes a client secret. The full login round trip still needs verification with a registered client on iPhone.

