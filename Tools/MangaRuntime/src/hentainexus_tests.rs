//! The published APK parses owned responses and decodes owned page metadata.
use super::*;

fn apk() -> Vec<u8> {
    std::fs::read(format!(
        "{}/tachiyomi-en.hentainexus-v1.6.20.apk",
        std::env::var("MANGA_TEST_APK_DIR").expect("Run test-manga-runtime.sh")
    ))
    .unwrap()
}
fn run(apk: &[u8], command: Value, html: &'static str) -> Value {
    execute(apk, serde_json::from_value(command).unwrap(), move |_| {
        HttpResp::ok(html)
    })
    .unwrap()
}
const CATALOG: &str =
    include_str!("../../../Tests/MangaRuntimeTests/OwnedFixtures/hentainexus-catalog.html");
const DETAILS: &str =
    include_str!("../../../Tests/MangaRuntimeTests/OwnedFixtures/hentainexus-details.html");
const READER: &str =
    include_str!("../../../Tests/MangaRuntimeTests/OwnedFixtures/hentainexus-pages.html");

#[test]
fn hentainexus_popular_latest_search_and_dated_chapter() {
    let apk = apk();
    for command in [
        json!({"op":"popular","modern":true}),
        json!({"op":"popular","modern":true,"page":2}),
        json!({"op":"latest","modern":true,"page":2}),
        json!({"op":"search","modern":true,"query":"Owned","page":2}),
    ] {
        let catalog = run(&apk, command, CATALOG);
        assert_eq!(catalog["mangas"].as_array().unwrap().len(), 2);
        assert_eq!(catalog["mangas"][0]["title"], "Owned story");
        assert_eq!(catalog["mangas"][0]["url"], "/view/42");
        assert_eq!(
            catalog["mangas"][0]["thumbnailURL"],
            "https://images.example/owned-cover.png"
        );
        assert_eq!(catalog["hasNext"], true);
    }
    let book = run(
        &apk,
        json!({"op":"book","modern":true,"manga":{"url":"/view/42","title":"Owned story"}}),
        DETAILS,
    );
    assert_eq!(book["manga"]["author"], "Owned author, Owned artist");
    assert_eq!(book["manga"]["genre"], "Owned tag");
    assert_eq!(book["chapters"].as_array().unwrap().len(), 1);
    assert_eq!(book["chapters"][0]["url"], "/read/42");
    assert_eq!(book["chapters"][0]["uploadedAt"], 1_792_454_400_000_i64);
}

#[test]
fn hentainexus_decodes_owned_pages_in_source_order_and_transports_images() {
    let apk = apk();
    let pages = run(
        &apk,
        json!({"op":"pages","modern":true,"chapter":{"url":"/read/42","name":"Owned chapter"}}),
        READER,
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
    let image = execute(
        &apk,
        serde_json::from_value(json!({"op":"image","modern":true,"image":pages[0]})).unwrap(),
        |request| {
            assert_eq!(request.url, "https://images.example/owned-page-2.webp");
            HttpResp {
                code: 200,
                message: "OK".into(),
                headers: vec![],
                body: Some(vec![0, 255, 23, 128]),
            }
        },
    )
    .unwrap();
    assert_eq!(
        STANDARD
            .decode(image["bodyBase64"].as_str().unwrap())
            .unwrap(),
        [0, 255, 23, 128]
    );
}

#[test]
fn hentainexus_image_quality_preferences_and_invalid_readers() {
    let apk = apk();
    let inspected = run(&apk, json!({"op":"inspect"}), "");
    let id = inspected["sources"][0]["id"].as_str().unwrap();
    for (quality, extension) in [("webp", "webp"), ("source", "png"), ("avif", "avif")] {
        let pages = run(
            &apk,
            json!({"op":"pages","modern":true,"chapter":{"url":"/read/42"},
                "settingsSourceID":id,"settings":{"pref_image_format":{"type":"string","value":quality}}}),
            READER,
        );
        assert_eq!(
            pages[0]["imageURL"],
            format!("https://images.example/owned-page-2.{extension}")
        );
    }
    let empty = run(
        &apk,
        json!({"op":"pages","modern":true,"chapter":{"url":"/read/42"}}),
        include_str!("../../../Tests/MangaRuntimeTests/OwnedFixtures/hentainexus-empty.html"),
    );
    assert!(empty.as_array().unwrap().is_empty());
    for html in [
        "<html><script>unrelated()</script></html>",
        "<html><script>initReader(\"AA==\",0)</script></html>",
        include_str!("../../../Tests/MangaRuntimeTests/OwnedFixtures/hentainexus-fallback.html"),
    ] {
        let result = execute(
            &apk,
            serde_json::from_value(json!({"op":"pages","modern":true,"chapter":{"url":"/read/42"},
                "settingsSourceID":id,"settings":{"pref_image_format":{"type":"string","value":"source"}}})).unwrap(),
            move |_| HttpResp::ok(html),
        );
        assert!(
            result.is_err(),
            "Unavailable reader quality or malformed input must not return pages"
        );
    }
}

#[test]
fn hentainexus_settings_schema_executes_the_real_typed_set_array_path() {
    let apk = apk();
    let settings = run(&apk, json!({"op":"settings","modern":true}), "");
    let controls = settings["settings"].as_array().unwrap();
    assert!(!controls.is_empty());
    assert!(controls.iter().any(|item| item["control"] == "choice"));
    assert!(controls
        .iter()
        .any(|item| item["key"] == "pref_image_format"));
}
