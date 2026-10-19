//! Owned responses exercise installed extension bytecode, never host scrapers.
use super::*;

#[test]
fn shared_runtime_loads_owned_catalog_entries_from_independent_current_families() {
    let dir = std::env::var("MANGA_TEST_APK_DIR").expect("Run test-manga-runtime.sh");
    let fixtures = [
        (
            "tachiyomi-en.manhuaus-v1.6.60.apk",
            0,
            "/wp-admin/admin-ajax.php",
            "POST",
            include_bytes!("../../../Tests/MangaRuntimeTests/OwnedFixtures/madara-catalog.html")
                .as_slice(),
        ),
        (
            "tachiyomi-all.mangafire-v1.6.34.apk",
            0,
            "/api/titles?",
            "GET",
            include_bytes!("../../../Tests/MangaRuntimeTests/OwnedFixtures/mangafire-catalog.json")
                .as_slice(),
        ),
        (
            "tachiyomi-all.mangadex-v1.6.0.apk",
            17,
            "/manga?",
            "GET",
            include_bytes!("../../../Tests/MangaRuntimeTests/OwnedFixtures/mangadex-catalog.json")
                .as_slice(),
        ),
    ];
    for (file, source, path, method, body) in fixtures {
        let apk = std::fs::read(format!("{dir}/{file}")).unwrap();
        let command =
            serde_json::from_value(json!({"op":"popular","source":source,"modern":true})).unwrap();
        let requests = std::rc::Rc::new(std::cell::Cell::new(0));
        let counter = requests.clone();
        let result = execute(&apk, command, move |request| {
            counter.set(counter.get() + 1);
            assert!(request.url.contains(path), "{file}: {}", request.url);
            assert_eq!(request.method, method);
            HttpResp {
                code: 200,
                message: "OK".into(),
                headers: vec![],
                body: Some(body.to_vec()),
            }
        })
        .unwrap_or_else(|error| panic!("{file}: {error}"));
        assert_eq!(requests.get(), 1, "{file}");
        assert_eq!(result["mangas"].as_array().unwrap().len(), 1, "{file}");
        assert_eq!(result["mangas"][0]["title"], "Owned story", "{file}");
        assert!(
            !result["mangas"][0]["thumbnailURL"]
                .as_str()
                .unwrap()
                .is_empty(),
            "{file}"
        );
    }
}

// Encode only owned protobuf strings/messages, including multi-byte field keys.
fn proto(field: u32, body: &[u8]) -> Vec<u8> {
    fn varint(mut n: u32, out: &mut Vec<u8>) {
        while n >= 128 {
            out.push((n as u8) | 128);
            n >>= 7;
        }
        out.push(n as u8);
    }
    let mut out = Vec::new();
    varint((field << 3) | 2, &mut out);
    varint(body.len() as u32, &mut out);
    out.extend_from_slice(body);
    out
}

fn proto_int(field: u32, mut value: u32) -> Vec<u8> {
    assert!(field < 16);
    let mut out = vec![(field << 3) as u8];
    while value >= 128 {
        out.push((value as u8) | 128);
        value >>= 7;
    }
    out.push(value as u8);
    out
}

#[test]
fn mangaplus_catalog_details_and_dated_chapters_use_real_serializers() {
    let dir = std::env::var("MANGA_TEST_APK_DIR").expect("Run test-manga-runtime.sh");
    let apk = std::fs::read(format!("{dir}/tachiyomi-all.mangaplus-v1.6.67.apk")).unwrap();
    let mut title = proto_int(1, 123);
    title.extend(proto(2, b"Owned story"));
    title.extend(proto(3, b"Owned author"));
    title.extend(proto(4, b"https://images.example/owned-cover.webp"));
    let catalog_response = proto(1, &proto(37, &proto(3, &proto(2, &title))));
    let command = serde_json::from_value(json!({"op":"popular","modern":true})).unwrap();
    let catalog = execute(&apk, command, move |request| {
        assert!(request.url.contains("/api/title_list/rankingV2?"));
        HttpResp {
            code: 200,
            message: "OK".into(),
            headers: vec![],
            body: Some(catalog_response.clone()),
        }
    })
    .unwrap();
    assert_eq!(catalog["mangas"][0]["title"], "Owned story");
    assert_eq!(
        catalog["mangas"][0]["thumbnailURL"],
        "https://images.example/owned-cover.webp"
    );
    let mut group = Vec::new();
    for (id, number) in [(12345, 1), (12346, 2)] {
        let mut chapter = proto_int(2, id);
        chapter.extend(proto(3, format!("#{number}").as_bytes()));
        chapter.extend(proto(4, b"Owned chapter"));
        chapter.extend(proto_int(6, 1_790_000_000 + number));
        group.extend(proto(2, &chapter));
    }
    let mut detail = proto(1, &title);
    detail.extend(proto(3, b"Owned synopsis"));
    detail.extend(proto(28, &group));
    let response = proto(1, &proto(8, &detail));
    let command =
        serde_json::from_value(json!({"op":"book","modern":true,"manga":catalog["mangas"][0]}))
            .unwrap();
    let book = execute(&apk, command, move |request| {
        assert!(request.url.contains("/api/title_detailV3?"));
        assert!(request.url.contains("title_id=123"));
        HttpResp {
            code: 200,
            message: "OK".into(),
            headers: vec![],
            body: Some(response.clone()),
        }
    })
    .unwrap();
    assert_eq!(book["manga"]["description"], "Owned synopsis");
    assert_eq!(book["manga"]["author"], "Owned author");
    assert_eq!(book["chapters"].as_array().unwrap().len(), 2);
    assert_eq!(book["chapters"][0]["url"], "#/viewer/12346");
    assert_eq!(book["chapters"][0]["uploadedAt"], 1_790_000_002_000_i64);
}

#[test]
fn mangaplus_protobuf_reader_preserves_pages_and_view_token() {
    let dir = std::env::var("MANGA_TEST_APK_DIR").expect("Run test-manga-runtime.sh");
    let apk = std::fs::read(format!("{dir}/tachiyomi-all.mangaplus-v1.6.67.apk")).unwrap();
    let mut first_image = proto(1, b"https://images.example/owned-2.webp");
    first_image.extend(proto(5, b"0f10aa"));
    let mut viewer = proto(1, &proto(1, &first_image));
    viewer.extend(proto(
        1,
        &proto(1, &proto(1, b"https://images.example/owned-1.webp")),
    ));
    viewer.extend(proto(19, b"owned-view-token"));
    let response = proto(1, &proto(10, &viewer));
    let command = serde_json::from_value(json!({"op":"pages","modern":true,
        "chapter":{"url":"#/viewer/12345","name":"Chapter 1"}}))
    .unwrap();
    let result = execute(&apk, command, move |request| {
        assert!(request
            .url
            .starts_with("https://jumpg-webapi.tokyo-cdn.com/api/manga_viewer_v3?"));
        assert!(request.url.contains("chapter_id=12345"));
        HttpResp {
            code: 200,
            message: "OK".into(),
            headers: vec![],
            body: Some(response.clone()),
        }
    })
    .unwrap();
    assert_eq!(result.as_array().unwrap().len(), 2);
    assert_eq!(
        result[0]["imageURL"],
        "https://images.example/owned-2.webp#0f10aa"
    );
    assert_eq!(result[1]["imageURL"], "https://images.example/owned-1.webp");
    assert_eq!(result[0]["url"], "owned-view-token");
    let command =
        serde_json::from_value(json!({"op":"image","modern":true,"image":result[0]})).unwrap();
    let image = execute(&apk, command, |request| {
        assert_eq!(request.url, "https://images.example/owned-2.webp");
        assert!(request
            .headers
            .iter()
            .any(|(name, value)| name.eq_ignore_ascii_case("Plus-Vw-Token")
                && value == "owned-view-token"));
        HttpResp {
            code: 200,
            message: "OK".into(),
            headers: vec![],
            body: Some(vec![15, 239, 189, 143]),
        }
    })
    .unwrap();
    assert_eq!(
        STANDARD
            .decode(image["bodyBase64"].as_str().unwrap())
            .unwrap(),
        vec![0, 255, 23, 128]
    );
}

#[test]
fn mangaplus_truncated_protobuf_returns_an_error() {
    let dir = std::env::var("MANGA_TEST_APK_DIR").expect("Run test-manga-runtime.sh");
    let apk = std::fs::read(format!("{dir}/tachiyomi-all.mangaplus-v1.6.67.apk")).unwrap();
    let command = serde_json::from_value(json!({"op":"pages","modern":true,
        "chapter":{"url":"#/viewer/12345","name":"Chapter 1"}}))
    .unwrap();
    assert!(execute(&apk, command, |_| HttpResp {
        code: 200,
        message: "OK".into(),
        headers: vec![],
        body: Some(vec![0x0a, 0x7f, 0x52]),
    })
    .is_err());
}

#[test]
fn source_preferences_are_declared_by_the_apk_and_change_its_requests() {
    let dir = std::env::var("MANGA_TEST_APK_DIR").expect("Run test-manga-runtime.sh");
    let apk = std::fs::read(format!("{dir}/tachiyomi-all.mangaplus-v1.6.67.apk")).unwrap();
    let command = serde_json::from_value(json!({"op":"settings","modern":true})).unwrap();
    let schema = execute(&apk, command, |_| {
        panic!("Source settings must not use HTTP")
    })
    .unwrap();
    let controls = schema["settings"].as_array().unwrap();
    let quality = controls
        .iter()
        .find(|v| v["control"] == "choice")
        .expect("Real image quality choice");
    assert_eq!(quality["choices"].as_array().unwrap().len(), 3);
    let value = quality["choices"]
        .as_array()
        .unwrap()
        .iter()
        .find(|v| v["value"] != quality["defaultValue"]["value"])
        .unwrap()["value"]
        .as_str()
        .unwrap()
        .to_owned();
    let split = controls
        .iter()
        .find(|v| v["control"] == "toggle" && v["key"].as_str().unwrap().contains("split"))
        .unwrap();
    let split_value = !split["defaultValue"]["value"].as_bool().unwrap();
    let mut settings = serde_json::Map::new();
    settings.insert(
        quality["key"].as_str().unwrap().to_owned(),
        json!({"type":"string","value":value}),
    );
    settings.insert(
        split["key"].as_str().unwrap().to_owned(),
        json!({"type":"boolean","value":split_value}),
    );
    let response = proto(
        1,
        &proto(
            10,
            &proto(
                1,
                &proto(1, &proto(1, b"https://images.example/owned.webp")),
            ),
        ),
    );
    let command = serde_json::from_value(
        json!({"op":"pages","modern":true,"settingsSourceID":schema["sourceID"],"settings":settings,
        "chapter":{"url":"#/viewer/12345","name":"Chapter 1"}}),
    )
    .unwrap();
    let result = execute(&apk, command, move |request| {
        assert!(
            request.url.contains(&format!("img_quality={value}")),
            "Selected quality was ignored"
        );
        assert!(
            request
                .url
                .contains(if split_value { "split=yes" } else { "split=no" }),
            "Selected split setting was ignored"
        );
        HttpResp {
            code: 200,
            message: "OK".into(),
            headers: vec![],
            body: Some(response.clone()),
        }
    })
    .unwrap();
    assert_eq!(result[0]["imageURL"], "https://images.example/owned.webp");
    // A fresh, unseeded operation continues to use the extension's defaults.
    let command = serde_json::from_value(json!({"op":"settings","modern":true})).unwrap();
    assert_eq!(
        execute(&apk, command, |_| panic!("No settings network")).unwrap(),
        schema
    );
}

#[test]
fn mangaplus_source_image_interceptor_decodes_owned_bytes() {
    let dir = std::env::var("MANGA_TEST_APK_DIR").expect("Run test-manga-runtime.sh");
    let apk = std::fs::read(format!("{dir}/tachiyomi-all.mangaplus-v1.6.67.apk")).unwrap();
    let command = serde_json::from_value(json!({"op":"image","modern":true,
        "image":{"url":"owned-view-token","imageURL":"https://images.example/owned.webp#0f10"}}))
    .unwrap();
    let result = execute(&apk, command, |request| {
        assert_eq!(request.url, "https://images.example/owned.webp");
        HttpResp {
            code: 200,
            message: "OK".into(),
            headers: vec![],
            body: Some(vec![0x0f, 0xef, 0x18, 0x90]),
        }
    })
    .unwrap();
    assert_eq!(
        STANDARD
            .decode(result["bodyBase64"].as_str().unwrap())
            .unwrap(),
        vec![0, 255, 23, 128]
    );
}

#[test]
fn mangaplus_source_transform_preserves_key_position_across_read_chunks() {
    let dir = std::env::var("MANGA_TEST_APK_DIR").expect("Run test-manga-runtime.sh");
    let apk = std::fs::read(format!("{dir}/tachiyomi-all.mangaplus-v1.6.67.apk")).unwrap();
    let plain: Vec<u8> = (0..1_048_579).map(|i| (i % 251) as u8).collect();
    let key = [0x0f, 0x10, 0xaa];
    let encrypted: Vec<u8> = plain
        .iter()
        .enumerate()
        .map(|(i, byte)| byte ^ key[i % key.len()])
        .collect();
    let command = serde_json::from_value(json!({"op":"image","modern":true,
        "image":{"url":"owned-view-token","imageURL":"https://images.example/owned.webp#0f10aa"}}))
    .unwrap();
    let result = execute(&apk, command, move |request| {
        assert_eq!(request.url, "https://images.example/owned.webp");
        HttpResp {
            code: 200,
            message: "OK".into(),
            headers: vec![],
            body: Some(encrypted.clone()),
        }
    })
    .unwrap();
    assert_eq!(
        STANDARD
            .decode(result["bodyBase64"].as_str().unwrap())
            .unwrap(),
        plain
    );
}

#[test]
fn dalvik_long_shifts_take_int_distances_and_mask_to_six_bits() {
    use std::sync::{Arc, OnceLock};
    for opcode in [0xa3_u16, 0xa4, 0xa5, 0xc3, 0xc4, 0xc5] {
        let mut vm = Vm::new(vec![], Box::new(std::io::sink())).unwrap();
        vm.register_native(NativeEntry {
            class: "LAnimeShiftFixture;",
            name: "shift",
            sig: "(JI)J",
            instance: false,
            f: abstract_function,
        })
        .unwrap();
        let class = vm.ensure_class_by_desc("LAnimeShiftFixture;").unwrap();
        let key = (vm.intern("shift"), vm.intern("(JI)J"));
        let slot = vm.classes[class as usize].dispatch[&key];
        // Owned DEX code units: shift-long v0,v0,v2, then return-wide v0.
        // Include both 23x and /2addr forms, which share the VM arithmetic path.
        let words = if opcode < 0xb0 {
            vec![opcode, 0x0200, 0x0010]
        } else {
            vec![opcode | 0x2000, 0x0010]
        };
        let method = &mut vm.classes[class as usize].methods[slot as usize];
        method.native_key = None;
        method.insns = OnceLock::new();
        method.code = Some(Arc::new(dexvm::dex::CodeItem {
            registers_size: 3,
            ins_size: 3,
            outs_size: 0,
            insns: words.into(),
            tries: vec![],
        }));
        for value in [-1_i64, 0, 1, i64::MIN, i64::MAX] {
            for distance in [-1_i32, 0, 1, 63, 64, 65] {
                let n = distance as u32 & 63;
                let expected = match opcode {
                    0xa3 | 0xc3 => value.wrapping_shl(n),
                    0xa4 | 0xc4 => value.wrapping_shr(n),
                    _ => (value as u64).wrapping_shr(n) as i64,
                };
                let result = dexvm::vm::interpret::run(
                    &mut vm,
                    class,
                    slot,
                    vec![
                        JValue::Long(value),
                        JValue::Long(value),
                        JValue::Int(distance),
                    ],
                )
                .unwrap();
                assert!(
                    matches!(result, JValue::Long(actual) if actual == expected),
                    "opcode {opcode:x}, value {value}, distance {distance}: {result:?}"
                );
            }
        }
    }
}

fn pages(file: &str, modern: bool, html: &'static str) -> Value {
    let dir = std::env::var("MANGA_TEST_APK_DIR").expect("Run test-manga-runtime.sh");
    let apk = std::fs::read(format!("{dir}/{file}")).unwrap();
    let command = serde_json::from_value(json!({"op":"pages","modern":modern,
        "chapter":{"url":"/chapters/owned-1","name":"Chapter 1"}}))
    .unwrap();
    execute(&apk, command, move |_| HttpResp::ok(html)).unwrap()
}

#[test]
fn mangapill_classic_reader_parses_lazy_images_in_document_order() {
    let result = pages(
        "tachiyomi-en.mangapill-v1.4.9.apk",
        false,
        r#"<html><body><picture><img data-src="https://images.example/second.webp"></picture><picture><img data-src="https://images.example/first.webp"></picture><img src="https://images.example/advert.webp"></body></html>"#,
    );
    assert_eq!(result.as_array().unwrap().len(), 2);
    assert_eq!(result[0]["imageURL"], "https://images.example/second.webp");
    assert_eq!(result[1]["imageURL"], "https://images.example/first.webp");
}

#[test]
fn cuutruyen_modern_reader_parses_lazy_images_in_document_order() {
    let result = pages(
        "tachiyomi-vi.cuutruyenmoe-v1.6.3.apk",
        true,
        r#"<html><body><div class="text-center"><img class="max-w-full" data-src="https://images.example/second.webp"><img class="max-w-full" src="https://images.example/first.webp"></div><img src="https://images.example/advert.webp"></body></html>"#,
    );
    assert_eq!(result.as_array().unwrap().len(), 2);
    assert_eq!(result[0]["imageURL"], "https://images.example/second.webp");
    assert_eq!(result[1]["imageURL"], "https://images.example/first.webp");
}
