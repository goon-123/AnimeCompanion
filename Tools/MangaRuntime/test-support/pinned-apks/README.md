# Pinned extension regression inputs

These 59 unmodified APKs were published by the Tachiyomi/Keiyoushi extension contributors and are retained solely for offline regression tests after historical release URLs stopped resolving. They are not included in the Release application.

- Original filenames, distribution URLs, SHA-256 digests and test coverage are recorded in `../../support/compatibility-fixtures.json`.
- Upstream source and contributor notices: https://github.com/keiyoushi/extensions-source
- Upstream license: Apache License 2.0, included in `LICENSE`.

The bytes were recovered from the hash-verified fixtures of this repository's successful runtime build (Actions run 40337296297, artifact 12657586488). Every file matches its original manifest digest. `scripts/test-manga-runtime.sh` checks all pinned APK digests before running any test. The three classic interpreter fixtures continue to come from its independently verified Git checkout.
