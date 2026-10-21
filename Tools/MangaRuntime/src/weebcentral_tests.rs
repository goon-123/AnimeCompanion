use super::*;

// Owned HTML, not captured manga content. The real, hash-pinned APK supplies
// every request and selector, including its async details/chapter update.
const DETAILS: &str =
    include_str!("../../../Tests/MangaRuntimeTests/OwnedFixtures/weebcentral-details.html");
const CHAPTERS: &str =
    include_str!("../../../Tests/MangaRuntimeTests/OwnedFixtures/weebcentral-chapters.html");
const PAGES: &str =
    include_str!("../../../Tests/MangaRuntimeTests/OwnedFixtures/weebcentral-pages.html");

fn apk() -> Vec<u8> {
    let dir = std::env::var("MANGA_TEST_APK_DIR").expect("Run test-manga-runtime.sh");
    std::fs::read(format!("{dir}/tachiyomi-en.weebcentral-v1.6.25.apk")).unwrap()
}

fn book_command() -> Command {
    serde_json::from_value(json!({"op":"book","modern":true,
        "manga":{"url":"/series/owned-id/owned-webtoon","title":"Owned webtoon"}}))
    .unwrap()
}

#[test]
fn weebcentral_details_chapters_pages_and_source_images() {
    let apk = apk();
    let book = execute(&apk, book_command(), |request| {
        assert_eq!(request.method, "GET");
        match request.url.as_str() {
            "https://weebcentral.com/series/owned-id/owned-webtoon" => HttpResp::ok(DETAILS),
            "https://weebcentral.com/series/owned-id/full-chapter-list" => HttpResp::ok(CHAPTERS),
            other => panic!("Unexpected extension request: {other}"),
        }
    })
    .unwrap();
    assert_eq!(book["manga"]["title"], "Owned webtoon");
    assert_eq!(book["manga"]["author"], "Owned author");
    assert_eq!(book["manga"]["description"], "Owned synopsis.");
    assert_eq!(book["manga"]["status"], 1);
    let chapters = book["chapters"].as_array().unwrap();
    assert_eq!(chapters.len(), 2);
    assert_eq!(chapters[0]["name"], "Chapter 2");
    assert_eq!(chapters[0]["url"], "/chapters/owned-2");
    assert_eq!(chapters[0]["scanlator"], "Official");
    assert_eq!(chapters[0]["uploadedAt"], 1_790_857_800_000_i64);
    let command = serde_json::from_value(json!({"op":"pages","modern":true,
        "chapter":{"url":chapters[0]["url"],"name":chapters[0]["name"]}}))
    .unwrap();
    let pages = execute(&apk, command, |request| {
        assert_eq!(request.url, "https://weebcentral.com/chapters/owned-2/images?is_prev=False&reading_style=long_strip");
        HttpResp::ok(PAGES)
    }).unwrap();
    assert_eq!(pages.as_array().unwrap().len(), 2);
    assert_eq!(pages[0]["imageURL"], "https://images.example/owned-1.webp");
    assert_eq!(pages[1]["imageURL"], "https://images.example/owned-2.webp");
    let command =
        serde_json::from_value(json!({"op":"image","modern":true,"image":pages[0]})).unwrap();
    let image =
        execute(&apk, command, |request| {
            assert_eq!(request.url, "https://images.example/owned-1.webp");
            assert!(request
                .headers
                .iter()
                .any(|(key, value)| key.eq_ignore_ascii_case("accept")
                    && value.contains("image/webp")));
            HttpResp {
                code: 200,
                message: "OK".into(),
                headers: vec![],
                body: Some(vec![0, 255, 23, 128]),
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
fn weebcentral_failed_update_does_not_become_an_empty_success() {
    let result = execute(&apk(), book_command(), |request| {
        if request.url.ends_with("full-chapter-list") {
            HttpResp {
                code: 503,
                message: "Unavailable".into(),
                headers: vec![],
                body: Some(b"unavailable".to_vec()),
            }
        } else {
            HttpResp::ok(DETAILS)
        }
    });
    let error = result.expect_err("A failed chapter update must remain retryable");
    assert!(
        error.contains("503"),
        "The task's actual failure was lost: {error}"
    );
}

#[test]
fn instant_companion_is_a_stable_static_root() {
    let mut vm = Vm::new(vec![], Box::new(std::io::sink())).unwrap();
    install_host_fields(&mut vm).unwrap();
    let field = dexvm::vm::FieldRef {
        class_desc: vm.intern("Lkotlin/time/Instant;"),
        name: vm.intern("Companion"),
        ty: vm.intern("Lkotlin/time/Instant$Companion;"),
    };
    let first = vm.static_field_get(field).unwrap();
    assert!(!first.is_null());
    install_host_fields(&mut vm).unwrap();
    vm.gc(&[]);
    assert_eq!(vm.static_field_get(field).unwrap(), first);
}

fn failed_task(vm: &mut Vm, _args: &[JValue]) -> Result<JValue, NatErr> {
    Err(NatErr::Throw(vm.throwable_of(
        "Ljava/io/IOException;",
        "Owned task failure",
    )))
}
fn exhausted_task(_vm: &mut Vm, _args: &[JValue]) -> Result<JValue, NatErr> {
    Err(NatErr::Fatal(dexvm::vm::error::JvmError::BudgetExceeded))
}
fn task_vm(f: dexvm::vm::NativeFn) -> (Vm, Vec<JValue>) {
    let mut vm = Vm::new(vec![], Box::new(std::io::sink())).unwrap();
    coroutine_compat::install(&mut vm).unwrap();
    vm.register_native(NativeEntry {
        class: "Lkotlin/jvm/functions/Function2;",
        name: "invoke",
        sig: "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;",
        instance: true,
        f,
    })
    .unwrap();
    let task = vm
        .alloc_native(
            "Lkotlin/jvm/functions/Function2;",
            dexvm::vm::object::Native::Opaque,
        )
        .unwrap();
    (vm, vec![JValue::Null, JValue::Null, JValue::Null, task])
}

#[test]
fn async_retains_thrown_errors_until_await() {
    let (mut vm, args) = task_vm(failed_task);
    let task = coroutine_async(&mut vm, &args).unwrap();
    let Some(dexvm::vm::object::Native::Deferred { value, error }) = vm.payload_of(task) else {
        panic!("Not a task")
    };
    assert!(value.is_null());
    assert!(!error.is_null());
    assert!(
        matches!(coroutine_await(&mut vm, &[task]), Err(NatErr::Throw(id)) if id == error.as_obj())
    );
}

#[test]
fn async_never_swallows_the_vm_instruction_limit() {
    let (mut vm, args) = task_vm(exhausted_task);
    assert!(matches!(
        coroutine_async(&mut vm, &args),
        Err(NatErr::Fatal(dexvm::vm::error::JvmError::BudgetExceeded))
    ));
}
