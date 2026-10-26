# Pinned extension regression input

`tachiyomi-all.mangaplus-v1.6.67.apk` is the unmodified MangaPlus extension published by the Tachiyomi/Keiyoushi extension contributors. This copy is retained solely as an offline regression fixture after its upstream release download stopped resolving. It is not included in the Release application.

- Original distribution: https://github.com/keiyoushi/extensions/releases/download/58fd63f/tachiyomi-all.mangaplus-v1.6.67.apk
- Upstream source and notices: https://github.com/keiyoushi/extensions-source
- Upstream license: Apache License 2.0, included in `LICENSE`.
- SHA-256: `1be92d6255eae1954c4deb525c96cd4933b37be85a927b1d5a3793b818ab8f98`.

The bytes were recovered from the hash-verified fixtures of the repository's successful runtime build (Actions run 40337296297, artifact 12657586488). `scripts/test-manga-runtime.sh` checks the original pinned digest before running any fixture, including this one.
