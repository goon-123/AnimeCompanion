//! Published APKs execute their own parsers, requests and DTO serializers.
use super::*;
const FURYO_CATALOG: &str =
    include_str!("../../../Tests/MangaRuntimeTests/OwnedFixtures/furyo-catalog.html");
const FURYO_BOOK: &str =
    include_str!("../../../Tests/MangaRuntimeTests/OwnedFixtures/furyo-book.html");
const FURYO_PAGES: &str =
    include_str!("../../../Tests/MangaRuntimeTests/OwnedFixtures/furyo-pages.html");
const HUB_CATALOG: &str =
    include_str!("../../../Tests/MangaRuntimeTests/OwnedFixtures/mangahub-catalog.json");
const HUB_BOOK: &str =
    include_str!("../../../Tests/MangaRuntimeTests/OwnedFixtures/mangahub-book.json");
const HUB_PAGES: &str =
    include_str!("../../../Tests/MangaRuntimeTests/OwnedFixtures/mangahub-pages.json");
const ADVENTURE_CATALOG: &str =
    include_str!("../../../Tests/MangaRuntimeTests/OwnedFixtures/mangadventure-catalog.json");
const ADVENTURE_BOOK: &str =
    include_str!("../../../Tests/MangaRuntimeTests/OwnedFixtures/mangadventure-book.json");
const ADVENTURE_CHAPTERS: &str =
    include_str!("../../../Tests/MangaRuntimeTests/OwnedFixtures/mangadventure-chapters.json");
const ADVENTURE_PAGES: &str =
    include_str!("../../../Tests/MangaRuntimeTests/OwnedFixtures/mangadventure-pages.json");

fn apk(name: &str) -> Vec<u8> {
    std::fs::read(format!(
        "{}/{name}",
        std::env::var("MANGA_TEST_APK_DIR").expect("Run test-manga-runtime.sh")
    ))
    .unwrap()
}
fn run(apk: &[u8], command: Value, http: impl Fn(&HttpData) -> HttpResp + 'static) -> Value {
    let op = command["op"].as_str().unwrap().to_owned();
    execute(apk, serde_json::from_value(command).unwrap(), http)
        .unwrap_or_else(|e| panic!("{op}: {e}"))
}
fn assert_reader(apk: &[u8], book: &Value, http: impl Fn(&HttpData) -> HttpResp + 'static) {
    let pages = run(
        apk,
        json!({"op":"pages","modern":true,"chapter":book["chapters"][0]}),
        http,
    );
    assert_eq!(pages.as_array().unwrap().len(), 2);
    assert_eq!(
        pages[0]["imageURL"],
        "https://images.example/owned-page-2.webp"
    );
    assert_eq!(
        pages[1]["imageURL"],
        "https://images.example/owned-page-1.webp"
    );
    let image = run(
        apk,
        json!({"op":"image","modern":true,"image":pages[0]}),
        |request| {
            assert_eq!(request.url, "https://images.example/owned-page-2.webp");
            HttpResp {
                code: 200,
                message: "OK".into(),
                headers: vec![],
                body: Some(vec![0, 255, 23, 128]),
            }
        },
    );
    assert_eq!(
        STANDARD
            .decode(image["bodyBase64"].as_str().unwrap())
            .unwrap(),
        [0, 255, 23, 128]
    );
}
#[test]
fn furyosquad_french_locale_catalog_dated_chapters_ordered_pages_and_images() {
    let apk = apk("tachiyomi-fr.furyosquad-v1.6.0.apk");
    let catalog = run(&apk, json!({"op":"popular","modern":true}), |request| {
        assert_eq!(request.url, "https://www.furyosociety.com/mangas");
        HttpResp::ok(FURYO_CATALOG)
    });
    assert_eq!(catalog["mangas"][0]["title"], "Owned story");
    let book = run(
        &apk,
        json!({"op":"book","modern":true,"timeZoneID":"UTC","manga":catalog["mangas"][0]}),
        |request| {
            assert_eq!(request.url, "https://www.furyosociety.com/series/owned/");
            HttpResp::ok(FURYO_BOOK)
        },
    );
    assert_eq!(book["manga"]["author"], "Owned author");
    assert_eq!(book["manga"]["artist"], "Owned artist");
    assert_eq!(book["chapters"].as_array().unwrap().len(), 2);
    assert_eq!(book["chapters"][0]["uploadedAt"], 1725062400000_i64);
    assert_eq!(book["chapters"][1]["uploadedAt"], 1709164800000_i64);
    assert_reader(&apk, &book, |request| {
        assert_eq!(request.url, "https://www.furyosociety.com/read/owned/2");
        HttpResp::ok(FURYO_PAGES)
    });
}
#[test]
fn mangahub_random_key_catalog_dated_chapters_plain_pages_and_images() {
    let apk = apk("tachiyomi-en.mangafoxfun-v1.6.38.apk");
    let catalog = run(&apk, json!({"op":"popular","modern":true}), |request| {
        assert_eq!(request.url, "https://api.mghcdn.com/graphql");
        let key = &request
            .headers
            .iter()
            .find(|(k, _)| k.eq_ignore_ascii_case("x-mhub-access"))
            .unwrap()
            .1;
        assert_eq!(key.len(), 32);
        assert!(key.bytes().all(|b| b.is_ascii_hexdigit()));
        HttpResp::ok(HUB_CATALOG)
    });
    assert_eq!(catalog["mangas"][0]["title"], "Owned story");
    let book = run(
        &apk,
        json!({"op":"book","modern":true,"manga":catalog["mangas"][0]}),
        |_| HttpResp::ok(HUB_BOOK),
    );
    assert_eq!(book["manga"]["author"], "Owned author");
    assert_eq!(book["chapters"][0]["uploadedAt"], 1709164800000_i64);
    assert_eq!(book["chapters"][0]["chapterNumber"], 1.5);
    assert_reader(&apk, &book, |_| HttpResp::ok(HUB_PAGES));
}
#[test]
fn mangadventure_delegated_iterables_catalog_book_pages_and_images() {
    let apk = apk("tachiyomi-en.assortedscans-v1.6.0.apk");
    let catalog = run(&apk, json!({"op":"popular","modern":true}), |request| {
        assert!(request
            .url
            .starts_with("https://assortedscans.com/api/v2/series?"));
        HttpResp::ok(ADVENTURE_CATALOG)
    });
    assert_eq!(catalog["mangas"][0]["title"], "Owned story");
    let book = run(
        &apk,
        json!({"op":"book","modern":true,"manga":catalog["mangas"][0]}),
        |request| {
            if request.url.contains("/chapters?") {
                HttpResp::ok(ADVENTURE_CHAPTERS)
            } else {
                assert_eq!(request.url, "https://assortedscans.com/api/v2/series/owned");
                HttpResp::ok(ADVENTURE_BOOK)
            }
        },
    );
    assert_eq!(book["manga"]["author"], "Owned author");
    assert_eq!(book["chapters"][0]["chapterNumber"], 1.5);
    assert_eq!(book["chapters"][0]["uploadedAt"], 1709164800000_i64);
    assert_reader(&apk, &book, |request| {
        assert_eq!(
            request.url,
            "https://assortedscans.com/api/v2/chapters/22/pages?track=true"
        );
        HttpResp::ok(ADVENTURE_PAGES)
    });
}
