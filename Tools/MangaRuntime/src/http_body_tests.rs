//! Standard request semantics: owned bytes only, no source-specific transport.
use super::*;
use dexvm::vm::error::JvmError;
use dexvm::vm::object::Native;
use std::cell::RefCell;
use std::rc::Rc;

fn vm() -> Vm {
    let mut vm = Vm::new(vec![], Box::new(std::io::sink())).unwrap();
    vm.perms.grant(Permission::Network(NetworkPermission::Any));
    vm
}

fn send(
    vm: &mut Vm,
    body: Option<JValue>,
    legacy: bool,
    headers: Vec<(String, String)>,
) -> Result<JValue, JvmError> {
    let request = vm.alloc_native(
        "Lokhttp3/Request;",
        Native::Request {
            url: "https://transport.example/owned".into(),
            method: "POST".into(),
            headers,
            body,
        },
    )?;
    if legacy {
        vm.invoke_static(
            "Leu/kanade/tachiyomi/network/RequestsKt;",
            "__host_execute",
            "(Lokhttp3/Request;)Lokhttp3/Response;",
            vec![request],
        )
    } else {
        let call = vm.alloc_native(
            "Lokhttp3/Call;",
            Native::Call {
                request,
                client: JValue::Null,
                canceled: false,
            },
        )?;
        vm.invoke_virtual(call, "execute", "()Lokhttp3/Response;")
    }
}

#[test]
fn both_request_paths_preserve_binary_empty_and_absent_bodies() {
    for legacy in [false, true] {
        let mut vm = vm();
        let seen = Rc::new(RefCell::new(Vec::new()));
        let captured = seen.clone();
        vm.http = Some(Rc::new(move |request| {
            captured.borrow_mut().push(request.clone());
            HttpResp::ok("")
        }));
        let binary = vec![0, 255, 128, 195, 40, 13, 10];
        for bytes in [
            binary.clone(),
            Vec::new(),
            "Owned café\0".as_bytes().to_vec(),
        ] {
            let body = vm
                .alloc_native(
                    "Lokhttp3/RequestBody;",
                    Native::RequestBody {
                        data: bytes.clone(),
                        content_type: Some("application/octet-stream".into()),
                    },
                )
                .unwrap();
            send(&mut vm, Some(body), legacy, vec![]).unwrap();
            let request = seen.borrow().last().unwrap().clone();
            assert_eq!(request.body_bytes, Some(bytes.clone()));
            assert_eq!(request.body, String::from_utf8(bytes.clone()).ok());
            assert!(request
                .headers
                .contains(&("Content-Type".into(), "application/octet-stream".into())));
            let wire = http_wire::request_json(&request);
            assert_eq!(
                STANDARD
                    .decode(wire["bodyBase64"].as_str().unwrap())
                    .unwrap(),
                bytes
            );
        }
        send(&mut vm, None, legacy, vec![]).unwrap();
        let absent = seen.borrow().last().unwrap().clone();
        assert_eq!(absent.body_bytes, None);
        assert!(http_wire::request_json(&absent)["bodyBase64"].is_null());
        assert!(absent.headers.is_empty());
        let body = vm
            .alloc_native(
                "Lokhttp3/RequestBody;",
                Native::RequestBody {
                    data: binary,
                    content_type: Some("application/octet-stream".into()),
                },
            )
            .unwrap();
        send(
            &mut vm,
            Some(body),
            legacy,
            vec![("content-type".into(), "application/owned".into())],
        )
        .unwrap();
        assert_eq!(
            seen.borrow().last().unwrap().headers,
            vec![("content-type".into(), "application/owned".into())]
        );
    }
}

fn custom_type(vm: &mut Vm, _: &[JValue]) -> Result<JValue, NatErr> {
    vm.alloc_native(
        "Lokhttp3/MediaType;",
        Native::Str("application/owned".into()),
    )
    .map_err(NatErr::Fatal)
}

fn custom_write(vm: &mut Vm, args: &[JValue]) -> Result<JValue, NatErr> {
    let Some(Native::OkioBuf { bytes, .. }) =
        vm.arena.objects[args[1].as_obj() as usize].native.as_mut()
    else {
        panic!("The guest must receive a real buffered sink");
    };
    bytes.extend([0, 255, 128]);
    Ok(JValue::Null)
}

fn custom_throw(vm: &mut Vm, _: &[JValue]) -> Result<JValue, NatErr> {
    Err(NatErr::Throw(vm.throwable_of(
        "Ljava/io/IOException;",
        "Owned write failure",
    )))
}

fn custom_fatal(_: &mut Vm, _: &[JValue]) -> Result<JValue, NatErr> {
    Err(NatErr::Fatal(JvmError::BudgetExceeded))
}

fn custom(vm: &mut Vm, write: dexvm::vm::NativeFn) -> JValue {
    for (name, sig, f) in [
        (
            "contentType",
            "()Lokhttp3/MediaType;",
            custom_type as dexvm::vm::NativeFn,
        ),
        ("writeTo", "(Lokio/BufferedSink;)V", write),
    ] {
        vm.register_native(NativeEntry {
            class: "LOwnedRequestBody;",
            name,
            sig,
            instance: true,
            f,
        })
        .unwrap();
    }
    vm.alloc_native("LOwnedRequestBody;", Native::Opaque)
        .unwrap()
}

#[test]
fn custom_request_body_dispatches_write_to_and_keeps_failures() {
    for legacy in [false, true] {
        let mut vm = vm();
        let seen = Rc::new(RefCell::new(Vec::new()));
        let captured = seen.clone();
        vm.http = Some(Rc::new(move |request| {
            captured.borrow_mut().push(request.clone());
            HttpResp::ok("")
        }));
        let body = custom(&mut vm, custom_write);
        send(&mut vm, Some(body), legacy, vec![]).unwrap();
        assert_eq!(
            seen.borrow().last().unwrap().body_bytes,
            Some(vec![0, 255, 128])
        );
        assert!(seen
            .borrow()
            .last()
            .unwrap()
            .headers
            .contains(&("Content-Type".into(), "application/owned".into())));
        for (fatal, write) in [
            (false, custom_throw as dexvm::vm::NativeFn),
            (true, custom_fatal),
        ] {
            let body = custom(&mut vm, write);
            let error = send(&mut vm, Some(body), legacy, vec![]).unwrap_err();
            if fatal {
                assert!(matches!(error, JvmError::BudgetExceeded));
            } else {
                assert!(matches!(error, JvmError::Uncaught(_)));
            }
            assert_eq!(seen.borrow().len(), 1);
        }
    }
}

#[test]
fn oversized_request_body_fails_before_the_callback() {
    for legacy in [false, true] {
        let mut vm = vm();
        vm.http = Some(Rc::new(|_| panic!("An oversized body must not be sent")));
        let body = vm
            .alloc_native(
                "Lokhttp3/RequestBody;",
                Native::RequestBody {
                    data: vec![0; 1_000_001],
                    content_type: None,
                },
            )
            .unwrap();
        assert!(send(&mut vm, Some(body), legacy, vec![]).is_err());
    }
}

#[test]
fn form_body_and_browser_wire_keep_text_compatibility() {
    for legacy in [false, true] {
        let mut vm = vm();
        vm.http = Some(Rc::new(|request| {
            assert_eq!(request.body.as_deref(), Some("owned=value&empty="));
            assert_eq!(
                request.body_bytes.as_deref(),
                Some(b"owned=value&empty=".as_slice())
            );
            assert!(request.headers.contains(&(
                "Content-Type".into(),
                "application/x-www-form-urlencoded".into()
            )));
            HttpResp::ok("")
        }));
        let body = vm
            .alloc_native(
                "Lokhttp3/FormBody;",
                Native::FormBody(vec![
                    ("owned".into(), "value".into()),
                    ("empty".into(), "".into()),
                ]),
            )
            .unwrap();
        send(&mut vm, Some(body), legacy, vec![]).unwrap();
    }
    let browser = HttpData {
        url: "ac-manga-browser://command".into(),
        method: "AC_BROWSER".into(),
        headers: vec![],
        body: Some("{}".into()),
        body_bytes: None,
    };
    let wire = http_wire::request_json(&browser);
    assert_eq!(wire["body"], "{}");
    assert!(wire["bodyBase64"].is_null());
}
