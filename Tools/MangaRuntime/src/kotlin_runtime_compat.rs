//! Shared collection marker interfaces and bounded default-generator byte APIs.
use dexvm::vm::{
    error::JvmError,
    object::{ArrayData, Native},
    NatErr, NativeEntry, Vm,
};
use dexvm::JValue;
type R = Result<JValue, NatErr>;
fn check_not_null(vm: &mut Vm, args: &[JValue]) -> R {
    if args[0].is_null_ref() {
        let message = args
            .get(1)
            .and_then(|v| vm.str_of_jvalue(*v))
            .unwrap_or_else(|| "Required value was null".into());
        Err(NatErr::Throw(
            vm.throwable_of("Ljava/lang/NullPointerException;", message),
        ))
    } else {
        Ok(JValue::Null)
    }
}
const DEFAULT: &str = "Lkotlin/random/Random$Default;";
const LIMIT: usize = 1_000_000;
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
fn map_value(vm: &mut Vm, args: &[JValue]) -> R {
    if super::kotlin_collection_compat::is_default_map(vm, args[0]) {
        return invoke(
            vm,
            args[0],
            "getOrImplicitDefault",
            "(Ljava/lang/Object;)Ljava/lang/Object;",
            vec![args[1]],
        );
    }
    // JsonObject and guest Map implementations need their own virtual get;
    // a Native::Map-only shortcut loses them and conflates null with absence.
    let cost = match vm.payload_of(args[0]) {
        Some(Native::Map(entries)) => entries.len(),
        Some(Native::Json(dexvm::vm::object::JsonVal::Object(entries))) => entries.len(),
        _ => 1,
    };
    charge(vm, cost)?;
    let value = invoke(
        vm,
        args[0],
        "get",
        "(Ljava/lang/Object;)Ljava/lang/Object;",
        vec![args[1]],
    )?;
    if !value.is_null_ref()
        || invoke(
            vm,
            args[0],
            "containsKey",
            "(Ljava/lang/Object;)Z",
            vec![args[1]],
        )?
        .as_int()
            != 0
    {
        return Ok(value);
    }
    Err(NatErr::Throw(vm.throwable_of(
        "Ljava/util/NoSuchElementException;",
        "Key is missing in the map",
    )))
}
fn instant_plus(vm: &mut Vm, args: &[JValue]) -> R {
    charge(vm, 1)?;
    let nanos = kotlin_instant_nanos(vm, args[0])? + i128::from(args[1].as_long()) * 1_000_000;
    kotlin_instant(vm, nanos)
}
fn instant_minus(vm: &mut Vm, args: &[JValue]) -> R {
    charge(vm, 1)?;
    let nanos = kotlin_instant_nanos(vm, args[0])? - i128::from(args[1].as_long()) * 1_000_000;
    kotlin_instant(vm, nanos)
}
fn kotlin_instant(vm: &mut Vm, nanos: i128) -> R {
    let nanos = nanos.clamp(
        i128::from(i64::MIN) * 1_000_000,
        i128::from(i64::MAX) * 1_000_000 + 999_999,
    );
    let value = vm
        .alloc_native(
            "Lkotlin/time/Instant;",
            Native::EpochMillis(nanos.div_euclid(1_000_000) as i64),
        )
        .map_err(NatErr::Fatal)?;
    vm.arena.objects[value.as_obj() as usize].fields =
        vec![JValue::Int(nanos.rem_euclid(1_000_000) as i32)];
    Ok(value)
}
fn instant_from_seconds(vm: &mut Vm, args: &[JValue]) -> R {
    charge(vm, 1)?;
    let nanos = if args.get(3).is_some_and(|mask| mask.as_int() & 2 != 0) {
        0
    } else {
        args[2].as_long()
    };
    kotlin_instant(
        vm,
        i128::from(args[1].as_long()) * 1_000_000_000 + i128::from(nanos),
    )
}
fn instant_from_seconds_int(vm: &mut Vm, args: &[JValue]) -> R {
    instant_from_seconds(
        vm,
        &[args[0], args[1], JValue::Long(i64::from(args[2].as_int()))],
    )
}
fn kotlin_instant_nanos(vm: &mut Vm, value: JValue) -> Result<i128, NatErr> {
    let Some(Native::EpochMillis(millis)) = vm.payload_of(value) else {
        return Err(NatErr::Throw(vm.err_npe()));
    };
    let extra = vm.arena.objects[value.as_obj() as usize]
        .fields
        .first()
        .map_or(0, |v| v.as_int());
    Ok(i128::from(millis) * 1_000_000 + i128::from(extra))
}
fn instant_compare(vm: &mut Vm, args: &[JValue]) -> R {
    charge(vm, 1)?;
    let a = kotlin_instant_nanos(vm, args[0])?;
    let b = kotlin_instant_nanos(vm, args[1])?;
    Ok(JValue::Int(a.cmp(&b) as i32))
}
fn box_float(vm: &mut Vm, args: &[JValue]) -> R {
    vm.invoke_static(
        "Ljava/lang/Float;",
        "valueOf",
        "(F)Ljava/lang/Float;",
        vec![args[0]],
    )
    .map_err(|e| match e {
        JvmError::Uncaught(o) => NatErr::Throw(o),
        e => NatErr::Fatal(e),
    })
}
fn charge(vm: &mut Vm, size: usize) -> Result<(), NatErr> {
    if size > LIMIT || vm.budget <= size as i64 {
        return Err(NatErr::Fatal(JvmError::BudgetExceeded));
    }
    vm.budget -= size as i64;
    Ok(())
}
fn entropy(vm: &mut Vm, bytes: &mut [u8]) -> Result<(), NatErr> {
    getrandom::fill(bytes).map_err(|_| {
        NatErr::Throw(vm.throwable_of(
            "Ljava/lang/IllegalStateException;",
            "Random generator unavailable",
        ))
    })
}
fn next_size(vm: &mut Vm, args: &[JValue]) -> R {
    let size = usize::try_from(args[1].as_int()).map_err(|_| {
        NatErr::Throw(vm.throwable_of(
            "Ljava/lang/NegativeArraySizeException;",
            "Negative byte count",
        ))
    })?;
    charge(vm, size)?;
    let mut bytes = vec![0_u8; size];
    entropy(vm, &mut bytes)?;
    vm.alloc_native(
        "[B",
        Native::Array(ArrayData::Byte(
            bytes.into_iter().map(|b| b as i8).collect(),
        )),
    )
    .map_err(NatErr::Fatal)
}
fn array_len(vm: &mut Vm, value: JValue) -> Result<usize, NatErr> {
    if value.is_null_ref() {
        return Err(NatErr::Throw(vm.err_npe()));
    }
    let object = &vm.arena.objects[value.as_obj() as usize];
    match &object.native {
        Some(Native::Array(ArrayData::Byte(bytes))) => Ok(bytes.len()),
        _ => Err(NatErr::Throw(vm.err_iae("Expected byte array"))),
    }
}
fn next_range(vm: &mut Vm, args: &[JValue]) -> R {
    let len = array_len(vm, args[1])?;
    let start = args[2].as_int();
    let end = args[3].as_int();
    if start < 0 || end < start || end as usize > len {
        return Err(NatErr::Throw(vm.err_iae("Invalid random byte range")));
    }
    let size = (end - start) as usize;
    charge(vm, size)?;
    let mut bytes = vec![0_u8; size];
    entropy(vm, &mut bytes)?;
    let Some(Native::Array(ArrayData::Byte(array))) =
        &mut vm.arena.objects[args[1].as_obj() as usize].native
    else {
        unreachable!()
    };
    for (target, byte) in array[start as usize..end as usize].iter_mut().zip(bytes) {
        *target = byte as i8;
    }
    Ok(args[1])
}
fn next_array(vm: &mut Vm, args: &[JValue]) -> R {
    let len = array_len(vm, args[1])?;
    next_range(
        vm,
        &[args[0], args[1], JValue::Int(0), JValue::Int(len as i32)],
    )
}
fn default_range(vm: &mut Vm, args: &[JValue]) -> R {
    if !args[5].is_null_ref() {
        return Err(NatErr::Throw(vm.throwable_of(
            "Ljava/lang/UnsupportedOperationException;",
            "Super calls with default arguments are unsupported",
        )));
    }
    let len = array_len(vm, args[1])?;
    let mask = args[4].as_int();
    let from = if mask & 2 != 0 {
        JValue::Int(0)
    } else {
        args[2]
    };
    let to = if mask & 4 != 0 {
        JValue::Int(len as i32)
    } else {
        args[3]
    };
    if vm.budget <= 0 {
        return Err(NatErr::Fatal(JvmError::BudgetExceeded));
    }
    if vm.recursion_depth >= vm.depth_limit {
        return Err(NatErr::Fatal(JvmError::StackOverflow));
    }
    vm.budget -= 1;
    vm.recursion_depth += 1;
    let result = vm.invoke_virtual_args(args[0], "nextBytes", "([BII)[B", vec![args[1], from, to]);
    vm.recursion_depth -= 1;
    result.map_err(|e| match e {
        JvmError::Uncaught(o) => NatErr::Throw(o),
        e => NatErr::Fatal(e),
    })
}
fn hex(vm: &mut Vm, args: &[JValue], defaults: bool) -> R {
    use dexvm::vm::object::HexFormatState;
    use std::fmt::Write;
    let len = array_len(vm, args[0])?;
    let state = if defaults && args[2].as_int() & 1 != 0 {
        HexFormatState {
            uppercase: false,
            byte_prefix: String::new(),
            byte_separator: String::new(),
        }
    } else {
        match vm.payload_of(args[1]) {
            Some(Native::HexFormat(state)) => state,
            _ => return Err(NatErr::Throw(vm.err_npe())),
        }
    };
    let size = state
        .byte_prefix
        .len()
        .checked_add(state.byte_separator.len())
        .and_then(|n| n.checked_add(2))
        .and_then(|n| n.checked_mul(len))
        .ok_or(NatErr::Fatal(JvmError::BudgetExceeded))?;
    charge(vm, size)?;
    let Some(Native::Array(ArrayData::Byte(bytes))) =
        &vm.arena.objects[args[0].as_obj() as usize].native
    else {
        unreachable!()
    };
    let mut text = String::with_capacity(size);
    for (index, byte) in bytes.iter().enumerate() {
        if index > 0 {
            text.push_str(&state.byte_separator);
        }
        text.push_str(&state.byte_prefix);
        let byte = *byte as u8;
        if state.uppercase {
            write!(text, "{byte:02X}").unwrap();
        } else {
            write!(text, "{byte:02x}").unwrap();
        }
    }
    Ok(vm.alloc_string(&text))
}
fn hex_default(vm: &mut Vm, args: &[JValue]) -> R {
    hex(vm, args, true)
}
fn hex_explicit(vm: &mut Vm, args: &[JValue]) -> R {
    hex(vm, args, false)
}
pub(super) fn install(vm: &mut Vm) -> Result<(), JvmError> {
    for (name, sig, instance, f) in [
        (
            "fromEpochSeconds",
            "(JJ)Lkotlin/time/Instant;",
            true,
            instant_from_seconds as dexvm::vm::NativeFn,
        ),
        (
            "fromEpochSeconds",
            "(JI)Lkotlin/time/Instant;",
            true,
            instant_from_seconds_int,
        ),
        (
            "fromEpochSeconds$default",
            "(Lkotlin/time/Instant$Companion;JJILjava/lang/Object;)Lkotlin/time/Instant;",
            false,
            instant_from_seconds,
        ),
    ] {
        vm.register_native(NativeEntry {
            class: "Lkotlin/time/Instant$Companion;",
            name,
            sig,
            instance,
            f,
        })?;
    }
    for sig in ["(Lkotlin/time/Instant;)I", "(Ljava/lang/Object;)I"] {
        vm.register_native(NativeEntry {
            class: "Lkotlin/time/Instant;",
            name: "compareTo",
            sig,
            instance: true,
            f: instant_compare,
        })?;
    }
    for sig in [
        "(Ljava/lang/Object;)V",
        "(Ljava/lang/Object;Ljava/lang/String;)V",
    ] {
        vm.register_native(NativeEntry {
            class: "Lkotlin/jvm/internal/Intrinsics;",
            name: "checkNotNull",
            sig,
            instance: false,
            f: check_not_null,
        })?;
    }
    vm.register_native(NativeEntry {
        class: "Lkotlin/collections/MapsKt;",
        name: "getValue",
        sig: "(Ljava/util/Map;Ljava/lang/Object;)Ljava/lang/Object;",
        instance: false,
        f: map_value,
    })?;
    vm.register_native(NativeEntry {
        class: "Lkotlin/time/Instant;",
        name: "minus-LRDsOJo",
        sig: "(J)Lkotlin/time/Instant;",
        instance: true,
        f: instant_minus,
    })?;
    vm.register_native(NativeEntry {
        class: "Lkotlin/time/Instant;",
        name: "plus-LRDsOJo",
        sig: "(J)Lkotlin/time/Instant;",
        instance: true,
        f: instant_plus,
    })?;
    super::kotlin_type_compat::marker(vm, "Lkotlin/jvm/functions/Function5;");
    vm.register_native(NativeEntry {
        class: "Lkotlin/coroutines/jvm/internal/Boxing;",
        name: "boxFloat",
        sig: "(F)Ljava/lang/Float;",
        instance: false,
        f: box_float,
    })?;
    for (name, parent) in [
        ("KMappedMarker", None),
        ("KMutableIterable", Some("KMappedMarker")),
        ("KMutableCollection", Some("KMutableIterable")),
        ("KMutableList", Some("KMutableCollection")),
        ("KMutableSet", Some("KMutableCollection")),
        ("KMutableMap", Some("KMappedMarker")),
        ("KMutableMap$Entry", Some("KMappedMarker")),
        ("KMutableIterator", Some("KMappedMarker")),
        ("KMutableListIterator", Some("KMutableIterator")),
    ] {
        let id =
            super::kotlin_type_compat::marker(vm, &format!("Lkotlin/jvm/internal/markers/{name};"));
        if let Some(parent) = parent {
            let parent = super::kotlin_type_compat::marker(
                vm,
                &format!("Lkotlin/jvm/internal/markers/{parent};"),
            );
            if !vm.classes[id as usize].interfaces.contains(&parent) {
                vm.classes[id as usize].interfaces.push(parent);
            }
        }
    }
    for (sig, f) in [
        ("(I)[B", next_size as dexvm::vm::NativeFn),
        ("([B)[B", next_array),
        ("([BII)[B", next_range),
    ] {
        vm.register_native(NativeEntry {
            class: DEFAULT,
            name: "nextBytes",
            sig,
            instance: true,
            f,
        })?;
    }
    vm.register_native(NativeEntry {
        class: "Lkotlin/random/Random;",
        name: "nextBytes$default",
        sig: "(Lkotlin/random/Random;[BIIILjava/lang/Object;)[B",
        instance: false,
        f: default_range,
    })?;
    for (name, sig, f) in [
        (
            "toHexString$default",
            "([BLkotlin/text/HexFormat;ILjava/lang/Object;)Ljava/lang/String;",
            hex_default as dexvm::vm::NativeFn,
        ),
        (
            "toHexString",
            "([BLkotlin/text/HexFormat;)Ljava/lang/String;",
            hex_explicit,
        ),
    ] {
        vm.register_native(NativeEntry {
            class: "Lkotlin/text/HexExtensionsKt;",
            name,
            sig,
            instance: false,
            f,
        })?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn kotlin_epoch_second_defaults_normalize_adjustments_and_compare_submilliseconds() {
        let mut vm = Vm::new(vec![], Box::new(std::io::sink())).unwrap();
        install(&mut vm).unwrap();
        let before =
            instant_from_seconds(&mut vm, &[JValue::Null, JValue::Long(0), JValue::Long(-1)])
                .unwrap();
        let epoch = instant_from_seconds(
            &mut vm,
            &[
                JValue::Null,
                JValue::Long(0),
                JValue::Long(99),
                JValue::Int(2),
                JValue::Null,
            ],
        )
        .unwrap();
        assert_eq!(kotlin_instant_nanos(&mut vm, before).unwrap(), -1);
        assert_eq!(kotlin_instant_nanos(&mut vm, epoch).unwrap(), 0);
        assert_eq!(
            instant_compare(&mut vm, &[before, epoch]).unwrap(),
            JValue::Int(-1)
        );
        let later = instant_plus(&mut vm, &[before, JValue::Long(1)]).unwrap();
        let restored = instant_minus(&mut vm, &[later, JValue::Long(1)]).unwrap();
        assert_eq!(kotlin_instant_nanos(&mut vm, restored).unwrap(), -1);
    }
    #[test]
    fn map_get_value_uses_virtual_map_contract_and_preserves_present_null() {
        let mut vm = Vm::new(vec![], Box::new(std::io::sink())).unwrap();
        super::super::json_compat::install(&mut vm).unwrap();
        install(&mut vm).unwrap();
        let key = vm.alloc_string("owned");
        let missing = vm.alloc_string("missing");
        let map = vm
            .alloc_native(
                "Ljava/util/HashMap;",
                Native::Map(vec![(key, JValue::Null)]),
            )
            .unwrap();
        assert_eq!(map_value(&mut vm, &[map, key]).unwrap(), JValue::Null);
        assert!(matches!(
            map_value(&mut vm, &[map, missing]),
            Err(NatErr::Throw(_))
        ));
        let object = super::super::json_compat::node(
            &mut vm,
            dexvm::vm::object::JsonVal::Object(vec![(
                "owned".into(),
                dexvm::vm::object::JsonVal::Int(42),
            )]),
        )
        .unwrap();
        let value = map_value(&mut vm, &[object, key]).unwrap();
        assert!(matches!(
            vm.payload_of(value),
            Some(Native::Json(dexvm::vm::object::JsonVal::Int(42)))
        ));
        assert!(matches!(
            map_value(&mut vm, &[object, missing]),
            Err(NatErr::Throw(_))
        ));
        vm.recursion_depth = vm.depth_limit;
        assert!(matches!(
            map_value(&mut vm, &[object, key]),
            Err(NatErr::Fatal(JvmError::StackOverflow))
        ));
        vm.budget = 0;
        assert!(matches!(
            map_value(&mut vm, &[object, key]),
            Err(NatErr::Fatal(JvmError::BudgetExceeded))
        ));
    }
    #[test]
    fn float_boxing_and_instant_addition_preserve_values_and_millisecond_units() {
        let mut vm = Vm::new(vec![], Box::new(std::io::sink())).unwrap();
        install(&mut vm).unwrap();
        let boxed = box_float(&mut vm, &[JValue::Float(1.5)]).unwrap();
        vm.gc(&[boxed.as_obj()]);
        assert!(matches!(vm.payload_of(boxed),Some(Native::FloatBox(v)) if v==1.5));
        let instant = vm
            .alloc_native(
                "Lkotlin/time/Instant;",
                Native::EpochMillis(1_709_164_800_000),
            )
            .unwrap();
        let added = instant_plus(&mut vm, &[instant, JValue::Long(60 * 86_400_000)]).unwrap();
        assert!(
            matches!(vm.payload_of(added),Some(Native::EpochMillis(v)) if v==1_714_348_800_000)
        );
        assert!(
            matches!(vm.payload_of(instant),Some(Native::EpochMillis(v)) if v==1_709_164_800_000)
        );
        let clamped = instant_plus(&mut vm, &[instant, JValue::Long(i64::MAX)]).unwrap();
        assert!(matches!(
            vm.payload_of(clamped),
            Some(Native::EpochMillis(i64::MAX))
        ));
        assert!(matches!(
            instant_plus(&mut vm, &[JValue::Null, JValue::Long(1)]),
            Err(NatErr::Throw(_))
        ));
    }
    #[test]
    fn random_bytes_keep_identity_ranges_errors_and_vm_limits() {
        let mut vm = Vm::new(vec![], Box::new(std::io::sink())).unwrap();
        install(&mut vm).unwrap();
        let random = vm.alloc_native(DEFAULT, Native::Opaque).unwrap();
        let untouched = vm
            .alloc_native("[B", Native::Array(ArrayData::Byte(vec![42; 32])))
            .unwrap();
        // Both defaults replace deliberately invalid supplied endpoints;
        // virtual dispatch still returns the receiver's actual byte array.
        assert_eq!(
            default_range(
                &mut vm,
                &[
                    random,
                    untouched,
                    JValue::Int(-9),
                    JValue::Int(-9),
                    JValue::Int(6),
                    JValue::Null
                ]
            )
            .unwrap(),
            untouched
        );
        assert!(
            matches!(vm.payload_of(untouched),Some(Native::Array(ArrayData::Byte(v))) if v.len()==32 && v!=vec![42;32])
        );
        let array = vm
            .alloc_native("[B", Native::Array(ArrayData::Byte(vec![42; 32])))
            .unwrap();
        assert_eq!(
            next_range(&mut vm, &[random, array, JValue::Int(4), JValue::Int(28)]).unwrap(),
            array
        );
        let Some(Native::Array(ArrayData::Byte(bytes))) = vm.payload_of(array) else {
            panic!()
        };
        assert_eq!(&bytes[..4], &[42; 4]);
        assert_eq!(&bytes[28..], &[42; 4]);
        assert_ne!(&bytes[4..28], &[42; 24]);
        assert_eq!(
            next_range(&mut vm, &[random, array, JValue::Int(32), JValue::Int(32)]).unwrap(),
            array
        );
        assert!(matches!(
            next_size(&mut vm, &[random, JValue::Int(-1)]),
            Err(NatErr::Throw(_))
        ));
        assert!(matches!(
            next_range(&mut vm, &[random, array, JValue::Int(3), JValue::Int(2)]),
            Err(NatErr::Throw(_))
        ));
        assert!(matches!(
            next_array(&mut vm, &[random, JValue::Null]),
            Err(NatErr::Throw(_))
        ));
        let empty = next_size(&mut vm, &[random, JValue::Int(0)]).unwrap();
        assert_eq!(array_len(&mut vm, empty).unwrap(), 0);
        let generated = next_size(&mut vm, &[random, JValue::Int(16)]).unwrap();
        assert_eq!(array_len(&mut vm, generated).unwrap(), 16);
        vm.budget = 0;
        assert!(matches!(
            next_size(&mut vm, &[random, JValue::Int(1)]),
            Err(NatErr::Fatal(JvmError::BudgetExceeded))
        ));
    }
    #[test]
    fn collection_markers_are_interfaces_with_real_transitive_parents() {
        let mut vm = Vm::new(vec![], Box::new(std::io::sink())).unwrap();
        install(&mut vm).unwrap();
        let root = vm
            .ensure_class_by_desc("Lkotlin/jvm/internal/markers/KMappedMarker;")
            .unwrap();
        let list = vm
            .ensure_class_by_desc("Lkotlin/jvm/internal/markers/KMutableList;")
            .unwrap();
        let set = vm
            .ensure_class_by_desc("Lkotlin/jvm/internal/markers/KMutableSet;")
            .unwrap();
        assert!(vm.classes[root as usize].is_interface);
        assert!(vm.is_assignable(list, root).unwrap());
        assert!(!vm.is_assignable(list, set).unwrap());
        let java = vm.ensure_class_by_desc("Ljava/util/ArrayList;").unwrap();
        assert!(!vm.is_assignable(java, root).unwrap());
    }
    #[test]
    fn byte_hex_defaults_respect_masks_signed_values_and_explicit_formats() {
        let mut vm = Vm::new(vec![], Box::new(std::io::sink())).unwrap();
        install(&mut vm).unwrap();
        let bytes = vm
            .alloc_native("[B", Native::Array(ArrayData::Byte(vec![0, 127, -128, -1])))
            .unwrap();
        let text = hex_default(
            &mut vm,
            &[bytes, JValue::Null, JValue::Int(1), JValue::Null],
        )
        .unwrap();
        assert_eq!(vm.str_of_jvalue(text).as_deref(), Some("007f80ff"));
        assert!(matches!(
            hex_default(
                &mut vm,
                &[bytes, JValue::Null, JValue::Int(0), JValue::Null]
            ),
            Err(NatErr::Throw(_))
        ));
        let format = vm
            .alloc_native(
                "Lkotlin/text/HexFormat;",
                Native::HexFormat(dexvm::vm::object::HexFormatState {
                    uppercase: true,
                    byte_prefix: "0x".into(),
                    byte_separator: ":".into(),
                }),
            )
            .unwrap();
        let text = hex_explicit(&mut vm, &[bytes, format]).unwrap();
        assert_eq!(
            vm.str_of_jvalue(text).as_deref(),
            Some("0x00:0x7F:0x80:0xFF")
        );
        vm.budget = 0;
        assert!(matches!(
            hex_explicit(&mut vm, &[bytes, format]),
            Err(NatErr::Fatal(JvmError::BudgetExceeded))
        ));
    }
}
