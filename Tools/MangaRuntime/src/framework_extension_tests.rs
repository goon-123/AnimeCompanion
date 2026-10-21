//! APK-owned requests and parsers; no website requests or site-specific host code.
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
fn run(
    apk: &[u8],
    id: &str,
    settings: Value,
    mut command: Value,
    http: impl Fn(&HttpData) -> HttpResp + 'static,
) -> Value {
    command["modern"] = json!(true);
    command["settingsSourceID"] = json!(id);
    command["settings"] = settings;
    let op = command["op"].clone();
    execute(apk, serde_json::from_value(command).unwrap(), http)
        .unwrap_or_else(|e| panic!("{op}: {e}"))
}
fn image() -> HttpResp {
    HttpResp {
        code: 200,
        message: "OK".into(),
        headers: vec![],
        body: Some(vec![0, 255, 23, 128]),
    }
}
fn assert_image(v: &Value) {
    assert_eq!(
        STANDARD.decode(v["bodyBase64"].as_str().unwrap()).unwrap(),
        [0, 255, 23, 128]
    );
}
fn lan_settings() -> Value {
    json!({"hostname":{"type":"string","value":"https://library.example"},"apiKey":{"type":"string","value":"owned-key"}})
}
#[test]
fn lanraragi_configured_catalog_dated_chapter_ordered_pages_and_images() {
    let apk = apk("tachiyomi-all.lanraragi-v1.6.1.apk");
    let id = "4482480338677079857";
    let catalog = run(&apk, id, lan_settings(), json!({"op":"popular"}), |r| {
        assert_eq!(r.url, "https://library.example/api/search?start=0");
        assert!(r
            .headers
            .iter()
            .any(|(k, v)| k.eq_ignore_ascii_case("authorization") && v == "Bearer b3duZWQta2V5"));
        HttpResp::ok(fixture("lanraragi-catalog.json"))
    });
    assert_eq!(catalog["mangas"][0]["title"], "Owned story");
    let book = run(
        &apk,
        id,
        lan_settings(),
        json!({"op":"book","manga":catalog["mangas"][0]}),
        |r| {
            assert_eq!(r.url,"https://library.example/api/archives/1111111111111111111111111111111111111111/metadata");
            HttpResp::ok(fixture("lanraragi-book.json"))
        },
    );
    assert_eq!(book["manga"]["author"], "Owned author");
    assert_eq!(book["chapters"][0]["uploadedAt"], 1709164800000_i64);
    let pages = run(
        &apk,
        id,
        lan_settings(),
        json!({"op":"pages","chapter":book["chapters"][0]}),
        |r| {
            assert_eq!(r.url,"https://library.example/api/archives/1111111111111111111111111111111111111111/files");
            HttpResp::ok(fixture("lanraragi-pages.json"))
        },
    );
    assert_eq!(pages.as_array().unwrap().len(), 2);
    assert_eq!(
        pages[0]["imageURL"],
        "https://library.example/owned-page-2.webp"
    );
    assert_eq!(
        pages[1]["imageURL"],
        "https://library.example/owned-page-1.webp"
    );
    assert_image(&run(
        &apk,
        id,
        lan_settings(),
        json!({"op":"image","image":pages[0]}),
        |r| {
            assert_eq!(r.url, "https://library.example/owned-page-2.webp");
            image()
        },
    ));
}
fn mango_settings() -> Value {
    json!({"overrideBaseUrl":{"type":"string","value":"https://library.example"},"Username":{"type":"string","value":"owned-user"},"Password":{"type":"string","value":"owned-password"}})
}
fn login(r: &HttpData) -> Option<HttpResp> {
    assert!(r.url.starts_with("https://library.example/"));
    if r.url.ends_with("/login") {
        assert_eq!(r.method, "POST");
        assert_eq!(
            r.body_bytes.as_deref(),
            Some(b"username=owned-user&password=owned-password".as_slice())
        );
        Some(HttpResp {
            code: 200,
            message: "OK".into(),
            headers: vec![("Set-Cookie".into(), "mango-sessid-9000=owned".into())],
            body: Some(vec![]),
        })
    } else {
        assert!(r
            .headers
            .iter()
            .any(|(k, v)| k.eq_ignore_ascii_case("cookie") && v == "mango-sessid-9000=owned"));
        None
    }
}
#[test]
fn mango_configured_login_catalog_dated_chapters_pages_and_images() {
    let apk = apk("tachiyomi-all.mango-v1.6.0.apk");
    let id = "2882993841250976719";
    let catalog = run(&apk, id, mango_settings(), json!({"op":"popular"}), |r| {
        if let Some(v) = login(r) {
            return v;
        }
        assert_eq!(r.url, "https://library.example/api/library?depth=0");
        HttpResp::ok(fixture("mango-catalog.json"))
    });
    assert_eq!(catalog["mangas"][0]["title"], "Owned story");
    let book = run(
        &apk,
        id,
        mango_settings(),
        json!({"op":"book","manga":catalog["mangas"][0]}),
        |r| {
            if let Some(v) = login(r) {
                return v;
            }
            assert_eq!(r.url, "https://library.example/api/book/owned?sort=auto");
            HttpResp::ok(fixture("mango-book.json"))
        },
    );
    assert_eq!(book["chapters"].as_array().unwrap().len(), 2);
    assert_eq!(book["chapters"][0]["name"], "Owned chapter 2");
    assert_eq!(book["chapters"][0]["uploadedAt"], 1709164800000_i64);
    let pages = run(
        &apk,
        id,
        mango_settings(),
        json!({"op":"pages","chapter":book["chapters"][0]}),
        |_| panic!("Pages are computed by the source"),
    );
    assert_eq!(pages.as_array().unwrap().len(), 2);
    assert_eq!(
        pages[0]["imageURL"],
        "https://library.example/api/page/owned/chapter2/1"
    );
    assert_eq!(
        pages[1]["imageURL"],
        "https://library.example/api/page/owned/chapter2/2"
    );
    assert_image(&run(
        &apk,
        id,
        mango_settings(),
        json!({"op":"image","image":pages[0]}),
        |r| {
            if let Some(v) = login(r) {
                return v;
            }
            assert_eq!(r.url, "https://library.example/api/page/owned/chapter2/1");
            image()
        },
    ));
}
fn stash_settings() -> Value {
    json!({"overrideBaseUrl":{"type":"string","value":"https://library.example"},"api_key":{"type":"string","value":"owned-key"}})
}
fn stash_http(r: &HttpData) -> HttpResp {
    assert_eq!(r.method, "POST");
    assert_eq!(r.url, "https://library.example/graphql");
    assert!(r
        .headers
        .iter()
        .any(|(k, v)| k.eq_ignore_ascii_case("ApiKey") && v == "owned-key"));
    let body: Value = serde_json::from_slice(r.body_bytes.as_ref().unwrap()).unwrap();
    let file = match body["operationName"].as_str().unwrap() {
        "MangaBrief" => {
            assert_eq!(body["variables"]["filter"]["direction"], "DESC");
            "stash-catalog.json"
        }
        "MangaDetails" | "ChapterList" => "stash-book.json",
        "PageList" => "stash-pages.json",
        other => panic!("Unexpected operation {other}"),
    };
    HttpResp::ok(fixture(file))
}
#[test]
fn stashapp_configured_enum_graphql_catalog_dated_chapter_pages_and_images() {
    let apk = apk("tachiyomi-all.stashapp-v1.6.0.apk");
    let id = "4332882684116196542";
    let catalog = run(
        &apk,
        id,
        stash_settings(),
        json!({"op":"popular"}),
        stash_http,
    );
    assert_eq!(catalog["mangas"][0]["title"], "Owned story");
    assert_eq!(
        catalog["mangas"][0]["thumbnailURL"],
        "https://images.example/owned-cover.webp"
    );
    let book = run(
        &apk,
        id,
        stash_settings(),
        json!({"op":"book","manga":catalog["mangas"][0]}),
        stash_http,
    );
    assert_eq!(book["manga"]["description"], "Owned description");
    assert_eq!(book["chapters"][0]["uploadedAt"], 1709164800000_i64);
    let pages = run(
        &apk,
        id,
        stash_settings(),
        json!({"op":"pages","chapter":book["chapters"][0]}),
        stash_http,
    );
    assert_eq!(pages.as_array().unwrap().len(), 2);
    assert_eq!(
        pages[0]["imageURL"],
        "https://library.example/image/2/image"
    );
    assert_eq!(
        pages[1]["imageURL"],
        "https://library.example/image/1/image"
    );
    assert_image(&run(
        &apk,
        id,
        stash_settings(),
        json!({"op":"image","image":pages[0]}),
        |r| {
            assert_eq!(r.url, "https://library.example/image/2/image");
            assert!(r
                .headers
                .iter()
                .any(|(k, v)| k.eq_ignore_ascii_case("Accept") && v == "image/*"));
            image()
        },
    ));
}
#[test]
fn mangadot_all_languages_enumerate_after_typed_preference_migrations() {
    let a = apk("tachiyomi-en.mangadotnet-v1.6.25.apk");
    let v = run(
        &a,
        "5900936305360403385",
        json!({"pref_nsfw_mode":{"type":"boolean","value":false}}),
        json!({"op":"inspect"}),
        |_| panic!("Inspection stays offline"),
    );
    let s = v["sources"].as_array().unwrap();
    assert_eq!(s.len(), 108);
    assert_eq!(s[9]["id"], "5900936305360403385");
    assert_eq!(s[9]["language"], "en");
    assert_eq!(
        s.iter()
            .map(|s| s["id"].as_str().unwrap())
            .collect::<std::collections::HashSet<_>>()
            .len(),
        108
    );
}
#[test]
fn favcomic_and_noyacg_native_settings_keep_guest_titles_and_keys() {
    for n in [
        "tachiyomi-zh.favcomic-v1.6.4.apk",
        "tachiyomi-zh.noyacg-v1.6.7.apk",
    ] {
        let v = execute(
            &apk(n),
            serde_json::from_value(json!({"op":"settings","modern":true})).unwrap(),
            |_| panic!("Settings stay offline"),
        )
        .unwrap();
        let s = v["settings"].as_array().unwrap();
        assert!(s
            .iter()
            .any(|s| s["key"] == "USERNAME" && !s["title"].as_str().unwrap().is_empty()));
        assert!(s.iter().any(|s| s["key"] == "PASSWORD"));
    }
}
