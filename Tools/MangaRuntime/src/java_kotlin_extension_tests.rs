//! Exercise published bytecode, with networking denied for metadata/settings.
use super::*;

fn apk(name: &str) -> Vec<u8> {
    std::fs::read(format!(
        "{}/{name}",
        std::env::var("MANGA_TEST_APK_DIR").expect("Run test-manga-runtime.sh")
    ))
    .unwrap()
}
#[test]
fn komga_coroutine_context_factory_and_settings() {
    let bytes = apk("tachiyomi-all.komga-v1.6.74.apk");
    let inspect = execute(
        &bytes,
        serde_json::from_value(json!({"op":"inspect","modern":true})).unwrap(),
        |_| panic!("Inspect must not network"),
    )
    .unwrap();
    let sources = inspect["sources"].as_array().unwrap();
    assert_eq!(sources.len(), 3);
    let settings = execute(
        &bytes,
        serde_json::from_value(json!({"op":"settings","modern":true})).unwrap(),
        |_| panic!("Settings must not network"),
    )
    .unwrap();
    assert!(
        !settings["settings"].as_array().unwrap().is_empty(),
        "{settings}"
    );
}

fn fixture(name: &str) -> String {
    std::fs::read_to_string(format!(
        "{}/../../Tests/MangaRuntimeTests/OwnedFixtures/{name}",
        env!("CARGO_MANIFEST_DIR")
    ))
    .unwrap()
}
fn komga(command: Value) -> Value {
    let bytes = apk("tachiyomi-all.komga-v1.6.74.apk");
    let mut command = command;
    command["modern"] = json!(true);
    command["timeZoneID"] = json!("UTC");
    command["settingsSourceID"] = json!("4508733312114627536");
    command["settings"] = json!({"Address":{"type":"string","value":"https://library.example"},"API key":{"type":"string","value":"owned-key"}});
    execute(&bytes, serde_json::from_value(command).unwrap(), |r| {
        assert!(r.url.starts_with("https://library.example/"), "{}", r.url);
        assert!(r
            .headers
            .iter()
            .any(|(k, v)| k.eq_ignore_ascii_case("X-API-Key") && v == "owned-key"));
        let name = if r.url.contains("/series?") {
            "komga-catalog.json"
        } else if r.url == "https://library.example/api/v1/series/owned" {
            "komga-series.json"
        } else if r.url.contains("/series/owned/books?") {
            "komga-books.json"
        } else if r.url.ends_with("/chapter2/pages") {
            "komga-pages.json"
        } else if r.url.ends_with("/pages/2") {
            assert!(r
                .headers
                .iter()
                .any(|(k, v)| k.eq_ignore_ascii_case("Accept") && v == "image/*,*/*;q=0.8"));
            return HttpResp {
                code: 200,
                message: "OK".into(),
                headers: vec![],
                body: Some(vec![0, 255, 23, 128]),
            };
        } else {
            panic!("Unexpected fixture request: {}", r.url)
        };
        HttpResp::ok(fixture(name))
    })
    .unwrap()
}
#[test]
fn komga_configured_catalog_async_details_dated_chapters_ordered_pages_and_images() {
    let catalog = komga(json!({"op":"popular"}));
    let manga = &catalog["mangas"][0];
    assert_eq!(manga["title"], "Owned story");
    let book = komga(json!({"op":"book","manga":manga}));
    assert_eq!(book["manga"]["author"], "Owned author");
    assert_eq!(book["chapters"][0]["uploadedAt"], 1_709_164_800_000_i64);
    assert_eq!(book["chapters"][1]["uploadedAt"], -86_400_000_i64);
    assert_eq!(book["chapters"][0]["name"], "2 - Owned chapter 2 (1 KB)");
    let pages = komga(json!({"op":"pages","chapter":book["chapters"][0]}));
    assert_eq!(
        pages[0]["imageURL"],
        "https://library.example/api/v1/books/chapter2/pages/2"
    );
    assert_eq!(
        pages[1]["imageURL"],
        "https://library.example/api/v1/books/chapter2/pages/1?convert=png"
    );
    let image = komga(json!({"op":"image","image":pages[0]}));
    assert_eq!(
        STANDARD
            .decode(image["bodyBase64"].as_str().unwrap())
            .unwrap(),
        [0, 255, 23, 128]
    );
}
#[test]
fn komga_authenticator_retries_once_with_guest_credentials_and_preserves_rejection() {
    use std::sync::{
        atomic::{AtomicUsize, Ordering},
        Arc,
    };
    let bytes = apk("tachiyomi-all.komga-v1.6.74.apk");
    for accepted in [true, false] {
        let requests = Arc::new(AtomicUsize::new(0));
        let count = requests.clone();
        let result=execute(&bytes,serde_json::from_value(json!({"op":"popular","modern":true,"settingsSourceID":"4508733312114627536","settings":{"Address":{"type":"string","value":"https://library.example"},"Username":{"type":"string","value":"owned-user"},"Password":{"type":"string","value":"owned-password"}}})).unwrap(),move |r| {
            let n=count.fetch_add(1,Ordering::SeqCst);assert!(n<2);
            assert!(r.url.starts_with("https://library.example/api/v1/series?"));
            let auth=r.headers.iter().find(|(k,_)|k.eq_ignore_ascii_case("Authorization")).map(|(_,v)|v.as_str());
            if n==0 {assert_eq!(auth,None);}else{assert_eq!(auth,Some("Basic b3duZWQtdXNlcjpvd25lZC1wYXNzd29yZA=="));}
            if n==1 && accepted {HttpResp::ok(fixture("komga-catalog.json"))}else{HttpResp{code:401,message:"Unauthorized".into(),headers:vec![],body:Some(vec![])}}
        });
        assert_eq!(requests.load(Ordering::SeqCst), 2, "{result:?}");
        if accepted {
            assert_eq!(result.unwrap()["mangas"][0]["title"], "Owned story");
        } else {
            assert!(result.is_err());
        }
    }
}
#[test]
fn jinman_typed_string_array_settings() {
    let bytes = apk("tachiyomi-zh.jinmantiantang-v1.6.59.apk");
    let settings = execute(
        &bytes,
        serde_json::from_value(json!({"op":"settings","modern":true})).unwrap(),
        |_| panic!("Settings must not network"),
    )
    .unwrap();
    let mirror = settings["settings"]
        .as_array()
        .unwrap()
        .iter()
        .find(|p| p["key"] == "useMirrorWebsitePreference")
        .unwrap();
    assert_eq!(mirror["control"], "choice");
    assert_eq!(mirror["choices"].as_array().unwrap().len(), 7);
    assert_eq!(mirror["choices"][6]["value"], "6");
}
fn jinman(command: Value) -> Value {
    let bytes = apk("tachiyomi-zh.jinmantiantang-v1.6.59.apk");
    let mut command = command;
    command["modern"] = json!(true);
    command["timeZoneID"] = json!("UTC");
    execute(&bytes, serde_json::from_value(command).unwrap(), |r| {
        let path = r
            .url
            .split_once("://")
            .unwrap()
            .1
            .split_once('/')
            .unwrap()
            .1;
        let name = if path.starts_with("albums?") {
            "jinman-catalog.html"
        } else if path == "album/1/" || path == "album/1" {
            "jinman-book.html"
        } else if path == "photo/1/" {
            "jinman-pages.html"
        } else if path.starts_with("media/photos/1/") {
            return HttpResp {
                code: 200,
                message: "OK".into(),
                headers: vec![],
                body: Some(vec![0, 255, 23, 128]),
            };
        } else {
            panic!("Unexpected fixture request: {}", r.url)
        };
        HttpResp::ok(fixture(name))
    })
    .unwrap()
}
#[test]
fn jinman_catalog_dated_book_ordered_pages_and_unscrambled_image() {
    let catalog = jinman(json!({"op":"popular"}));
    let manga = &catalog["mangas"][0];
    assert_eq!(manga["title"], "Owned story");
    let book = jinman(json!({"op":"book","manga":manga}));
    assert_eq!(book["manga"]["description"], "Owned description");
    assert_eq!(book["chapters"][0]["uploadedAt"], 1_709_164_800_000_i64);
    let pages = jinman(json!({"op":"pages","chapter":book["chapters"][0]}));
    assert_eq!(
        pages[0]["imageURL"],
        "https://images.example/media/photos/1/owned-page-2.webp"
    );
    assert_eq!(
        pages[1]["imageURL"],
        "https://images.example/media/photos/1/owned-page-1.webp"
    );
    let image = jinman(json!({"op":"image","image":pages[0]}));
    assert_eq!(
        STANDARD
            .decode(image["bodyBase64"].as_str().unwrap())
            .unwrap(),
        [0, 255, 23, 128]
    );
}
#[test]
fn jinman_scrambled_images_report_the_remaining_okio_peek_gap() {
    let bytes = apk("tachiyomi-zh.jinmantiantang-v1.6.59.apk");
    let result=execute(&bytes,serde_json::from_value(json!({"op":"image","modern":true,"image":{"index":0,"url":"","imageURL":"https://images.example/media/photos/300000/owned.webp"}})).unwrap(),|r| {
        assert_eq!(r.url,"https://images.example/media/photos/300000/owned.webp");
        HttpResp{code:200,message:"OK".into(),headers:vec![],body:Some(vec![137,80,78,71])}
    });
    let error = result.unwrap_err();
    assert!(
        error.contains("no method peek ()Lokio/BufferedSource;"),
        "{error}"
    );
}
