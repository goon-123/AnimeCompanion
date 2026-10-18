#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
fixture_dir="$PWD/Tools/MangaRuntime/target/fixtures"
mkdir -p "$fixture_dir"
revision=38d3438d7e36b5c2c17414029fd36b2d717eefcb
for file in tachiyomi-en.mangapill-v1.4.9.apk tachiyomi-vi.cuutruyenmoe-v1.6.3.apk tachiyomi-all.akuma-v1.4.10.apk; do
  if [[ ! -f "$fixture_dir/$file" ]]; then
    curl --proto '=https' --tlsv1.2 -fsSL --retry 2 \
      "https://raw.githubusercontent.com/tachibana-shin/dexvm/$revision/fixtures/$file" -o "$fixture_dir/$file"
  fi
done
if [[ ! -f "$fixture_dir/tachiyomi-all.commitstrip-v1.6.0.apk" ]]; then
  curl --proto '=https' --tlsv1.2 -fsSL --retry 2 \
    https://github.com/keiyoushi/extensions/releases/download/24bc6c2/tachiyomi-all.commitstrip-v1.6.0.apk \
    -o "$fixture_dir/tachiyomi-all.commitstrip-v1.6.0.apk"
fi
python3 - "$fixture_dir" <<'PY'
import hashlib, pathlib, sys
root = pathlib.Path(sys.argv[1])
expected = {
    'tachiyomi-en.mangapill-v1.4.9.apk': 'a89cedebe600d4545625b59022b4f241d8416c245916cb451476aaa954451b5c',
    'tachiyomi-vi.cuutruyenmoe-v1.6.3.apk': '508a81325727bbf2ec7151265dcf24a294d0d0dab5b639c7ffbb902809814340',
    'tachiyomi-all.akuma-v1.4.10.apk': '9f5e744ee3066ccf0c785dc8f427af8b7854933997eee1fe349fea388d4ba39a',
    'tachiyomi-all.commitstrip-v1.6.0.apk': 'f843f2c7ded62a2da5762e6c68547c89c8e200ab26c4f3805b24b9223d046fb9',
}
for name, digest in expected.items():
    assert hashlib.sha256((root / name).read_bytes()).hexdigest() == digest, name
PY
MANGA_TEST_APK_DIR="$fixture_dir" cargo test --locked --manifest-path Tools/MangaRuntime/Cargo.toml -j 2
