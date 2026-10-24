# Safari → VidHub

The Safari web extension is embedded in AnimeCompanion and first shipped in 0.17.0/build 36. It requires iOS/iPadOS 18 or later; the host app retains its iOS 17 minimum.

## Enable on iPhone or iPad

1. Sign and install the entire IPA, **including its SafariVideoExtension.appex**. If the sideloading tool asks whether to retain app extensions, keep this extension and sign it as well as the app.
2. Open Settings → Apps → Safari → Extensions → **Anime Companion – VidHub** and enable it.
3. Set website access to **All Websites → Allow** for detection wherever you browse. An embedded player may require permission for its own hostname. Private Browsing has its own Safari access setting.
4. Reload an already-open page and start its video. Tap **Open in VidHub** on the prompt, or open Safari's page/Extensions menu → **Anime Companion – VidHub** to see detected streams.

The toolbar popup provides global detection and automatic-prompt switches, per-website exclusion/re-enable, a reset for website preferences, and a manual scan/stream picker. Dismissing a prompt suppresses it for that video for the current page lifetime. New videos can prompt again. Opening is always an explicit tap and may also show iOS's confirmation for opening another app.

Build 69 repairs recovery with partial/stale Safari sender-tab URLs and a missing MAIN-world observer. **Scan again** reinstalls both idempotent scripts even if an isolated script was already acknowledging messages. **Open from webpage** places the selected stream's launch link in the top-level page; close the extension menu and tap that link. This also works for embedded media and manual-only mode. It does not turn on automatic prompts. A session-storage failure uses a bounded memory cache, never persistent URL storage; rescanning rebuilds that cache after a background restart.

## Detection and handoff

- Declarative MAIN-world and isolated scripts run at document start in permitted HTTP(S) frames. Safari 18's `content_scripts.world` support is required; `match_about_blank` also covers inherited player frames on Safari 18.4 and later. The toolbar can inject the scripts after website access was granted to an already-loaded page.
- Observe actual video sources/source elements, media events, open and subsequently created shadow trees, resource timing, and successful fetch/XHR response URL/content-type metadata. Do not read request bodies, consume media responses, fetch playlists, or extract cookies. Native `fetch` still returns its original promise and response.
- Direct MP4/WebM/etc. and HLS/DASH playlist URLs can be offered. Extensionless URLs can be recognized from video elements or response MIME types. Transport chunks, audio-only files, encryption keys and `blob:` addresses are excluded. A blob player may use a recent manifest observed in its own frame, but opaque players are not guaranteed to be resolvable.
- Rank the actual playing source first. A visible video with sufficient area can prompt; muted autoplay without recent user interaction does not. Use one top-page prompt for embedded players, with a manual stream list to select another candidate. Detected DRM media is excluded; no DRM circumvention is attempted.
- Build the documented `open-vidhub://x-callback-url/play` URL with the media URL, title and available current position. Percent-encode values exactly once, preserving signed queries. Pause page videos after an explicit open tap. Do not create AniList mappings, playback callback requests, or library writes for Safari videos.
- `webRequest` is intentionally absent: Apple does not support it in iOS Safari extensions. Some cookie-, referrer-, custom-header- or license-dependent streams cannot be played by handing over a URL. VidHub's documented `/play` API does not expose arbitrary HTTP headers or Safari-session transfer. No claim of every-site compatibility is made.

## Storage and permissions

Only enable/prompt settings and excluded hostnames persist in `browser.storage.local`. Detected stream URLs are kept in the extension's session storage, bounded to 1.5 MB/12 recent tabs and eight frames per tab. Closing a tab, navigating/reloading or disabling its website clears its cached links. Safari can discard session state; the page observer can report again. No analytics, external resolver, proxy, remote code, or persistent URL history is used. A selected media URL is shared with the installed VidHub app only after the user taps Open.

HTTP(S) host access is needed for automatic detection and iframe handling. `activeTab`/`scripting` support manual activation on an already-open page. The extension does not request cookies, history, downloads, native messaging or unrestricted network request interception. There is no app-group entitlement to complicate sideloading.

## Verification

```sh
python3 scripts/check-safari-bundle.py
npm --prefix Tools/SafariExtension ci --ignore-scripts --no-audit --no-fund
npm --prefix Tools/SafariExtension test
cd Tools/SafariExtension
npx playwright install --with-deps webkit
npm run test:browser
```

Node regressions cover signed-link encoding/positions, source ranking, iframe isolation, suppressed prompts, DRM exclusion, bounded reports/cache, background suspension/restart, website preferences, navigation and privacy. WebKit tests exercise real video playback, the prompt, embedded frames, extensionless response detection, SPA cleanup and inert rendering. Their browser API bridge tests JavaScript behavior; it is not a substitute for activating the signed Safari extension and launching an installed VidHub on a real iPhone/iPad. Native UI checks verify the setup page on both device families. The IPA workflow separately verifies the actual embedded extension executable, manifest/resources, bundle ID and matching versions before packaging.

References: [Apple extension compatibility](https://developer.apple.com/documentation/safariservices/assessing-your-safari-web-extension-s-browser-compatibility), [MDN content-script compatibility](https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/manifest.json/content_scripts), [VidHub integration](https://vidhub.okaapps.com/3rd-party-app-integration/).
# Playback compatibility — build 72

Compatible opening is the default and uses VidHub’s documented Apple `/open` method with only the encoded media URL. Resume playback uses `/play` with URL and position; neither Safari opener attaches anime tracking callbacks or replaces the media filename with a webpage title. The popup remembers the preferred method, offers an alternate opener for each stream, and can copy the direct stream URL on an explicit tap. The page prompt offers the same alternate/copy actions. A public MDN sample is available in the popup and app setup screen to distinguish a generic VidHub failure from a provider-specific stream failure. Reload the video webpage after updating the extension.

Both methods keep signed query strings intact. Automated browser tests decode the handoff and play that URL using a local owned fixture. Actual iOS Safari-to-installed-VidHub playback is a separate device check. A URL alone cannot supply Safari’s login cookies, custom referrers or DRM playback session; no proxy, cookie export or unsupported header URL syntax is implemented.
