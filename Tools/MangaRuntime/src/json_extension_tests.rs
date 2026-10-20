//! Real, checksum-pinned APKs exercise generic JSON paths on owned data only.
use super::*;

fn apk(name: &str) -> Vec<u8> {
    std::fs::read(format!(
        "{}/{}",
        std::env::var("MANGA_TEST_APK_DIR").expect("Run test-manga-runtime.sh"),
        name
    ))
    .unwrap()
}
fn run(apk: &[u8], command: Value, http: impl Fn(&HttpData) -> HttpResp + 'static) -> Value {
    execute(apk, serde_json::from_value(command).unwrap(), http).unwrap()
}
fn flame_http(request: &HttpData) -> HttpResp {
    assert_eq!(request.method, "GET");
    if request.url == "https://flamecomics.xyz" || request.url == "https://flamecomics.xyz/" {
        return HttpResp::ok(include_str!(
            "../../../Tests/MangaRuntimeTests/OwnedFixtures/flame-home.html"
        ));
    }
    let body = if request.url.contains("/browse.json") {
        include_str!("../../../Tests/MangaRuntimeTests/OwnedFixtures/flame-catalog.json").to_owned()
    } else if request.url.contains("/latest.json") {
        include_str!("../../../Tests/MangaRuntimeTests/OwnedFixtures/flame-catalog.json")
            .replace("\"series\":", "\"allSeries\":")
    } else if request.url.contains("/42/owned-token.json") {
        // Deliberately not lexical key order: map insertion order is page order.
        include_str!("../../../Tests/MangaRuntimeTests/OwnedFixtures/flame-pages.json").to_owned()
    } else {
        assert!(request.url.contains("/series/42.json"), "{}", request.url);
        include_str!("../../../Tests/MangaRuntimeTests/OwnedFixtures/flame-book.json").to_owned()
    };
    HttpResp::ok(body)
}

#[test]
fn flame_generic_dtos_catalog_book_ordered_pages_and_image_transport() {
    let apk = apk("tachiyomi-en.flamecomics-v1.6.1.apk");
    let catalog = run(&apk, json!({"op":"popular","modern":true}), flame_http);
    assert_eq!(catalog["mangas"][0]["title"], "Owned story");
    assert_eq!(catalog["mangas"][0]["url"], "/series/42");
    for command in [
        json!({"op":"latest","modern":true}),
        json!({"op":"search","modern":true,"query":"Owned"}),
    ] {
        let result = run(&apk, command, flame_http);
        assert_eq!(result["mangas"][0]["title"], "Owned story");
    }
    let book = run(
        &apk,
        json!({"op":"book","modern":true,"manga":catalog["mangas"][0]}),
        flame_http,
    );
    assert_eq!(book["manga"]["description"], "Owned description");
    assert_eq!(book["manga"]["author"], "Owned author");
    assert_eq!(book["chapters"][0]["chapterNumber"], 1.5);
    assert_eq!(book["chapters"][0]["uploadedAt"], 1792300000000_i64);
    let pages = run(
        &apk,
        json!({"op":"pages","modern":true,"chapter":book["chapters"][0]}),
        flame_http,
    );
    assert_eq!(pages.as_array().unwrap().len(), 2);
    for (index, page) in [2, 1].iter().enumerate() {
        assert_eq!(pages[index]["imageURL"], format!("https://cdn.flamecomics.xyz/uploads/images/series/42/owned-token/owned-page-{page}.webp?1792300000"));
    }
    let expected = pages[0]["imageURL"].as_str().unwrap().to_owned();
    let result = run(
        &apk,
        json!({"op":"image","modern":true,"image":pages[0]}),
        move |request| {
            assert_eq!(request.url, expected);
            HttpResp {
                code: 200,
                message: "OK".into(),
                headers: vec![],
                body: Some(b"owned image bytes".to_vec()),
            }
        },
    );
    assert_eq!(
        STANDARD
            .decode(result["bodyBase64"].as_str().unwrap())
            .unwrap(),
        b"owned image bytes"
    );
}

#[test]
fn allmanga_encodes_graphql_variables_and_decodes_generic_json_elements() {
    let apk = apk("tachiyomi-en.allanime-v1.6.29.apk");
    let catalog = run(&apk, json!({"op":"popular","modern":true}), |request| {
        assert_eq!(request.method, "POST");
        let body: Value = serde_json::from_str(request.body.as_deref().unwrap()).unwrap();
        assert_eq!(body["variables"]["type"], "manga");
        assert_eq!(body["variables"]["page"], 1);
        HttpResp::ok(include_str!(
            "../../../Tests/MangaRuntimeTests/OwnedFixtures/allmanga-catalog.json"
        ))
    });
    assert_eq!(catalog["mangas"][0]["title"], "Owned story");
    assert_eq!(
        catalog["mangas"][0]["thumbnailURL"],
        "https://images.example/owned-cover.webp"
    );
    let book = run(
        &apk,
        json!({"op":"book","modern":true,"manga":catalog["mangas"][0]}),
        |request| {
            let body: Value = serde_json::from_str(request.body.as_deref().unwrap()).unwrap();
            assert_eq!(body["variables"]["id"], "owned");
            assert_eq!(
                body["variables"]["search"],
                json!({"fromSearch":true,"allowAdult":true})
            );
            HttpResp::ok(include_str!(
                "../../../Tests/MangaRuntimeTests/OwnedFixtures/allmanga-book.json"
            ))
        },
    );
    assert_eq!(book["manga"]["author"], "Owned author");
    assert_eq!(book["chapters"][0]["url"], "1.5");
    assert_eq!(book["chapters"][0]["uploadedAt"], 1792281600000_i64);
    let memo: Value = serde_json::from_str(book["chapters"][0]["memo"].as_str().unwrap()).unwrap();
    assert_eq!(memo["mangaId"], "owned");
}
