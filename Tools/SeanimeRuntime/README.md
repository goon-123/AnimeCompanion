# On-device Seanime torrent-provider compatibility runtime

This is a small, independent runtime for `anime-torrent-provider` JavaScript/TypeScript, not the Seanime Go server or its complete plugin API. It uses the official TypeScript compiler (Apache-2.0) and linkedom (ISC plus dependency licenses), bundled at build time. No compiler is downloaded at app runtime. `build.mjs` collects notices for the actual bundled package versions, including nested dependencies and TypeScript's third-party notices.

```sh
npm ci --ignore-scripts --no-audit --no-fund
npm run build
npm test
```

Generated `App/SeanimeRuntimeResources/worker.js` and notices are ignored by git. Every native CI job and `scripts/build-ios.sh` builds them before XcodeGen. XcodeGen copies the folder into the app. Swift package tests do not require the JS bundle. Node.js 22+ is recommended.

## Supported subset

- Manifest `payload` or HTTPS `payloadURI`, `javascript`/`typescript`, string-based preference defaults and select options.
- `Provider.getSettings`, regular `Provider.search`, and `getTorrentMagnetLink` when a result has no usable magnet/hash.
- `$getUserPreference`, console, cloning/byte helpers, bounded HTTPS GET fetches and synchronous body `text()`/`json()` (also compatible with `await`).
- An inert `LoadDoc` selector adapter with wrapped Seanime elements: `length()`, attributes/data, text/HTML, find/filter, each/map, parent/child/sibling traversal, closest, negative `eq` and `end`.
- A **conservative display-only** `$habari.parse` shim. This is not the real Habari parser. It does not verify audio or drive automatic episode/season/file selection.

Smart Search, `$scannerUtils`, ChromeDP, CryptoJS, torrent-file parsing, POST, authenticated/cookie requests, manga/online-streaming providers and UI plugins are not implemented. Unsupported calls fail instead of being silently stubbed as successful empty searches. Provider code that catches network errors cannot turn those into a successful empty result; partial provider console errors are disclosed.

## Boundaries and limits

The reviewed source snapshot and its own preferences enter a disposable Web Worker in a non-persistent WKWebView. No AniList credentials, app tracking history, other providers or TorBox key are passed. A trusted host document has `connect-src 'none'` and blocks remote script/iframe navigation; native code performs only approved public-host HTTPS GETs, without cookies, ambient credentials, redirects or authenticated/cookie headers. A bounded allowlist permits public GET metadata headers (Accept, Accept-Language, User-Agent, Referer, Origin, Content-Type, Cache-Control and Range); the native bridge independently validates them. The native bridge and worker cap requests at 24, individual responses at 4 MB after download, and cumulative accepted response bodies at 12 MB. This is not a streaming download cap or a hard memory/heap guarantee. Source is capped at 1 MB and persisted state at 4 MB / 12 installations.

The parent terminates workers on cancel or after 60 seconds, including CPU-bound script; leaving the search cancels work. Backgrounding pauses unfinished providers; returning to the visible search restarts only those providers and keeps completed results. Temporary inactive states do not cancel searches. A dedicated non-persistent WebKit process and inert DOM are isolation measures, **not a guarantee that arbitrary untrusted code is safe**. Only install trusted extensions. Approved hostname checks are not a DNS firewall and cannot promise protection from malicious/rebinding DNS on an approved domain. Runtime compatibility and providers' live behavior can change independently.

TorBox calls live in `AnimeCore/TorBoxClient.swift`, completely outside this runtime. Only explicit native confirmation adds a torrent. Cached-only defaults on, no seeding/account settings are overridden, readiness is manually refreshed, and the user selects the exact safe video file. The native client requests a temporary CDN URL rather than forwarding an API-key permalink to VidHub. Successful job references are stored locally under the current TorBox key and cleared when the key changes. Removing a provider or local reference does not delete cloud jobs. An interrupted add may have reached TorBox; check the dashboard before re-submitting.

## Validation limits

Node tests cover owned fixture code, callable DOM traversal, response metadata, exported TypeScript providers and two bundled workers with separate preferences/networking/failures; they are not iOS security/layout validation. Offline iPhone/iPad cases exercise the actual WKWebView, worker, bundled compiler, native request clients and player URL builders with synthetic responses. The three supplied upstream providers were inspected and transpiled locally, not executed against live services or a real TorBox account. Real on-device provider/website/API-key playback remains a device check.

References: [Seanime provider contract](https://seanime.gitbook.io/seanime-extensions/content-providers/anime-torrent-provider), [Core APIs](https://seanime.gitbook.io/seanime-extensions/seanime/core-apis), [TorBox API](https://api-docs.torbox.app/).
