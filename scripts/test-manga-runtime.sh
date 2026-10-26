#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/prepare-manga-interpreter.py
fixture_dir="$PWD/Tools/MangaRuntime/target/fixtures"
mkdir -p "$fixture_dir"
for file in tachiyomi-en.mangapill-v1.4.9.apk tachiyomi-vi.cuutruyenmoe-v1.6.3.apk tachiyomi-all.akuma-v1.4.10.apk; do
  if [[ ! -f "$fixture_dir/$file" ]]; then
    # prepare-manga-interpreter verifies this exact checkout and its patches.
    # Use its tracked fixtures instead of a second raw-CDN download; the SHA-256
    # checks below still validate every APK before it is executed.
    cp "Tools/MangaRuntime/target/patched-dexvm/fixtures/$file" "$fixture_dir/$file"
  fi
done
if [[ ! -f "$fixture_dir/tachiyomi-all.commitstrip-v1.6.0.apk" ]]; then
  echo "Fetching pinned fixture: tachiyomi-all.commitstrip-v1.6.0.apk"
  curl --proto '=https' --tlsv1.2 -fsSL --retry 2 \
    https://github.com/keiyoushi/extensions/releases/download/24bc6c2/tachiyomi-all.commitstrip-v1.6.0.apk \
    -o "$fixture_dir/tachiyomi-all.commitstrip-v1.6.0.apk"
fi
if [[ ! -f "$fixture_dir/tachiyomi-en.weebcentral-v1.6.25.apk" ]]; then
  echo "Fetching pinned fixture: tachiyomi-en.weebcentral-v1.6.25.apk"
  curl --proto '=https' --tlsv1.2 -fsSL --retry 2 \
    https://github.com/keiyoushi/extensions/releases/download/8ef06cd-1/tachiyomi-en.weebcentral-v1.6.25.apk \
    -o "$fixture_dir/tachiyomi-en.weebcentral-v1.6.25.apk"
fi
if [[ ! -f "$fixture_dir/tachiyomi-all.mangaplus-v1.6.67.apk" ]]; then
  echo "Fetching pinned fixture: tachiyomi-all.mangaplus-v1.6.67.apk"
  curl --proto '=https' --tlsv1.2 -fsSL --retry 2 \
    https://github.com/keiyoushi/extensions/releases/download/58fd63f/tachiyomi-all.mangaplus-v1.6.67.apk \
    -o "$fixture_dir/tachiyomi-all.mangaplus-v1.6.67.apk"
fi
while read -r release file; do
  if [[ ! -f "$fixture_dir/$file" ]]; then
    echo "Fetching pinned fixture: $file"
    curl --proto '=https' --tlsv1.2 -fsSL --retry 2 \
      "https://github.com/keiyoushi/extensions/releases/download/$release/$file" -o "$fixture_dir/$file"
  fi
done <<'PINS'
23345ef tachiyomi-en.omegascans-v1.6.52.apk
e97033f tachiyomi-en.toonily-v1.6.72.apk
e97033f tachiyomi-all.mangaball-v1.6.5.apk
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
4217666-0 tachiyomi-en.deathtollscans-v1.6.6.apk
bdcf84f tachiyomi-en.dynasty-v1.6.1.apk
cfc0199 tachiyomi-en.hiveworks-v1.6.2.apk
24bc6c2 tachiyomi-fr.furyosquad-v1.6.0.apk
b5d2cd5 tachiyomi-en.mangafoxfun-v1.6.38.apk
bdcf84f tachiyomi-en.assortedscans-v1.6.0.apk
bdcf84f tachiyomi-en.digitalcomicmuseum-v1.6.0.apk
4217666-2 tachiyomi-ja.rawkuma-v1.6.41.apk
bdcf84f tachiyomi-zh.manhuawu-v1.6.0.apk
d0c0864 tachiyomi-all.lanraragi-v1.6.1.apk
bdcf84f tachiyomi-all.mango-v1.6.0.apk
bdcf84f tachiyomi-all.stashapp-v1.6.0.apk
1319949 tachiyomi-en.mangadotnet-v1.6.25.apk
58fd63f tachiyomi-zh.favcomic-v1.6.4.apk
4217666-2 tachiyomi-zh.noyacg-v1.6.7.apk
ff521c1 tachiyomi-all.komga-v1.6.74.apk
2ba5b61 tachiyomi-zh.jinmantiantang-v1.6.59.apk
bdcf84f tachiyomi-all.tappytoon-v1.6.0.apk
cfc0199 tachiyomi-ar.arabmanhwa-v1.6.57.apk
7363e42 tachiyomi-ar.procomic-v1.6.0.apk
7363e42 tachiyomi-es.codearc-v1.6.2.apk
39e8efc tachiyomi-es.inmanga-v1.6.1.apk
4217666-1 tachiyomi-es.lectorjpg-v1.6.50.apk
4217666-1 tachiyomi-ja.linemanga-v1.6.1.apk
cfc0199 tachiyomi-ru.nudemoon-v1.6.32.apk
24bc6c2 tachiyomi-all.danbooru-v1.6.0.apk
4217666-0 tachiyomi-all.hentaifox-v1.6.18.apk
bdcf84f tachiyomi-all.pixiv-v1.6.0.apk
4217666-0 tachiyomi-all.webcomics-v1.6.11.apk
ac40914 tachiyomi-en.hentaihere-v1.6.1.apk
7363e42 tachiyomi-ko.sbxh-v1.6.1.apk
ac40914 tachiyomi-pt.nexusmangas-v1.6.1.apk
a0e93c0 tachiyomi-ru.wamanga-v1.6.2.apk
24bc6c2 tachiyomi-zh.comicabc-v1.6.0.apk
a2d7e26 tachiyomi-es.lectormonline-v1.6.4.apk
06f6d69 tachiyomi-ru.senkuro-v1.6.0.apk
06f6d69 tachiyomi-ru.senkognito-v1.6.0.apk
PINS
python3 - "$fixture_dir" <<'PY'
import hashlib, pathlib, sys
root = pathlib.Path(sys.argv[1])
expected = {
    'tachiyomi-en.omegascans-v1.6.52.apk': 'f63427eb1b468dc45210913f6c10637e98895d9f1b7d59ac6bc73a9d04b18743',
    'tachiyomi-en.toonily-v1.6.72.apk': '3cfefdaa4b798ef303b16d9d09c69b227ad76caa9ed13cdef495b42020af46b5',
    'tachiyomi-all.mangaball-v1.6.5.apk': 'b5fd0a8f5b5c99e346e8d4b639dffa50cbad9756e939cb32dba3fac21ae4857b',
    'tachiyomi-ru.senkuro-v1.6.0.apk': '85f79e81b858697454273c409c05564c914d83e930b7916e63fcec323b42b8f7',
    'tachiyomi-ru.senkognito-v1.6.0.apk': '33064a7cf823632d380b7d4c5617e2b71ba48ca013b9bb915e2a592ff624b0a9',
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
    'tachiyomi-en.deathtollscans-v1.6.6.apk': 'a5ce8f912140f5c9ba816b8119bf04e673a3e173acfa52631d287245824813e8',
    'tachiyomi-en.dynasty-v1.6.1.apk': '0c6bd0be254e73cca3401c6a7578a368c3fc9af2461c5b9fbe03fe6251eb2d72',
    'tachiyomi-en.hiveworks-v1.6.2.apk': '7d869e29b2f7835719ebef6600077556c13517063f29b7f825bc0997c4f06bf4',
    'tachiyomi-fr.furyosquad-v1.6.0.apk': 'd12bb8884031351379af39c99ce47632cd9fc3329624f6d3e682ab75288f85e3',
    'tachiyomi-en.mangafoxfun-v1.6.38.apk': '1e3ba3767c9f09455a1787f2b626c915cbb088feed5672816fcec0009c8514ba',
    'tachiyomi-en.assortedscans-v1.6.0.apk': '864b7da29949a73a5be754a07256d6103422cf2e69c39749530fb84b3c7c0fef',
    'tachiyomi-en.digitalcomicmuseum-v1.6.0.apk': '167187db99558eb918115dabbb33320f81968437565771385872a27391b6b468',
    'tachiyomi-ja.rawkuma-v1.6.41.apk': '4ac058403b9fd7ec2b5c9913c2dafa6022e06eb3ac8a306e297795f58cf9fc49',
    'tachiyomi-zh.manhuawu-v1.6.0.apk': 'a025a564c91368037728ad35da7975b3adbbbee88a1a7370e9e7e7c0f63c2257',
    'tachiyomi-all.lanraragi-v1.6.1.apk': '152a626bd08a1c92c3be2bbfc587cb8ece73aedca27a994d0f6fc5753fa14da6',
    'tachiyomi-all.mango-v1.6.0.apk': 'd78adac40c9db6d853508776250adcd648b7f61c0d0c8e11b912788db06e85e8',
    'tachiyomi-all.stashapp-v1.6.0.apk': '27f9fb02ad20982947d6abacb18fc9034e84d9c67d8b92d603ebd0b8b50ed78e',
    'tachiyomi-en.mangadotnet-v1.6.25.apk': 'df1987dc6f89b5111a0004b605a3422b50f1afa8b1ed2f2bcc3eda3b854fbdf9',
    'tachiyomi-zh.favcomic-v1.6.4.apk': '5b582b534d6f37850480d4ab0b74013b7020415337fff155f4fe1a0bf946933e',
    'tachiyomi-zh.noyacg-v1.6.7.apk': '119100c7bba5b7158644e0dd75ad0a8aa051b234fab268fe85ed0e1595b1971d',
    'tachiyomi-all.komga-v1.6.74.apk': '0fd95b938742d7f203281350c7f901098425b6fe5eafab873411e2430bd693b9',
    'tachiyomi-zh.jinmantiantang-v1.6.59.apk': 'baebb449741b28f110f88408ff5a7edf6fc76fae0d60134e4b71c15cb7c3d56a',
    'tachiyomi-all.tappytoon-v1.6.0.apk': '0512c19b9a1b3ad6e846cb62e5eb3a1fc640c4eddd6f1c6f2ec94eb8b1cc48b5',
    'tachiyomi-ar.arabmanhwa-v1.6.57.apk': '6f1255bf46426d80c61cb244aef0fe091c1332161178afb7f6323d3e86a7c018',
    'tachiyomi-ar.procomic-v1.6.0.apk': '96cdbd7033c7b050d70d9fa73531c7020beb005985c25b2e77b043ac2054e444',
    'tachiyomi-es.codearc-v1.6.2.apk': 'fae361c711f31104e4303dec63c69c1c4554e5b85de8ddd03caa5e1a2516b836',
    'tachiyomi-es.inmanga-v1.6.1.apk': '10d0bcc52ecb0e272c145af4d2c7a05f1b6dcecd6c415012e5f216284a4f15d0',
    'tachiyomi-es.lectorjpg-v1.6.50.apk': '13135c71b001bf86d601f7eeda291dabc5541d2caadfd4dc3ddbb289f7be2f76',
    'tachiyomi-ja.linemanga-v1.6.1.apk': '41dac9936f81e2446a86b14e76076fcf41551dcf59eddebb092b99714166dca7',
    'tachiyomi-ru.nudemoon-v1.6.32.apk': 'ef4d485fd8abe4ed5357094a4cfb5b14ef5945990512707279b058b55b16218b',
    'tachiyomi-all.danbooru-v1.6.0.apk': 'bcad22cfbb9a6b6d4405e6fe8b27ff2b6a8f388e8f29cb103533a8d82ab0ac72',
    'tachiyomi-all.hentaifox-v1.6.18.apk': '97d7d2d6b37192190a1de36ebaa0dc7fe0ce4be684b61d69547e8610372ca2ca',
    'tachiyomi-all.pixiv-v1.6.0.apk': 'a813adfc5a8e1d1bd9e0ed19a45e4237b8bc036595bdfd7de0f11dd3ce110eb3',
    'tachiyomi-all.webcomics-v1.6.11.apk': 'eb39e08062310f0640971e5ce4dbcb611b4cd393186933c91ac94dedd3e265c3',
    'tachiyomi-en.hentaihere-v1.6.1.apk': '6bff924148b9be583396ad8eb1f80ed66af646fe9c1fbb9ebdfc039ec28eefaa',
    'tachiyomi-ko.sbxh-v1.6.1.apk': '90ecb3072c12df46820255f9ab3b1bbb6e9da278a68771c166dd9a8915f905f9',
    'tachiyomi-pt.nexusmangas-v1.6.1.apk': 'e37bc8e33684b041dbd93c67a6f1f8a15eed1ed9f3ba1732392eed6fea825d66',
    'tachiyomi-ru.wamanga-v1.6.2.apk': '5e695c6704d713283f613816fb9655f66df6d2121058ae35ce9d14dac79bab68',
    'tachiyomi-zh.comicabc-v1.6.0.apk': '0180a4796d8152f1c3759dbf9fb0171d7a596b932fa861167256f4dd0ea2ebfb',
    'tachiyomi-es.lectormonline-v1.6.4.apk': '6315fcd1cde5f7b0f46ce715cb8a98bd845851a81a6d940d9dc89e6cbd117979',
}
for name, digest in expected.items():
    assert hashlib.sha256((root / name).read_bytes()).hexdigest() == digest, name
PY
python3 -c 'import hashlib; from pathlib import Path; assert hashlib.sha256(Path("Tools/MangaRuntime/test-support/shared-jvm-probe.dex").read_bytes()).hexdigest() == "11bc678a705469c525b3bdff11aedd045cf09894a15cb9ed994ec697f714d3db"'
MANGA_TEST_APK_DIR="$fixture_dir" cargo test --locked --manifest-path Tools/MangaRuntime/Cargo.toml -j 2
