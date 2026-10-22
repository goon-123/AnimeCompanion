//! Lazy line splitting and iterator-based sequence operations. Neither creation
//! nor a short-circuiting consumer evaluates the remainder of a sequence.
use super::kotlin_collection_compat::{charge, invoke};
use dexvm::vm::object::{IterKind, Native};
use dexvm::vm::{error::JvmError, NatErr, NativeEntry, Vm};
use dexvm::JValue;
type R = Result<JValue, NatErr>;
const LINES: &str = "Lapp/animecompanion/runtime/LineSequence;";
const LINE_ITER: &str = "Lapp/animecompanion/runtime/LineIterator;";
const TRANSFORM: &str = "Lapp/animecompanion/runtime/TransformSequence;";
const TRANSFORM_ITER: &str = "Lapp/animecompanion/runtime/TransformIterator;";
fn object(vm: &mut Vm, class: &str, fields: Vec<JValue>) -> R {
    let value = vm
        .alloc_native(class, Native::Opaque)
        .map_err(NatErr::Fatal)?;
    vm.arena.objects[value.as_obj() as usize].fields = fields;
    Ok(value)
}
fn fields(vm: &mut Vm, value: JValue) -> Result<Vec<JValue>, NatErr> {
    charge(vm, 1)?;
    if value.is_null_ref() {
        return Err(NatErr::Throw(vm.err_npe()));
    }
    Ok(vm.arena.objects[value.as_obj() as usize].fields.clone())
}
fn no_element(vm: &mut Vm) -> NatErr {
    NatErr::Throw(vm.throwable_of(
        "Ljava/util/NoSuchElementException;",
        "Sequence has no matching element",
    ))
}
fn line_sequence(vm: &mut Vm, args: &[JValue]) -> R {
    if args[0].is_null_ref() {
        return Err(NatErr::Throw(vm.err_npe()));
    }
    object(vm, LINES, vec![args[0]])
}
fn line_iterator(vm: &mut Vm, args: &[JValue]) -> R {
    let text = fields(vm, args[0])?[0];
    object(vm, LINE_ITER, vec![text, JValue::Int(0), JValue::Int(0)])
}
fn line_has_next(vm: &mut Vm, args: &[JValue]) -> R {
    Ok(JValue::Int(i32::from(
        fields(vm, args[0])?[2].as_int() == 0,
    )))
}
fn line_next(vm: &mut Vm, args: &[JValue]) -> R {
    let state = fields(vm, args[0])?;
    if state[2].as_int() != 0 {
        return Err(no_element(vm));
    }
    let text = state[0];
    let start = state[1].as_int() as usize;
    if let Some(Native::Str(text_value)) = vm.arena.objects[text.as_obj() as usize].native.as_ref()
    {
        // Newlines are ASCII bytes, so immutable strings need no UTF-16 copy
        // and no repeated scan of already-consumed or unrequested lines.
        let tail = text_value.get(start..).ok_or_else(|| {
            NatErr::Fatal(JvmError::Resolution(
                "Invalid line iterator position".into(),
            ))
        })?;
        let end = start + tail.find(['\r', '\n']).unwrap_or(tail.len());
        let done = end == text_value.len();
        let next = if !done
            && text_value.as_bytes()[end] == 13
            && text_value.as_bytes().get(end + 1) == Some(&10)
        {
            end + 2
        } else {
            end + usize::from(!done)
        };
        let content = text_value[start..end].to_owned();
        charge(vm, next - start)?;
        let result = vm.alloc_string(&content);
        vm.arena.objects[args[0].as_obj() as usize].fields =
            vec![text, JValue::Int(next as i32), JValue::Int(i32::from(done))];
        return Ok(result);
    }
    // Read at iteration time, preserving mutations between creation/iteration.
    let direct = if matches!(
        vm.arena.objects[text.as_obj() as usize].native,
        Some(Native::Str(_) | Native::StringBuilder(_))
    ) {
        Some(super::kotlin_text_compat::units(vm, text)?)
    } else {
        None
    };
    let length = if let Some(units) = &direct {
        units.len()
    } else {
        let n = invoke(vm, text, "length", "()I", vec![])?.as_int();
        if n < 0 {
            return Err(NatErr::Throw(vm.err_iae("Negative CharSequence length")));
        }
        charge(vm, n as usize)?;
        n as usize
    };
    if start > length {
        return Err(NatErr::Throw(vm.throwable_of(
            "Ljava/lang/IndexOutOfBoundsException;",
            "CharSequence shrank during iteration",
        )));
    }
    let unit = |vm: &mut Vm, index: usize| -> Result<u16, NatErr> {
        if let Some(units) = &direct {
            Ok(units[index])
        } else {
            Ok(
                invoke(vm, text, "charAt", "(I)C", vec![JValue::Int(index as i32)])?.as_int()
                    as u16,
            )
        }
    };
    let mut end = start;
    let mut content = vec![];
    let mut delimiter = 0;
    while end < length {
        let c = unit(vm, end)?;
        if c == 13 || c == 10 {
            delimiter = c;
            break;
        }
        content.push(c);
        end += 1;
    }
    let done = end == length;
    let next = if delimiter == 13 && end + 1 < length && unit(vm, end + 1)? == 10 {
        end + 2
    } else {
        end + usize::from(!done)
    };
    let result = vm.alloc_string(&String::from_utf16_lossy(&content));
    vm.arena.objects[args[0].as_obj() as usize].fields =
        vec![text, JValue::Int(next as i32), JValue::Int(i32::from(done))];
    Ok(result)
}
fn list_iterator(vm: &mut Vm, args: &[JValue]) -> R {
    if !matches!(
        vm.arena.objects[args[0].as_obj() as usize].native,
        Some(Native::List(_))
    ) {
        return Err(NatErr::Throw(
            vm.err_iae("Unsupported sequence representation"),
        ));
    }
    vm.alloc_native(
        "Ljava/util/Iterator;",
        Native::Iter(IterKind::List {
            list: args[0].as_obj(),
            idx: 0,
        }),
    )
    .map_err(NatErr::Fatal)
}
fn iterator(vm: &mut Vm, value: JValue) -> R {
    invoke(vm, value, "iterator", "()Ljava/util/Iterator;", vec![])
}
fn more(vm: &mut Vm, value: JValue) -> Result<bool, NatErr> {
    Ok(invoke(vm, value, "hasNext", "()Z", vec![])?.as_int() != 0)
}
fn next(vm: &mut Vm, value: JValue) -> R {
    invoke(vm, value, "next", "()Ljava/lang/Object;", vec![])
}
fn transform(vm: &mut Vm, args: &[JValue], filter: bool) -> R {
    if args[0].is_null_ref() || args[1].is_null_ref() {
        return Err(NatErr::Throw(vm.err_npe()));
    }
    object(
        vm,
        TRANSFORM,
        vec![args[0], args[1], JValue::Int(i32::from(filter))],
    )
}
fn map(vm: &mut Vm, args: &[JValue]) -> R {
    transform(vm, args, false)
}
fn filter(vm: &mut Vm, args: &[JValue]) -> R {
    transform(vm, args, true)
}
fn transform_iterator(vm: &mut Vm, args: &[JValue]) -> R {
    let f = fields(vm, args[0])?;
    let upstream = iterator(vm, f[0])?;
    object(
        vm,
        TRANSFORM_ITER,
        vec![upstream, f[1], f[2], JValue::Null, JValue::Int(0)],
    )
}
fn boolean(vm: &mut Vm, value: JValue) -> Result<bool, NatErr> {
    match vm.payload_of(value) {
        Some(Native::BoolBox(b)) => Ok(b),
        _ if value.is_null_ref() => Err(NatErr::Throw(vm.err_npe())),
        _ => Err(NatErr::Throw(vm.throwable_of(
            "Ljava/lang/ClassCastException;",
            "Predicate must return Boolean",
        ))),
    }
}
fn transform_has_next(vm: &mut Vm, args: &[JValue]) -> R {
    let f = fields(vm, args[0])?;
    if f[4].as_int() != 0 {
        return Ok(JValue::Int(i32::from(f[4].as_int() == 1)));
    }
    if f[2].as_int() == 0 {
        return Ok(JValue::Int(i32::from(more(vm, f[0])?)));
    }
    while more(vm, f[0])? {
        let value = next(vm, f[0])?;
        let keep = invoke(
            vm,
            f[1],
            "invoke",
            "(Ljava/lang/Object;)Ljava/lang/Object;",
            vec![value],
        )?;
        if boolean(vm, keep)? {
            let state = &mut vm.arena.objects[args[0].as_obj() as usize].fields;
            state[3] = value;
            state[4] = JValue::Int(1);
            return Ok(JValue::Int(1));
        }
    }
    vm.arena.objects[args[0].as_obj() as usize].fields[4] = JValue::Int(2);
    Ok(JValue::Int(0))
}
fn transform_next(vm: &mut Vm, args: &[JValue]) -> R {
    if transform_has_next(vm, args)?.as_int() == 0 {
        return Err(no_element(vm));
    }
    let f = fields(vm, args[0])?;
    if f[2].as_int() != 0 {
        let state = &mut vm.arena.objects[args[0].as_obj() as usize].fields;
        state[3] = JValue::Null;
        state[4] = JValue::Int(0);
        return Ok(f[3]);
    }
    let value = next(vm, f[0])?;
    invoke(
        vm,
        f[1],
        "invoke",
        "(Ljava/lang/Object;)Ljava/lang/Object;",
        vec![value],
    )
}
fn to_list(vm: &mut Vm, args: &[JValue]) -> R {
    let it = iterator(vm, args[0])?;
    let mut values = vec![];
    while more(vm, it)? {
        if values.len() >= 100_000 {
            return Err(NatErr::Fatal(JvmError::BudgetExceeded));
        }
        charge(vm, 1)?;
        values.push(next(vm, it)?);
    }
    vm.alloc_native("Ljava/util/ArrayList;", Native::List(values))
        .map_err(NatErr::Fatal)
}
fn first(vm: &mut Vm, args: &[JValue], nullable: bool) -> R {
    if args.get(1).is_some_and(|p| p.is_null_ref()) {
        return Err(NatErr::Throw(vm.err_npe()));
    }
    let it = iterator(vm, args[0])?;
    while more(vm, it)? {
        let value = next(vm, it)?;
        let accept = if let Some(predicate) = args.get(1) {
            let result = invoke(
                vm,
                *predicate,
                "invoke",
                "(Ljava/lang/Object;)Ljava/lang/Object;",
                vec![value],
            )?;
            boolean(vm, result)?
        } else {
            true
        };
        if accept {
            return Ok(value);
        }
    }
    if nullable {
        Ok(JValue::Null)
    } else {
        Err(no_element(vm))
    }
}
fn first_required(vm: &mut Vm, args: &[JValue]) -> R {
    first(vm, args, false)
}
fn first_nullable(vm: &mut Vm, args: &[JValue]) -> R {
    first(vm, args, true)
}
fn readonly(vm: &mut Vm, _args: &[JValue]) -> R {
    Err(NatErr::Throw(vm.throwable_of(
        "Ljava/lang/UnsupportedOperationException;",
        "Read-only sequence iterator",
    )))
}
pub(super) fn install(vm: &mut Vm) -> Result<(), JvmError> {
    vm.register_native(NativeEntry {
        class: "Lkotlin/text/StringsKt;",
        name: "lineSequence",
        sig: "(Ljava/lang/CharSequence;)Lkotlin/sequences/Sequence;",
        instance: false,
        f: line_sequence,
    })?;
    vm.register_native(NativeEntry {
        class: "Lkotlin/sequences/Sequence;",
        name: "iterator",
        sig: "()Ljava/util/Iterator;",
        instance: true,
        f: list_iterator,
    })?;
    for (class, f) in [
        (LINES, line_iterator as dexvm::vm::NativeFn),
        (TRANSFORM, transform_iterator),
    ] {
        vm.register_native(NativeEntry {
            class,
            name: "iterator",
            sig: "()Ljava/util/Iterator;",
            instance: true,
            f,
        })?;
        let id = vm.ensure_class_by_desc(class)?;
        let interface = vm.ensure_class_by_desc("Lkotlin/sequences/Sequence;")?;
        vm.classes[id as usize].interfaces.push(interface);
    }
    for (class, has, next) in [
        (
            LINE_ITER,
            line_has_next as dexvm::vm::NativeFn,
            line_next as dexvm::vm::NativeFn,
        ),
        (TRANSFORM_ITER, transform_has_next, transform_next),
    ] {
        for (name, sig, f) in [
            ("hasNext", "()Z", has),
            ("next", "()Ljava/lang/Object;", next),
            ("remove", "()V", readonly),
        ] {
            vm.register_native(NativeEntry {
                class,
                name,
                sig,
                instance: true,
                f,
            })?;
        }
        let id = vm.ensure_class_by_desc(class)?;
        let interface = vm.ensure_class_by_desc("Ljava/util/Iterator;")?;
        vm.classes[id as usize].interfaces.push(interface);
    }
    for(name,sig,f)in[
        ("map","(Lkotlin/sequences/Sequence;Lkotlin/jvm/functions/Function1;)Lkotlin/sequences/Sequence;",map as dexvm::vm::NativeFn),
        ("filter","(Lkotlin/sequences/Sequence;Lkotlin/jvm/functions/Function1;)Lkotlin/sequences/Sequence;",filter),
        ("toList","(Lkotlin/sequences/Sequence;)Ljava/util/List;",to_list),
        ("first","(Lkotlin/sequences/Sequence;)Ljava/lang/Object;",first_required),
        ("first","(Lkotlin/sequences/Sequence;Lkotlin/jvm/functions/Function1;)Ljava/lang/Object;",first_required),
        ("firstOrNull","(Lkotlin/sequences/Sequence;)Ljava/lang/Object;",first_nullable),
        ("firstOrNull","(Lkotlin/sequences/Sequence;Lkotlin/jvm/functions/Function1;)Ljava/lang/Object;",first_nullable),
        ("find","(Lkotlin/sequences/Sequence;Lkotlin/jvm/functions/Function1;)Ljava/lang/Object;",first_nullable),
    ]{vm.register_native(NativeEntry{class:"Lkotlin/sequences/SequencesKt;",name,sig,instance:false,f})?;}
    Ok(())
}
