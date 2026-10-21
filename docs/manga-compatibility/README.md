# Manga compatibility matrix

Build 57 extends coroutine task/continuation handling, Java method and Kotlin property
reflection, and the observed Java date/time gaps. Its [focused matrix](build57/compatibility.html),
[CSV](build57/compatibility.csv) and [JSON](build57/compatibility.json) cover ten exact APKs,
fourteen source identities and 108 production C-ABI preflights against code
`6b65cb91e187051eb9de990d600428c8e9ad28a1`. All expected cells ran. Four source rows
have complete owned reading flows: InManga, ArabManhwa, Komga source 0 and JinmanTiantang.
Five are partial, four unverified and one remains runtime-blocked. The observed Java/Kotlin
gaps targeted by this batch no longer occur in these probes; Line Manga's page path now
reaches a separate `okio.BufferedSource.readUtf8Line()` gap. Its localized weekday/latest
request is independently verified. This selected-package result is not a catalog-wide rate.

The 191 passing Rust tests include actual Kotlin compiler-produced suspend/resume bytecode,
GC, cancellation/lazy-start/timeout checks, method argument/access/exception contracts,
optional/custom-month/fractional date builders, DST and overflow behavior. The eight new
APKs load factories and settings. InManga and ArabManhwa replay catalog to image; ProComic
verifies mutable pagination, Code Arc verifies image-access refresh after HTTP rejection or
an expired token, and Tappytoon/LectorJPG/Line Manga/Nude-Moon exercise their respective date
paths. New native bridge cases cover four sources; hosted verification is tracked in the PR.
General parallel coroutine scheduling, complete reflection/proxy APIs, all date ranges and
sub-millisecond formatter transport remain outside these claims. The full-catalog committed
baseline remains build 53; hosted audit artifacts provide later catalog-wide snapshots.


Build 56 completes the owned JinmanTiantang image replay through shared Okio peek,
bitmap codecs/rectangle copies and bounded gzip streams. The pinned APK restores
PNG/JPEG/WebP input, including gzip, through all three strip-count branches; every
output row is checked with JPEG tolerance. Ordinary and gzipped animated GIFs
retain every byte. The [focused matrix](build56/compatibility.html),
[CSV](build56/compatibility.csv) and [JSON](build56/compatibility.json) inventory
2/2 packages, enumerate four sources and record 30 production C-ABI preflights,
with no expected cells left unexecuted. Komga source 0 and Jinman are verified
against owned fixtures; Komga's other two identities remain enumeration-only.
Runtime evidence points to `64d70e7584d54af37735282ff3edf03f21cf1644`.
Native iPhone/iPad checks and live availability are separate. The full-catalog
baseline remains build 53; this selected-package result is not a catalog-wide
success rate. Bitmap decode options, other pixel storage/paint/transform paths,
WebP output encoding, login/check-in and browser paths remain outside this result.

Build 55 fixes the shared Komga coroutine and JinmanTiantang typed-array settings blockers. Komga source 0 has a complete owned reading replay; its other two source identities enumerate. Jinman has catalog/details/dated-chapter/ordered-page evidence and a legacy unscrambled-image replay, but modern scrambled images still encounter missing `okio.BufferedSource.peek()`. It remains partial. Native iPhone/iPad checks and live availability are separate from this offline evidence. The full-catalog baseline remains build 53. The [focused matrix](build55/compatibility.html), [CSV](build55/compatibility.csv) and [JSON](build55/compatibility.json) inventory both packages, enumerate four sources and record 30 production C-ABI preflights against runtime code `001e361119e0adbd21c18a20a7ecd58b42ea03bc`. One row is verified offline, one partial and two have enumeration-only evidence. All expected generic probe cells ran. The scrambled-image blocker is established by its named real-APK regression, beyond the generic image probe's synthetic path.

Build 54's [focused matrix](build54/compatibility.html) and [CSV](build54/compatibility.csv) cover the eleven packages targeted in this batch. It inventories all eleven, enumerates 118 source instances and records 88 offline preflights. LANraragi (1), Mango and StashApp have complete owned reading-flow evidence; one row has a confirmed runtime blocker and 115 rows remain unverified. MangaDot's large source factory leaves 748 generic operation cells unexecuted. This is a selected-package snapshot against runtime code `adc98e3803731ab3d31733eb620b8a8e24f17d61`, not a new full-catalog success rate. The complete catalog baseline below remains explicitly build 53.

The new flows use source-configured public HTTPS servers. They verify saved custom URLs, source-owned login/API-key requests, dated chapters, ordered pages and image transport. Source-written state across commands, local/private HTTP servers, complete browser readers and live availability remain separate gaps. Those build-54 Komga coroutine and JinmanTiantang typed-array settings failures are fixed by build 55; the historical matrix remains unchanged.

[Open or download the matrix](compatibility.html). Save the HTML file and open it in a browser for search, language/status filters, per-source reading stages, evidence details and CSV export. The file works offline and makes no website requests.

The matrix tracks the exact frozen catalog, APK checksums, source indexes and runtime code revision shown in the report. It is a development compatibility snapshot, not live website certification.

The committed build-53 snapshot inventories all 1,444 packages, enumerates 2,042 source instances and records 11,342 offline probes. It has 14 complete owned flows, 13 partial rows, 48 runtime-blocked rows and 2,247 unverified rows. Counts include package rows where sources could not enumerate. Local limits leave 271 packages without operation probes and 3,887 known operation cells unexecuted; their immutable dependency inventories are still complete. These limitations appear in the HTML. [Download the CSV](compatibility.csv) for a spreadsheet.

| Status | Evidence required |
| --- | --- |
| Verified offline | Named passing tests for the exact APK/source across popular catalog, details, chapters, ordered pages and image transport |
| Partial | Some reading stages have exact-version fixture evidence; a complete flow is not established |
| Runtime blocker | A loading or reading probe reached a missing runtime API or interpreter decoding error in this build |
| Unverified | Representative reading evidence is insufficient; an empty-response failure or acceptance does not establish support |

Each stage is shown separately. Generic accepted responses say **Probe only**; browser, execution-limit and unexecuted paths remain visible. Failed package inspection produces one package row instead of invented source indexes. Languages and names join to the public catalog by source ID where available. A package update or another source language cannot inherit previous fixture results.

The **Shared dependencies** tab groups actual external DEX references, distinguishing dependency use from observed API blockers. The **Runtime backlog** ranks confirmed gaps by distinct affected packages; selecting one filters the source matrix. Static unmatched references remain investigation candidates in the machine-readable audit, not confirmed failures.

Build 53 fixes the largest remaining HTTP groups: multipart request serialization and Headers factories/companion initialization. Complete owned flows are added for Digital Comic Museum 1.6.0, Rawkuma 1.6.41 and Manhuawu 1.6.0. Their full replays also require correct Jsoup evaluator class/ID behavior and the host's explicit default HTTP user-agent property.

Build 54 adds the source marker, monotonic clock, typed preference snapshots/title getters, generated custom-URL migration fix and enum serializer contracts. The next batches should address coroutine-context construction, remaining browser behavior, typed arrays, cryptography/TLS, additional serializers and remaining date APIs. Every batch should reproduce a real APK failure, add the shared contract, replay a complete owned flow and refresh the relevant matrix. Website sign-in, server configuration, optional encrypted readers and live availability need separate evidence.

## Reproduce and refresh

```bash
mkdir -p build/manga-audit
MANGA_RUNTIME_INVENTORY="$PWD/build/manga-audit/runtime-inventory.json" \
  bash scripts/test-manga-runtime.sh 2>&1 | tee build/manga-audit/tests.log
MANGA_TEST_APK_DIR=Tools/MangaRuntime/target/fixtures \
  python3 -m unittest discover -s scripts/tests -p test_manga_audit.py -v
GITHUB_SHA="$(git rev-parse HEAD)" python3 scripts/audit-manga-compatibility.py --workers 4
npm --prefix Tools/MangaAudit ci --ignore-scripts --no-audit --no-fund
node Tools/MangaAudit/node_modules/playwright/cli.js install chromium --only-shell
node scripts/test-manga-matrix.cjs
```

Use `--library` when Cargo's output is in another directory. An audit must use the production library and actual passing test log from the same runtime code. Limits and incomplete cells are recorded. Refresh the pinned catalog revision deliberately; evidence remains checksum-specific.

The Manga compatibility audit workflow rebuilds HTML, CSV, JSON and Markdown, checks real browser interactions, and uploads those files with the runtime API inventory and screenshots. Its report for a PR is newer than this committed snapshot when that PR changes runtime behavior. A report can also be rendered from an existing audit:

```bash
python3 scripts/render-manga-matrix.py build/manga-audit/compatibility.json --output build/manga-matrix
```

No source chapter content, production test APK or source-specific parser is added by the audit.
