# Six reported sources — focused compatibility triage (build 61)

Reported by an AnimeCompanion user: Omega Scans, Kiutaku, Flame Comics, Toonily, HentaiHand and Manga Ball fail in the app. A source may fail in popular/search, title details, chapters, page URLs or image bytes. **No device error trace or live end-to-end proof has been supplied.** Do not convert the existing generic offline preflights into claims of working websites.

| Source (frozen APK) | Build-53 evidence | Current conclusion |
| --- | --- | --- |
| Omega Scans (en.omegascans 1.6.52) | Unverified | Uses HeanCms and login-capable network paths; isolate the first failing operation with the exact APK. |
| Kiutaku (all.kiutaku 1.6.0) | Unverified | Confirmed image-transport contract bug: its `Headers.Builder.configureHeaders()` **removes** `Referer` because its image CDN rejects that header. The runtime previously synthesized `Referer` again when absent. Build 61 stops doing so. Catalog/details/chapters/images must still pass an exact-APK full-flow replay and iOS/live checks. |
| Flame Comics (en.flamecomics 1.6.1) | **Verified offline** | Existing owned popular/latest/search/details/chapters/pages/images replay passes; this does **not** establish live access. Extension depends on the website's current Next.js build ID and a CDN. Check HTTP status and public website response rather than adding a host scraper. |
| Toonily (en.toonily 1.6.72) | Unverified | This is the Madara/MangaAjax extension, not Toonily.me. Validate cookie headers, AJAX chapter request and image transport separately. |
| HentaiHand (all.hentaihand 1.6.1) | Unverified; probe cells incomplete | Many language-specific sources, with optional account authentication and JSON APIs. Test source index/language and actual API requests; an incomplete audit is not a recorded missing API. |
| Manga Ball (all.mangaball 1.6.5) | Unverified; probe cells incomplete | Many language-specific sources; API includes JSON POST chapter lists and asynchronous view-count callback. Confirm main reader path and any asynchronous API gap independently. |

Build-53 matrix: [CSV](compatibility.csv) and [HTML](compatibility.html). This is the latest *committed full-catalog* baseline. Build 60's focused matrix is not a full catalog re-run. The approximately 93% shared Java/Kotlin roadmap estimate is **not** an extension success percentage.

## Regression in build 61

Only merge image headers the extension actually provides, preserving request-specific precedence. Do not fabricate a `Referer` when the source intentionally removed it. The associated Rust tests assert (1) omitted Referer stays omitted, (2) explicit source Referer is forwarded, and (3) request-specific headers win case-insensitively.

This is a **confirmed shared bug fix**, not a promise that Kiutaku or the other five sites can presently load all operations. The production runtime keeps ordinary HTTPS/cookie/domain bounds and no per-site parser.

## Audit and next verification

Run the runtime test suite and targeted frozen APK preflight (no website requests):

```sh
mkdir -p build/manga-audit
MANGA_RUNTIME_INVENTORY="$PWD/build/manga-audit/runtime-inventory.json" bash scripts/test-manga-runtime.sh 2>&1 | tee build/manga-audit/tests.log
python3 scripts/audit-manga-compatibility.py --packages en.omegascans all.kiutaku en.flamecomics en.toonily all.hentaihand all.mangaball --workers 4 --probe-seconds 60 --deadline-seconds 600 --output build/manga-six-sources
```

Inspect `build/manga-six-sources/compatibility.json` for bounded missing-API identifiers, source indexes and unexecuted cells. Then replay real APKs with controlled **owned** catalog/details/chapter/page/image responses, plus Swift/C native bridge tests on iPhone/iPad, and only then test public site availability. Record HTTP failures and browser challenges separately from runtime errors. Never collect cookies, credentials, raw private URLs or copyrighted chapter content in reports.

**Completion metrics:** Java/Kotlin roadmap remains approximately **93%** (unchanged by this HTTP contract change). Confirmed live success across the six reported sources: **not measured**. No unsupported percentages should be inferred.
