//! Integrity-pinned APKs run their own parsers against original, owned fixtures.
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
fn image(apk: &[u8], source: usize, page: &Value) {
    let url = page["imageURL"].as_str().unwrap().to_owned();
    let expected = url.clone();
    let result = run(
        apk,
        json!({"op":"image","source":source,"modern":true,"image":page}),
        move |request| {
            assert_eq!(request.url, expected);
            assert_eq!(request.method, "GET");
            HttpResp {
                code: 200,
                message: "OK".into(),
                headers: vec![],
                body: Some(b"owned image transport bytes".to_vec()),
            }
        },
    );
    assert_eq!(
        STANDARD
            .decode(result["bodyBase64"].as_str().unwrap())
            .unwrap(),
        b"owned image transport bytes"
    );
}

#[test]
fn comicfury_catalog_dated_chapters_ordered_pages_and_images() {
    let apk = apk("tachiyomi-all.comicfury-v1.6.0.apk");
    let catalog = run(
        &apk,
        json!({"op":"popular","source":1,"modern":true}),
        |request| {
            assert!(request.url.contains("/search.php?"));
            HttpResp::ok(include_str!(
                "../../../Tests/MangaRuntimeTests/OwnedFixtures/comicfury-catalog.html"
            ))
        },
    );
    assert_eq!(catalog["mangas"][0]["title"], "Owned story");
    assert_eq!(
        catalog["mangas"][0]["thumbnailURL"],
        "https://images.example/owned-cover.png"
    );
    assert_eq!(catalog["hasNext"], true);
    let book = run(
        &apk,
        json!({"op":"book","source":1,"modern":true,"manga":catalog["mangas"][0]}),
        |request| {
            if request.url.ends_with("/archive") {
                HttpResp::ok(include_str!(
                    "../../../Tests/MangaRuntimeTests/OwnedFixtures/comicfury-archive.html"
                ))
            } else {
                assert!(request.url.contains("/profile.php?url=owned"));
                HttpResp::ok("<html><body><div class=\"username-and-title\"><em>Owned description</em></div><a class=\"authorname\">Owned author</a></body></html>")
            }
        },
    );
    assert_eq!(book["manga"]["author"], "Owned author");
    assert_eq!(book["chapters"].as_array().unwrap().len(), 2);
    assert_eq!(book["chapters"][0]["name"], "Owned second chapter");
    assert!(book["chapters"][0]["uploadedAt"].as_i64().unwrap() > 1_792_300_000_000);
    let pages = run(
        &apk,
        json!({"op":"pages","source":1,"modern":true,"chapter":book["chapters"][0]}),
        |_| {
            HttpResp::ok(include_str!(
                "../../../Tests/MangaRuntimeTests/OwnedFixtures/comicfury-pages.html"
            ))
        },
    );
    assert_eq!(pages.as_array().unwrap().len(), 2);
    assert_eq!(
        pages[0]["imageURL"],
        "https://images.example/owned-page-2.png"
    );
    assert_eq!(
        pages[1]["imageURL"],
        "https://images.example/owned-page-1.png"
    );
    image(&apk, 1, &pages[0]);
}

#[test]
fn comicskingdom_catalog_compact_and_individual_chapters_pages_and_images() {
    let apk = apk("tachiyomi-all.comicskingdom-v1.6.0.apk");
    let source = run(&apk, json!({"op":"inspect"}), |_| {
        panic!("Inspection must not network")
    })["sources"][0]
        .clone();
    let catalog = run(&apk, json!({"op":"popular","modern":true}), |_| {
        HttpResp::ok(format!(
            "[{}]",
            include_str!("../../../Tests/MangaRuntimeTests/OwnedFixtures/comicskingdom-manga.json")
        ))
    });
    assert_eq!(catalog["mangas"][0]["title"], "Owned story");
    assert_eq!(
        catalog["mangas"][0]["thumbnailURL"],
        "https://images.example/owned-cover.png"
    );
    for compact in [true, false] {
        let settings = json!({"compactPref":{"type":"boolean","value":compact}});
        let book = run(
            &apk,
            json!({"op":"book","modern":true,"manga":catalog["mangas"][0],"settingsSourceID":source["id"],"settings":settings}),
            move |request| {
                if request.url.contains("/ck_feature/") {
                    HttpResp::ok(include_str!(
                        "../../../Tests/MangaRuntimeTests/OwnedFixtures/comicskingdom-manga.json"
                    ))
                } else if request.url.contains("/ck_comic?") {
                    HttpResp::ok(include_str!("../../../Tests/MangaRuntimeTests/OwnedFixtures/comicskingdom-chapters.json"))
                } else {
                    assert!(compact);
                    HttpResp::ok("<script>{\"totalItems\":2}</script>")
                }
            },
        );
        assert_eq!(book["manga"]["author"], "Owned author");
        assert_eq!(book["manga"]["description"], "Owned description");
        assert_eq!(
            book["chapters"].as_array().unwrap().len(),
            if compact { 1 } else { 2 }
        );
        if !compact {
            assert!(book["chapters"][0]["uploadedAt"].as_i64().unwrap() > 0);
        }
        let pages = run(
            &apk,
            json!({"op":"pages","modern":true,"chapter":book["chapters"][0],"settingsSourceID":source["id"],"settings":settings}),
            move |_| {
                let data = include_str!(
                    "../../../Tests/MangaRuntimeTests/OwnedFixtures/comicskingdom-chapters.json"
                );
                if compact {
                    HttpResp::ok(data)
                } else {
                    HttpResp::ok(serde_json::from_str::<Value>(data).unwrap()[0].to_string())
                }
            },
        );
        assert_eq!(pages.as_array().unwrap().len(), if compact { 2 } else { 1 });
        assert_eq!(
            pages[0]["imageURL"],
            "https://images.example/owned-page-2.png"
        );
        image(&apk, 0, &pages[0]);
    }
}

#[test]
fn projectsuki_delegates_catalog_and_sorted_posted_chapter_pages() {
    let apk = apk("tachiyomi-all.projectsuki-v1.6.0.apk");
    let catalog = run(&apk, json!({"op":"popular","modern":true}), |_| {
        HttpResp::ok(include_str!(
            "../../../Tests/MangaRuntimeTests/OwnedFixtures/projectsuki-catalog.html"
        ))
    });
    assert_eq!(catalog["mangas"][0]["title"], "Owned story");
    assert_eq!(
        catalog["mangas"][0]["thumbnailURL"],
        "https://projectsuki.com/images/gallery/42/thumb.png"
    );
    let pages = run(
        &apk,
        json!({"op":"pages","modern":true,"chapter":{"url":"/read/42/7/1","name":"Owned chapter"}}),
        |request| {
            assert_eq!(request.url, "https://projectsuki.com/callpage");
            assert_eq!(request.method, "POST");
            let body: Value = serde_json::from_str(request.body.as_deref().unwrap()).unwrap();
            assert_eq!(body["bookid"], "42");
            assert_eq!(body["chapterid"], "7");
            HttpResp::ok(include_str!(
                "../../../Tests/MangaRuntimeTests/OwnedFixtures/projectsuki-pages.json"
            ))
        },
    );
    assert_eq!(pages.as_array().unwrap().len(), 3);
    for (index, number) in [1, 2, 10].iter().enumerate() {
        assert_eq!(
            pages[index]["imageURL"],
            format!("https://projectsuki.com/images/gallery/42/owned/{number}")
        );
    }
    image(&apk, 0, &pages[0]);
}

#[test]
fn mangabuddy_catalog_and_nextjs_chapter_pages_keep_source_order() {
    let apk = apk("tachiyomi-en.mangabuddy-v1.6.34.apk");
    let catalog = run(&apk, json!({"op":"popular","modern":true}), |_| {
        HttpResp::ok(include_str!(
            "../../../Tests/MangaRuntimeTests/OwnedFixtures/mangabuddy-catalog.json"
        ))
    });
    assert_eq!(catalog["mangas"][0]["title"], "Owned story");
    assert_eq!(catalog["hasNext"], true);
    let pages = run(
        &apk,
        json!({"op":"pages","modern":true,"chapter":{"url":"/manga/owned/chapter-1","name":"Owned chapter"}}),
        |_| {
            let mut response = HttpResp::ok(include_str!(
                "../../../Tests/MangaRuntimeTests/OwnedFixtures/mangabuddy-pages.html"
            ));
            response
                .headers
                .push(("Content-Type".into(), "text/html; charset=utf-8".into()));
            response
        },
    );
    assert_eq!(pages.as_array().unwrap().len(), 2);
    assert_eq!(
        pages[0]["imageURL"],
        "https://images.example/owned-page-2.png"
    );
    assert_eq!(
        pages[1]["imageURL"],
        "https://images.example/owned-page-1.png"
    );
    image(&apk, 0, &pages[0]);
}
