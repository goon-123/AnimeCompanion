//! Published APKs interpret their own source code against neutral owned data.
use super::*;

const FOOL_CATALOG: &str =
    include_str!("../../../Tests/MangaRuntimeTests/OwnedFixtures/foolslide-catalog.html");
const FOOL_BOOK: &str =
    include_str!("../../../Tests/MangaRuntimeTests/OwnedFixtures/foolslide-book.html");
const FOOL_PAGES: &str =
    include_str!("../../../Tests/MangaRuntimeTests/OwnedFixtures/foolslide-pages.html");
const DYNASTY_CATALOG: &str =
    include_str!("../../../Tests/MangaRuntimeTests/OwnedFixtures/dynasty-catalog.html");
const DYNASTY_CHAPTER: &str =
    include_str!("../../../Tests/MangaRuntimeTests/OwnedFixtures/dynasty-chapter.json");
const HIVE_LATEST: &str =
    include_str!("../../../Tests/MangaRuntimeTests/OwnedFixtures/hiveworks-latest.html");

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
        .unwrap_or_else(|error| panic!("{op}: {error}"))
}
fn image(apk: &[u8], page: &Value) {
    let expected = page["imageURL"].as_str().unwrap().to_owned();
    let response = run(
        apk,
        json!({"op":"image","modern":true,"image":page}),
        move |request| {
            assert_eq!(request.url, expected);
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
            .decode(response["bodyBase64"].as_str().unwrap())
            .unwrap(),
        [0, 255, 23, 128]
    );
}

#[test]
fn foolslide_calendar_defaults_catalog_dated_chapters_and_ordered_pages() {
    let apk = apk("tachiyomi-en.deathtollscans-v1.6.6.apk");
    let catalog = run(&apk, json!({"op":"popular","modern":true}), |request| {
        assert!(request.url.ends_with("/directory/1/"));
        HttpResp::ok(FOOL_CATALOG)
    });
    assert_eq!(catalog["mangas"][0]["title"], "Owned story");
    let book = run(
        &apk,
        json!({"op":"book","modern":true,"timeZoneID":"UTC","manga":catalog["mangas"][0]}),
        |request| {
            assert_eq!(
                request.url,
                "https://reader.deathtollscans.net/series/owned"
            );
            HttpResp::ok(FOOL_BOOK)
        },
    );
    assert_eq!(book["chapters"].as_array().unwrap().len(), 2);
    assert_eq!(book["manga"]["author"], "Owned author");
    assert_eq!(book["manga"]["description"], "Owned description");
    let year = time::OffsetDateTime::now_utc().year();
    let expected = time::Date::from_calendar_date(year, time::Month::October, 20)
        .unwrap()
        .midnight()
        .assume_utc()
        .unix_timestamp()
        * 1000;
    assert_eq!(book["chapters"][0]["uploadedAt"], expected);
    assert_eq!(book["chapters"][1]["uploadedAt"], 1709164800000_i64);
    let local_book = run(
        &apk,
        json!({"op":"book","modern":true,"timeZoneID":"America/Los_Angeles","manga":catalog["mangas"][0]}),
        |_| HttpResp::ok(FOOL_BOOK),
    );
    assert_eq!(local_book["chapters"][1]["uploadedAt"], 1709193600000_i64);
    let pages = run(
        &apk,
        json!({"op":"pages","modern":true,"chapter":book["chapters"][0]}),
        |request| {
            assert_eq!(
                request.url,
                "https://reader.deathtollscans.net/read/owned/2"
            );
            HttpResp::ok(FOOL_PAGES)
        },
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
    image(&apk, &pages[0]);
}

#[test]
fn dynasty_formatter_zone_dated_chapter_and_json_reader() {
    let apk = apk("tachiyomi-en.dynasty-v1.6.1.apk");
    let catalog = run(&apk, json!({"op":"popular","modern":true}), |request| {
        assert!(
            request.url == "https://dynasty-scans.com"
                || request.url == "https://dynasty-scans.com/"
        );
        HttpResp::ok(DYNASTY_CATALOG)
    });
    assert_eq!(catalog["mangas"].as_array().unwrap().len(), 1);
    let book = run(
        &apk,
        json!({"op":"book","modern":true,"timeZoneID":"America/Los_Angeles","manga":catalog["mangas"][0]}),
        |request| {
            assert!(
                request.url.contains("/chapters/owned_story.json"),
                "{}",
                request.url
            );
            HttpResp::ok(DYNASTY_CHAPTER)
        },
    );
    assert_eq!(book["chapters"][0]["uploadedAt"], 1709164800000_i64);
    assert_eq!(book["manga"]["title"], "Owned story");
    let pages = run(
        &apk,
        json!({"op":"pages","modern":true,"chapter":book["chapters"][0]}),
        |_| HttpResp::ok(DYNASTY_CHAPTER),
    );
    assert_eq!(
        pages[0]["imageURL"],
        "https://dynasty-scans.com/owned-page-2.webp"
    );
    assert_eq!(
        pages[1]["imageURL"],
        "https://dynasty-scans.com/owned-page-1.webp"
    );
    image(&apk, &pages[0]);
}

#[test]
fn hiveworks_latest_uses_the_real_calendar_weekday() {
    let apk = apk("tachiyomi-en.hiveworks-v1.6.2.apk");
    let expected = time::OffsetDateTime::now_utc()
        .weekday()
        .to_string()
        .to_lowercase();
    let catalog = run(
        &apk,
        json!({"op":"latest","modern":true,"timeZoneID":"UTC"}),
        move |request| {
            assert_eq!(
                request.url,
                format!("https://hiveworkscomics.com/home/update-day/{expected}")
            );
            HttpResp::ok(HIVE_LATEST)
        },
    );
    assert_eq!(catalog["mangas"].as_array().unwrap().len(), 1);
    assert_eq!(catalog["mangas"][0]["title"], "Owned story");
}
