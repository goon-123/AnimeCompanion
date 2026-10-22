//! Java TimeUnit arithmetic uses saturating multiplication and truncation
//! toward zero, including negative durations. It is not a floating-point scale.
use dexvm::vm::{
    error::JvmError,
    object::{ArrayData, Native},
    FieldRef, NatErr, NativeEntry, Vm,
};
use dexvm::JValue;
type R = Result<JValue, NatErr>;
const CLASS: &str = "Ljava/util/concurrent/TimeUnit;";
const NAMES: [&str; 7] = [
    "NANOSECONDS",
    "MICROSECONDS",
    "MILLISECONDS",
    "SECONDS",
    "MINUTES",
    "HOURS",
    "DAYS",
];
const NANOS: [i128; 7] = [
    1,
    1_000,
    1_000_000,
    1_000_000_000,
    60_000_000_000,
    3_600_000_000_000,
    86_400_000_000_000,
];
fn ordinal(vm: &mut Vm, value: JValue) -> Result<usize, NatErr> {
    if value.is_null_ref() {
        return Err(NatErr::Throw(vm.err_npe()));
    }
    let Some(class) = vm.object_class(value) else {
        return Err(NatErr::Throw(vm.err_iae("Expected TimeUnit")));
    };
    if vm.str_of(vm.classes[class as usize].descriptor) != CLASS {
        return Err(NatErr::Throw(vm.err_iae("Expected TimeUnit")));
    }
    match vm.payload_of(value) {
        Some(Native::Enum { ordinal, .. }) if (0..7).contains(&ordinal) => Ok(ordinal as usize),
        _ => Err(NatErr::Throw(vm.err_iae("Invalid TimeUnit"))),
    }
}
fn clamp(value: i128) -> JValue {
    JValue::Long(value.clamp(i128::from(i64::MIN), i128::from(i64::MAX)) as i64)
}
fn convert(vm: &mut Vm, args: &[JValue]) -> R {
    let target = ordinal(vm, args[0])?;
    let source = ordinal(vm, args[2])?;
    Ok(clamp(
        i128::from(args[1].as_long()) * NANOS[source] / NANOS[target],
    ))
}
fn convert_duration(vm: &mut Vm, args: &[JValue]) -> R {
    let target = ordinal(vm, args[0])?;
    Ok(clamp(
        super::date_amount_compat::duration(vm, args[1])? / NANOS[target],
    ))
}
fn scaled(vm: &mut Vm, args: &[JValue], target: usize) -> R {
    let source = ordinal(vm, args[0])?;
    Ok(clamp(
        i128::from(args[1].as_long()) * NANOS[source] / NANOS[target],
    ))
}
macro_rules! scale {
    ($name:ident, $target:literal) => {
        fn $name(vm: &mut Vm, args: &[JValue]) -> R {
            scaled(vm, args, $target)
        }
    };
}
scale!(to_nanos, 0);
scale!(to_micros, 1);
scale!(to_millis, 2);
scale!(to_seconds, 3);
scale!(to_minutes, 4);
scale!(to_hours, 5);
scale!(to_days, 6);
fn constant(vm: &mut Vm, name: &str) -> R {
    let fr = FieldRef {
        class_desc: vm.intern(CLASS),
        name: vm.intern(name),
        ty: vm.intern(CLASS),
    };
    vm.static_field_get(fr).map_err(NatErr::Fatal)
}
fn values(vm: &mut Vm, _args: &[JValue]) -> R {
    let values = NAMES
        .into_iter()
        .map(|name| constant(vm, name))
        .collect::<Result<Vec<_>, _>>()?;
    vm.alloc_native(
        "[Ljava/util/concurrent/TimeUnit;",
        Native::Array(ArrayData::Obj(values)),
    )
    .map_err(NatErr::Fatal)
}
fn value_of(vm: &mut Vm, args: &[JValue]) -> R {
    let name = vm
        .str_of_jvalue(args[0])
        .ok_or_else(|| NatErr::Throw(vm.err_npe()))?;
    if !NAMES.contains(&name.as_str()) {
        return Err(NatErr::Throw(vm.err_iae("Unknown TimeUnit")));
    }
    constant(vm, &name)
}
pub(super) fn install(vm: &mut Vm) -> Result<(), JvmError> {
    for (name, sig, instance, f) in [
        (
            "values",
            "()[Ljava/util/concurrent/TimeUnit;",
            false,
            values as dexvm::vm::NativeFn,
        ),
        (
            "valueOf",
            "(Ljava/lang/String;)Ljava/util/concurrent/TimeUnit;",
            false,
            value_of,
        ),
        (
            "convert",
            "(JLjava/util/concurrent/TimeUnit;)J",
            true,
            convert,
        ),
        ("convert", "(Ljava/time/Duration;)J", true, convert_duration),
        ("toNanos", "(J)J", true, to_nanos),
        ("toMicros", "(J)J", true, to_micros),
        ("toMillis", "(J)J", true, to_millis),
        ("toSeconds", "(J)J", true, to_seconds),
        ("toMinutes", "(J)J", true, to_minutes),
        ("toHours", "(J)J", true, to_hours),
        ("toDays", "(J)J", true, to_days),
    ] {
        vm.register_native(NativeEntry {
            class: CLASS,
            name,
            sig,
            instance,
            f,
        })?;
    }
    let id = vm.ensure_class_by_desc(CLASS)?;
    vm.classes[id as usize].superclass = Some(vm.ensure_class_by_desc("Ljava/lang/Enum;")?);
    for (ordinal, name) in NAMES.into_iter().enumerate() {
        let value = vm.alloc_native(
            CLASS,
            Native::Enum {
                name: name.into(),
                ordinal: ordinal as i32,
            },
        )?;
        super::multipart_compat::static_value(vm, CLASS, name, CLASS, value)?;
    }
    Ok(())
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn every_time_unit_pair_preserves_integer_truncation_and_signed_saturation() {
        let mut vm = Vm::new(vec![], Box::new(std::io::sink())).unwrap();
        install(&mut vm).unwrap();
        for (target, target_name) in NAMES.iter().enumerate() {
            let to = constant(&mut vm, target_name).unwrap();
            for (source, source_name) in NAMES.iter().enumerate() {
                let from = constant(&mut vm, source_name).unwrap();
                for input in [i64::MIN, i64::MIN + 1, -1_001, -1, 0, 1, 1_001, i64::MAX] {
                    assert_eq!(
                        convert(&mut vm, &[to, JValue::Long(input), from]).unwrap(),
                        clamp(i128::from(input) * NANOS[source] / NANOS[target])
                    );
                }
            }
        }
        let micros = constant(&mut vm, "MICROSECONDS").unwrap();
        assert_eq!(
            to_millis(&mut vm, &[micros, JValue::Long(-999)]).unwrap(),
            JValue::Long(0)
        );
        assert!(matches!(
            convert(&mut vm, &[micros, JValue::Long(1), JValue::Null]),
            Err(NatErr::Throw(_))
        ));
    }
}
