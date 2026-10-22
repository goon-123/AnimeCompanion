//! Published extension bytecode replays neutral owned responses, never live sites.
use super::*;
fn fixture(name: &str) -> String {
    std::fs::read_to_string(format!(
        "{}/../../Tests/MangaRuntimeTests/OwnedFixtures/{name}",
        env!("CARGO_MANIFEST_DIR")
    ))
    .unwrap()
}
fn image(bytes: &[u8], page: &Value) {
    let expected = page["imageURL"].as_str().unwrap().to_owned();
    let value = run(bytes, json!({"op":"image","image":page}), move |request| {
        assert_eq!(request.url, expected);
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
fn apk(name: &str) -> Vec<u8> {
    std::fs::read(format!(
        "{}/{name}",
        std::env::var("MANGA_TEST_APK_DIR").expect("Run test-manga-runtime.sh")
    ))
    .unwrap()
}
fn run(bytes: &[u8], command: Value, http: impl Fn(&HttpData) -> HttpResp + 'static) -> Value {
    let mut command = command;
    command["modern"] = json!(true);
    command["timeZoneID"] = json!("UTC");
    execute(bytes, serde_json::from_value(command).unwrap(), http).unwrap()
}
#[test]
fn shared_jvm_extensions_load_their_real_factories_and_settings_without_network() {
    for name in [
        "tachiyomi-all.tappytoon-v1.6.0.apk",
        "tachiyomi-ar.arabmanhwa-v1.6.57.apk",
        "tachiyomi-ar.procomic-v1.6.0.apk",
        "tachiyomi-es.codearc-v1.6.2.apk",
        "tachiyomi-es.inmanga-v1.6.1.apk",
        "tachiyomi-es.lectorjpg-v1.6.50.apk",
        "tachiyomi-ja.linemanga-v1.6.1.apk",
        "tachiyomi-ru.nudemoon-v1.6.32.apk",
        "tachiyomi-es.lectormonline-v1.6.4.apk",
    ] {
        let bytes = apk(name);
        for op in ["inspect", "settings"] {
            let result = execute(
                &bytes,
                serde_json::from_value(json!({"op":op,"modern":true})).unwrap(),
                |_| panic!("Metadata must not network"),
            );
            assert!(result.is_ok(), "{name} {op}: {result:?}");
        }
    }
}
#[test]
fn procomic_mutable_cursor_references_skip_unreadable_pages() {
    let bytes = apk("tachiyomi-ar.procomic-v1.6.0.apk");
    let result = run(&bytes, json!({"op":"popular"}), |request| {
        assert!(
            request.url.contains("/api/public/content?"),
            "{}",
            request.url
        );
        if request.url.contains("page=1") {
            HttpResp::ok(fixture("procomic-catalog-1.json"))
        } else {
            assert!(request.url.contains("page=2"), "{}", request.url);
            HttpResp::ok(fixture("procomic-catalog-2.json"))
        }
    });
    assert_eq!(result["mangas"][0]["title"], "Owned story");
    assert_eq!(result["hasNext"], false);
}
#[test]
fn codearc_bound_client_headers_and_url_references_execute_in_the_image_interceptor() {
    let bytes = apk("tachiyomi-es.codearc-v1.6.2.apk");
    let catalog = run(&bytes, json!({"op":"popular"}), |request| {
        assert!(request.url.contains("/ranking?"), "{}", request.url);
        HttpResp::ok(fixture("codearc-catalog.html"))
    });
    assert_eq!(catalog["mangas"][0]["title"], "Owned story");
    for access in ["", "&access=eyJleHAiOjB9.owned"] {
        let url=format!("https://images.example/owned.webp?reader_slug=owned&reader_chapter=chapter&reader_page=1{access}");
        let image = run(
            &bytes,
            json!({"op":"image","image":{"imageURL":url,"url":"","index":0}}),
            |request| {
                if request.url.contains("/api/mangas/reader-access") {
                    assert_eq!(request.method, "POST");
                    return HttpResp::ok(fixture("codearc-reader-access.json"));
                }
                if request.url.contains("/api/mangas/reader-pages?") {
                    return HttpResp::ok(fixture("codearc-reader-pages.json"));
                }
                if request.url.contains("/owned.webp?") {
                    return HttpResp {
                        code: 403,
                        message: "Forbidden".into(),
                        headers: vec![],
                        body: Some(vec![]),
                    };
                }
                assert_eq!(request.url, "https://images.example/owned-refreshed.webp");
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
}
#[test]
fn inmanga_fractional_dates_async_details_ordered_pages_and_images() {
    let bytes = apk("tachiyomi-es.inmanga-v1.6.1.apk");
    let catalog = run(&bytes, json!({"op":"popular"}), |r| {
        assert!(r.url.ends_with("/manga/getMangasConsultResult"));
        assert_eq!(r.method, "POST");
        HttpResp::ok(fixture("inmanga-catalog.html"))
    });
    assert_eq!(catalog["mangas"][0]["title"], "Owned story");
    let book = run(
        &bytes,
        json!({"op":"book","manga":catalog["mangas"][0]}),
        |r| {
            if r.url.ends_with("/ver/manga/owned/1") {
                HttpResp::ok(fixture("inmanga-book.html"))
            } else {
                assert!(
                    r.url.contains("/chapter/getall?mangaIdentification=1"),
                    "{}",
                    r.url
                );
                HttpResp::ok(fixture("inmanga-chapters.json"))
            }
        },
    );
    assert_eq!(book["manga"]["description"], "Owned description");
    assert_eq!(book["chapters"][0]["uploadedAt"], 1_709_251_200_000_i64);
    assert_eq!(book["chapters"][1]["uploadedAt"], 1_709_210_096_123_i64);
    assert_eq!(book["chapters"][2]["uploadedAt"], -1_i64);
    let pages = run(
        &bytes,
        json!({"op":"pages","chapter":book["chapters"][0]}),
        |r| {
            assert!(r
                .url
                .ends_with("/chapter/chapterIndexControls?identification=owned-3"));
            HttpResp::ok(fixture("inmanga-pages.html"))
        },
    );
    assert_eq!(
        pages[0]["imageURL"],
        "https://cdn1.intomanga.com/i/m/1/c/owned-chapter/o/2.jpg"
    );
    assert_eq!(
        pages[1]["imageURL"],
        "https://cdn1.intomanga.com/i/m/1/c/owned-chapter/o/1.jpg"
    );
    image(&bytes, &pages[0]);
}
#[test]
fn arabmanhwa_java_duration_relative_dates_pages_and_images() {
    let bytes = apk("tachiyomi-ar.arabmanhwa-v1.6.57.apk");
    let catalog = run(&bytes, json!({"op":"popular"}), |r| {
        assert!(r.url.contains("/manga/"));
        HttpResp::ok(fixture("arabmanhwa-catalog.html"))
    });
    assert_eq!(catalog["mangas"][0]["title"], "Owned story");
    let before = time::OffsetDateTime::now_utc().unix_timestamp_nanos() / 1_000_000;
    let book = run(
        &bytes,
        json!({"op":"book","manga":catalog["mangas"][0]}),
        |r| {
            assert!(r.url.ends_with("/manga/owned/"));
            HttpResp::ok(fixture("arabmanhwa-book.html"))
        },
    );
    let after = time::OffsetDateTime::now_utc().unix_timestamp_nanos() / 1_000_000;
    for (index, age) in [(0, 120_000_i128), (1, 8 * 30 * 86_400_000_i128)] {
        let uploaded = i128::from(book["chapters"][index]["uploadedAt"].as_i64().unwrap());
        assert!((before - age..=after - age).contains(&uploaded), "{book}");
    }
    let pages = run(
        &bytes,
        json!({"op":"pages","chapter":book["chapters"][0]}),
        |r| {
            assert!(r.url.ends_with("/chapter/owned-2/"));
            HttpResp::ok(fixture("arabmanhwa-pages.html"))
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
    image(&bytes, &pages[0]);
}
#[test]
fn localized_weekday_and_instant_cursors_reach_the_real_catalog_requests() {
    let line = apk("tachiyomi-ja.linemanga-v1.6.1.apk");
    let today = time::OffsetDateTime::now_utc()
        .to_offset(time::UtcOffset::from_hms(9, 0, 0).unwrap())
        .weekday()
        .number_days_from_sunday()
        + 1;
    let catalog = run(&line, json!({"op":"latest"}), move |r| {
        assert!(r.url.contains(&format!("week_day={today}")), "{}", r.url);
        HttpResp::ok(
            r#"{"rows":[{"thumbnail":null,"is_light_novel":false,"id":"owned","name":"Owned story"}],"pager":null}"#,
        )
    });
    assert_eq!(catalog["mangas"][0]["title"], "Owned story");
    let lector = apk("tachiyomi-es.lectorjpg-v1.6.50.apk");
    let catalog = run(&lector, json!({"op":"latest"}), |r| {
        let encoded = r
            .url
            .split_once("cursor=")
            .unwrap()
            .1
            .split('&')
            .next()
            .unwrap();
        let mut decoded = Vec::new();
        let mut input = encoded.bytes();
        while let Some(byte) = input.next() {
            if byte == b'%' {
                let digits = [input.next().unwrap(), input.next().unwrap()];
                decoded
                    .push(u8::from_str_radix(std::str::from_utf8(&digits).unwrap(), 16).unwrap());
            } else {
                decoded.push(byte);
            }
        }
        let cursor: Value = serde_json::from_slice(&STANDARD.decode(decoded).unwrap()).unwrap();
        assert_eq!(cursor["id"], 0);
        let date = cursor["last_update_at"].as_str().unwrap();
        assert_eq!(date.len(), 19);
        assert_eq!(&date[10..11], " ");
        HttpResp::ok(
            r#"{"data":[{"name":"Owned story","slug":"owned","cover_url":null}],"next_cursor":null}"#,
        )
    });
    assert_eq!(catalog["mangas"][0]["title"], "Owned story");
}
#[test]
fn nudemoon_optional_custom_month_text_parses_a_real_chapter_date() {
    let bytes = apk("tachiyomi-ru.nudemoon-v1.6.32.apk");
    let book = run(
        &bytes,
        json!({"op":"book","manga":{"url":"/owned.html","title":"Owned story"}}),
        |_| {
            HttpResp::ok(
                r#"<h1>Owned story</h1><table><tr><td><img src="/time.png"><span class="small2">29 февраль 2024</span></td></tr></table>"#,
            )
        },
    );
    assert_eq!(book["chapters"][0]["uploadedAt"], 1_709_164_800_000_i64);
}
#[test]
fn tappytoon_localized_short_weekday_is_used_for_latest() {
    let bytes = apk("tachiyomi-all.tappytoon-v1.6.0.apk");
    let expected = time::OffsetDateTime::now_utc().weekday().to_string()[..3].to_lowercase();
    let catalog = run(&bytes, json!({"op":"latest"}), move |r| {
        if r.url.contains("day_of_week=") {
            assert!(
                r.url.contains(&format!("day_of_week={expected}")),
                "{}",
                r.url
            );
            HttpResp::ok("[]")
        } else {
            HttpResp::ok(
                r#"<script id="__NEXT_DATA__" type="application/json">{"props":{"initialState":{"axios":{"headers":{"Authorization":"owned-token","X-Device-Uuid":"owned-device"}}}}}</script>"#,
            )
        }
    });
    assert_eq!(catalog["mangas"].as_array().unwrap().len(), 0);
}
