//! UTF-16 characters, character ranges, and bounded virtual CharSequence access.
use super::kotlin_collection_compat::{charge, invoke};
use dexvm::vm::object::Native;
use dexvm::vm::{error::JvmError, NatErr, NativeEntry, Vm};
use dexvm::JValue;
type R = Result<JValue, NatErr>;
const ITERATOR: &str = "Lkotlin/ranges/CharProgressionIterator;";
pub(super) fn units(vm: &mut Vm, value: JValue) -> Result<Vec<u16>, NatErr> {
    if value.is_null_ref() {
        return Err(NatErr::Throw(vm.err_npe()));
    }
    if let Some(Native::Str(text) | Native::StringBuilder(text)) =
        vm.arena.objects[value.as_obj() as usize].native.as_ref()
    {
        let count = text.len();
        charge(vm, count)?;
        let Some(Native::Str(text) | Native::StringBuilder(text)) = vm.payload_of(value) else {
            unreachable!()
        };
        return Ok(text.encode_utf16().collect());
    }
    let length = invoke(vm, value, "length", "()I", vec![])?.as_int();
    if length < 0 {
        return Err(NatErr::Throw(vm.err_iae("Negative CharSequence length")));
    }
    charge(vm, length as usize)?;
    let mut units = Vec::with_capacity(length as usize);
    for index in 0..length {
        units.push(invoke(vm, value, "charAt", "(I)C", vec![JValue::Int(index)])?.as_int() as u16);
    }
    Ok(units)
}
fn to_list(vm: &mut Vm, args: &[JValue]) -> R {
    let units = units(vm, args[0])?;
    let mut values = Vec::with_capacity(units.len());
    for c in units {
        values.push(
            vm.alloc_native("Ljava/lang/Character;", Native::CharBox(c))
                .map_err(NatErr::Fatal)?,
        );
    }
    vm.alloc_native("Ljava/util/ArrayList;", Native::List(values))
        .map_err(NatErr::Fatal)
}
fn range(vm: &mut Vm, value: JValue) -> Result<(i32, i32), NatErr> {
    match vm.payload_of(value) {
        Some(Native::CharRange(a, b)) => Ok((a as u16 as i32, b as u16 as i32)),
        _ => Err(NatErr::Throw(vm.err_npe())),
    }
}
fn iterator(vm: &mut Vm, args: &[JValue]) -> R {
    charge(vm, 1)?;
    let (a, b) = range(vm, args[0])?;
    let result = vm
        .alloc_native(ITERATOR, Native::Opaque)
        .map_err(NatErr::Fatal)?;
    vm.arena.objects[result.as_obj() as usize].fields = vec![JValue::Int(a), JValue::Int(b)];
    Ok(result)
}
fn has_next(vm: &mut Vm, args: &[JValue]) -> R {
    charge(vm, 1)?;
    let fields = &vm.arena.objects[args[0].as_obj() as usize].fields;
    Ok(JValue::Int(i32::from(
        fields[0].as_int() <= fields[1].as_int(),
    )))
}
fn next_char(vm: &mut Vm, args: &[JValue]) -> R {
    if has_next(vm, args)?.as_int() == 0 {
        return Err(NatErr::Throw(vm.throwable_of(
            "Ljava/util/NoSuchElementException;",
            "Character iterator is exhausted",
        )));
    }
    let fields = &mut vm.arena.objects[args[0].as_obj() as usize].fields;
    let value = fields[0].as_int();
    // An i32 sentinel permits the final UTF-16 unit without wrapping to zero.
    fields[0] = JValue::Int(value + 1);
    Ok(JValue::Int(value))
}
fn next_boxed(vm: &mut Vm, args: &[JValue]) -> R {
    let c = next_char(vm, args)?.as_int() as u16;
    vm.alloc_native("Ljava/lang/Character;", Native::CharBox(c))
        .map_err(NatErr::Fatal)
}
fn remove(vm: &mut Vm, _args: &[JValue]) -> R {
    Err(NatErr::Throw(vm.throwable_of(
        "Ljava/lang/UnsupportedOperationException;",
        "Read-only character iterator",
    )))
}
fn random(vm: &mut Vm, args: &[JValue]) -> R {
    let (a, b) = range(vm, args[0])?;
    if a > b {
        return Err(NatErr::Throw(vm.throwable_of(
            "Ljava/util/NoSuchElementException;",
            "Empty character range",
        )));
    }
    let result = invoke(
        vm,
        args[1],
        "nextInt",
        "(II)I",
        vec![JValue::Int(a), JValue::Int(b + 1)],
    )?;
    if !(a..=b).contains(&result.as_int()) {
        return Err(NatErr::Throw(
            vm.err_iae("Random returned a value outside the requested range"),
        ));
    }
    Ok(result)
}
pub(super) fn install(vm: &mut Vm) -> Result<(), JvmError> {
    vm.register_native(NativeEntry {
        class: "Lkotlin/text/StringsKt;",
        name: "toList",
        sig: "(Ljava/lang/CharSequence;)Ljava/util/List;",
        instance: false,
        f: to_list,
    })?;
    for sig in [
        "()Ljava/util/Iterator;",
        "()Lkotlin/collections/CharIterator;",
    ] {
        vm.register_native(NativeEntry {
            class: "Lkotlin/ranges/CharRange;",
            name: "iterator",
            sig,
            instance: true,
            f: iterator,
        })?;
    }
    for (name, sig, f) in [
        ("hasNext", "()Z", has_next as dexvm::vm::NativeFn),
        ("nextChar", "()C", next_char),
        ("next", "()Ljava/lang/Character;", next_boxed),
        ("next", "()Ljava/lang/Object;", next_boxed),
        ("remove", "()V", remove),
    ] {
        vm.register_native(NativeEntry {
            class: ITERATOR,
            name,
            sig,
            instance: true,
            f,
        })?;
    }
    let id = vm.ensure_class_by_desc(ITERATOR)?;
    let parent = vm.ensure_class_by_desc("Lkotlin/collections/CharIterator;")?;
    vm.classes[id as usize].superclass = Some(parent);
    let java_iterator = vm.ensure_class_by_desc("Ljava/util/Iterator;")?;
    vm.classes[parent as usize].interfaces.push(java_iterator);
    vm.register_native(NativeEntry {
        class: "Lkotlin/ranges/RangesKt;",
        name: "random",
        sig: "(Lkotlin/ranges/CharRange;Lkotlin/random/Random;)C",
        instance: false,
        f: random,
    })?;
    Ok(())
}
