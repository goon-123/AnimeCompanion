//! Android browser contracts backed by the host's private WebKit session.
//! Keep callbacks as guest objects: R8 may rename the extension's entire DSL.
use base64::{engine::general_purpose::STANDARD, Engine};
use dexvm::keiyoushi::HttpData;
use dexvm::vm::error::JvmError;
use dexvm::vm::object::Native;
use dexvm::vm::{NatErr, NativeEntry, Vm};
use dexvm::JValue;
use serde_json::{json, Value};
use std::time::{SystemTime, UNIX_EPOCH};

type R = Result<JValue, NatErr>;
const ROOT: &str = "Lcom/animecompanion/manga/BrowserState;";
const WEB: &str = "Landroid/webkit/WebView;";
const DEFERRED: &str = "Lkotlinx/coroutines/CompletableDeferred;";

fn err(vm: &mut Vm, message: &str) -> NatErr {
    NatErr::Throw(vm.throwable_of("Ljava/io/IOException;", message))
}
fn now() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as i64
}
fn noop(_: &mut Vm, _: &[JValue]) -> R {
    Ok(JValue::Null)
}
fn log_suppressed(_: &mut Vm, _: &[JValue]) -> R {
    Ok(JValue::Int(0))
}
fn duration_int(vm: &mut Vm, args: &[JValue]) -> R {
    duration(vm, i64::from(args[0].as_int()), args[1])
}
fn duration_long(vm: &mut Vm, args: &[JValue]) -> R {
    duration(vm, args[0].as_long(), args[1])
}
fn duration(vm: &mut Vm, value: i64, unit: JValue) -> R {
    let nanos: i128 = match vm.payload_of(unit) {
        Some(Native::Enum { name, .. }) => match name.as_str() {
            "NANOSECONDS" => 1,
            "MICROSECONDS" => 1_000,
            "MILLISECONDS" => 1_000_000,
            "SECONDS" => 1_000_000_000,
            "MINUTES" => 60_000_000_000,
            "HOURS" => 3_600_000_000_000,
            "DAYS" => 86_400_000_000_000,
            _ => return Err(err(vm, "Invalid duration unit")),
        },
        _ => return Err(err(vm, "Invalid duration unit")),
    };
    Ok(JValue::Long(
        (i128::from(value) * nanos / 1_000_000).clamp(i128::from(i64::MIN), i128::from(i64::MAX))
            as i64,
    ))
}
fn set_init(vm: &mut Vm, args: &[JValue]) -> R {
    vm.arena.objects[args[0].as_obj() as usize].native = Some(Native::Set(vec![]));
    Ok(JValue::Null)
}
fn field(vm: &Vm, object: JValue, index: usize) -> JValue {
    vm.arena.objects[object.as_obj() as usize]
        .fields
        .get(index)
        .copied()
        .unwrap_or(JValue::Null)
}
fn set(vm: &mut Vm, object: JValue, index: usize, value: JValue) {
    let fields = &mut vm.arena.objects[object.as_obj() as usize].fields;
    fields.resize(fields.len().max(index + 1), JValue::Null);
    fields[index] = value;
}
fn root(vm: &mut Vm) -> Result<JValue, NatErr> {
    let class = vm.ensure_class_by_desc(ROOT).map_err(NatErr::Fatal)?;
    Ok(vm.classes[class as usize].statics[0])
}
fn list(vm: &Vm, value: JValue) -> Vec<JValue> {
    match vm.payload_of(value) {
        Some(Native::List(v)) => v,
        _ => Vec::new(),
    }
}
fn append(vm: &mut Vm, collection: JValue, value: JValue) -> Result<(), NatErr> {
    let Some(Native::List(mut values)) = vm.payload_of(collection) else {
        return Err(err(vm, "Invalid browser queue"));
    };
    if values.len() >= 256 {
        return Err(err(vm, "Browser event limit exceeded"));
    }
    values.push(value);
    vm.arena.objects[collection.as_obj() as usize].native = Some(Native::List(values));
    Ok(())
}
fn text(vm: &Vm, value: JValue) -> String {
    vm.str_of_jvalue(value).unwrap_or_default()
}
fn invoke(vm: &mut Vm, receiver: JValue, name: &str, sig: &str, args: Vec<JValue>) -> R {
    vm.invoke_virtual_args(receiver, name, sig, args)
        .map_err(|error| match error {
            JvmError::Uncaught(object) => NatErr::Throw(object),
            other => NatErr::Fatal(other),
        })
}

/// Internal messages use the existing owned C callback, never a socket or URLSession URL.
fn host(vm: &mut Vm, input: Value) -> Result<Value, NatErr> {
    let Some(callback) = vm.http.clone() else {
        return Err(err(vm, "Browser host unavailable"));
    };
    let input = input.to_string();
    if input.len() > 1_000_000 {
        return Err(err(vm, "Browser command is too large"));
    }
    let response = callback(&HttpData {
        url: "ac-manga-browser://command".into(),
        method: "AC_BROWSER".into(),
        headers: vec![],
        body: Some(input),
        body_bytes: None,
    });
    let bytes = response.body.unwrap_or_default();
    if response.code != 200 || bytes.len() > 2_000_000 {
        return Err(err(vm, "Browser operation failed"));
    }
    let value: Value =
        serde_json::from_slice(&bytes).map_err(|_| err(vm, "Invalid browser response"))?;
    if value.get("error").is_some() {
        return Err(err(
            vm,
            "The source browser could not finish this operation",
        ));
    }
    Ok(value)
}

fn web_init(vm: &mut Vm, args: &[JValue]) -> R {
    let state = root(vm)?;
    let webs = field(vm, state, 0);
    let count = list(vm, webs).len();
    if count >= 8 {
        return Err(err(vm, "Too many source browser sessions"));
    }
    let bridges = vm
        .alloc_native("Ljava/util/HashMap;", Native::Map(vec![]))
        .map_err(NatErr::Fatal)?;
    let settings = vm
        .alloc_native("Landroid/webkit/WebSettings;", Native::Opaque)
        .map_err(NatErr::Fatal)?;
    set(vm, settings, 0, args[0]);
    for index in 1..=4 {
        set(vm, settings, index, JValue::Int(0));
    }
    vm.arena.objects[args[0].as_obj() as usize].fields = vec![
        JValue::Int(count as i32 + 1),
        JValue::Null,
        JValue::Null,
        bridges,
        settings,
        JValue::Int(0),
        JValue::Int(0),
    ];
    append(vm, webs, args[0])?;
    Ok(JValue::Null)
}
fn web_client(vm: &mut Vm, args: &[JValue]) -> R {
    set(vm, args[0], 1, args[1]);
    Ok(JValue::Null)
}
fn web_settings(vm: &mut Vm, args: &[JValue]) -> R {
    Ok(field(vm, args[0], 4))
}
fn user_agent_set(vm: &mut Vm, args: &[JValue]) -> R {
    let web = field(vm, args[0], 0);
    set(vm, web, 2, args[1]);
    Ok(JValue::Null)
}
fn multiple_windows(vm: &mut Vm, args: &[JValue]) -> R {
    set(vm, args[0], 1, args[1]);
    // WebKit's navigation delegate refuses new ad windows for this source.
    Ok(JValue::Null)
}
fn javascript_enabled(vm: &mut Vm, args: &[JValue]) -> R {
    set(vm, args[0], 2, args[1]);
    Ok(JValue::Null)
}
fn storage_enabled(vm: &mut Vm, args: &[JValue]) -> R {
    set(vm, args[0], 3, args[1]);
    Ok(JValue::Null)
}
fn images_blocked(vm: &mut Vm, args: &[JValue]) -> R {
    set(vm, args[0], 4, args[1]);
    Ok(JValue::Null)
}
fn resource_url(vm: &mut Vm, args: &[JValue]) -> R {
    Ok(field(vm, args[0], 0))
}
fn uri_string(vm: &mut Vm, args: &[JValue]) -> R {
    match vm.payload_of(args[0]) {
        Some(Native::URI(value)) => Ok(vm.alloc_string(&value)),
        _ => Err(err(vm, "Invalid Android URI")),
    }
}
fn resource_method(vm: &mut Vm, args: &[JValue]) -> R {
    Ok(field(vm, args[0], 1))
}
fn resource_headers(vm: &mut Vm, args: &[JValue]) -> R {
    Ok(field(vm, args[0], 2))
}
fn resource_main(vm: &mut Vm, args: &[JValue]) -> R {
    Ok(field(vm, args[0], 3))
}
fn resource_response(vm: &mut Vm, args: &[JValue]) -> R {
    let fields = if args.len() == 4 {
        vec![args[1], args[2], JValue::Int(200), JValue::Null, args[3]]
    } else {
        vec![args[1], args[2], args[3], args[5], args[6]]
    };
    vm.arena.objects[args[0].as_obj() as usize].fields = fields;
    Ok(JValue::Null)
}
fn resource_status(vm: &mut Vm, args: &[JValue]) -> R {
    Ok(field(vm, args[0], 2))
}
fn intercept(vm: &mut Vm, web: JValue, event: &Value) -> Result<(), NatErr> {
    let uri = vm
        .alloc_native(
            "Landroid/net/Uri;",
            Native::URI(event["url"].as_str().unwrap_or_default().into()),
        )
        .map_err(NatErr::Fatal)?;
    let method = vm.alloc_string(event["method"].as_str().unwrap_or("GET"));
    let mut pairs = vec![];
    for pair in event["headers"].as_array().into_iter().flatten() {
        if let (Some(k), Some(v)) = (pair[0].as_str(), pair[1].as_str()) {
            pairs.push((vm.alloc_string(k), vm.alloc_string(v)));
        }
    }
    let headers = vm
        .alloc_native("Ljava/util/HashMap;", Native::Map(pairs))
        .map_err(NatErr::Fatal)?;
    let request = vm
        .alloc_native("Landroid/webkit/WebResourceRequest;", Native::Opaque)
        .map_err(NatErr::Fatal)?;
    vm.arena.objects[request.as_obj() as usize].fields = vec![
        uri,
        method,
        headers,
        JValue::Int(i32::from(event["mainFrame"].as_bool().unwrap_or(false))),
    ];
    let client = field(vm, web, 1);
    let response = if client.is_null_ref() {
        JValue::Null
    } else {
        invoke(vm,client,"shouldInterceptRequest","(Landroid/webkit/WebView;Landroid/webkit/WebResourceRequest;)Landroid/webkit/WebResourceResponse;",vec![web,request])?
    };
    let mut output = json!({"op":"decision","id":field(vm,web,0).as_int(),"requestID":event["requestID"],"allow":response.is_null_ref()});
    if !response.is_null_ref() {
        let data = field(vm, response, 4);
        let bytes = match vm.payload_of(data) {
            Some(Native::ByteArrayInputStream { bytes, pos }) => {
                bytes.get(pos..).unwrap_or_default().to_vec()
            }
            Some(Native::OkioBuf { bytes, pos }) => bytes.get(pos..).unwrap_or_default().to_vec(),
            _ if data.is_null() => vec![],
            _ => return Err(err(vm, "Unsupported browser response stream")),
        };
        if bytes.len() > 1_000_000 {
            return Err(err(vm, "Browser response is too large"));
        }
        let headers = match vm.payload_of(field(vm, response, 3)) {
            Some(Native::Map(items)) => items
                .into_iter()
                .map(|(k, v)| (text(vm, k), text(vm, v)))
                .collect::<Vec<_>>(),
            _ => vec![],
        };
        output["response"] = json!({"mimeType":text(vm,field(vm,response,0)),"encoding":text(vm,field(vm,response,1)),"status":field(vm,response,2).as_int(),"headers":headers,"bodyBase64":STANDARD.encode(bytes)});
    }
    host(vm, output)?;
    Ok(())
}
fn user_agent_get(vm: &mut Vm, args: &[JValue]) -> R {
    let value = field(vm, field(vm, args[0], 0), 2);
    if value.is_null() {
        Ok(vm.alloc_string("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"))
    } else {
        Ok(value)
    }
}
fn web_bridge(vm: &mut Vm, args: &[JValue]) -> R {
    let bridges = field(vm, args[0], 3);
    invoke(
        vm,
        bridges,
        "put",
        "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;",
        vec![args[2], args[1]],
    )?;
    Ok(JValue::Null)
}
fn web_load(vm: &mut Vm, args: &[JValue]) -> R {
    load(vm, args, false)
}
fn web_data(vm: &mut Vm, args: &[JValue]) -> R {
    load(vm, args, true)
}
fn load(vm: &mut Vm, args: &[JValue], data: bool) -> R {
    let web = args[0];
    if !field(vm, web, 5).is_zero() {
        return Err(err(vm, "Browser has already been destroyed"));
    }
    let bridges = match vm.payload_of(field(vm, web, 3)) {
        Some(Native::Map(values)) => values
            .into_iter()
            .map(|(name, _)| text(vm, name))
            .collect::<Vec<_>>(),
        _ => vec![],
    };
    let headers = if !data && args.len() > 2 {
        match vm.payload_of(args[2]) {
            Some(Native::Map(values)) => values
                .into_iter()
                .map(|(k, v)| (text(vm, k), text(vm, v)))
                .collect::<Vec<_>>(),
            _ => vec![],
        }
    } else {
        vec![]
    };
    let settings = field(vm, web, 4);
    host(
        vm,
        json!({"op":"load", "id":field(vm,web,0).as_int(), "url":text(vm,args[1]), "html":if data {Some(text(vm,args[2]))} else {None}, "headers":headers, "userAgent":text(vm,field(vm,web,2)), "bridges":bridges,"javaScriptEnabled":!field(vm,settings,2).is_zero(),"domStorageEnabled":!field(vm,settings,3).is_zero(),"blockImages":!field(vm,settings,4).is_zero()}),
    )?;
    set(vm, web, 6, JValue::Int(1));
    Ok(JValue::Null)
}
fn web_eval(vm: &mut Vm, args: &[JValue]) -> R {
    let result = host(
        vm,
        json!({"op":"evaluate", "id":field(vm,args[0],0).as_int(), "script":text(vm,args[1])}),
    )?;
    if args.len() > 2 && !args[2].is_null() {
        let value = vm.alloc_string(result["value"].as_str().unwrap_or("null"));
        invoke(
            vm,
            args[2],
            "onReceiveValue",
            "(Ljava/lang/Object;)V",
            vec![value],
        )?;
    }
    Ok(JValue::Null)
}
fn web_destroy(vm: &mut Vm, args: &[JValue]) -> R {
    if field(vm, args[0], 5).is_zero() {
        set(vm, args[0], 5, JValue::Int(1));
        if !field(vm, args[0], 6).is_zero() {
            host(vm, json!({"op":"close","id":field(vm,args[0],0).as_int()}))?;
        }
    }
    Ok(JValue::Null)
}
fn web_stop(vm: &mut Vm, args: &[JValue]) -> R {
    if !field(vm, args[0], 6).is_zero() {
        host(vm, json!({"op":"stop","id":field(vm,args[0],0).as_int()}))?;
    }
    Ok(JValue::Null)
}

fn deferred_new(vm: &mut Vm, _: &[JValue]) -> R {
    let value = vm
        .alloc_native(
            DEFERRED,
            Native::Deferred {
                value: JValue::Null,
                error: JValue::Null,
            },
        )
        .map_err(NatErr::Fatal)?;
    set(vm, value, 0, JValue::Int(0));
    Ok(value)
}
fn deferred_completed(vm: &mut Vm, args: &[JValue]) -> R {
    Ok(field(vm, args[0], 0))
}
fn complete(vm: &mut Vm, args: &[JValue], failed: bool) -> R {
    if !field(vm, args[0], 0).is_zero() {
        return Ok(JValue::Int(0));
    }
    vm.arena.objects[args[0].as_obj() as usize].native = Some(Native::Deferred {
        value: if failed { JValue::Null } else { args[1] },
        error: if failed { args[1] } else { JValue::Null },
    });
    set(vm, args[0], 0, JValue::Int(1));
    Ok(JValue::Int(1))
}
fn deferred_complete(vm: &mut Vm, args: &[JValue]) -> R {
    complete(vm, args, false)
}
fn deferred_fail(vm: &mut Vm, args: &[JValue]) -> R {
    complete(vm, args, true)
}
fn with_timeout(vm: &mut Vm, args: &[JValue]) -> R {
    let state = root(vm)?;
    let previous = field(vm, state, 2);
    let raw = args[0].as_long();
    // The pinned Kotlin host represents Duration values as milliseconds.
    let millis = raw.clamp(0, 60_000);
    set(
        vm,
        state,
        2,
        JValue::Long(
            previous
                .as_long()
                .min(now().saturating_add(millis.clamp(0, 60_000))),
        ),
    );
    let result = invoke(
        vm,
        args[1],
        "invoke",
        "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;",
        vec![JValue::Null, args[2]],
    );
    set(vm, state, 2, previous);
    result
}
fn with_context(vm: &mut Vm, args: &[JValue]) -> R {
    let state = root(vm)?;
    let previous = field(vm, state, 3);
    let context = super::coroutine_compat::merged_current(vm, args[0])?;
    let main = if context.is_null() {
        false
    } else {
        super::coroutine_compat::contains_main(vm, context)?
    };
    let scope = super::coroutine_compat::scope(vm, context)?;
    super::coroutine_compat::ensure_active(vm, scope)?;
    let previous_context = super::coroutine_compat::enter(vm, context)?;
    set(vm, state, 3, JValue::Int(i32::from(main)));
    let result = invoke(
        vm,
        args[1],
        "invoke",
        "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;",
        vec![scope, args[2]],
    );
    super::coroutine_compat::restore(vm, previous_context)?;
    set(vm, state, 3, previous);
    result
}
fn main_looper(vm: &mut Vm, _: &[JValue]) -> R {
    let state = root(vm)?;
    Ok(field(vm, state, 4))
}
fn my_looper(vm: &mut Vm, _: &[JValue]) -> R {
    let state = root(vm)?;
    Ok(field(
        vm,
        state,
        if field(vm, state, 3).is_zero() { 5 } else { 4 },
    ))
}
fn post_delayed(vm: &mut Vm, args: &[JValue]) -> R {
    let state = root(vm)?;
    let record = vm
        .alloc_native(ROOT, Native::Opaque)
        .map_err(NatErr::Fatal)?;
    set(vm, record, 0, args[1]);
    set(
        vm,
        record,
        1,
        JValue::Long(
            now().saturating_add(
                args.get(2)
                    .copied()
                    .unwrap_or(JValue::Long(0))
                    .as_long()
                    .max(1),
            ),
        ),
    );
    append(vm, field(vm, state, 1), record)?;
    Ok(JValue::Int(1))
}
fn run_due(vm: &mut Vm) -> Result<(), NatErr> {
    let state = root(vm)?;
    let queue = field(vm, state, 1);
    let (due, rest): (Vec<_>, Vec<_>) = list(vm, queue)
        .into_iter()
        .partition(|v| field(vm, *v, 1).as_long() <= now());
    vm.arena.objects[queue.as_obj() as usize].native = Some(Native::List(rest));
    for record in due {
        invoke(vm, field(vm, record, 0), "run", "()V", vec![])?;
    }
    Ok(())
}
fn deferred_await(vm: &mut Vm, args: &[JValue]) -> R {
    let state = root(vm)?;
    // Ordinary inline async results have no pending-state field.
    for _ in 0..4096 {
        let pending = vm.arena.objects[args[0].as_obj() as usize]
            .fields
            .first()
            .copied()
            == Some(JValue::Int(0));
        if !pending {
            break;
        }
        if now() >= field(vm, state, 2).as_long() {
            return Err(NatErr::Throw(vm.throwable_of(
                "Lkotlinx/coroutines/TimeoutCancellationException;",
                "Browser timed out",
            )));
        }
        run_due(vm)?;
        let webs = list(vm, field(vm, state, 0));
        let active: Vec<_> = webs
            .into_iter()
            .filter(|w| field(vm, *w, 5).is_zero() && !field(vm, *w, 6).is_zero())
            .collect();
        if active.is_empty() && list(vm, field(vm, state, 1)).is_empty() {
            return Err(err(vm, "Deferred has no event source"));
        }
        for web in active {
            let event = host(vm, json!({"op":"next","id":field(vm,web,0).as_int()}))?;
            dispatch(vm, web, &event)?;
        }
    }
    if field(vm, args[0], 0) == JValue::Int(0) {
        return Err(err(vm, "Browser event limit exceeded"));
    }
    match vm.payload_of(args[0]) {
        Some(Native::Deferred { value, error }) if error.is_null() => Ok(value),
        Some(Native::Deferred { error, .. }) => Err(NatErr::Throw(error.as_obj())),
        _ => Err(err(vm, "Invalid deferred result")),
    }
}
fn dispatch(vm: &mut Vm, web: JValue, event: &Value) -> Result<(), NatErr> {
    let url = vm.alloc_string(event["url"].as_str().unwrap_or_default());
    let client = field(vm, web, 1);
    match event["type"].as_str().unwrap_or("idle") {
        "started" if !client.is_null() => {
            invoke(
                vm,
                client,
                "onPageStarted",
                "(Landroid/webkit/WebView;Ljava/lang/String;Landroid/graphics/Bitmap;)V",
                vec![web, url, JValue::Null],
            )?;
        }
        "finished" if !client.is_null() => {
            invoke(
                vm,
                client,
                "onPageFinished",
                "(Landroid/webkit/WebView;Ljava/lang/String;)V",
                vec![web, url],
            )?;
        }
        "message" => {
            let name = vm.alloc_string(event["name"].as_str().unwrap_or_default());
            let receiver = invoke(
                vm,
                field(vm, web, 3),
                "get",
                "(Ljava/lang/Object;)Ljava/lang/Object;",
                vec![name],
            )?;
            if !receiver.is_null() {
                let message = vm.alloc_string(event["message"].as_str().unwrap_or_default());
                let method = if event["method"].as_str() == Some("postMessage") {
                    "postMessage"
                } else {
                    "post"
                };
                invoke(vm, receiver, method, "(Ljava/lang/String;)V", vec![message])?;
            }
        }
        "request" => intercept(vm, web, event)?,
        "error" => return Err(err(vm, "Website navigation or JavaScript failed")),
        "idle" => {}
        _ => return Err(err(vm, "Unsupported browser event")),
    }
    Ok(())
}
fn metrics(vm: &mut Vm, _: &[JValue]) -> R {
    let cid = vm
        .ensure_class_by_desc("Landroid/util/DisplayMetrics;")
        .map_err(NatErr::Fatal)?;
    let id = vm.alloc_instance(cid).map_err(NatErr::Fatal)?;
    // Logical CSS viewport; WebKit supplies actual display dimensions in JS.
    vm.instance_field_set(id, "widthPixels", JValue::Int(390));
    vm.instance_field_set(id, "heightPixels", JValue::Int(844));
    vm.instance_field_set(id, "density", JValue::Float(1.0));
    Ok(JValue::Obj(id))
}

macro_rules! n {
    ($c:expr,$name:expr,$sig:expr,$instance:expr,$f:ident) => {
        NativeEntry {
            class: $c,
            name: $name,
            sig: $sig,
            instance: $instance,
            f: $f,
        }
    };
}
pub fn install(vm: &mut Vm) -> Result<(), JvmError> {
    for entry in [
        n!(ROOT,"unused","()V",false,noop),
        n!("Landroid/net/Uri;","toString","()Ljava/lang/String;",true,uri_string),
        n!("Landroid/os/Looper;","getMainLooper","()Landroid/os/Looper;",false,main_looper),
        n!("Landroid/os/Looper;","myLooper","()Landroid/os/Looper;",false,my_looper),
        n!("Lkotlinx/coroutines/BuildersKt;","withContext","(Lkotlin/coroutines/CoroutineContext;Lkotlin/jvm/functions/Function2;Lkotlin/coroutines/Continuation;)Ljava/lang/Object;",false,with_context),
        n!("Ljava/lang/Runnable;","run","()V",true,abstract_property),
        n!("Landroid/webkit/ValueCallback;","onReceiveValue","(Ljava/lang/Object;)V",true,abstract_property),
        n!("Landroid/webkit/WebResourceRequest;","getUrl","()Landroid/net/Uri;",true,resource_url),
        n!("Landroid/webkit/WebResourceRequest;","getMethod","()Ljava/lang/String;",true,resource_method),
        n!("Landroid/webkit/WebResourceRequest;","getRequestHeaders","()Ljava/util/Map;",true,resource_headers),
        n!("Landroid/webkit/WebResourceRequest;","isForMainFrame","()Z",true,resource_main),
        n!("Landroid/webkit/WebResourceResponse;","<init>","(Ljava/lang/String;Ljava/lang/String;Ljava/io/InputStream;)V",true,resource_response),
        n!("Landroid/webkit/WebResourceResponse;","<init>","(Ljava/lang/String;Ljava/lang/String;ILjava/lang/String;Ljava/util/Map;Ljava/io/InputStream;)V",true,resource_response),
        n!("Landroid/webkit/WebResourceResponse;","getStatusCode","()I",true,resource_status),
        n!("Lkotlin/time/DurationKt;","toDuration","(ILkotlin/time/DurationUnit;)J",false,duration_int),
        n!("Lkotlin/time/DurationKt;","toDuration","(JLkotlin/time/DurationUnit;)J",false,duration_long),
        n!("Lkotlinx/coroutines/TimeoutCancellationException;","unused","()V",false,noop),
        n!("Ljava/util/concurrent/CopyOnWriteArraySet;","<init>","()V",true,set_init),
        n!("Landroid/os/Build;","unused","()V",false,noop),
        n!("Lkotlin/properties/ReadWriteProperty;","getValue","(Ljava/lang/Object;Lkotlin/reflect/KProperty;)Ljava/lang/Object;",true,abstract_property),
        n!("Lkotlin/properties/ReadWriteProperty;","setValue","(Ljava/lang/Object;Lkotlin/reflect/KProperty;Ljava/lang/Object;)V",true,abstract_property),
        n!("Landroid/util/DisplayMetrics;","<init>","()V",true,noop),
        n!("Landroid/content/res/Resources;","getDisplayMetrics","()Landroid/util/DisplayMetrics;",true,metrics),
        n!(WEB,"<init>","(Landroid/content/Context;)V",true,web_init),
        n!(WEB,"setWebViewClient","(Landroid/webkit/WebViewClient;)V",true,web_client),
        n!(WEB,"getSettings","()Landroid/webkit/WebSettings;",true,web_settings),
        n!(WEB,"loadUrl","(Ljava/lang/String;)V",true,web_load),
        n!(WEB,"loadUrl","(Ljava/lang/String;Ljava/util/Map;)V",true,web_load),
        n!(WEB,"loadDataWithBaseURL","(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V",true,web_data),
        n!(WEB,"evaluateJavascript","(Ljava/lang/String;Landroid/webkit/ValueCallback;)V",true,web_eval),
        n!(WEB,"addJavascriptInterface","(Ljava/lang/Object;Ljava/lang/String;)V",true,web_bridge),
        n!(WEB,"destroy","()V",true,web_destroy),
        n!(WEB,"stopLoading","()V",true,web_stop),
        n!("Landroid/webkit/WebSettings;","setUserAgentString","(Ljava/lang/String;)V",true,user_agent_set),
        n!("Landroid/webkit/WebSettings;","setSupportMultipleWindows","(Z)V",true,multiple_windows),
        n!("Landroid/webkit/WebSettings;","setJavaScriptEnabled","(Z)V",true,javascript_enabled),
        n!("Landroid/webkit/WebSettings;","setDomStorageEnabled","(Z)V",true,storage_enabled),
        n!("Landroid/webkit/WebSettings;","setBlockNetworkImage","(Z)V",true,images_blocked),
        n!("Landroid/webkit/WebSettings;","getUserAgentString","()Ljava/lang/String;",true,user_agent_get),
        n!("Landroid/os/Handler;","post","(Ljava/lang/Runnable;)Z",true,post_delayed),
        n!("Landroid/os/Handler;","postDelayed","(Ljava/lang/Runnable;J)Z",true,post_delayed),
        n!("Lkotlinx/coroutines/CompletableDeferredKt;","CompletableDeferred$default","(Lkotlinx/coroutines/Job;ILjava/lang/Object;)Lkotlinx/coroutines/CompletableDeferred;",false,deferred_new),
        n!(DEFERRED,"complete","(Ljava/lang/Object;)Z",true,deferred_complete),
        n!(DEFERRED,"completeExceptionally","(Ljava/lang/Throwable;)Z",true,deferred_fail),
        n!(DEFERRED,"isCompleted","()Z",true,deferred_completed),
        n!(DEFERRED,"await","(Lkotlin/coroutines/Continuation;)Ljava/lang/Object;",true,deferred_await),
        n!("Lkotlinx/coroutines/Deferred;","await","(Lkotlin/coroutines/Continuation;)Ljava/lang/Object;",true,deferred_await),
        n!("Lkotlinx/coroutines/TimeoutKt;","withTimeout-KLykuaI","(JLkotlin/jvm/functions/Function2;Lkotlin/coroutines/Continuation;)Ljava/lang/Object;",false,with_timeout),
    ] { vm.register_native(entry)?; }
    for name in ["v", "d", "i", "w", "e"] {
        vm.register_native(NativeEntry {
            class: "Landroid/util/Log;",
            name,
            sig: "(Ljava/lang/String;Ljava/lang/String;)I",
            instance: false,
            f: log_suppressed,
        })?;
        vm.register_native(NativeEntry {
            class: "Landroid/util/Log;",
            name,
            sig: "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/Throwable;)I",
            instance: false,
            f: log_suppressed,
        })?;
    }
    let view = vm.ensure_class_by_desc("Landroid/view/ViewGroup;")?;
    let web = vm.ensure_class_by_desc(WEB)?;
    vm.classes[web as usize].superclass = Some(view);
    let set = vm.ensure_class_by_desc("Ljava/util/concurrent/CopyOnWriteArraySet;")?;
    let parent = vm.ensure_class_by_desc("Ljava/util/HashSet;")?;
    vm.classes[set as usize].superclass = Some(parent);
    let continuation = vm.ensure_class_by_desc("Lkotlin/coroutines/Continuation;")?;
    let suspend = vm.ensure_class_by_desc("Lkotlin/coroutines/jvm/internal/SuspendLambda;")?;
    vm.classes[suspend as usize].interfaces.push(continuation);
    let timeout = vm.ensure_class_by_desc("Lkotlinx/coroutines/TimeoutCancellationException;")?;
    vm.classes[timeout as usize].superclass =
        Some(vm.ensure_class_by_desc("Ljava/lang/Exception;")?);
    for (ordinal, name) in [
        "NANOSECONDS",
        "MICROSECONDS",
        "MILLISECONDS",
        "SECONDS",
        "MINUTES",
        "HOURS",
        "DAYS",
    ]
    .into_iter()
    .enumerate()
    {
        let value = vm.alloc_native(
            "Lkotlin/time/DurationUnit;",
            Native::Enum {
                name: name.into(),
                ordinal: ordinal as i32,
            },
        )?;
        let field = dexvm::vm::FieldRef {
            class_desc: vm.intern("Lkotlin/time/DurationUnit;"),
            name: vm.intern(name),
            ty: vm.intern("Lkotlin/time/DurationUnit;"),
        };
        vm.static_field_put(field, value)?;
    }
    let build = vm.ensure_class_by_desc("Landroid/os/Build;")?;
    for (name, value) in [
        ("MANUFACTURER", "Apple"),
        ("MODEL", "iPhone"),
        ("ID", "AnimeCompanion"),
    ] {
        let value = vm.alloc_string(value);
        let key = (vm.intern(name), vm.intern("Ljava/lang/String;"));
        let class = &mut vm.classes[build as usize];
        let offset = class.statics.len() as u32;
        class.static_fields.insert(key, (build, offset));
        class.statics.push(value);
        class.statics_lazy.push(None);
    }
    let metrics = vm.ensure_class_by_desc("Landroid/util/DisplayMetrics;")?;
    for (name, ty) in [
        ("widthPixels", "I"),
        ("heightPixels", "I"),
        ("density", "F"),
    ] {
        let name = vm.intern(name);
        let ty = vm.intern(ty);
        let class = &mut vm.classes[metrics as usize];
        let offset = class.instance_fields.len() as u32;
        class.instance_fields.push((name, ty, 1));
        class.field_offsets.insert((name, ty), offset);
    }
    let webs = vm.alloc_native("Ljava/util/ArrayList;", Native::List(vec![]))?;
    let queue = vm.alloc_native("Ljava/util/ArrayList;", Native::List(vec![]))?;
    let main = vm.alloc_native("Landroid/os/Looper;", Native::Opaque)?;
    let worker = vm.alloc_native("Landroid/os/Looper;", Native::Opaque)?;
    let state = vm.alloc_native(ROOT, Native::Opaque)?;
    vm.arena.objects[state.as_obj() as usize].fields = vec![
        webs,
        queue,
        JValue::Long(now() + 60_000),
        JValue::Int(0),
        main,
        worker,
    ];
    let cid = vm.ensure_class_by_desc(ROOT)?;
    vm.classes[cid as usize].statics.push(state);
    vm.classes[cid as usize].statics_lazy.push(None);
    Ok(())
}
fn abstract_property(vm: &mut Vm, _: &[JValue]) -> R {
    Err(err(vm, "Abstract delegated property"))
}

#[cfg(test)]
mod tests {
    use super::*;
    fn vm() -> Vm {
        let mut vm = Vm::new(vec![], Box::new(std::io::sink())).unwrap();
        install(&mut vm).unwrap();
        super::super::coroutine_compat::install(&mut vm).unwrap();
        vm
    }
    fn throws(vm: &mut Vm, _: &[JValue]) -> R {
        Err(err(vm, "Owned callback failure"))
    }
    fn exceeds_budget(_: &mut Vm, _: &[JValue]) -> R {
        Err(NatErr::Fatal(JvmError::BudgetExceeded))
    }
    #[test]
    fn callbacks_keep_throwable_failures_catchable_and_vm_limits_fatal() {
        for (f, throwable) in [
            (throws as dexvm::vm::NativeFn, true),
            (exceeds_budget as dexvm::vm::NativeFn, false),
        ] {
            let mut vm = vm();
            vm.register_native(NativeEntry {
                class: "Lcom/example/Callback;",
                name: "invoke",
                sig: "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;",
                instance: true,
                f,
            })
            .unwrap();
            let callback = vm
                .alloc_native("Lcom/example/Callback;", Native::Opaque)
                .unwrap();
            let context = vm
                .alloc_native(
                    "Lkotlinx/coroutines/MainCoroutineDispatcher;",
                    Native::Opaque,
                )
                .unwrap();
            let result = with_context(&mut vm, &[context, callback, JValue::Null]);
            if throwable {
                assert!(matches!(result, Err(NatErr::Throw(_))));
            } else {
                assert!(matches!(
                    result,
                    Err(NatErr::Fatal(JvmError::BudgetExceeded))
                ));
            }
            assert_ne!(
                main_looper(&mut vm, &[]).unwrap(),
                my_looper(&mut vm, &[]).unwrap()
            );
        }
    }
    #[test]
    fn completed_null_is_distinct_from_a_pending_deferred_and_first_result_wins() {
        let mut vm = vm();
        let deferred = deferred_new(&mut vm, &[]).unwrap();
        assert_eq!(
            deferred_completed(&mut vm, &[deferred]).unwrap(),
            JValue::Int(0)
        );
        assert_eq!(
            deferred_complete(&mut vm, &[deferred, JValue::Null]).unwrap(),
            JValue::Int(1)
        );
        let failure = vm.alloc_string("late failure");
        assert_eq!(
            deferred_fail(&mut vm, &[deferred, failure]).unwrap(),
            JValue::Int(0)
        );
        assert_eq!(
            deferred_await(&mut vm, &[deferred, JValue::Null]).unwrap(),
            JValue::Null
        );
    }
    #[test]
    fn duration_units_do_not_turn_millisecond_polls_into_seconds() {
        let mut vm = vm();
        for (name, expected) in [
            ("MILLISECONDS", 500),
            ("SECONDS", 500_000),
            ("MINUTES", 30_000_000),
        ] {
            let field = dexvm::vm::FieldRef {
                class_desc: vm.intern("Lkotlin/time/DurationUnit;"),
                name: vm.intern(name),
                ty: vm.intern("Lkotlin/time/DurationUnit;"),
            };
            let unit = vm.static_field_get(field).unwrap();
            assert_eq!(
                duration_int(&mut vm, &[JValue::Int(500), unit]).unwrap(),
                JValue::Long(expected)
            );
        }
    }
}
