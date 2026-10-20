//! Kotlin capture groups differ from groupValues: an unmatched group is null,
//! and matched groups retain their UTF-16 range (including empty captures).
use dexvm::vm::object::Native;
use dexvm::vm::{error::JvmError, NatErr, NativeEntry, Vm};
use dexvm::JValue;
type R = Result<JValue, NatErr>;
fn groups(vm: &mut Vm, args: &[JValue]) -> R {
    let Some(Native::Matcher(state)) = vm.payload_of(args[0]) else {
        return Err(NatErr::Throw(vm.err_npe()));
    };
    if state.groups.len() > 4096 || state.text.len() > 1_000_000 {
        return Err(NatErr::Fatal(JvmError::BudgetExceeded));
    }
    let mut out = vec![];
    vm.budget -= (state.text.len() + state.groups.len()) as i64;
    if vm.budget <= 0 {
        return Err(NatErr::Fatal(JvmError::BudgetExceeded));
    }
    for range in state.groups {
        let Some((start, end)) = range else {
            out.push(JValue::Null);
            continue;
        };
        vm.budget -= end as i64;
        if vm.budget <= 0 {
            return Err(NatErr::Fatal(JvmError::BudgetExceeded));
        }
        let text = state
            .text
            .get(start..end)
            .ok_or_else(|| NatErr::Throw(vm.err_iae("Invalid capture range")))?;
        let first = state.text[..start].encode_utf16().count() as i32;
        let last = first + text.encode_utf16().count() as i32 - 1;
        let value = vm.alloc_string(text);
        let range = vm
            .alloc_native("Lkotlin/ranges/IntRange;", Native::IntRange(first, last))
            .map_err(NatErr::Fatal)?;
        out.push(
            vm.alloc_native("Lkotlin/text/MatchGroup;", Native::List(vec![value, range]))
                .map_err(NatErr::Fatal)?,
        );
    }
    vm.alloc_native("Lkotlin/text/MatchGroupCollection;", Native::List(out))
        .map_err(NatErr::Fatal)
}
fn get(vm: &mut Vm, args: &[JValue]) -> R {
    match vm.payload_of(args[0]) {
        Some(Native::List(values)) => values
            .get(args[1].as_int() as usize)
            .copied()
            .ok_or_else(|| NatErr::Throw(vm.err_ioobe(args[1].as_int()))),
        _ => Err(NatErr::Throw(vm.err_npe())),
    }
}
fn size(vm: &mut Vm, args: &[JValue]) -> R {
    match vm.payload_of(args[0]) {
        Some(Native::List(values)) => Ok(JValue::Int(values.len() as i32)),
        _ => Err(NatErr::Throw(vm.err_npe())),
    }
}
fn value(vm: &mut Vm, args: &[JValue]) -> R {
    match vm.payload_of(args[0]) {
        Some(Native::List(values)) => values
            .first()
            .copied()
            .ok_or_else(|| NatErr::Throw(vm.err_npe())),
        Some(Native::Str(value)) => Ok(vm.alloc_string(&value)),
        _ => Err(NatErr::Throw(vm.err_npe())),
    }
}
fn range(vm: &mut Vm, args: &[JValue]) -> R {
    match vm.payload_of(args[0]) {
        Some(Native::List(values)) => values
            .get(1)
            .copied()
            .ok_or_else(|| NatErr::Throw(vm.err_npe())),
        _ => Err(NatErr::Throw(vm.err_npe())),
    }
}
pub(super) fn install(vm: &mut Vm) -> Result<(), JvmError> {
    for (class, name, sig, f) in [
        (
            "Lkotlin/text/MatcherMatchResult;",
            "getGroups",
            "()Lkotlin/text/MatchGroupCollection;",
            groups as dexvm::vm::NativeFn,
        ),
        (
            "Lkotlin/text/MatchResult;",
            "getGroups",
            "()Lkotlin/text/MatchGroupCollection;",
            groups,
        ),
        (
            "Lkotlin/text/MatchGroupCollection;",
            "get",
            "(I)Lkotlin/text/MatchGroup;",
            get,
        ),
        ("Lkotlin/text/MatchGroupCollection;", "getSize", "()I", size),
        ("Lkotlin/text/MatchGroupCollection;", "size", "()I", size),
        (
            "Lkotlin/text/MatchGroup;",
            "getValue",
            "()Ljava/lang/String;",
            value,
        ),
        (
            "Lkotlin/text/MatchGroup;",
            "getRange",
            "()Lkotlin/ranges/IntRange;",
            range,
        ),
    ] {
        vm.register_native(NativeEntry {
            class,
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
    fn groups_keep_null_empty_and_utf16_positions() {
        let mut vm = Vm::new(vec![], Box::new(std::io::sink())).unwrap();
        install(&mut vm).unwrap();
        let matched = vm
            .alloc_native(
                "Lkotlin/text/MatcherMatchResult;",
                Native::Matcher(dexvm::vm::object::MatcherState {
                    pattern: fancy_regex::Regex::new("(😀)(x)?()").unwrap(),
                    text: "a😀".into(),
                    pos: 5,
                    last: Some((1, 5)),
                    groups: vec![Some((1, 5)), Some((1, 5)), None, Some((5, 5))],
                }),
            )
            .unwrap();
        let collection = groups(&mut vm, &[matched]).unwrap();
        assert_eq!(size(&mut vm, &[collection]).unwrap(), JValue::Int(4));
        assert_eq!(
            get(&mut vm, &[collection, JValue::Int(2)]).unwrap(),
            JValue::Null
        );
        let emoji = get(&mut vm, &[collection, JValue::Int(1)]).unwrap();
        let text = value(&mut vm, &[emoji]).unwrap();
        assert_eq!(vm.str_of_jvalue(text).unwrap(), "😀");
        let r = range(&mut vm, &[emoji]).unwrap();
        assert!(matches!(vm.payload_of(r), Some(Native::IntRange(1, 2))));
        let empty = get(&mut vm, &[collection, JValue::Int(3)]).unwrap();
        let r = range(&mut vm, &[empty]).unwrap();
        assert!(matches!(vm.payload_of(r), Some(Native::IntRange(3, 2))));
        assert!(get(&mut vm, &[collection, JValue::Int(4)]).is_err());
    }
}
