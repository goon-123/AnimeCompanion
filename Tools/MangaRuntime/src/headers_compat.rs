//! OkHttp's rooted Headers companion and bounded immutable factories.
use dexvm::vm::{
    error::JvmError,
    object::{ArrayData, Native},
    NatErr, NativeEntry, Vm,
};
use dexvm::JValue;
type R = Result<JValue, NatErr>;
static ORIGINAL_PROPERTIES: std::sync::OnceLock<[dexvm::vm::NativeFn; 2]> =
    std::sync::OnceLock::new();
fn property(vm: &mut Vm, args: &[JValue]) -> R {
    if vm.str_of_jvalue(args[0]).as_deref() == Some("http.agent") {
        if vm.budget <= 0 {
            return Err(NatErr::Fatal(JvmError::BudgetExceeded));
        }
        vm.budget -= 1;
        let field = dexvm::vm::FieldRef {
            class_desc: vm.intern("Ljava/lang/System;"),
            name: vm.intern("$acHttpAgent"),
            ty: vm.intern("Ljava/lang/String;"),
        };
        return vm.static_field_get(field).map_err(|e| match e {
            JvmError::Uncaught(o) => NatErr::Throw(o),
            e => NatErr::Fatal(e),
        });
    }
    ORIGINAL_PROPERTIES.get().ok_or_else(|| {
        NatErr::Fatal(JvmError::Resolution(
            "Missing virtual property helper".into(),
        ))
    })?[args.len() - 1](vm, args)
}
fn string(vm: &mut Vm, value: JValue) -> Result<String, NatErr> {
    vm.str_of_jvalue(value)
        .ok_or_else(|| NatErr::Throw(vm.err_npe()))
}
fn headers(vm: &mut Vm, pairs: Vec<(JValue, JValue)>) -> R {
    if pairs.len() > 4096 {
        return Err(NatErr::Fatal(JvmError::BudgetExceeded));
    }
    let mut values = Vec::with_capacity(pairs.len());
    let mut total = 0_usize;
    for (name, value) in pairs {
        let name = string(vm, name)?.trim().to_owned();
        let value = string(vm, value)?.trim().to_owned();
        if name.is_empty()
            || !name.bytes().all(|b| b > 32 && b < 127)
            || !value.bytes().all(|b| b == b'\t' || (32..127).contains(&b))
        {
            return Err(NatErr::Throw(vm.err_iae("Invalid HTTP header")));
        }
        total = total.saturating_add(name.len()).saturating_add(value.len());
        if total > 256_000 || vm.budget <= total as i64 {
            return Err(NatErr::Fatal(JvmError::BudgetExceeded));
        }
        values.push((name, value));
    }
    if vm.budget <= 0 {
        return Err(NatErr::Fatal(JvmError::BudgetExceeded));
    }
    vm.budget -= total as i64 + 1;
    vm.alloc_native("Lokhttp3/Headers;", Native::Headers(values))
        .map_err(NatErr::Fatal)
}
fn array(vm: &mut Vm, args: &[JValue]) -> R {
    let Some(Native::Array(ArrayData::Obj(values))) = vm.payload_of(args[1]) else {
        return Err(NatErr::Throw(vm.err_npe()));
    };
    if values.len() % 2 != 0 {
        return Err(NatErr::Throw(
            vm.err_iae("Expected alternating header names and values"),
        ));
    }
    headers(
        vm,
        values
            .as_chunks::<2>()
            .0
            .iter()
            .map(|v| (v[0], v[1]))
            .collect(),
    )
}
fn map(vm: &mut Vm, args: &[JValue]) -> R {
    let Some(Native::Map(values)) = vm.payload_of(args[1]) else {
        return Err(NatErr::Throw(vm.err_npe()));
    };
    headers(vm, values)
}
fn static_array(vm: &mut Vm, args: &[JValue]) -> R {
    array(vm, &[JValue::Null, args[0]])
}
fn static_map(vm: &mut Vm, args: &[JValue]) -> R {
    map(vm, &[JValue::Null, args[0]])
}
pub(super) fn install(vm: &mut Vm, user_agent: &str) -> Result<(), JvmError> {
    // Default DNS is a configuration token. Swift still resolves and connects.
    super::kotlin_type_compat::marker(vm, "Lokhttp3/Dns;");
    let dns = vm.alloc_native("Lokhttp3/Dns;", Native::Opaque)?;
    super::multipart_compat::static_value(vm, "Lokhttp3/Dns;", "SYSTEM", "Lokhttp3/Dns;", dns)?;
    if user_agent.is_empty()
        || user_agent.len() > 2048
        || !user_agent.bytes().all(|b| (32..127).contains(&b))
    {
        return Err(JvmError::Resolution("Invalid host HTTP user agent".into()));
    }
    let signatures = [
        "(Ljava/lang/String;)Ljava/lang/String;",
        "(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;",
    ];
    if ORIGINAL_PROPERTIES.get().is_none() {
        let mut functions = vec![];
        for sig in signatures {
            let key = (
                vm.intern("Ljava/lang/System;"),
                vm.intern("getProperty"),
                vm.intern(sig),
            );
            functions.push(
                *vm.natives.get(&key).ok_or_else(|| {
                    JvmError::Resolution("Missing virtual property helper".into())
                })?,
            );
        }
        let _ = ORIGINAL_PROPERTIES.set(
            functions
                .try_into()
                .map_err(|_| JvmError::Resolution("Invalid property helper table".into()))?,
        );
    }
    let agent = vm.alloc_string(user_agent);
    super::multipart_compat::static_value(
        vm,
        "Ljava/lang/System;",
        "$acHttpAgent",
        "Ljava/lang/String;",
        agent,
    )?;
    for sig in signatures {
        vm.register_native(NativeEntry {
            class: "Ljava/lang/System;",
            name: "getProperty",
            sig,
            instance: false,
            f: property,
        })?;
    }
    let companion = vm.alloc_native("Lokhttp3/Headers$Companion;", Native::Opaque)?;
    super::multipart_compat::static_value(
        vm,
        "Lokhttp3/Headers;",
        "Companion",
        "Lokhttp3/Headers$Companion;",
        companion,
    )?;
    for (sig, f, sf) in [
        (
            "([Ljava/lang/String;)Lokhttp3/Headers;",
            array as dexvm::vm::NativeFn,
            static_array as dexvm::vm::NativeFn,
        ),
        ("(Ljava/util/Map;)Lokhttp3/Headers;", map, static_map),
    ] {
        vm.register_native(NativeEntry {
            class: "Lokhttp3/Headers$Companion;",
            name: "of",
            sig,
            instance: true,
            f,
        })?;
        vm.register_native(NativeEntry {
            class: "Lokhttp3/Headers;",
            name: "of",
            sig,
            instance: false,
            f: sf,
        })?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn header_factories_keep_order_duplicates_gc_roots_and_validation() {
        let mut vm = Vm::new(vec![], Box::new(std::io::sink())).unwrap();
        install(&mut vm, "Owned runtime").unwrap();
        let field = dexvm::vm::FieldRef {
            class_desc: vm.intern("Lokhttp3/Headers;"),
            name: vm.intern("Companion"),
            ty: vm.intern("Lokhttp3/Headers$Companion;"),
        };
        let companion = vm.static_field_get(field).unwrap();
        vm.gc(&[]);
        assert_eq!(vm.static_field_get(field).unwrap(), companion);
        let key = vm.alloc_string("http.agent");
        let agent = property(&mut vm, &[key]).unwrap();
        assert_eq!(vm.str_of_jvalue(agent).as_deref(), Some("Owned runtime"));
        let key = vm.alloc_string("unavailable.private.property");
        let fallback = vm.alloc_string("owned fallback");
        assert_eq!(property(&mut vm, &[key, fallback]).unwrap(), fallback);
        assert_eq!(property(&mut vm, &[key]).unwrap(), JValue::Null);
        let values = ["X-Owned", "one", "X-Owned", "two"]
            .map(|s| vm.alloc_string(s))
            .to_vec();
        let input = vm
            .alloc_native("[Ljava/lang/String;", Native::Array(ArrayData::Obj(values)))
            .unwrap();
        let result = array(&mut vm, &[companion, input]).unwrap();
        assert!(
            matches!(vm.payload_of(result),Some(Native::Headers(v)) if v==vec![("X-Owned".into(),"one".into()),("X-Owned".into(),"two".into())])
        );
        let name = vm.alloc_string(" X-Owned ");
        let value = vm.alloc_string(" value ");
        let source = vm
            .alloc_native(
                "Ljava/util/LinkedHashMap;",
                Native::Map(vec![(name, value)]),
            )
            .unwrap();
        let result = map(&mut vm, &[companion, source]).unwrap();
        assert!(
            matches!(vm.payload_of(result),Some(Native::Headers(v)) if v==vec![("X-Owned".into(),"value".into())])
        );
        for strings in [
            vec!["odd"],
            vec!["Bad name", "value"],
            vec!["X-Owned", "value\r\ninjected"],
            vec!["X-Owned", "café"],
        ] {
            let values = strings.iter().map(|s| vm.alloc_string(s)).collect();
            let values = vm
                .alloc_native("[Ljava/lang/String;", Native::Array(ArrayData::Obj(values)))
                .unwrap();
            assert!(matches!(
                array(&mut vm, &[companion, values]),
                Err(NatErr::Throw(_))
            ));
        }
        vm.budget = 0;
        assert!(matches!(
            array(&mut vm, &[companion, input]),
            Err(NatErr::Fatal(JvmError::BudgetExceeded))
        ));
    }
}
