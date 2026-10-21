//! Kotlin capture groups differ from groupValues: an unmatched group is null,
//! and matched groups retain their UTF-16 range (including empty captures).
use dexvm::vm::object::Native;
use dexvm::vm::{error::JvmError, NatErr, NativeEntry, Vm};
use dexvm::JValue;
type R = Result<JValue, NatErr>;

fn pattern_compile(vm: &mut Vm, args: &[JValue]) -> R {
    let source = vm
        .str_of_jvalue(args[0])
        .ok_or_else(|| NatErr::Throw(vm.err_npe()))?;
    if source.len() > 65_536 || vm.budget <= source.len() as i64 {
        return Err(NatErr::Fatal(JvmError::BudgetExceeded));
    }
    vm.budget -= source.len() as i64 + 1;
    let flags = args.get(1).map(|v| v.as_int()).unwrap_or(0);
    if flags & !(2 | 4 | 8 | 16 | 32 | 64 | 256) != 0 {
        return Err(NatErr::Throw(vm.err_iae("Unsupported regex flags")));
    }
    let mut translated = if flags & 16 != 0 {
        fancy_regex::escape(&source).into_owned()
    } else {
        // Java Unicode block syntax used by normal accent stripping. Rust's
        // regex engine supports categories/scripts, but not Java block names.
        source
            .replace(r"\p{InCombiningDiacriticalMarks}", r"[\u{0300}-\u{036f}]")
            .replace(r"\P{InCombiningDiacriticalMarks}", r"[^\u{0300}-\u{036f}]")
    };
    for (bit, mode) in [(2, "i"), (4, "x"), (8, "m"), (32, "s")] {
        if flags & bit != 0 {
            translated = format!("(?{mode}){translated}");
        }
    }
    let re = fancy_regex::RegexBuilder::new(&translated)
        .backtrack_limit(1_000_000)
        .build()
        .map_err(|_| NatErr::Throw(vm.err_iae("Unsupported or invalid regex")))?;
    let value = vm
        .alloc_native("Ljava/util/regex/Pattern;", Native::Pattern { re, source })
        .map_err(NatErr::Fatal)?;
    vm.arena.objects[value.as_obj() as usize].fields = vec![JValue::Int(flags)];
    Ok(value)
}
fn pattern_flags(vm: &mut Vm, args: &[JValue]) -> R {
    let JValue::Obj(id) = args[0] else {
        return Err(NatErr::Throw(vm.err_npe()));
    };
    Ok(vm.arena.objects[id as usize]
        .fields
        .first()
        .copied()
        .unwrap_or(JValue::Int(0)))
}
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
    for sig in [
        "(Ljava/lang/String;)Ljava/util/regex/Pattern;",
        "(Ljava/lang/String;I)Ljava/util/regex/Pattern;",
    ] {
        vm.register_native(NativeEntry {
            class: "Ljava/util/regex/Pattern;",
            name: "compile",
            sig,
            instance: false,
            f: pattern_compile,
        })?;
    }
    vm.register_native(NativeEntry {
        class: "Ljava/util/regex/Pattern;",
        name: "flags",
        sig: "()I",
        instance: true,
        f: pattern_flags,
    })?;
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
    fn java_unicode_blocks_compile_and_flags_preserve_matching_and_pattern_identity() {
        let mut vm = Vm::new(vec![], Box::new(std::io::sink())).unwrap();
        install(&mut vm).unwrap();
        let source = vm.alloc_string(r"\p{InCombiningDiacriticalMarks}+");
        let pattern = pattern_compile(&mut vm, &[source]).unwrap();
        let Some(Native::Pattern { re, source }) = vm.payload_of(pattern) else {
            panic!("Missing pattern")
        };
        assert_eq!(source, r"\p{InCombiningDiacriticalMarks}+");
        assert_eq!(re.replace_all("Cafe\u{301}", ""), "Cafe");
        let source = vm.alloc_string("owned.*");
        let pattern = pattern_compile(&mut vm, &[source, JValue::Int(2 | 16)]).unwrap();
        assert_eq!(pattern_flags(&mut vm, &[pattern]).unwrap(), JValue::Int(18));
        let Some(Native::Pattern { re, .. }) = vm.payload_of(pattern) else {
            panic!("Missing pattern")
        };
        assert!(re.is_match("OWNED.*").unwrap());
        assert!(!re.is_match("owned text").unwrap());
        assert!(pattern_compile(&mut vm, &[source, JValue::Int(128)]).is_err());
        vm.budget = 0;
        assert!(matches!(
            pattern_compile(&mut vm, &[source]),
            Err(NatErr::Fatal(JvmError::BudgetExceeded))
        ));
    }
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
