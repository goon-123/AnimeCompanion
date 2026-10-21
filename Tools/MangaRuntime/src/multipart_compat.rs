//! Bounded OkHttp multipart bodies. Parts remain guest RequestBody objects;
//! custom serializers execute only when the HTTP bridge writes the body.
use dexvm::vm::{error::JvmError, object::Native, NatErr, NativeEntry, Vm};
use dexvm::JValue;
type R = Result<JValue, NatErr>;
const BODY: &str = "Lokhttp3/MultipartBody;";
const BUILDER: &str = "Lokhttp3/MultipartBody$Builder;";
const PART: &str = "Lokhttp3/MultipartBody$Part;";
const LIMIT: usize = 1_000_000;
fn invalid(vm: &mut Vm, message: &str) -> NatErr {
    NatErr::Throw(vm.err_iae(message))
}
fn charge(vm: &mut Vm, size: usize) -> Result<(), NatErr> {
    if size > LIMIT || vm.budget <= size as i64 {
        return Err(NatErr::Fatal(JvmError::BudgetExceeded));
    }
    vm.budget -= size as i64;
    Ok(())
}

fn text(vm: &mut Vm, value: JValue) -> Result<String, NatErr> {
    let result = vm
        .str_of_jvalue(value)
        .ok_or_else(|| NatErr::Throw(vm.err_npe()))?;
    charge(vm, result.len())?;
    Ok(result)
}
fn invoke(vm: &mut Vm, receiver: JValue, name: &str, sig: &str, args: Vec<JValue>) -> R {
    charge(vm, 1)?;
    if receiver.is_null_ref() {
        return Err(NatErr::Throw(vm.err_npe()));
    }
    if vm.recursion_depth >= vm.depth_limit {
        return Err(NatErr::Fatal(JvmError::StackOverflow));
    }
    vm.recursion_depth += 1;
    let result = vm.invoke_virtual_args(receiver, name, sig, args);
    vm.recursion_depth -= 1;
    result.map_err(|e| match e {
        JvmError::Uncaught(o) => NatErr::Throw(o),
        e => NatErr::Fatal(e),
    })
}
fn fields(vm: &mut Vm, value: JValue) -> Result<Vec<JValue>, NatErr> {
    if value.is_null_ref() {
        return Err(NatErr::Throw(vm.err_npe()));
    }
    Ok(vm.arena.objects[value.as_obj() as usize].fields.clone())
}
fn init(vm: &mut Vm, args: &[JValue]) -> R {
    let boundary = if args.len() == 1 || (args.len() == 4 && args[2].as_int() & 1 != 0) {
        let mut random = [0_u8; 16];
        getrandom::fill(&mut random).map_err(|_| {
            NatErr::Throw(vm.throwable_of(
                "Ljava/lang/IllegalStateException;",
                "Multipart boundary unavailable",
            ))
        })?;
        random.iter().map(|b| format!("{b:02x}")).collect()
    } else {
        text(vm, args[1])?
    };
    // Keep delimiters bounded and ASCII so they cannot inject MIME headers.
    if boundary.is_empty()
        || boundary.len() > 200
        || !boundary
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b"'()+_,-./:=? ".contains(&b))
        || boundary.ends_with(' ')
    {
        return Err(invalid(vm, "Invalid multipart boundary"));
    }
    let boundary = vm.alloc_string(&boundary);
    let media = vm.alloc_string("multipart/mixed");
    let parts = vm
        .alloc_native("Ljava/util/ArrayList;", Native::List(vec![]))
        .map_err(NatErr::Fatal)?;
    vm.arena.objects[args[0].as_obj() as usize].native = Some(Native::Opaque);
    vm.arena.objects[args[0].as_obj() as usize].fields = vec![boundary, media, parts];
    Ok(JValue::Null)
}
fn set_type(vm: &mut Vm, args: &[JValue]) -> R {
    let media = text(vm, args[1])?;
    if !media.to_ascii_lowercase().starts_with("multipart/") || media.contains(['\r', '\n']) {
        return Err(invalid(vm, "Expected multipart media type"));
    }
    let value = vm.alloc_string(&media);
    vm.arena.objects[args[0].as_obj() as usize].fields[1] = value;
    Ok(args[0])
}
fn create_part(vm: &mut Vm, headers: JValue, body: JValue) -> R {
    if body.is_null_ref() {
        return Err(NatErr::Throw(vm.err_npe()));
    }
    if !headers.is_null_ref() {
        let Some(Native::Headers(values)) = vm.payload_of(headers) else {
            return Err(invalid(vm, "Expected part headers"));
        };
        for (name, value) in values {
            if name.eq_ignore_ascii_case("Content-Type")
                || name.eq_ignore_ascii_case("Content-Length")
            {
                return Err(invalid(vm, "Part content headers come from its body"));
            }
            if name.is_empty()
                || !name.bytes().all(|b| b > 32 && b < 127)
                || value.contains(['\r', '\n'])
            {
                return Err(invalid(vm, "Invalid part header"));
            }
            charge(vm, name.len() + value.len())?;
        }
    }
    let part = vm
        .alloc_native(PART, Native::Opaque)
        .map_err(NatErr::Fatal)?;
    vm.arena.objects[part.as_obj() as usize].fields = vec![headers, body];
    Ok(part)
}
fn quoted(value: &str) -> String {
    let mut result = String::from("\"");
    for c in value.chars() {
        match c {
            '\r' => result.push_str("%0D"),
            '\n' => result.push_str("%0A"),
            '"' => result.push_str("%22"),
            c => result.push(c),
        }
    }
    result.push('"');
    result
}
fn form_part(vm: &mut Vm, args: &[JValue]) -> R {
    let name = text(vm, args[0])?;
    let (filename, body) = if args.len() == 2 {
        let value = text(vm, args[1])?;
        let body = vm
            .alloc_native(
                "Lokhttp3/RequestBody;",
                Native::RequestBody {
                    data: value.into_bytes(),
                    content_type: None,
                },
            )
            .map_err(NatErr::Fatal)?;
        (None, body)
    } else {
        (
            if args[1].is_null_ref() {
                None
            } else {
                Some(text(vm, args[1])?)
            },
            args[2],
        )
    };
    let mut disposition = format!("form-data; name={}", quoted(&name));
    if let Some(filename) = filename {
        disposition.push_str(&format!("; filename={}", quoted(&filename)));
    }
    charge(vm, disposition.len())?;
    let headers = vm
        .alloc_native(
            "Lokhttp3/Headers;",
            Native::Headers(vec![("Content-Disposition".into(), disposition)]),
        )
        .map_err(NatErr::Fatal)?;
    create_part(vm, headers, body)
}
fn append_part(vm: &mut Vm, builder: JValue, part: JValue) -> R {
    let part_fields = fields(vm, part)?;
    if part_fields.len() != 2 {
        return Err(invalid(vm, "Expected multipart part"));
    }
    let state = fields(vm, builder)?;
    let Some(Native::List(parts)) = &mut vm.arena.objects[state[2].as_obj() as usize].native else {
        return Err(invalid(vm, "Invalid multipart builder"));
    };
    if parts.len() >= 1024 {
        return Err(NatErr::Fatal(JvmError::BudgetExceeded));
    }
    parts.push(part);
    Ok(builder)
}
fn add_form(vm: &mut Vm, args: &[JValue]) -> R {
    let part = form_part(vm, &args[1..])?;
    append_part(vm, args[0], part)
}
fn add_body(vm: &mut Vm, args: &[JValue]) -> R {
    let part = create_part(vm, JValue::Null, args[1])?;
    append_part(vm, args[0], part)
}
fn add_headers(vm: &mut Vm, args: &[JValue]) -> R {
    let part = create_part(vm, args[1], args[2])?;
    append_part(vm, args[0], part)
}
fn add_part(vm: &mut Vm, args: &[JValue]) -> R {
    append_part(vm, args[0], args[1])
}
fn parts(vm: &mut Vm, value: JValue) -> Result<Vec<JValue>, NatErr> {
    let state = fields(vm, value)?;
    if state.len() != 3 {
        return Err(invalid(vm, "Invalid multipart state"));
    }
    let Some(Native::List(parts)) = vm.payload_of(state[2]) else {
        return Err(invalid(vm, "Invalid multipart parts"));
    };
    Ok(parts)
}
fn build(vm: &mut Vm, args: &[JValue]) -> R {
    let parts = parts(vm, args[0])?;
    if parts.is_empty() {
        return Err(NatErr::Throw(vm.throwable_of(
            "Ljava/lang/IllegalStateException;",
            "Multipart body must have a part",
        )));
    }
    let list = vm
        .alloc_native("Ljava/util/ArrayList;", Native::List(parts))
        .map_err(NatErr::Fatal)?;
    let mut state = fields(vm, args[0])?;
    state[2] = list;
    let body = vm
        .alloc_native(BODY, Native::Opaque)
        .map_err(NatErr::Fatal)?;
    vm.arena.objects[body.as_obj() as usize].fields = state;
    Ok(body)
}
fn boundary(vm: &mut Vm, args: &[JValue]) -> R {
    Ok(fields(vm, args[0])?[0])
}
fn media_type(vm: &mut Vm, args: &[JValue]) -> R {
    let value = fields(vm, args[0])?[1];
    let value = text(vm, value)?;
    vm.alloc_native("Lokhttp3/MediaType;", Native::Str(value))
        .map_err(NatErr::Fatal)
}
fn content_type(vm: &mut Vm, args: &[JValue]) -> R {
    let state = fields(vm, args[0])?;
    let boundary = text(vm, state[0])?;
    let media = text(vm, state[1])?;
    let delimiter = if boundary
        .bytes()
        .all(|b| b.is_ascii_alphanumeric() || b"!#$%&'*+-.^_`|~".contains(&b))
    {
        boundary
    } else {
        quoted(&boundary)
    };
    vm.alloc_native(
        "Lokhttp3/MediaType;",
        Native::Str(format!("{media}; boundary={delimiter}")),
    )
    .map_err(NatErr::Fatal)
}
fn size(vm: &mut Vm, args: &[JValue]) -> R {
    Ok(JValue::Int(parts(vm, args[0])?.len() as i32))
}
fn part_at(vm: &mut Vm, args: &[JValue]) -> R {
    let parts = parts(vm, args[0])?;
    parts
        .get(args[1].as_int() as usize)
        .copied()
        .ok_or_else(|| {
            NatErr::Throw(vm.throwable_of(
                "Ljava/lang/IndexOutOfBoundsException;",
                "Part index outside body",
            ))
        })
}
fn body_parts(vm: &mut Vm, args: &[JValue]) -> R {
    let parts = parts(vm, args[0])?;
    vm.alloc_native("Ljava/util/ArrayList;", Native::List(parts))
        .map_err(NatErr::Fatal)
}
fn part_headers(vm: &mut Vm, args: &[JValue]) -> R {
    Ok(fields(vm, args[0])?[0])
}
fn part_body(vm: &mut Vm, args: &[JValue]) -> R {
    Ok(fields(vm, args[0])?[1])
}
fn request_length(vm: &mut Vm, args: &[JValue]) -> R {
    let size = match vm.payload_of(args[0]) {
        Some(Native::RequestBody { data, .. } | Native::RespBody(data)) => data.len() as i64,
        Some(Native::Str(value)) => value.len() as i64,
        Some(Native::FormBody(fields)) => fields
            .iter()
            .map(|(k, v)| k.len() + v.len() + 1)
            .sum::<usize>()
            .saturating_add(fields.len().saturating_sub(1))
            as i64,
        _ => -1,
    };
    Ok(JValue::Long(size))
}
fn form_type(vm: &mut Vm, _args: &[JValue]) -> R {
    vm.alloc_native(
        "Lokhttp3/MediaType;",
        Native::Str("application/x-www-form-urlencoded".into()),
    )
    .map_err(NatErr::Fatal)
}
fn form_write(vm: &mut Vm, args: &[JValue]) -> R {
    let Some(Native::FormBody(fields)) = vm.payload_of(args[0]) else {
        return Err(invalid(vm, "Expected form body"));
    };
    let mut output = Vec::new();
    for (i, (key, value)) in fields.iter().enumerate() {
        if i > 0 {
            extend(vm, &mut output, b"&")?;
        }
        extend(vm, &mut output, key.as_bytes())?;
        extend(vm, &mut output, b"=")?;
        extend(vm, &mut output, value.as_bytes())?;
    }
    sink_append(vm, args[1], output)
}
fn extend(vm: &mut Vm, out: &mut Vec<u8>, bytes: &[u8]) -> Result<(), NatErr> {
    if out.len().saturating_add(bytes.len()) > LIMIT {
        return Err(NatErr::Fatal(JvmError::BudgetExceeded));
    }
    charge(vm, bytes.len())?;
    out.extend_from_slice(bytes);
    Ok(())
}
fn header(vm: &mut Vm, out: &mut Vec<u8>, name: &str, value: &str) -> Result<(), NatErr> {
    if name.contains(['\r', '\n']) || value.contains(['\r', '\n']) {
        return Err(invalid(vm, "Invalid multipart header"));
    }
    extend(vm, out, name.as_bytes())?;
    extend(vm, out, b": ")?;
    extend(vm, out, value.as_bytes())?;
    extend(vm, out, b"\r\n")
}
fn encode(vm: &mut Vm, body: JValue, count_only: bool) -> Result<(Vec<u8>, i64), NatErr> {
    let boundary = boundary(vm, &[body])?;
    let boundary = text(vm, boundary)?;
    let mut output = Vec::new();
    let mut content = 0_i64;
    for part in parts(vm, body)? {
        let state = fields(vm, part)?;
        extend(vm, &mut output, format!("--{boundary}\r\n").as_bytes())?;
        if !state[0].is_null_ref() {
            let Some(Native::Headers(headers)) = vm.payload_of(state[0]) else {
                return Err(invalid(vm, "Invalid multipart headers"));
            };
            for (name, value) in headers {
                header(vm, &mut output, &name, &value)?;
            }
        }
        let media = invoke(vm, state[1], "contentType", "()Lokhttp3/MediaType;", vec![])?;
        if !media.is_null_ref() {
            let media = text(vm, media)?;
            header(vm, &mut output, "Content-Type", &media)?;
        }
        let length = invoke(vm, state[1], "contentLength", "()J", vec![])?.as_long();
        if length >= 0 {
            header(vm, &mut output, "Content-Length", &length.to_string())?;
        } else if count_only {
            return Ok((vec![], -1));
        }
        extend(vm, &mut output, b"\r\n")?;
        if count_only {
            content = content
                .checked_add(length)
                .ok_or(NatErr::Fatal(JvmError::BudgetExceeded))?;
        } else {
            let sink = vm
                .alloc_native(
                    "Lokio/Buffer;",
                    Native::OkioBuf {
                        bytes: vec![],
                        pos: 0,
                    },
                )
                .map_err(NatErr::Fatal)?;
            invoke(
                vm,
                state[1],
                "writeTo",
                "(Lokio/BufferedSink;)V",
                vec![sink],
            )?;
            let Some(Native::OkioBuf { bytes, .. }) = vm.payload_of(sink) else {
                return Err(invalid(vm, "Invalid part buffer"));
            };
            extend(vm, &mut output, &bytes)?;
        }
        extend(vm, &mut output, b"\r\n")?;
    }
    extend(vm, &mut output, format!("--{boundary}--\r\n").as_bytes())?;
    let length = content
        .checked_add(output.len() as i64)
        .ok_or(NatErr::Fatal(JvmError::BudgetExceeded))?;
    Ok((output, length))
}
fn content_length(vm: &mut Vm, args: &[JValue]) -> R {
    Ok(JValue::Long(encode(vm, args[0], true)?.1))
}
fn write_to(vm: &mut Vm, args: &[JValue]) -> R {
    let (bytes, _) = encode(vm, args[0], false)?;
    sink_append(vm, args[1], bytes)
}
fn sink_append(vm: &mut Vm, sink: JValue, bytes: Vec<u8>) -> R {
    if sink.is_null_ref() {
        return Err(NatErr::Throw(vm.err_npe()));
    }
    match &mut vm.arena.objects[sink.as_obj() as usize].native {
        Some(Native::OkioBuf { bytes: out, .. } | Native::OkioSink { bytes: out, .. })
            if out.len().saturating_add(bytes.len()) <= LIMIT =>
        {
            out.extend(bytes)
        }
        _ => return Err(invalid(vm, "Invalid or oversized multipart sink")),
    }
    Ok(JValue::Null)
}
fn part_create(vm: &mut Vm, args: &[JValue]) -> R {
    if args.len() == 1 {
        create_part(vm, JValue::Null, args[0])
    } else {
        create_part(vm, args[0], args[1])
    }
}
fn companion_create(vm: &mut Vm, args: &[JValue]) -> R {
    part_create(vm, &args[1..])
}
fn companion_form(vm: &mut Vm, args: &[JValue]) -> R {
    form_part(vm, &args[1..])
}
pub(super) fn static_value(
    vm: &mut Vm,
    class: &str,
    name: &str,
    ty: &str,
    value: JValue,
) -> Result<(), JvmError> {
    let owner = vm.ensure_class_by_desc(class)?;
    let key = (vm.intern(name), vm.intern(ty));
    let class = &mut vm.classes[owner as usize];
    if let Some((_, offset)) = class.static_fields.get(&key) {
        class.statics[*offset as usize] = value;
        class.statics_lazy[*offset as usize] = None;
    } else {
        let offset = class.statics.len() as u32;
        class.statics.push(value);
        class.statics_lazy.push(None);
        class.static_fields.insert(key, (owner, offset));
    }
    Ok(())
}
pub(super) fn install(vm: &mut Vm) -> Result<(), JvmError> {
    let class = vm.ensure_class_by_desc("Lokhttp3/RequestBody;")?;
    // Registering the first native supplies the concrete class. Its ancestry
    // is corrected below before any guest operation executes.
    for (owner,name,sig,f) in [
        (BUILDER,"<init>","()V",init as dexvm::vm::NativeFn),
        (BUILDER,"<init>","(Ljava/lang/String;)V",init),
        (BUILDER,"<init>","(Ljava/lang/String;ILkotlin/jvm/internal/DefaultConstructorMarker;)V",init),
        (BUILDER,"setType","(Lokhttp3/MediaType;)Lokhttp3/MultipartBody$Builder;",set_type),
        (BUILDER,"addFormDataPart","(Ljava/lang/String;Ljava/lang/String;)Lokhttp3/MultipartBody$Builder;",add_form),
        (BUILDER,"addFormDataPart","(Ljava/lang/String;Ljava/lang/String;Lokhttp3/RequestBody;)Lokhttp3/MultipartBody$Builder;",add_form),
        (BUILDER,"addPart","(Lokhttp3/RequestBody;)Lokhttp3/MultipartBody$Builder;",add_body),
        (BUILDER,"addPart","(Lokhttp3/Headers;Lokhttp3/RequestBody;)Lokhttp3/MultipartBody$Builder;",add_headers),
        (BUILDER,"addPart","(Lokhttp3/MultipartBody$Part;)Lokhttp3/MultipartBody$Builder;",add_part),
        (BUILDER,"build","()Lokhttp3/MultipartBody;",build),
        (BODY,"boundary","()Ljava/lang/String;",boundary),(BODY,"type","()Lokhttp3/MediaType;",media_type),
        (BODY,"size","()I",size),(BODY,"part","(I)Lokhttp3/MultipartBody$Part;",part_at),
        (BODY,"parts","()Ljava/util/List;",body_parts),(BODY,"contentType","()Lokhttp3/MediaType;",content_type),
        (BODY,"contentLength","()J",content_length),(BODY,"writeTo","(Lokio/BufferedSink;)V",write_to),
        (PART,"headers","()Lokhttp3/Headers;",part_headers),(PART,"body","()Lokhttp3/RequestBody;",part_body),
        ("Lokhttp3/RequestBody;","contentLength","()J",request_length),
        ("Lokhttp3/FormBody;","contentLength","()J",request_length),
        ("Lokhttp3/FormBody;","contentType","()Lokhttp3/MediaType;",form_type),
        ("Lokhttp3/FormBody;","writeTo","(Lokio/BufferedSink;)V",form_write),
    ]{vm.register_native(NativeEntry{class:owner,name,sig,instance:true,f})?;}
    let multipart = vm.ensure_class_by_desc(BODY)?;
    vm.classes[multipart as usize].superclass = Some(class);
    for (name, subtype) in [
        ("MIXED", "mixed"),
        ("ALTERNATIVE", "alternative"),
        ("DIGEST", "digest"),
        ("PARALLEL", "parallel"),
        ("FORM", "form-data"),
    ] {
        let value = vm.alloc_native(
            "Lokhttp3/MediaType;",
            Native::Str(format!("multipart/{subtype}")),
        )?;
        static_value(vm, BODY, name, "Lokhttp3/MediaType;", value)?;
    }
    for (name,sig,f,cf) in [
        ("create","(Lokhttp3/RequestBody;)Lokhttp3/MultipartBody$Part;",part_create as dexvm::vm::NativeFn,companion_create as dexvm::vm::NativeFn),
        ("create","(Lokhttp3/Headers;Lokhttp3/RequestBody;)Lokhttp3/MultipartBody$Part;",part_create,companion_create),
        ("createFormData","(Ljava/lang/String;Ljava/lang/String;)Lokhttp3/MultipartBody$Part;",form_part,companion_form),
        ("createFormData","(Ljava/lang/String;Ljava/lang/String;Lokhttp3/RequestBody;)Lokhttp3/MultipartBody$Part;",form_part,companion_form),
    ] {
        vm.register_native(NativeEntry{class:PART,name,sig,instance:false,f})?;
        vm.register_native(NativeEntry{class:"Lokhttp3/MultipartBody$Part$Companion;",name,sig,instance:true,f:cf})?;
    }
    let companion = vm.alloc_native("Lokhttp3/MultipartBody$Part$Companion;", Native::Opaque)?;
    static_value(
        vm,
        PART,
        "Companion",
        "Lokhttp3/MultipartBody$Part$Companion;",
        companion,
    )?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    fn vm() -> Vm {
        let mut vm = Vm::new(vec![], Box::new(std::io::sink())).unwrap();
        install(&mut vm).unwrap();
        vm
    }
    fn builder(vm: &mut Vm) -> JValue {
        let builder = vm.alloc_native(BUILDER, Native::Opaque).unwrap();
        let boundary = vm.alloc_string("owned-boundary");
        init(vm, &[builder, boundary]).unwrap();
        let media = vm
            .alloc_native(
                "Lokhttp3/MediaType;",
                Native::Str("multipart/form-data".into()),
            )
            .unwrap();
        set_type(vm, &[builder, media]).unwrap();
        builder
    }
    #[test]
    fn multipart_snapshots_escape_names_preserve_binary_and_cross_both_http_paths() {
        use std::{cell::RefCell, rc::Rc};
        let mut vm = vm();
        vm.perms.grant(dexvm::permission::Permission::Network(
            dexvm::permission::NetworkPermission::Any,
        ));
        let builder = builder(&mut vm);
        let name = vm.alloc_string("field\r\n\"");
        let filename = vm.alloc_string("café.bin");
        let binary = vm
            .alloc_native(
                "Lokhttp3/RequestBody;",
                Native::RequestBody {
                    data: vec![0, 255, 128],
                    content_type: Some("application/octet-stream".into()),
                },
            )
            .unwrap();
        add_form(&mut vm, &[builder, name, filename, binary]).unwrap();
        let body = build(&mut vm, &[builder]).unwrap();
        let another = vm.alloc_string("second");
        let value = vm.alloc_string("owned");
        add_form(&mut vm, &[builder, another, value]).unwrap();
        vm.gc(&[body.as_obj(), builder.as_obj()]);
        assert_eq!(size(&mut vm, &[body]).unwrap(), JValue::Int(1));
        let (bytes, _) = encode(&mut vm, body, false).unwrap();
        let mut expected="--owned-boundary\r\nContent-Disposition: form-data; name=\"field%0D%0A%22\"; filename=\"café.bin\"\r\nContent-Type: application/octet-stream\r\nContent-Length: 3\r\n\r\n".as_bytes().to_vec();
        expected.extend([0, 255, 128]);
        expected.extend(b"\r\n--owned-boundary--\r\n");
        assert_eq!(bytes, expected);
        assert_eq!(
            content_length(&mut vm, &[body]).unwrap(),
            JValue::Long(expected.len() as i64)
        );
        let seen = Rc::new(RefCell::new(vec![]));
        let captured = seen.clone();
        vm.http = Some(Rc::new(move |request| {
            captured.borrow_mut().push(request.clone());
            dexvm::keiyoushi::HttpResp::ok("")
        }));
        for legacy in [false, true] {
            let request = vm
                .alloc_native(
                    "Lokhttp3/Request;",
                    Native::Request {
                        url: "https://transport.example/owned".into(),
                        method: "POST".into(),
                        headers: vec![],
                        body: Some(body),
                    },
                )
                .unwrap();
            if legacy {
                vm.invoke_static(
                    "Leu/kanade/tachiyomi/network/RequestsKt;",
                    "__host_execute",
                    "(Lokhttp3/Request;)Lokhttp3/Response;",
                    vec![request],
                )
                .unwrap();
            } else {
                let call = vm
                    .alloc_native(
                        "Lokhttp3/Call;",
                        Native::Call {
                            request,
                            client: JValue::Null,
                            canceled: false,
                        },
                    )
                    .unwrap();
                vm.invoke_virtual(call, "execute", "()Lokhttp3/Response;")
                    .unwrap();
            }
        }
        assert_eq!(seen.borrow().len(), 2);
        for request in seen.borrow().iter() {
            assert_eq!(request.body_bytes.as_deref(), Some(expected.as_slice()));
            assert!(request.headers.contains(&(
                "Content-Type".into(),
                "multipart/form-data; boundary=owned-boundary".into()
            )));
        }
    }
    fn custom_write(vm: &mut Vm, args: &[JValue]) -> R {
        let n = vm.arena.objects[args[0].as_obj() as usize].fields[0].as_int();
        vm.arena.objects[args[0].as_obj() as usize].fields[0] = JValue::Int(n + 1);
        sink_append(vm, args[1], vec![0, 255, 128])
    }
    fn failed_write(vm: &mut Vm, _args: &[JValue]) -> R {
        Err(NatErr::Throw(
            vm.throwable_of("Ljava/io/IOException;", "Owned failure"),
        ))
    }
    #[test]
    fn custom_parts_write_lazily_retain_unknown_lengths_and_propagate_errors() {
        let mut vm = vm();
        let builder = builder(&mut vm);
        vm.register_native(NativeEntry {
            class: "LOwnedMultipartBody;",
            name: "writeTo",
            sig: "(Lokio/BufferedSink;)V",
            instance: true,
            f: custom_write,
        })
        .unwrap();
        let request = vm.ensure_class_by_desc("Lokhttp3/RequestBody;").unwrap();
        let child = vm.ensure_class_by_desc("LOwnedMultipartBody;").unwrap();
        vm.classes[child as usize].superclass = Some(request);
        let custom = vm
            .alloc_native("LOwnedMultipartBody;", Native::Opaque)
            .unwrap();
        vm.arena.objects[custom.as_obj() as usize].fields = vec![JValue::Int(0)];
        add_body(&mut vm, &[builder, custom]).unwrap();
        let body = build(&mut vm, &[builder]).unwrap();
        assert_eq!(content_length(&mut vm, &[body]).unwrap(), JValue::Long(-1));
        assert_eq!(
            vm.arena.objects[custom.as_obj() as usize].fields[0],
            JValue::Int(0)
        );
        let (bytes, _) = encode(&mut vm, body, false).unwrap();
        assert!(bytes.windows(3).any(|p| p == [0, 255, 128]));
        assert!(!String::from_utf8_lossy(&bytes).contains("Content-Length"));
        assert_eq!(
            vm.arena.objects[custom.as_obj() as usize].fields[0],
            JValue::Int(1)
        );
        vm.register_native(NativeEntry {
            class: "LOwnedMultipartBody;",
            name: "writeTo",
            sig: "(Lokio/BufferedSink;)V",
            instance: true,
            f: failed_write,
        })
        .unwrap();
        assert!(matches!(
            encode(&mut vm, body, false),
            Err(NatErr::Throw(_))
        ));
        assert_eq!(vm.recursion_depth, 0);
        vm.budget = 0;
        assert!(matches!(
            encode(&mut vm, body, false),
            Err(NatErr::Fatal(JvmError::BudgetExceeded))
        ));
    }
    #[test]
    fn multipart_rejects_invalid_parts_and_bounds_output_without_losing_form_bytes() {
        let mut vm = vm();
        let builder = builder(&mut vm);
        assert!(matches!(build(&mut vm, &[builder]), Err(NatErr::Throw(_))));
        assert!(matches!(
            add_body(&mut vm, &[builder, JValue::Null]),
            Err(NatErr::Throw(_))
        ));
        let bad = vm
            .alloc_native(
                "Lokhttp3/MediaType;",
                Native::Str("application/json".into()),
            )
            .unwrap();
        assert!(set_type(&mut vm, &[builder, bad]).is_err());
        let form = vm
            .alloc_native(
                "Lokhttp3/FormBody;",
                Native::FormBody(vec![("a".into(), "b%2Bc".into())]),
            )
            .unwrap();
        add_body(&mut vm, &[builder, form]).unwrap();
        let body = build(&mut vm, &[builder]).unwrap();
        let (bytes, _) = encode(&mut vm, body, false).unwrap();
        assert!(String::from_utf8_lossy(&bytes).contains(
            "Content-Type: application/x-www-form-urlencoded\r\nContent-Length: 7\r\n\r\na=b%2Bc"
        ));
        let headers = vm
            .alloc_native(
                "Lokhttp3/Headers;",
                Native::Headers(vec![("content-type".into(), "bad".into())]),
            )
            .unwrap();
        assert!(create_part(&mut vm, headers, form).is_err());
        assert!(matches!(
            write_to(&mut vm, &[body, JValue::Null]),
            Err(NatErr::Throw(_))
        ));
        let huge = vm
            .alloc_native(
                "Lokhttp3/RequestBody;",
                Native::RequestBody {
                    data: vec![0; LIMIT],
                    content_type: None,
                },
            )
            .unwrap();
        add_body(&mut vm, &[builder, huge]).unwrap();
        let body = build(&mut vm, &[builder]).unwrap();
        assert!(matches!(
            encode(&mut vm, body, false),
            Err(NatErr::Fatal(JvmError::BudgetExceeded))
        ));
    }
}
