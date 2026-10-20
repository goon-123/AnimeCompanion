//! Owned responses exercise installed extension bytecode, never host scrapers.
use super::*;

#[test]
fn dalvik_floating_unary_instructions_read_raw_constants() {
    use std::sync::{Arc, OnceLock};
    for (opcode, input, expected) in [
        (
            0x7f,
            JValue::Int(2.5_f32.to_bits() as i32),
            JValue::Float(-2.5),
        ),
        (
            0x80,
            JValue::Long(2.5_f64.to_bits() as i64),
            JValue::Double(-2.5),
        ),
        (
            0x89,
            JValue::Int(2.5_f32.to_bits() as i32),
            JValue::Double(2.5),
        ),
        (
            0x8a,
            JValue::Long(f64::NAN.to_bits() as i64),
            JValue::Int(0),
        ),
        (
            0x8b,
            JValue::Long(f64::INFINITY.to_bits() as i64),
            JValue::Long(i64::MAX),
        ),
    ] {
        let mut vm = Vm::new(vec![], Box::new(std::io::sink())).unwrap();
        vm.register_native(NativeEntry {
            class: "LOwnedUnary;",
            name: "calculate",
            sig: "()D",
            instance: false,
            f: abstract_function,
        })
        .unwrap();
        let class = vm.ensure_class_by_desc("LOwnedUnary;").unwrap();
        let key = (vm.intern("calculate"), vm.intern("()D"));
        let slot = vm.classes[class as usize].dispatch[&key];
        let method = &mut vm.classes[class as usize].methods[slot as usize];
        method.native_key = None;
        method.insns = OnceLock::new();
        method.code = Some(Arc::new(dexvm::dex::CodeItem {
            registers_size: 5,
            ins_size: 5,
            outs_size: 0,
            insns: vec![opcode | 0x0400, 0x040f].into(),
            tries: vec![],
        }));
        assert_eq!(
            dexvm::vm::interpret::run(
                &mut vm,
                class,
                slot,
                vec![
                    input,
                    JValue::Null,
                    JValue::Null,
                    JValue::Null,
                    JValue::Null
                ]
            )
            .unwrap(),
            expected
        );
    }
}

#[test]
fn dalvik_float_and_double_arithmetic_keep_the_opcode_type_for_raw_constants() {
    use std::sync::{Arc, OnceLock};
    for (base, double, two_address) in [
        (0xa6_u16, false, false),
        (0xab, true, false),
        (0xc6, false, true),
        (0xcb, true, true),
    ] {
        for offset in 0..5 {
            let mut vm = Vm::new(vec![], Box::new(std::io::sink())).unwrap();
            vm.register_native(NativeEntry {
                class: "LOwnedArithmetic;",
                name: "calculate",
                sig: "()D",
                instance: false,
                f: abstract_function,
            })
            .unwrap();
            let class = vm.ensure_class_by_desc("LOwnedArithmetic;").unwrap();
            let key = (vm.intern("calculate"), vm.intern("()D"));
            let slot = vm.classes[class as usize].dispatch[&key];
            let method = &mut vm.classes[class as usize].methods[slot as usize];
            method.native_key = None;
            method.insns = OnceLock::new();
            let opcode = base + offset;
            let code = if two_address {
                vec![opcode | 0x2000, 0x000f]
            } else {
                vec![opcode | 0x0400, 0x0200, 0x040f]
            };
            method.code = Some(Arc::new(dexvm::dex::CodeItem {
                registers_size: 5,
                ins_size: 5,
                outs_size: 0,
                insns: code.into(),
                tries: vec![],
            }));
            for a in [-2.5_f64, -0.0, 0.0, 2.5, f64::INFINITY, f64::NAN] {
                for b in [-3.0_f64, 0.0, 3.0, f64::NAN] {
                    for raw_a in [false, true] {
                        for raw_b in [false, true] {
                            let value = |v: f64, raw| {
                                if double {
                                    if raw {
                                        JValue::Long(v.to_bits() as i64)
                                    } else {
                                        JValue::Double(v)
                                    }
                                } else if raw {
                                    JValue::Int((v as f32).to_bits() as i32)
                                } else {
                                    JValue::Float(v as f32)
                                }
                            };
                            let result = dexvm::vm::interpret::run(
                                &mut vm,
                                class,
                                slot,
                                vec![
                                    value(a, raw_a),
                                    JValue::Null,
                                    value(b, raw_b),
                                    JValue::Null,
                                    JValue::Int(0),
                                ],
                            )
                            .unwrap();
                            let expected = match offset {
                                0 => a + b,
                                1 => a - b,
                                2 => a * b,
                                3 => a / b,
                                _ => a % b,
                            };
                            let expected = if double {
                                expected
                            } else {
                                f64::from(expected as f32)
                            };
                            let actual = match result {
                                JValue::Double(v) if double => v,
                                JValue::Float(v) if !double => f64::from(v),
                                _ => panic!("Wrong opcode result type: {result:?}"),
                            };
                            if expected.is_nan() {
                                assert!(actual.is_nan());
                            } else {
                                assert_eq!(
                                    actual.to_bits(),
                                    expected.to_bits(),
                                    "opcode {opcode:x}"
                                );
                            }
                        }
                    }
                }
            }
        }
    }
}

#[test]
fn dalvik_float_comparisons_read_raw_constant_bits_and_preserve_nan_bias() {
    use std::sync::{Arc, OnceLock};
    for opcode in 0x2d_u16..=0x30 {
        let mut vm = Vm::new(vec![], Box::new(std::io::sink())).unwrap();
        vm.register_native(NativeEntry {
            class: "LOwnedCompare;",
            name: "compare",
            sig: "()I",
            instance: false,
            f: abstract_function,
        })
        .unwrap();
        let class = vm.ensure_class_by_desc("LOwnedCompare;").unwrap();
        let key = (vm.intern("compare"), vm.intern("()I"));
        let slot = vm.classes[class as usize].dispatch[&key];
        let method = &mut vm.classes[class as usize].methods[slot as usize];
        method.native_key = None;
        method.insns = OnceLock::new();
        method.code = Some(Arc::new(dexvm::dex::CodeItem {
            registers_size: 5,
            ins_size: 5,
            outs_size: 0,
            insns: vec![opcode | 0x0400, 0x0200, 0x040f].into(),
            tries: vec![],
        }));
        for a in [-2.5_f64, -0.0, 0.0, 2.5, f64::INFINITY, f64::NAN] {
            for b in [-0.0_f64, 0.0, 3.0, f64::NAN] {
                for raw_a in [false, true] {
                    for raw_b in [false, true] {
                        let value = |x: f64, raw: bool| {
                            if opcode <= 0x2e {
                                if raw {
                                    JValue::Int((x as f32).to_bits() as i32)
                                } else {
                                    JValue::Float(x as f32)
                                }
                            } else if raw {
                                JValue::Long(x.to_bits() as i64)
                            } else {
                                JValue::Double(x)
                            }
                        };
                        let expected = if a.is_nan() || b.is_nan() {
                            if opcode == 0x2e || opcode == 0x30 {
                                1
                            } else {
                                -1
                            }
                        } else if a < b {
                            -1
                        } else if a > b {
                            1
                        } else {
                            0
                        };
                        let result = dexvm::vm::interpret::run(
                            &mut vm,
                            class,
                            slot,
                            vec![
                                value(a, raw_a),
                                JValue::Null,
                                value(b, raw_b),
                                JValue::Null,
                                JValue::Int(0),
                            ],
                        )
                        .unwrap();
                        assert_eq!(result, JValue::Int(expected), "{opcode:x}: {a:?}, {b:?}");
                    }
                }
            }
        }
    }
}

#[test]
fn namicomi_catalog_uses_configured_serializers_and_unknown_relationships() {
    let dir = std::env::var("MANGA_TEST_APK_DIR").expect("Run test-manga-runtime.sh");
    let apk = std::fs::read(format!("{dir}/tachiyomi-all.namicomi-v1.6.0.apk")).unwrap();
    let catalog = execute(
        &apk,
        serde_json::from_value(json!({"op":"popular","modern":true})).unwrap(),
        |request| {
            assert!(request.url.contains("/title/search?"));
            HttpResp::ok(include_str!(
                "../../../Tests/MangaRuntimeTests/OwnedFixtures/namicomi-catalog.json"
            ))
        },
    )
    .unwrap();
    assert_eq!(catalog["mangas"][0]["title"], "Owned story");
    assert_eq!(catalog["mangas"][0]["author"], "Owned author");
    assert!(catalog["mangas"][0]["thumbnailURL"]
        .as_str()
        .unwrap()
        .contains("owned.webp"));
    assert_eq!(catalog["hasNext"], false);
}

#[test]
fn hiper_catalog_uses_nullable_filters_and_guest_serializers() {
    let dir = std::env::var("MANGA_TEST_APK_DIR").expect("Run test-manga-runtime.sh");
    let apk = std::fs::read(format!("{dir}/tachiyomi-en.hiperdex-v1.6.89.apk")).unwrap();
    for op in ["popular", "latest", "search"] {
        let command = serde_json::from_value(json!({"op":op,"modern":true,"query":"Owned", "settingsSourceID":"3064755045370217842", "settings":{"MAX_RATING":{"type":"string","value":"safe"}}})).unwrap();
        let result = execute(&apk, command, move |request| {
            assert!(request.url.contains("/api/trpc/search.query?"));
            assert_eq!(request.method, "GET");
            let input: Value = serde_json::from_str(&http_query_compat::decode(
                request.url.split("&input=").nth(1).unwrap(),
            ))
            .unwrap();
            assert_eq!(input["0"]["json"]["maxRating"], "safe");
            assert_eq!(input["0"]["json"]["filters"]["type"], Value::Null);
            HttpResp::ok(include_str!(
                "../../../Tests/MangaRuntimeTests/OwnedFixtures/hiper-catalog.json"
            ))
        })
        .unwrap();
        assert_eq!(result["mangas"][0]["title"], "Owned story");
        assert_eq!(
            result["mangas"][0]["thumbnailURL"],
            "https://images.example/owned-cover.webp"
        );
        assert_eq!(result["mangas"][0]["url"], "/manga/owned");
    }
}

#[test]
fn hiper_book_and_pages_use_real_dto_serializers() {
    let dir = std::env::var("MANGA_TEST_APK_DIR").expect("Run test-manga-runtime.sh");
    let apk = std::fs::read(format!("{dir}/tachiyomi-en.hiperdex-v1.6.89.apk")).unwrap();
    let book = execute(
        &apk,
        serde_json::from_value(
            json!({"op":"book","modern":true,"manga":{"url":"/manga/owned","title":"Owned story"}}),
        )
        .unwrap(),
        |request| {
            if request.url.contains("series.bySlugWithGenres?") {
                HttpResp::ok(include_str!(
                    "../../../Tests/MangaRuntimeTests/OwnedFixtures/hiper-details.json"
                ))
            } else {
                assert!(request.url.contains("series.chapters?"), "{}", request.url);
                let input: Value = serde_json::from_str(&http_query_compat::decode(
                    request.url.split("&input=").nth(1).unwrap(),
                ))
                .unwrap();
                assert_eq!(input["1"]["json"]["seriesId"], 1234567890123_i64);
                HttpResp::ok(include_str!(
                    "../../../Tests/MangaRuntimeTests/OwnedFixtures/hiper-chapters.json"
                ))
            }
        },
    )
    .unwrap();
    assert_eq!(book["manga"]["author"], "Owned author");
    assert_eq!(book["chapters"][0]["chapterNumber"], 2.5);
    assert_eq!(book["chapters"][0]["uploadedAt"], 1_790_856_000_000_i64);
    assert_eq!(book["chapters"][1]["url"], "/manga/owned/9000000000002");
    assert_eq!(book["chapters"][1]["memo"], "{\"chapterId\":9000000000002}");
    let pages = execute(
        &apk,
        serde_json::from_value(json!({"op":"pages","modern":true,"chapter":book["chapters"][1]}))
            .unwrap(),
        |request| {
            assert!(request.url.contains("reader.chapterPages?"));
            let input: Value = serde_json::from_str(&http_query_compat::decode(
                request.url.split("&input=").nth(1).unwrap(),
            ))
            .unwrap();
            assert_eq!(input["2"]["json"]["chapterNumber"], 2.5);
            assert_eq!(input["2"]["json"]["chapterId"], 9000000000002_i64);
            HttpResp::ok(include_str!(
                "../../../Tests/MangaRuntimeTests/OwnedFixtures/hiper-pages.json"
            ))
        },
    )
    .unwrap();
    assert_eq!(pages[0]["imageURL"], "https://images.example/owned-1.webp");
    assert_eq!(pages[1]["imageURL"], "https://images.example/owned-2.avif");
}

#[test]
fn hiper_reader_retries_with_headers_captured_by_its_browser_callback() {
    use std::cell::{Cell, RefCell};
    use std::collections::VecDeque;
    use std::rc::Rc;
    let dir = std::env::var("MANGA_TEST_APK_DIR").unwrap();
    let apk = std::fs::read(format!("{dir}/tachiyomi-en.hiperdex-v1.6.89.apk")).unwrap();
    let count = Rc::new(Cell::new(0));
    let calls = count.clone();
    let events = RefCell::new(VecDeque::new());
    let result = execute(&apk, serde_json::from_value(json!({"op":"pages","modern":true,"chapter":{"url":"/manga/owned/2.5","name":"Chapter 2.5","chapterNumber":2.5}})).unwrap(), move |request| {
        if request.method == "AC_BROWSER" {
            let body: Value = serde_json::from_str(request.body.as_deref().unwrap()).unwrap();
            let response = match body["op"].as_str().unwrap() {
                "load" => {
                    assert!(body["html"].as_str().unwrap().contains("X-Owned-Session"));
                    events.borrow_mut().extend([json!({"type":"started","url":body["url"]}),json!({"type":"finished","url":body["url"]}),json!({"type":"request","requestID":10,"url":"https://hiperdex.tv/api/owned-session","method":"GET","headers":[["X-Owned-Session","owned-session"]],"mainFrame":false})]);
                    json!({})
                },
                "next" => events.borrow_mut().pop_front().expect("The guest must resolve its header callback"),
                "evaluate" => json!({"value":"null"}),
                "decision" | "stop" | "close" => json!({}),
                _ => panic!("Unexpected browser operation"),
            };
            return HttpResp::ok(response.to_string());
        }
        if request.url.contains("reader.chapterPages?") {
            calls.set(calls.get() + 1);
            if calls.get() == 1 { return HttpResp::ok(r#"[{"error":{"message":"Owned session refresh required"}}]"#); }
            assert!(request.headers.iter().any(|(k,v)| k.eq_ignore_ascii_case("X-Owned-Session") && v == "owned-session"));
            return HttpResp::ok(include_str!("../../../Tests/MangaRuntimeTests/OwnedFixtures/hiper-pages.json"));
        }
        assert_eq!(request.url,"https://hiperdex.tv/manga/owned/2.5");
        HttpResp::ok(include_str!("../../../Tests/MangaRuntimeTests/OwnedFixtures/hiper-session.html"))
    }).unwrap();
    assert_eq!(result.as_array().unwrap().len(), 2);
    assert_eq!(count.get(), 2);
}

#[test]
fn hiper_catalog_401_follows_the_guest_homepage_refresh_and_retry() {
    use std::cell::Cell;
    use std::rc::Rc;
    let dir = std::env::var("MANGA_TEST_APK_DIR").unwrap();
    let apk = std::fs::read(format!("{dir}/tachiyomi-en.hiperdex-v1.6.89.apk")).unwrap();
    let count = Rc::new(Cell::new(0));
    let calls = count.clone();
    let result = execute(
        &apk,
        serde_json::from_value(json!({"op":"popular","modern":true})).unwrap(),
        move |request| {
            let n = calls.get();
            calls.set(n + 1);
            match n {
                0 => HttpResp {
                    code: 401,
                    message: "Unauthorized".into(),
                    headers: vec![],
                    body: Some(vec![]),
                },
                1 => {
                    assert!(request.url.trim_end_matches('/') == "https://hiperdex.tv");
                    HttpResp::ok("<html></html>")
                }
                2 => HttpResp::ok(include_str!(
                    "../../../Tests/MangaRuntimeTests/OwnedFixtures/hiper-catalog.json"
                )),
                _ => panic!("Unexpected retry"),
            }
        },
    )
    .unwrap();
    assert_eq!(count.get(), 3);
    assert_eq!(result["mangas"][0]["title"], "Owned story");
}

#[test]
fn hiper_fractional_reader_request_does_not_expand_float_rounding_error() {
    let dir = std::env::var("MANGA_TEST_APK_DIR").unwrap();
    let apk = std::fs::read(format!("{dir}/tachiyomi-en.hiperdex-v1.6.89.apk")).unwrap();
    let result = execute(&apk, serde_json::from_value(json!({"op":"pages","modern":true,"chapter":{"url":"/manga/owned/1.1","name":"Chapter 1.1","chapterNumber":1.1}})).unwrap(), |request| {
        let input: Value = serde_json::from_str(&http_query_compat::decode(request.url.split("&input=").nth(1).unwrap())).unwrap();
        assert_eq!(input["2"]["json"]["chapterNumber"],1.1);
        HttpResp::ok(include_str!("../../../Tests/MangaRuntimeTests/OwnedFixtures/hiper-pages.json"))
    }).unwrap();
    assert_eq!(result.as_array().unwrap().len(), 2);
}

#[test]
fn malformed_or_oversized_chapter_metadata_is_rejected_before_networking() {
    let dir = std::env::var("MANGA_TEST_APK_DIR").unwrap();
    let apk = std::fs::read(format!("{dir}/tachiyomi-en.hiperdex-v1.6.89.apk")).unwrap();
    for memo in [
        "[]".into(),
        "{bad}".into(),
        " ".repeat(65_537),
        format!("{{\"v\":{}0{}}}", "[".repeat(40), "]".repeat(40)),
    ] {
        assert!(execute(
            &apk,
            serde_json::from_value(
                json!({"op":"pages","modern":true,"chapter":{"url":"/manga/owned/1","memo":memo}})
            )
            .unwrap(),
            |_| panic!("Invalid metadata cannot trigger a request")
        )
        .is_err());
    }
}

#[test]
fn browser_sources_use_real_callbacks_to_decode_owned_catalogs() {
    use std::cell::RefCell;
    use std::collections::VecDeque;
    use std::rc::Rc;
    let dir = std::env::var("MANGA_TEST_APK_DIR").expect("Run test-manga-runtime.sh");
    for name in [
        "tachiyomi-all.cubari-v1.6.0.apk",
        "tachiyomi-en.comix-v1.6.54.apk",
        "tachiyomi-all.mangaup-v1.6.3.apk",
    ] {
        let apk = std::fs::read(format!("{dir}/{name}")).unwrap();
        let command = serde_json::from_value(json!({"op":"popular","modern":true})).unwrap();
        let events = Rc::new(RefCell::new(VecDeque::<Value>::new()));
        let bridges = Rc::new(RefCell::new(Vec::<String>::new()));
        let loaded = Rc::new(std::cell::Cell::new(false));
        let count = loaded.clone();
        let delivered = Rc::new(std::cell::Cell::new(false));
        let result = execute(&apk, command, move |request| {
            if request.method != "AC_BROWSER" {
                assert!(name.contains("mangaup"));
                assert!(request.url.contains("/api/search"));
                let title = [
                    proto_int(1, 1),
                    proto(2, b"Owned story"),
                    proto(3, b"/owned-cover.jpg"),
                    proto_int(7, 1),
                    proto(9, b"Oct 19, 2026"),
                ]
                .concat();
                return HttpResp::ok_bytes(proto(2, &title));
            }
            let value: Value = serde_json::from_str(request.body.as_deref().unwrap()).unwrap();
            let response = match value["op"].as_str().unwrap() {
                "load" => {
                    count.set(true);
                    *bridges.borrow_mut() = value["bridges"]
                        .as_array()
                        .unwrap()
                        .iter()
                        .map(|v| v.as_str().unwrap().to_owned())
                        .collect();
                    events.borrow_mut().extend([json!({"type":"request","requestID":1,"url":value["url"],"method":"GET","headers":[["Accept","text/html"]],"mainFrame":true}),json!({"type":"started","url":value["url"]}),json!({"type":"finished","url":value["url"]})]);
                    if name.contains("comix") {
                        events.borrow_mut().push_front(json!({"type":"request","requestID":2,"url":"https://blocked.example/ad.js","method":"GET","headers":[],"mainFrame":false}));
                    }
                    json!({})
                }
                "close" | "stop" => json!({}),
                "decision" => {
                    assert_eq!(value["allow"], value["requestID"] != 2, "{name}: {value}");
                    if value["requestID"] == 2 {
                        assert_eq!(value["response"]["bodyBase64"], "");
                    }
                    json!({})
                }
                "next" => events
                    .borrow_mut()
                    .pop_front()
                    .expect("Browser must resolve from owned data"),
                "evaluate" => {
                    let script = value["script"].as_str().unwrap();
                    if script.contains("__comixBrowsePayload") && !delivered.replace(true) {
                        events.borrow_mut().push_back(json!({"type":"message","name":bridges.borrow()[0],"method":"post","message":include_str!("../../../Tests/MangaRuntimeTests/OwnedFixtures/comix-catalog.json")}));
                    } else if script.contains("globalHistoryHandler") && !delivered.replace(true) {
                        events.borrow_mut().push_back(json!({"type":"message","name":"android","method":"post","message":include_str!("../../../Tests/MangaRuntimeTests/OwnedFixtures/cubari-history.json")}));
                    }
                    json!({"value":"null"})
                }
                _ => panic!("Unknown browser command for {name}: {value}"),
            };
            HttpResp::ok(response.to_string())
        });
        let page = result.unwrap_or_else(|e| panic!("{name}: {e}"));
        assert!(loaded.get(), "{name}");
        assert_eq!(page["mangas"].as_array().unwrap().len(), 1, "{name}");
        assert_eq!(page["mangas"][0]["title"], "Owned story", "{name}");
        assert!(
            !page["mangas"][0]["thumbnailURL"]
                .as_str()
                .unwrap()
                .is_empty(),
            "{name}"
        );
    }
}

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
