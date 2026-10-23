//! Actual requested APKs, neutral owned catalog-to-image responses, fresh VMs.
use super::*;
fn fixture(name: &str) -> String {
    std::fs::read_to_string(format!(
        "{}/../../Tests/MangaRuntimeTests/OwnedFixtures/{name}",
        env!("CARGO_MANIFEST_DIR")
    ))
    .unwrap()
}
fn run(
    apk: &[u8],
    mut command: Value,
    source: usize,
    http: impl Fn(&HttpData) -> HttpResp + 'static,
) -> Value {
    command["modern"] = json!(true);
    command["source"] = json!(source);
    command["timeZoneID"] = json!("UTC");
    execute(apk, serde_json::from_value(command).unwrap(), http).unwrap()
}
fn respond(prefix: &str, request: &HttpData) -> HttpResp {
    eprintln!("{prefix}: {} {}", request.method, request.url);
    let file = if request.url.contains("search-advanced")
        || request.url.contains("api.omegascans.org/query?")
        || request.url.ends_with("/wp-admin/admin-ajax.php")
    {
        "catalog"
    } else if request.url.contains("chapter/query")
        || request.url.contains("chapter-listing-by-title-id")
        || request.url.ends_with("/ajax/chapters/")
    {
        "chapters"
    } else if request.url.contains("chapter-detail?")
        || request.url.contains("/chapter/owned/")
        || request.url.ends_with("/chapter-3/")
    {
        "pages"
    } else if request.url.ends_with("/views/update") {
        return HttpResp::ok("{}");
    } else if request.url.contains("/series/owned")
        || request.url.contains("/title/detail/owned-id")
        || request.url.trim_end_matches('/').ends_with("/serie/owned")
    {
        "book"
    } else {
        panic!("Unexpected {prefix} request: {}", request.url)
    };
    if prefix == "mangaball" && file == "chapters" {
        assert_eq!(request.method, "POST");
        assert_eq!(request.body.as_deref(), Some("{\"title_id\":\"owned-id\"}"));
        assert!(request
            .headers
            .iter()
            .any(|(k, v)| k.eq_ignore_ascii_case("Content-Type") && v == "application/json"));
    }
    HttpResp::ok(fixture(&format!(
        "{prefix}-{file}.{}",
        if prefix == "toonily" { "html" } else { "json" }
    )))
}
fn flow(name: &str, prefix: &'static str, source: usize) {
    let apk = std::fs::read(format!(
        "{}/{name}",
        std::env::var("MANGA_TEST_APK_DIR").unwrap()
    ))
    .unwrap();
    for op in ["inspect", "settings"] {
        run(&apk, json!({"op":op}), source, |_| {
            panic!("Metadata must not network")
        });
    }
    let catalog = run(&apk, json!({"op":"popular"}), source, move |r| {
        respond(prefix, r)
    });
    assert_eq!(catalog["mangas"][0]["title"], "Owned story");
    assert_eq!(catalog["hasNext"], false);
    let title = &catalog["mangas"][0];
    assert!(title["memo"].as_str().is_some());
    let book = run(&apk, json!({"op":"book","manga":title}), source, move |r| {
        respond(prefix, r)
    });
    assert_eq!(book["manga"]["description"], "Owned description");
    assert_eq!(book["chapters"].as_array().unwrap().len(), 2);
    assert_eq!(
        book["chapters"][0]["uploadedAt"],
        if prefix == "toonily" {
            1_709_164_800_000_i64
        } else {
            1_709_210_096_123_i64
        }
    );
    let pages = run(
        &apk,
        json!({"op":"pages","chapter":book["chapters"][0]}),
        source,
        move |r| respond(prefix, r),
    );
    assert_eq!(
        pages[0]["imageURL"],
        "https://images.example/owned-page-2.webp"
    );
    assert_eq!(
        pages[1]["imageURL"],
        "https://images.example/owned-page-1.webp"
    );
    let image = run(&apk, json!({"op":"image","image":pages[0]}), source, |r| {
        assert_eq!(r.url, "https://images.example/owned-page-2.webp");
        HttpResp {
            code: 200,
            message: "OK".into(),
            headers: vec![],
            body: Some(vec![0, 255, 23, 128]),
        }
    });
    assert_eq!(
        STANDARD
            .decode(image["bodyBase64"].as_str().unwrap())
            .unwrap(),
        [0, 255, 23, 128]
    );
    // Separate refresh operations must receive the same opaque title metadata.
    run(
        &apk,
        json!({"op":"details","manga":title}),
        source,
        move |r| respond(prefix, r),
    );
    run(
        &apk,
        json!({"op":"chapters","manga":title}),
        source,
        move |r| respond(prefix, r),
    );
}
#[test]
fn omega_owned_reading_flow() {
    flow("tachiyomi-en.omegascans-v1.6.52.apk", "omega", 0)
}
#[test]
fn toonily_owned_reading_flow() {
    flow("tachiyomi-en.toonily-v1.6.72.apk", "toonily", 0)
}
#[test]
fn mangaball_owned_reading_flow() {
    flow("tachiyomi-all.mangaball-v1.6.5.apk", "mangaball", 8)
}
#[test]
fn invalid_title_metadata_is_rejected_before_any_source_request() {
    let apk = std::fs::read(format!(
        "{}/tachiyomi-all.mangaball-v1.6.5.apk",
        std::env::var("MANGA_TEST_APK_DIR").unwrap()
    ))
    .unwrap();
    for memo in [
        "[]".to_owned(),
        "invalid".into(),
        format!("{{\"large\":\"{}\"}}", "x".repeat(65_536)),
        format!("{{\"deep\":{}0{}}}", "[".repeat(33), "]".repeat(33)),
        "{\"id\":18446744073709551615}".into(),
    ] {
        let command = serde_json::from_value(
            json!({"op":"book","source":8,"modern":true,"manga":{"url":"owned","memo":memo}}),
        )
        .unwrap();
        let result = execute(&apk, command, |_| {
            panic!("Invalid metadata must not network")
        });
        assert!(result.is_err(), "Invalid metadata was accepted");
    }
}
