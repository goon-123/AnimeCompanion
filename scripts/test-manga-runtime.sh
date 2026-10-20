#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/prepare-manga-interpreter.py
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
if [[ ! -f "$fixture_dir/tachiyomi-en.weebcentral-v1.6.25.apk" ]]; then
  curl --proto '=https' --tlsv1.2 -fsSL --retry 2 \
    https://github.com/keiyoushi/extensions/releases/download/8ef06cd-1/tachiyomi-en.weebcentral-v1.6.25.apk \
    -o "$fixture_dir/tachiyomi-en.weebcentral-v1.6.25.apk"
fi
if [[ ! -f "$fixture_dir/tachiyomi-all.mangaplus-v1.6.67.apk" ]]; then
  curl --proto '=https' --tlsv1.2 -fsSL --retry 2 \
    https://github.com/keiyoushi/extensions/releases/download/58fd63f/tachiyomi-all.mangaplus-v1.6.67.apk \
    -o "$fixture_dir/tachiyomi-all.mangaplus-v1.6.67.apk"
fi
while read -r release file; do
  if [[ ! -f "$fixture_dir/$file" ]]; then
    curl --proto '=https' --tlsv1.2 -fsSL --retry 2 \
      "https://github.com/keiyoushi/extensions/releases/download/$release/$file" -o "$fixture_dir/$file"
  fi
done <<'PINS'
8ef06cd-0 tachiyomi-all.mangadex-v1.6.0.apk
7363e42 tachiyomi-all.mangafire-v1.6.34.apk
4217666-0 tachiyomi-en.asurascans-v1.6.69.apk
24bd7e6 tachiyomi-en.comix-v1.6.54.apk
e97033f tachiyomi-en.manhuaus-v1.6.60.apk
7363e42 tachiyomi-all.cubari-v1.6.0.apk
7363e42 tachiyomi-all.mangaup-v1.6.3.apk
7363e42 tachiyomi-en.hiperdex-v1.6.89.apk
7363e42 tachiyomi-all.namicomi-v1.6.0.apk
24bc6c2 tachiyomi-all.comicfury-v1.6.0.apk
24bc6c2 tachiyomi-all.comicskingdom-v1.6.0.apk
bdcf84f tachiyomi-all.projectsuki-v1.6.0.apk
4217666-0 tachiyomi-en.mangabuddy-v1.6.34.apk
4217666-0 tachiyomi-en.hentainexus-v1.6.20.apk
cfc0199 tachiyomi-en.flamecomics-v1.6.1.apk
7363e42 tachiyomi-en.allanime-v1.6.29.apk
PINS
python3 - "$fixture_dir" <<'PY'
import hashlib, pathlib, sys
root = pathlib.Path(sys.argv[1])
expected = {
    'tachiyomi-en.mangapill-v1.4.9.apk': 'a89cedebe600d4545625b59022b4f241d8416c245916cb451476aaa954451b5c',
    'tachiyomi-vi.cuutruyenmoe-v1.6.3.apk': '508a81325727bbf2ec7151265dcf24a294d0d0dab5b639c7ffbb902809814340',
    'tachiyomi-all.akuma-v1.4.10.apk': '9f5e744ee3066ccf0c785dc8f427af8b7854933997eee1fe349fea388d4ba39a',
    'tachiyomi-all.commitstrip-v1.6.0.apk': 'f843f2c7ded62a2da5762e6c68547c89c8e200ab26c4f3805b24b9223d046fb9',
    'tachiyomi-en.weebcentral-v1.6.25.apk': '04331a9b4bb878325dfca1079757c9152cdf66916f7859d0dddf41cf26553d30',
    'tachiyomi-all.mangaplus-v1.6.67.apk': '1be92d6255eae1954c4deb525c96cd4933b37be85a927b1d5a3793b818ab8f98',
    'tachiyomi-all.mangadex-v1.6.0.apk': '12fde77601d48c8b231340694db8446fba5a555ced4109b231c9d2e3000915fb',
    'tachiyomi-all.mangafire-v1.6.34.apk': '77abea779ed379388d79c6461b8910fae9e067dc017164b62df8fb323f15bebf',
    'tachiyomi-en.asurascans-v1.6.69.apk': '559144ddf25bc7f348efa523318e45b7544727a55f3c5ddc4bd91b3a861295f3',
    'tachiyomi-en.comix-v1.6.54.apk': '6053794beb3416e8bb04fd0f523c8a0dede2aa4543422f45ad41a7526324fd6e',
    'tachiyomi-en.manhuaus-v1.6.60.apk': 'eed10bcba241ef0fa6549762c0de5d327c9e1f341419803ac5de645777e2ed46',
    'tachiyomi-all.cubari-v1.6.0.apk': 'd5289a0a94376a6aea232119c39b28cd8362c6b6de95d053ad0e6b460bc8fbb2',
    'tachiyomi-all.mangaup-v1.6.3.apk': '486e0cd864cc9eb5bceff566c9790737f508c1b35b50fa04538d30ad6036ac55',
    'tachiyomi-en.hiperdex-v1.6.89.apk': '7ac5566a04d6cb7105fcaf7570d7edca985366393f4589c067a2bc18e4772a8f',
    'tachiyomi-all.namicomi-v1.6.0.apk': 'f357ccaa47f197b55eb0223ed83d5ee1b835c895a8162593f59c9e8790391c22',
    'tachiyomi-all.comicfury-v1.6.0.apk': '526500f49ba9a016675439e538fbbfd92cdf35047e806c0156c4d4ab24a4a92a',
    'tachiyomi-all.comicskingdom-v1.6.0.apk': '3123f5c96374f7e6d8fa4cda3c9602b3897c646377d096627cf3e9b319f556d8',
    'tachiyomi-all.projectsuki-v1.6.0.apk': 'ef32135fd2aec84d8b949a58de255272dfdb9668298eb351f9d3438032fde7a8',
    'tachiyomi-en.mangabuddy-v1.6.34.apk': '6db9eb23ec4c065632de8ad425c3db6a7e5a373826190d14e2c25ac9b0ef5b25',
    'tachiyomi-en.hentainexus-v1.6.20.apk': '3cbfbbdd6e4bd1cac8116df8d86ad0d6dc07cedf2197b15a99a51910f3d7cc56',
    'tachiyomi-en.flamecomics-v1.6.1.apk': '83199410013398b1552887b43b30355d575ce32493d394c1b62f5ded2d1092d9',
    'tachiyomi-en.allanime-v1.6.29.apk': '88f751348962664bab7b74ede9aa209583968f6ed8508e08cb1e9f8bcc62cee4',
}
for name, digest in expected.items():
    assert hashlib.sha256((root / name).read_bytes()).hexdigest() == digest, name
PY
MANGA_TEST_APK_DIR="$fixture_dir" cargo test --locked --manifest-path Tools/MangaRuntime/Cargo.toml -j 2
