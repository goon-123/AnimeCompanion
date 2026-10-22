//! Exact published APKs exercise the shared collection APIs against owned data.
use super::*;
fn apk(name: &str) -> Vec<u8> {
    std::fs::read(format!(
        "{}/{name}",
        std::env::var("MANGA_TEST_APK_DIR").expect("Run test-manga-runtime.sh")
    ))
    .unwrap()
}
fn fixture(name: &str) -> String {
    std::fs::read_to_string(format!(
        "{}/../../Tests/MangaRuntimeTests/OwnedFixtures/{name}",
        env!("CARGO_MANIFEST_DIR")
    ))
    .unwrap()
}
fn run(bytes: &[u8], mut command: Value, http: impl Fn(&HttpData) -> HttpResp + 'static) -> Value {
    command["modern"] = json!(true);
    command["timeZoneID"] = json!("UTC");
    execute(bytes, serde_json::from_value(command).unwrap(), http).unwrap()
}
fn image(bytes: &[u8], page: &Value, referer: Option<&'static str>) {
    let expected = page["imageURL"].as_str().unwrap().to_owned();
    let value = run(bytes, json!({"op":"image","image":page}), move |r| {
        assert_eq!(r.url, expected);
        if let Some(referer) = referer {
            assert!(r
                .headers
                .iter()
                .any(|(k, v)| k.eq_ignore_ascii_case("referer") && v == referer));
        }
        HttpResp {
            code: 200,
            message: "OK".into(),
            headers: vec![],
            body: Some(vec![0, 255, 23, 128]),
        }
    });
    assert_eq!(
        STANDARD
            .decode(value["bodyBase64"].as_str().unwrap())
            .unwrap(),
        [0, 255, 23, 128]
    );
}
#[test]
fn collection_extension_factories_and_settings_use_real_guest_types() {
    for name in [
        "tachiyomi-all.danbooru-v1.6.0.apk",
        "tachiyomi-all.hentaifox-v1.6.18.apk",
        "tachiyomi-all.pixiv-v1.6.0.apk",
        "tachiyomi-all.webcomics-v1.6.11.apk",
        "tachiyomi-en.hentaihere-v1.6.1.apk",
        "tachiyomi-ko.sbxh-v1.6.1.apk",
        "tachiyomi-pt.nexusmangas-v1.6.1.apk",
        "tachiyomi-ru.wamanga-v1.6.2.apk",
        "tachiyomi-zh.comicabc-v1.6.0.apk",
    ] {
        let bytes = apk(name);
        for op in ["inspect", "settings"] {
            let result = execute(
                &bytes,
                serde_json::from_value(json!({"op":op,"modern":true})).unwrap(),
                |_| panic!("Inspection must not network"),
            );
            assert!(result.is_ok(), "{name} {op}: {result:?}");
        }
    }
}
#[test]
fn wamanga_lazy_svelte_lines_catalog_dated_chapters_sorted_pages_and_image() {
    let bytes = apk("tachiyomi-ru.wamanga-v1.6.2.apk");
    let catalog = run(&bytes, json!({"op":"popular"}), |r| {
        assert!(r.url.starts_with("https://wamanga.ru/catalog/__data.json?"));
        HttpResp::ok(fixture("wamanga-catalog.jsonl"))
    });
    assert_eq!(catalog["mangas"][0]["title"], "Owned story");
    assert_eq!(catalog["hasNext"], false);
    let book = run(
        &bytes,
        json!({"op":"book","manga":catalog["mangas"][0]}),
        |r| {
            assert!(r
                .url
                .starts_with("https://wamanga.ru/manga/owned/__data.json?"));
            HttpResp::ok(fixture("wamanga-book.jsonl"))
        },
    );
    assert_eq!(book["manga"]["description"], "Owned description");
    assert_eq!(book["chapters"][0]["uploadedAt"], 1_709_210_096_123_i64);
    assert_eq!(book["chapters"][1]["uploadedAt"], -1_i64);
    let pages = run(
        &bytes,
        json!({"op":"pages","chapter":book["chapters"][0]}),
        |r| {
            assert!(r
                .url
                .starts_with("https://wamanga.ru/manga/owned/glava-2/__data.json?"));
            HttpResp::ok(fixture("wamanga-pages.jsonl"))
        },
    );
    assert_eq!(pages[0]["imageURL"], "https://wamanga.ru/owned-page-1.webp");
    assert_eq!(pages[1]["imageURL"], "https://wamanga.ru/owned-page-2.webp");
    image(&bytes, &pages[0], None);
}
#[test]
fn comicabc_utf16_dictionary_catalog_details_and_chapters() {
    let bytes = apk("tachiyomi-zh.comicabc-v1.6.0.apk");
    let catalog = run(&bytes, json!({"op":"popular"}), |r| {
        assert_eq!(r.url, "https://www.8comic.com/comic/h-1.html");
        HttpResp::ok(fixture("comicabc-catalog.html"))
    });
    assert_eq!(catalog["mangas"][0]["title"], "Owned story");
    assert_eq!(catalog["hasNext"], true);
    let book = run(
        &bytes,
        json!({"op":"book","manga":catalog["mangas"][0]}),
        |r| {
            assert_eq!(r.url, "https://www.8comic.com/comic/owned.html");
            HttpResp::ok(fixture("comicabc-book.html"))
        },
    );
    assert_eq!(book["manga"]["description"], "Owned description");
    assert_eq!(book["chapters"][0]["name"], "Chapter 2");
    assert_eq!(book["chapters"][1]["name"], "Chapter 1");
}
#[test]
fn webcomics_latest_uses_array_last_and_the_guest_user_agent_interceptor() {
    let bytes = apk("tachiyomi-all.webcomics-v1.6.11.apk");
    let catalog = run(&bytes, json!({"op":"latest"}), |r| {
        if r.url == "https://keiyoushi.github.io/user-agents/user-agents.json" {
            return HttpResp::ok(r#"{"desktop":["Owned desktop agent"]}"#);
        }
        assert_eq!(r.url, "https://webcomicsapp.com/en/genres/all/all/newest/1");
        assert!(r
            .headers
            .iter()
            .any(|(k, v)| k.eq_ignore_ascii_case("user-agent") && v == "Owned desktop agent"));
        HttpResp::ok(
            r#"<html><body><div class="grid"><a href="/en/owned/owned-name/owned-id"><p class="text-ink">Owned story</p><img src="https://images.example/owned-cover.webp"></a></div></body></html>"#,
        )
    });
    assert_eq!(catalog["mangas"][0]["title"], "Owned story");
}
#[test]
fn hentaihere_character_range_filters_catalog_chapters_ordered_pages_and_image() {
    let bytes = apk("tachiyomi-en.hentaihere-v1.6.1.apk");
    let catalog = run(&bytes, json!({"op":"popular"}), |r| {
        assert!(r.url.starts_with("https://hentaihere.com/") && r.url.ends_with("/most-viewed"));
        HttpResp::ok(fixture("hentaihere-catalog.html"))
    });
    assert_eq!(catalog["mangas"][0]["title"], "Owned story");
    assert_eq!(catalog["hasNext"], false);
    let book = run(
        &bytes,
        json!({"op":"book","manga":catalog["mangas"][0]}),
        |r| {
            assert_eq!(r.url, "https://hentaihere.com/original/owned");
            HttpResp::ok(fixture("hentaihere-book.html"))
        },
    );
    assert_eq!(book["manga"]["author"], "Owned Author");
    assert_eq!(book["chapters"][0]["name"], "Chapter 2");
    assert_eq!(book["chapters"][0]["chapterNumber"], 2.0);
    let pages = run(
        &bytes,
        json!({"op":"pages","chapter":book["chapters"][0]}),
        |r| {
            assert_eq!(r.url, "https://hentaihere.com/read/owned-2");
            HttpResp::ok(fixture("hentaihere-pages.html"))
        },
    );
    assert_eq!(
        pages[0]["imageURL"],
        "https://images.example/owned-page-2.webp"
    );
    assert_eq!(
        pages[1]["imageURL"],
        "https://images.example/owned-page-1.webp"
    );
    image(&bytes, &pages[0], None);
}
