//! Published APKs own multipart requests, parsers and lazy image resolution.
use super::*;
fn fixture(name: &str) -> String {
    std::fs::read_to_string(format!(
        "{}/../../Tests/MangaRuntimeTests/OwnedFixtures/{name}",
        env!("CARGO_MANIFEST_DIR")
    ))
    .unwrap()
}
fn apk(name: &str) -> Vec<u8> {
    std::fs::read(format!(
        "{}/{name}",
        std::env::var("MANGA_TEST_APK_DIR").expect("Run test-manga-runtime.sh")
    ))
    .unwrap()
}
fn run(apk: &[u8], command: Value, http: impl Fn(&HttpData) -> HttpResp + 'static) -> Value {
    let op = command["op"].clone();
    execute(apk, serde_json::from_value(command).unwrap(), http)
        .unwrap_or_else(|error| panic!("{op}: {error}"))
}
fn ordered_reader(apk: &[u8], book: &Value, http: impl Fn(&HttpData) -> HttpResp + 'static) {
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
fn digitalcomicmuseum_multipart_search_catalog_book_lazy_pages_and_images() {
    let apk = apk("tachiyomi-en.digitalcomicmuseum-v1.6.0.apk");
    let catalog = run(&apk, json!({"op":"popular","modern":true}), |request| {
        assert!(request
            .url
            .starts_with("https://digitalcomicmuseum.com/stats.php?ACT=topdl"));
        HttpResp::ok(fixture("dcm-catalog.html"))
    });
    assert_eq!(catalog["mangas"][0]["title"], "Owned story");
    let search = run(
        &apk,
        json!({"op":"search","modern":true,"query":"Owned café + story"}),
        |request| {
            assert_eq!(request.method, "POST");
            assert_eq!(
                request.url,
                "https://digitalcomicmuseum.com/index.php?ACT=dosearch"
            );
            let media = &request
                .headers
                .iter()
                .find(|(name, _)| name.eq_ignore_ascii_case("content-type"))
                .unwrap()
                .1;
            let boundary = media
                .strip_prefix("multipart/form-data; boundary=")
                .unwrap();
            let expected=format!("--{boundary}\r\nContent-Disposition: form-data; name=\"terms\"\r\nContent-Length: {}\r\n\r\nOwned café + story\r\n--{boundary}--\r\n","Owned café + story".len());
            assert_eq!(request.body_bytes.as_deref(), Some(expected.as_bytes()));
            HttpResp::ok(fixture("dcm-catalog.html"))
        },
    );
    assert_eq!(search["mangas"][0]["title"], "Owned story");
    let book = run(
        &apk,
        json!({"op":"book","modern":true,"manga":catalog["mangas"][0]}),
        |_| HttpResp::ok(fixture("dcm-book.html")),
    );
    assert_eq!(book["manga"]["description"], "Owned description");
    assert_eq!(book["chapters"].as_array().unwrap().len(), 1);
    let pages = run(
        &apk,
        json!({"op":"pages","modern":true,"chapter":book["chapters"][0]}),
        |_| HttpResp::ok(fixture("dcm-pages.html")),
    );
    assert_eq!(pages.as_array().unwrap().len(), 2);
    assert_eq!(
        pages[0]["url"],
        "https://digitalcomicmuseum.com/read/owned/2"
    );
    assert_eq!(
        pages[1]["url"],
        "https://digitalcomicmuseum.com/read/owned/1"
    );
    assert_eq!(pages[0]["imageURL"], "");
    let image = run(
        &apk,
        json!({"op":"image","modern":true,"image":pages[0]}),
        |request| {
            if request.url == "https://digitalcomicmuseum.com/read/owned/2" {
                HttpResp::ok(fixture("dcm-image.html"))
            } else {
                assert_eq!(request.url, "https://images.example/owned-page-2.webp");
                HttpResp {
                    code: 200,
                    message: "OK".into(),
                    headers: vec![],
                    body: Some(vec![0, 255, 23, 128]),
                }
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
fn natsuid_multipart_nonce_dtos_dated_chapters_and_ordered_reader() {
    let apk = apk("tachiyomi-ja.rawkuma-v1.6.41.apk");
    let catalog = run(&apk, json!({"op":"popular","modern":true}), |request| {
        if request.url.contains("action=get_nonce") {
            return HttpResp::ok(fixture("natsuid-nonce.html"));
        }
        if request.url.contains("action=advanced_search") {
            assert_eq!(request.method, "POST");
            let body = std::str::from_utf8(request.body_bytes.as_ref().unwrap()).unwrap();
            assert!(body.contains("name=\"nonce\"\r\nContent-Length: 11\r\n\r\nowned-nonce\r\n"));
            assert!(body.contains("name=\"orderby\""));
            return HttpResp::ok(fixture("natsuid-catalog.html"));
        }
        assert!(request.url.contains("/wp-json/wp/v2/manga?"));
        HttpResp::ok(format!("[{}]", fixture("natsuid-book.json")))
    });
    assert_eq!(catalog["mangas"][0]["title"], "Owned story");
    let book = run(
        &apk,
        json!({"op":"book","modern":true,"manga":catalog["mangas"][0]}),
        |request| {
            if request.url.contains("action=chapter_list") {
                HttpResp::ok(fixture("natsuid-chapters.html"))
            } else {
                assert!(request.url.contains("/wp-json/wp/v2/manga/42"));
                HttpResp::ok(fixture("natsuid-book.json"))
            }
        },
    );
    assert_eq!(book["manga"]["author"], "Owned author");
    assert_eq!(book["chapters"][0]["uploadedAt"], 1725062400000_i64);
    ordered_reader(&apk, &book, |_| HttpResp::ok(fixture("natsuid-pages.html")));
}
#[test]
fn mccms_header_factory_catalog_details_chapters_pages_and_images() {
    let apk = apk("tachiyomi-zh.manhuawu-v1.6.0.apk");
    let catalog = run(&apk, json!({"op":"popular","modern":true}), |request| {
        assert_eq!(
            request.url,
            "https://www.mhua5.com/category/order/hits/page/1"
        );
        assert!(request
            .headers
            .iter()
            .any(|(name, value)| name.eq_ignore_ascii_case("User-Agent")
                && value.contains("Windows")));
        HttpResp::ok(fixture("mccms-catalog.html"))
    });
    assert_eq!(catalog["mangas"][0]["title"], "Owned story");
    let book = run(
        &apk,
        json!({"op":"book","modern":true,"manga":catalog["mangas"][0]}),
        |_| HttpResp::ok(fixture("mccms-book.html")),
    );
    assert_eq!(book["manga"]["author"], "Owned author");
    assert_eq!(book["chapters"][0]["name"], "Chapter 2");
    ordered_reader(&apk, &book, |_| HttpResp::ok(fixture("mccms-pages.html")));
}
