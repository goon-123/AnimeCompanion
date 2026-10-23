//! OkHttp query components are data, not preassembled URL delimiters. A bare
//! builder retains empty scheme/authority components until they are supplied.
use dexvm::vm::error::JvmError;
use dexvm::vm::object::Native;
use dexvm::vm::{NatErr, NativeEntry, Vm};
use dexvm::JValue;
type R = Result<JValue, NatErr>;
fn url_equals(vm: &mut Vm, args: &[JValue]) -> R {
    let equal = matches!((vm.payload_of(args[0]),vm.payload_of(args[1])),
        (Some(Native::HttpUrl(a)),Some(Native::HttpUrl(b))) if a==b);
    Ok(JValue::Int(i32::from(equal)))
}
fn url_hash(vm: &mut Vm, args: &[JValue]) -> R {
    let Some(Native::HttpUrl(url)) = vm.payload_of(args[0]) else {
        return Err(NatErr::Throw(vm.err_npe()));
    };
    Ok(JValue::Int(url.encode_utf16().fold(0i32, |h, c| {
        h.wrapping_mul(31).wrapping_add(i32::from(c))
    })))
}

fn builder_init(vm: &mut Vm, args: &[JValue]) -> R {
    // The core mutators operate on serialized components. Both required
    // components are empty here; build must never expose this as an HttpUrl.
    vm.arena.objects[args[0].as_obj() as usize].native = Some(Native::HttpUrl(":///".into()));
    Ok(JValue::Null)
}
fn builder_build(vm: &mut Vm, args: &[JValue]) -> R {
    let Some(Native::HttpUrl(url)) = vm.payload_of(args[0]) else {
        return Err(NatErr::Throw(vm.err_npe()));
    };
    let Some((scheme, rest)) = url.split_once("://") else {
        return Err(NatErr::Throw(vm.throwable_of(
            "Ljava/lang/IllegalStateException;",
            "scheme == null",
        )));
    };
    let authority = rest.split(['/', '?', '#']).next().unwrap_or_default();
    if !matches!(scheme, "http" | "https") || authority.is_empty() || authority.starts_with(':') {
        return Err(NatErr::Throw(vm.throwable_of(
            "Ljava/lang/IllegalStateException;",
            "Missing URL scheme or host",
        )));
    }
    vm.alloc_native("Lokhttp3/HttpUrl;", Native::HttpUrl(url))
        .map_err(NatErr::Fatal)
}
fn builder_string(vm: &mut Vm, args: &[JValue]) -> R {
    let Some(Native::HttpUrl(url)) = vm.payload_of(args[0]) else {
        return Err(NatErr::Throw(vm.err_npe()));
    };
    Ok(vm.alloc_string(url.strip_prefix(':').unwrap_or(&url)))
}

fn invalid(vm: &mut Vm) -> NatErr {
    NatErr::Throw(vm.throwable_of("Ljava/lang/IllegalArgumentException;", "Invalid URL query"))
}
fn encode(text: &str, encoded: bool) -> String {
    use std::fmt::Write;
    let mut result = String::new();
    for b in text.bytes() {
        if b.is_ascii_alphanumeric()
            || b"-._~".contains(&b)
            || (encoded && b"%+[]!$(),/:;?@".contains(&b))
        {
            result.push(char::from(b));
        } else {
            write!(result, "%{b:02X}").expect("String writes cannot fail");
        }
    }
    result
}
pub(super) fn decode(text: &str) -> String {
    let mut result = Vec::new();
    let bytes = text.as_bytes();
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'%' && i + 2 < bytes.len() {
            if let (Some(a), Some(b)) = (
                (bytes[i + 1] as char).to_digit(16),
                (bytes[i + 2] as char).to_digit(16),
            ) {
                result.push((a * 16 + b) as u8);
                i += 3;
                continue;
            }
        }
        result.push(if bytes[i] == b'+' { b' ' } else { bytes[i] });
        i += 1;
    }
    String::from_utf8_lossy(&result).into_owned()
}
fn query(url: &str) -> impl Iterator<Item = (&str, Option<&str>)> {
    url.split('#')
        .next()
        .unwrap_or("")
        .split_once('?')
        .map(|(_, q)| q)
        .into_iter()
        .flat_map(|q| q.split('&'))
        .map(|q| {
            q.split_once('=')
                .map(|(k, v)| (k, Some(v)))
                .unwrap_or((q, None))
        })
}
fn change(vm: &mut Vm, args: &[JValue], encoded: bool, replace: bool, remove: bool) -> R {
    let name = vm.str_of_jvalue(args[1]).ok_or_else(|| invalid(vm))?;
    let value = if remove || args[2].is_null_ref() {
        None
    } else {
        Some(vm.str_of_jvalue(args[2]).ok_or_else(|| invalid(vm))?)
    };
    let Some(Native::HttpUrl(old)) = vm.payload_of(args[0]) else {
        return Err(invalid(vm));
    };
    let (without_fragment, fragment) = old
        .split_once('#')
        .map(|(a, b)| (a, Some(b)))
        .unwrap_or((&old, None));
    let base = without_fragment.split('?').next().unwrap_or("");
    let matching = if encoded { decode(&name) } else { name.clone() };
    let mut pairs: Vec<String> = query(&old)
        .filter(|(k, _)| !replace || decode(k) != matching)
        .map(|(k, v)| v.map(|v| format!("{k}={v}")).unwrap_or(k.into()))
        .collect();
    if !remove {
        let key = encode(&name, encoded);
        pairs.push(
            value
                .map(|v| format!("{key}={}", encode(&v, encoded)))
                .unwrap_or(key),
        );
    }
    let mut url = base.to_owned();
    if !pairs.is_empty() {
        url.push('?');
        url.push_str(&pairs.join("&"));
    }
    if let Some(fragment) = fragment {
        url.push('#');
        url.push_str(fragment);
    }
    vm.arena.objects[args[0].as_obj() as usize].native = Some(Native::HttpUrl(url));
    Ok(args[0])
}
fn add(vm: &mut Vm, args: &[JValue]) -> R {
    change(vm, args, false, false, false)
}
fn add_encoded(vm: &mut Vm, args: &[JValue]) -> R {
    change(vm, args, true, false, false)
}
fn set(vm: &mut Vm, args: &[JValue]) -> R {
    change(vm, args, false, true, false)
}
fn set_encoded(vm: &mut Vm, args: &[JValue]) -> R {
    change(vm, args, true, true, false)
}
fn remove(vm: &mut Vm, args: &[JValue]) -> R {
    change(vm, &[args[0], args[1], JValue::Null], false, true, true)
}
fn remove_encoded(vm: &mut Vm, args: &[JValue]) -> R {
    change(vm, &[args[0], args[1], JValue::Null], true, true, true)
}
fn values(vm: &mut Vm, args: &[JValue]) -> Result<Vec<Option<String>>, NatErr> {
    let name = vm.str_of_jvalue(args[1]).ok_or_else(|| invalid(vm))?;
    let Some(Native::HttpUrl(url)) = vm.payload_of(args[0]) else {
        return Err(invalid(vm));
    };
    Ok(query(&url)
        .filter(|(k, _)| decode(k) == name)
        .map(|(_, v)| v.map(decode))
        .collect())
}
fn first(vm: &mut Vm, args: &[JValue]) -> R {
    Ok(values(vm, args)?
        .into_iter()
        .next()
        .flatten()
        .map(|v| vm.alloc_string(&v))
        .unwrap_or(JValue::Null))
}
fn all(vm: &mut Vm, args: &[JValue]) -> R {
    let values = values(vm, args)?
        .into_iter()
        .map(|v| v.map(|v| vm.alloc_string(&v)).unwrap_or(JValue::Null))
        .collect();
    vm.alloc_native("Ljava/util/ArrayList;", Native::List(values))
        .map_err(NatErr::Fatal)
}
fn names(vm: &mut Vm, args: &[JValue]) -> R {
    let Some(Native::HttpUrl(url)) = vm.payload_of(args[0]) else {
        return Err(invalid(vm));
    };
    let mut names = Vec::<String>::new();
    for (name, _) in query(&url) {
        let name = decode(name);
        if !names.contains(&name) {
            names.push(name);
        }
    }
    let names = names.into_iter().map(|n| vm.alloc_string(&n)).collect();
    vm.alloc_native("Ljava/util/LinkedHashSet;", Native::Set(names))
        .map_err(NatErr::Fatal)
}
pub fn install(vm: &mut Vm) -> Result<(), JvmError> {
    for (name, sig, f) in [
        (
            "equals",
            "(Ljava/lang/Object;)Z",
            url_equals as dexvm::vm::NativeFn,
        ),
        ("hashCode", "()I", url_hash),
    ] {
        vm.register_native(NativeEntry {
            class: "Lokhttp3/HttpUrl;",
            name,
            sig,
            instance: true,
            f,
        })?;
    }
    for (name, sig, f) in [
        ("<init>", "()V", builder_init as dexvm::vm::NativeFn),
        ("build", "()Lokhttp3/HttpUrl;", builder_build),
        ("toString", "()Ljava/lang/String;", builder_string),
    ] {
        vm.register_native(NativeEntry {
            class: "Lokhttp3/HttpUrl$Builder;",
            name,
            sig,
            instance: true,
            f,
        })?;
    }
    for (name, f) in [
        ("addQueryParameter", add as dexvm::vm::NativeFn),
        ("addEncodedQueryParameter", add_encoded),
        ("setQueryParameter", set),
        ("setEncodedQueryParameter", set_encoded),
    ] {
        vm.register_native(NativeEntry {
            class: "Lokhttp3/HttpUrl$Builder;",
            name,
            sig: "(Ljava/lang/String;Ljava/lang/String;)Lokhttp3/HttpUrl$Builder;",
            instance: true,
            f,
        })?;
    }
    for (name, f) in [
        ("removeAllQueryParameters", remove as dexvm::vm::NativeFn),
        ("removeAllEncodedQueryParameters", remove_encoded),
    ] {
        vm.register_native(NativeEntry {
            class: "Lokhttp3/HttpUrl$Builder;",
            name,
            sig: "(Ljava/lang/String;)Lokhttp3/HttpUrl$Builder;",
            instance: true,
            f,
        })?;
    }
    for (name, sig, f) in [
        (
            "queryParameter",
            "(Ljava/lang/String;)Ljava/lang/String;",
            first as dexvm::vm::NativeFn,
        ),
        (
            "queryParameterValues",
            "(Ljava/lang/String;)Ljava/util/List;",
            all,
        ),
        ("queryParameterNames", "()Ljava/util/Set;", names),
    ] {
        vm.register_native(NativeEntry {
            class: "Lokhttp3/HttpUrl;",
            name,
            sig,
            instance: true,
            f,
        })?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn fresh_builders_require_both_components_and_build_immutable_urls() {
        let mut vm = Vm::new(vec![], Box::new(std::io::sink())).unwrap();
        install(&mut vm).unwrap();
        for host_first in [false, true] {
            let class = vm
                .ensure_class_by_desc("Lokhttp3/HttpUrl$Builder;")
                .unwrap();
            let builder = JValue::Obj(vm.alloc_instance(class).unwrap());
            vm.invoke_virtual(builder, "<init>", "()V").unwrap();
            assert!(matches!(
                builder_build(&mut vm, &[builder]),
                Err(NatErr::Throw(_))
            ));
            let scheme = vm.alloc_string("https");
            let host = vm.alloc_string("owned.example");
            let steps = if host_first {
                [("host", host), ("scheme", scheme)]
            } else {
                [("scheme", scheme), ("host", host)]
            };
            for (i, (name, arg)) in steps.into_iter().enumerate() {
                vm.invoke_virtual_args(
                    builder,
                    name,
                    "(Ljava/lang/String;)Lokhttp3/HttpUrl$Builder;",
                    vec![arg],
                )
                .unwrap();
                if i == 0 {
                    assert!(matches!(
                        builder_build(&mut vm, &[builder]),
                        Err(NatErr::Throw(_))
                    ));
                }
            }
            let snapshot = builder_build(&mut vm, &[builder]).unwrap();
            let key = vm.alloc_string("q");
            let value = vm.alloc_string("a&b");
            add(&mut vm, &[builder, key, value]).unwrap();
            assert!(
                matches!(vm.payload_of(snapshot), Some(Native::HttpUrl(url)) if url == "https://owned.example/")
            );
            let built = builder_build(&mut vm, &[builder]).unwrap();
            assert!(
                matches!(vm.payload_of(built), Some(Native::HttpUrl(url)) if url == "https://owned.example/?q=a%26b")
            );
        }
    }
    #[test]
    fn queries_round_trip_reserved_unicode_nullable_and_repeated_values() {
        let mut vm = Vm::new(vec![], Box::new(std::io::sink())).unwrap();
        install(&mut vm).unwrap();
        let builder = vm
            .alloc_native(
                "Lokhttp3/HttpUrl$Builder;",
                Native::HttpUrl("https://owned.example/path#kept".into()),
            )
            .unwrap();
        let name = vm.alloc_string("filter[]");
        let value = vm.alloc_string("a&b=+ #日本");
        add(&mut vm, &[builder, name, value]).unwrap();
        let result = first(&mut vm, &[builder, name]).unwrap();
        assert_eq!(vm.str_of_jvalue(result), Some("a&b=+ #日本".into()));
        add(&mut vm, &[builder, name, JValue::Null]).unwrap();
        assert_eq!(
            values(&mut vm, &[builder, name]).unwrap(),
            vec![Some("a&b=+ #日本".into()), None]
        );
        set(&mut vm, &[builder, name, value]).unwrap();
        assert_eq!(values(&mut vm, &[builder, name]).unwrap().len(), 1);
        let raw = vm.alloc_string("already%20encoded%26");
        let key = vm.alloc_string("q");
        add_encoded(&mut vm, &[builder, key, raw]).unwrap();
        assert_eq!(
            values(&mut vm, &[builder, key]).unwrap(),
            vec![Some("already encoded&".into())]
        );
        remove(&mut vm, &[builder, name]).unwrap();
        assert!(values(&mut vm, &[builder, name]).unwrap().is_empty());
        assert!(
            matches!(vm.payload_of(builder),Some(Native::HttpUrl(s)) if s.ends_with("#kept") && !s.contains("filter"))
        );
    }
}
