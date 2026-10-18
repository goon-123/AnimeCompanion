# On-device Keiyoushi extensions — first stage

Settings → Manga extensions accepts `https://keiyoushi.github.io` and the official repository/install-link variants. It reads the current gzip/protobuf v2 catalog; the obsolete JSON list is never used. Search, language/mature-source filters, manual installation/updates, enable/disable, removal and catalog refresh are included. Cached catalogs remain available when a refresh fails.

The runtime is bundled into the iPhone/iPad app. It interprets each downloaded APK's DEX bytecode locally using the pinned Apache-2.0 `dexvm` dependency. There is no Android device, Java process, Suwayomi server, JIT entitlement or remote source-execution service. The interpreter has explicit classic and 1.6 coroutine API paths. Swift owns HTTPS requests and filesystem writes. Package hashes are checked against the official published release inventory before execution; the APK's package/version must match the selected catalog entry. This is integrity verification over HTTPS, **not an implementation of Android APK signer verification**.

Installation enumerates the actual bytecode's sources before saving. Updating writes a new content-addressed APK and atomically replaces saved state before removing the old file. Corrupt state is preserved instead of overwritten. Cancellation, request/depth/instruction/response-size limits and fresh contexts keep source work off the UI thread. Extensions have no guest filesystem, process or environment access. HTTPS is limited to public-looking DNS names on port 443, including redirects; this is not a DNS-rebinding defense or an OS process sandbox. Each operation has its own ephemeral, credential-free URLSession; no Safari cookies or app account credentials are supplied.

## Compatibility and reader scope

This is an **experimental extension layer**, not a universal compatibility claim. Matching extension API versions establishes eligibility to try a package, not full support for every source. The manager explicitly labels this distinction. Source browsing supports popular/latest/search and pagination; the bridge also exposes details, chapters and page lists for the next reader stage. This change does not add a page reader, downloads, AniList manga tracking, source preference screens or browser-challenge handling.

Verification includes real legacy APK metadata and request/HTML parsing; real 1.6 APK metadata; the current Commit Strip 1.6.0 extension's own catalog/detail code; the live Keiyoushi catalog. Live probes found HTTP 403 responses from MangaPill/CuuTruyen in this environment and an unsupported descriptor API in current MANGA Plus. Those probes are not reported as successful source compatibility. Authenticated/challenged sources and less common host APIs need further runtime work. No copyrighted chapter/image fixtures or extension APKs are bundled in the production app.

## Build and verification

```bash
# macOS/Xcode: device arm64 plus universal arm64/x86_64 simulator XCFramework
bash scripts/build-manga-runtime.sh
# Fetch integrity-pinned APKs into ignored test storage, then run offline tests
bash scripts/test-manga-runtime.sh
swift test -j 2
xcodegen generate
```

CI builds the XCFramework once and shares it, test-only APK fixtures and license notices with native build/test jobs. The layout checks run `MangaRuntimeTests` on both iPhone and iPad simulators, exercising the actual Swift/C/Rust bridge and a 1.6 catalog. Test APKs are resources of the test bundle only. Third-party license notices are generated from Cargo's resolved dependency metadata and displayed in About → Runtime licenses.

`support/serialization-decoder.dex` contains unmodified Apache-2.0 classes from JetBrains' kotlinx.serialization 1.9.0 (AbstractDecoder, serialization kinds and protobuf annotations), filling missing host types. It does not contain website-specific logic. Rebuild with `python3 scripts/rebuild-manga-support.py` (Java 17); both input artifacts and resulting bytecode are hash-pinned. Standard Kotlin progression iteration and Java functional/map APIs are implemented in the host bridge; unsupported abstract calls fail explicitly.
