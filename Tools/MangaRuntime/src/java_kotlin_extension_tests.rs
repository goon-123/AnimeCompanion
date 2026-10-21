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
fn owned_image(name: &str) -> Vec<u8> {
    std::fs::read(format!(
        "{}/../../Tests/MangaRuntimeTests/OwnedFixtures/{name}",
        env!("CARGO_MANIFEST_DIR")
    ))
    .unwrap()
}
fn jinman_image(aid: u32, body: Vec<u8>, gzip: bool) -> Result<Vec<u8>, String> {
    use std::io::Write;
    let body = if gzip {
        let mut encoder = flate2::write::GzEncoder::new(Vec::new(), flate2::Compression::fast());
        encoder.write_all(&body).unwrap();
        encoder.finish().unwrap()
    } else {
        body
    };
    let bytes = apk("tachiyomi-zh.jinmantiantang-v1.6.59.apk");
    let url = format!("https://images.example/media/photos/{aid}/owned.webp");
    let result = execute(
        &bytes,
        serde_json::from_value(
            json!({"op":"image","modern":true,"image":{"index":0,"url":"","imageURL":url}}),
        )
        .unwrap(),
        move |r| {
            assert_eq!(r.url, url);
            HttpResp {
                code: 200,
                message: "OK".into(),
                headers: if gzip {
                    vec![
                        ("Content-Encoding".into(), "gzip".into()),
                        ("Content-Length".into(), body.len().to_string()),
                    ]
                } else {
                    vec![]
                },
                body: Some(body.clone()),
            }
        },
    )?;
    STANDARD
        .decode(result["bodyBase64"].as_str().unwrap())
        .map_err(|e| e.to_string())
}
#[test]
fn jinman_scrambled_png_jpeg_webp_and_gzip_restore_pixels_through_guest_bytecode() {
    // Explicit source strip starts for the three published row-count branches.
    for (aid, starts) in [
        (260000, vec![144, 128, 112, 96, 80, 64, 48, 32, 16, 0]),
        (
            300000,
            vec![
                150, 140, 130, 120, 110, 100, 90, 80, 70, 60, 50, 40, 30, 20, 10, 0,
            ],
        ),
        (500000, vec![140, 120, 100, 80, 60, 40, 20, 0]),
    ] {
        for name in ["owned-bands.png", "owned-bands.jpg", "owned-bands.webp"] {
            let input = owned_image(name);
            let original = image::load_from_memory(&input).unwrap().to_rgb8();
            for gzip in [false, true] {
                let bytes = jinman_image(aid, input.clone(), gzip)
                    .unwrap_or_else(|e| panic!("{aid}/{name}/gzip={gzip}: {e}"));
                assert!(bytes.starts_with(&[255, 216]), "Output must be a real JPEG");
                let decoded = image::load_from_memory(&bytes).unwrap().to_rgb8();
                assert_eq!(decoded.dimensions(), (32, 163));
                let mut out_y = 0;
                for (index, &source_y) in starts.iter().enumerate() {
                    let height = if index == 0 {
                        163 / starts.len() as u32 + 163 % starts.len() as u32
                    } else {
                        163 / starts.len() as u32
                    };
                    for row in 0..height {
                        let expected = original.get_pixel(16, source_y + row);
                        let actual = decoded.get_pixel(16, out_y + row);
                        for channel in 0..3 {
                            assert!(
                                (i16::from(expected[channel]) - i16::from(actual[channel])).abs() <= 30,
                                "{aid}/{name}/gzip={gzip}, strip={index}, row={row}: {expected:?} != {actual:?}"
                            );
                        }
                    }
                    out_y += height;
                }
                assert_eq!(out_y, 163);
            }
        }
    }
}
#[test]
fn jinman_modern_gif_and_gzipped_gif_preserve_animation_bytes() {
    let bytes = owned_image("owned-animation.gif");
    for gzip in [false, true] {
        assert_eq!(jinman_image(300000, bytes.clone(), gzip).unwrap(), bytes);
    }
}
#[test]
fn jinman_malformed_scrambled_image_fails_without_placeholder_output() {
    assert!(jinman_image(300000, b"not an image".to_vec(), false).is_err());
}
