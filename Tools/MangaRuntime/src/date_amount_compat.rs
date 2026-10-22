//! Java durations retain normalized seconds/nanoseconds. Kotlin's separate
//! pinned millisecond Duration ABI is deliberately not used here.
use dexvm::vm::{error::JvmError, object::Native, NatErr, NativeEntry, Vm};
use dexvm::JValue;
type R = Result<JValue, NatErr>;
const DURATION: &str = "Ljava/time/Duration;";
const INSTANT: &str = "Ljava/time/Instant;";
const BILLION: i128 = 1_000_000_000;

fn overflow(vm: &mut Vm) -> NatErr {
    NatErr::Throw(vm.throwable_of(
        "Ljava/lang/ArithmeticException;",
        "Time arithmetic overflow",
    ))
}
pub(super) fn duration(vm: &mut Vm, value: JValue) -> Result<i128, NatErr> {
    if value.is_null_ref() {
        return Err(NatErr::Throw(vm.err_npe()));
    }
    let Some(class) = vm.object_class(value) else {
        return Err(NatErr::Throw(vm.err_npe()));
    };
    if vm.str_of(vm.classes[class as usize].descriptor) != DURATION {
        return Err(NatErr::Throw(vm.err_iae("Expected a Java duration")));
    }
    let fields = &vm.arena.objects[value.as_obj() as usize].fields;
    if fields.len() != 2 {
        return Err(NatErr::Throw(vm.err_iae("Invalid Java duration")));
    }
    Ok(i128::from(fields[0].as_long()) * BILLION + i128::from(fields[1].as_int()))
}
fn new_duration(vm: &mut Vm, nanos: i128) -> R {
    let seconds = i64::try_from(nanos.div_euclid(BILLION)).map_err(|_| overflow(vm))?;
    let value = vm
        .alloc_native(DURATION, Native::Opaque)
        .map_err(NatErr::Fatal)?;
    vm.arena.objects[value.as_obj() as usize].fields = vec![
        JValue::Long(seconds),
        JValue::Int(nanos.rem_euclid(BILLION) as i32),
    ];
    Ok(value)
}
pub(super) fn instant_nanos(vm: &mut Vm, value: JValue) -> Result<i128, NatErr> {
    if value.is_null_ref() {
        return Err(NatErr::Throw(vm.err_npe()));
    }
    let Some(Native::EpochMillis(millis)) = vm.payload_of(value) else {
        return Err(NatErr::Throw(vm.err_iae("Expected an instant")));
    };
    let class = vm
        .object_class(value)
        .ok_or_else(|| NatErr::Throw(vm.err_npe()))?;
    let remainder = if vm.str_of(vm.classes[class as usize].descriptor) == INSTANT {
        vm.arena.objects[value.as_obj() as usize]
            .fields
            .first()
            .map_or(0, |v| v.as_int())
    } else {
        0
    };
    Ok(i128::from(millis) * 1_000_000 + i128::from(remainder))
}
pub(super) fn new_instant(vm: &mut Vm, nanos: i128) -> R {
    let millis = i64::try_from(nanos.div_euclid(1_000_000)).map_err(|_| overflow(vm))?;
    let value = vm
        .alloc_native(INSTANT, Native::EpochMillis(millis))
        .map_err(NatErr::Fatal)?;
    vm.arena.objects[value.as_obj() as usize].fields =
        vec![JValue::Int(nanos.rem_euclid(1_000_000) as i32)];
    Ok(value)
}
fn of_seconds(vm: &mut Vm, args: &[JValue]) -> R {
    new_duration(
        vm,
        i128::from(args[0].as_long()) * BILLION
            + args.get(1).map_or(0, |v| i128::from(v.as_long())),
    )
}
fn scaled(vm: &mut Vm, args: &[JValue], scale: i128) -> R {
    new_duration(vm, i128::from(args[0].as_long()) * scale)
}
fn of_nanos(vm: &mut Vm, args: &[JValue]) -> R {
    scaled(vm, args, 1)
}
fn of_millis(vm: &mut Vm, args: &[JValue]) -> R {
    scaled(vm, args, 1_000_000)
}
fn of_minutes(vm: &mut Vm, args: &[JValue]) -> R {
    scaled(vm, args, 60 * BILLION)
}
fn of_hours(vm: &mut Vm, args: &[JValue]) -> R {
    scaled(vm, args, 3600 * BILLION)
}
fn of_days(vm: &mut Vm, args: &[JValue]) -> R {
    scaled(vm, args, 86400 * BILLION)
}
fn multiplied(vm: &mut Vm, args: &[JValue]) -> R {
    let nanos = duration(vm, args[0])?
        .checked_mul(i128::from(args[1].as_long()))
        .ok_or_else(|| overflow(vm))?;
    new_duration(vm, nanos)
}
fn duration_plus(vm: &mut Vm, args: &[JValue]) -> R {
    let nanos = duration(vm, args[0])? + duration(vm, args[1])?;
    new_duration(vm, nanos)
}
fn duration_minus(vm: &mut Vm, args: &[JValue]) -> R {
    let nanos = duration(vm, args[0])? - duration(vm, args[1])?;
    new_duration(vm, nanos)
}
fn negated(vm: &mut Vm, args: &[JValue]) -> R {
    let nanos = -duration(vm, args[0])?;
    new_duration(vm, nanos)
}
fn seconds(vm: &mut Vm, args: &[JValue]) -> R {
    Ok(JValue::Long(
        (duration(vm, args[0])?.div_euclid(BILLION)) as i64,
    ))
}
fn nano(vm: &mut Vm, args: &[JValue]) -> R {
    Ok(JValue::Int(
        duration(vm, args[0])?.rem_euclid(BILLION) as i32
    ))
}
fn to_millis(vm: &mut Vm, args: &[JValue]) -> R {
    let value = i64::try_from(duration(vm, args[0])? / 1_000_000).map_err(|_| overflow(vm))?;
    Ok(JValue::Long(value))
}
fn to_nanos(vm: &mut Vm, args: &[JValue]) -> R {
    let value = i64::try_from(duration(vm, args[0])?).map_err(|_| overflow(vm))?;
    Ok(JValue::Long(value))
}
fn to_minutes(vm: &mut Vm, args: &[JValue]) -> R {
    Ok(JValue::Long(
        (duration(vm, args[0])?.div_euclid(BILLION) / 60) as i64,
    ))
}
fn to_hours(vm: &mut Vm, args: &[JValue]) -> R {
    Ok(JValue::Long(
        (duration(vm, args[0])?.div_euclid(BILLION) / 3600) as i64,
    ))
}
fn to_days(vm: &mut Vm, args: &[JValue]) -> R {
    Ok(JValue::Long(
        (duration(vm, args[0])?.div_euclid(BILLION) / 86400) as i64,
    ))
}
fn negative(vm: &mut Vm, args: &[JValue]) -> R {
    Ok(JValue::Int(i32::from(duration(vm, args[0])? < 0)))
}
fn zero(vm: &mut Vm, args: &[JValue]) -> R {
    Ok(JValue::Int(i32::from(duration(vm, args[0])? == 0)))
}
fn between(vm: &mut Vm, args: &[JValue]) -> R {
    let nanos = instant_nanos(vm, args[1])? - instant_nanos(vm, args[0])?;
    new_duration(vm, nanos)
}
fn now(vm: &mut Vm, _: &[JValue]) -> R {
    let nanos = match std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH) {
        Ok(value) => value.as_nanos() as i128,
        Err(value) => -(value.duration().as_nanos() as i128),
    };
    new_instant(vm, nanos)
}
fn epoch_seconds(vm: &mut Vm, args: &[JValue]) -> R {
    new_instant(
        vm,
        i128::from(args[0].as_long()) * BILLION
            + args.get(1).map_or(0, |v| i128::from(v.as_long())),
    )
}
fn epoch_millis(vm: &mut Vm, args: &[JValue]) -> R {
    new_instant(vm, i128::from(args[0].as_long()) * 1_000_000)
}
fn instant_seconds(vm: &mut Vm, args: &[JValue]) -> R {
    Ok(JValue::Long(
        (instant_nanos(vm, args[0])?.div_euclid(BILLION)) as i64,
    ))
}
fn instant_nano(vm: &mut Vm, args: &[JValue]) -> R {
    Ok(JValue::Int(
        instant_nanos(vm, args[0])?.rem_euclid(BILLION) as i32
    ))
}
fn instant_plus(vm: &mut Vm, args: &[JValue]) -> R {
    let value = instant_nanos(vm, args[0])? + duration(vm, args[1])?;
    new_instant(vm, value)
}
fn instant_minus(vm: &mut Vm, args: &[JValue]) -> R {
    let value = instant_nanos(vm, args[0])? - duration(vm, args[1])?;
    new_instant(vm, value)
}
fn parse_instant(vm: &mut Vm, args: &[JValue]) -> R {
    let text = vm
        .str_of_jvalue(args[0])
        .ok_or_else(|| NatErr::Throw(vm.err_npe()))?;
    if text.len() > 128 {
        return Err(NatErr::Throw(vm.err_iae("Instant text exceeds host limit")));
    }
    let date = chrono::DateTime::parse_from_rfc3339(&text).map_err(|_| {
        NatErr::Throw(vm.throwable_of(
            "Ljava/time/format/DateTimeParseException;",
            "Invalid ISO instant",
        ))
    })?;
    new_instant(
        vm,
        i128::from(date.timestamp()) * BILLION + i128::from(date.timestamp_subsec_nanos()),
    )
}
fn same_type(vm: &Vm, value: JValue, desc: &str) -> bool {
    vm.object_class(value)
        .is_some_and(|class| vm.str_of(vm.classes[class as usize].descriptor) == desc)
}
fn instant_equal(vm: &mut Vm, args: &[JValue]) -> R {
    Ok(JValue::Int(i32::from(
        same_type(vm, args[1], INSTANT)
            && instant_nanos(vm, args[0])? == instant_nanos(vm, args[1])?,
    )))
}
fn duration_equal(vm: &mut Vm, args: &[JValue]) -> R {
    Ok(JValue::Int(i32::from(
        same_type(vm, args[1], DURATION) && duration(vm, args[0])? == duration(vm, args[1])?,
    )))
}
fn hash_nanos(nanos: i128) -> JValue {
    let seconds = nanos.div_euclid(BILLION) as i64;
    JValue::Int(
        ((seconds ^ (seconds >> 32)) as i32)
            .wrapping_add((nanos.rem_euclid(BILLION) as i32).wrapping_mul(51)),
    )
}
fn instant_hash(vm: &mut Vm, args: &[JValue]) -> R {
    Ok(hash_nanos(instant_nanos(vm, args[0])?))
}
fn duration_hash(vm: &mut Vm, args: &[JValue]) -> R {
    Ok(hash_nanos(duration(vm, args[0])?))
}
fn instant_compare(vm: &mut Vm, args: &[JValue]) -> R {
    Ok(JValue::Int(
        instant_nanos(vm, args[0])?.cmp(&instant_nanos(vm, args[1])?) as i32,
    ))
}
fn duration_compare(vm: &mut Vm, args: &[JValue]) -> R {
    Ok(JValue::Int(
        duration(vm, args[0])?.cmp(&duration(vm, args[1])?) as i32,
    ))
}
fn instant_string(vm: &mut Vm, args: &[JValue]) -> R {
    let nanos = instant_nanos(vm, args[0])?;
    let date = chrono::DateTime::from_timestamp(
        nanos.div_euclid(BILLION) as i64,
        nanos.rem_euclid(BILLION) as u32,
    )
    .ok_or_else(|| {
        NatErr::Throw(vm.throwable_of(
            "Ljava/time/DateTimeException;",
            "Instant exceeds supported formatter range",
        ))
    })?;
    Ok(vm.alloc_string(&date.to_rfc3339_opts(chrono::SecondsFormat::AutoSi, true)))
}
fn duration_string(vm: &mut Vm, args: &[JValue]) -> R {
    let nanos = duration(vm, args[0])?;
    if nanos == 0 {
        return Ok(vm.alloc_string("PT0S"));
    }
    let sign = if nanos < 0 { "-" } else { "" };
    let value = nanos.abs();
    let seconds = value / BILLION;
    let mut text = String::from("PT");
    if seconds / 3600 != 0 {
        text.push_str(&format!("{sign}{}H", seconds / 3600));
    }
    if seconds / 60 % 60 != 0 {
        text.push_str(&format!("{sign}{}M", seconds / 60 % 60));
    }
    let fraction = value % BILLION;
    if seconds % 60 != 0 || fraction != 0 || text == "PT" {
        text.push_str(&format!("{sign}{}", seconds % 60));
        if fraction != 0 {
            text.push('.');
            text.push_str(format!("{fraction:09}").trim_end_matches('0'));
        }
        text.push('S');
    }
    Ok(vm.alloc_string(&text))
}
fn instant_scaled(vm: &mut Vm, args: &[JValue], scale: i128) -> R {
    let nanos = instant_nanos(vm, args[0])? + i128::from(args[1].as_long()) * scale;
    new_instant(vm, nanos)
}
macro_rules! instant_scale {
    ($name:ident, $scale:expr) => {
        fn $name(vm: &mut Vm, args: &[JValue]) -> R {
            instant_scaled(vm, args, $scale)
        }
    };
}
instant_scale!(plus_seconds, BILLION);
instant_scale!(plus_millis, 1_000_000);
instant_scale!(plus_nanos, 1);
instant_scale!(minus_seconds, -BILLION);
instant_scale!(minus_millis, -1_000_000);
instant_scale!(minus_nanos, -1);
pub(super) fn install(vm: &mut Vm) -> Result<(), JvmError> {
    for (class, name, sig, f) in [
        (
            DURATION,
            "equals",
            "(Ljava/lang/Object;)Z",
            duration_equal as dexvm::vm::NativeFn,
        ),
        (DURATION, "hashCode", "()I", duration_hash),
        (
            DURATION,
            "toString",
            "()Ljava/lang/String;",
            duration_string,
        ),
        (
            DURATION,
            "compareTo",
            "(Ljava/time/Duration;)I",
            duration_compare,
        ),
        (INSTANT, "equals", "(Ljava/lang/Object;)Z", instant_equal),
        (INSTANT, "hashCode", "()I", instant_hash),
        (INSTANT, "toString", "()Ljava/lang/String;", instant_string),
        (
            INSTANT,
            "compareTo",
            "(Ljava/time/Instant;)I",
            instant_compare,
        ),
        (
            INSTANT,
            "plusSeconds",
            "(J)Ljava/time/Instant;",
            plus_seconds,
        ),
        (INSTANT, "plusMillis", "(J)Ljava/time/Instant;", plus_millis),
        (INSTANT, "plusNanos", "(J)Ljava/time/Instant;", plus_nanos),
        (
            INSTANT,
            "minusSeconds",
            "(J)Ljava/time/Instant;",
            minus_seconds,
        ),
        (
            INSTANT,
            "minusMillis",
            "(J)Ljava/time/Instant;",
            minus_millis,
        ),
        (INSTANT, "minusNanos", "(J)Ljava/time/Instant;", minus_nanos),
    ] {
        vm.register_native(NativeEntry {
            class,
            name,
            sig,
            instance: true,
            f,
        })?;
    }
    for (name, sig, instance, f) in [
        (
            "ofSeconds",
            "(J)Ljava/time/Duration;",
            false,
            of_seconds as dexvm::vm::NativeFn,
        ),
        ("ofSeconds", "(JJ)Ljava/time/Duration;", false, of_seconds),
        ("ofNanos", "(J)Ljava/time/Duration;", false, of_nanos),
        ("ofMillis", "(J)Ljava/time/Duration;", false, of_millis),
        ("ofMinutes", "(J)Ljava/time/Duration;", false, of_minutes),
        ("ofHours", "(J)Ljava/time/Duration;", false, of_hours),
        ("ofDays", "(J)Ljava/time/Duration;", false, of_days),
        (
            "between",
            "(Ljava/time/temporal/Temporal;Ljava/time/temporal/Temporal;)Ljava/time/Duration;",
            false,
            between,
        ),
        ("multipliedBy", "(J)Ljava/time/Duration;", true, multiplied),
        (
            "plus",
            "(Ljava/time/Duration;)Ljava/time/Duration;",
            true,
            duration_plus,
        ),
        (
            "minus",
            "(Ljava/time/Duration;)Ljava/time/Duration;",
            true,
            duration_minus,
        ),
        ("negated", "()Ljava/time/Duration;", true, negated),
        ("getSeconds", "()J", true, seconds),
        ("getNano", "()I", true, nano),
        ("toMillis", "()J", true, to_millis),
        ("toNanos", "()J", true, to_nanos),
        ("toMinutes", "()J", true, to_minutes),
        ("toHours", "()J", true, to_hours),
        ("toDays", "()J", true, to_days),
        ("isNegative", "()Z", true, negative),
        ("isZero", "()Z", true, zero),
    ] {
        vm.register_native(NativeEntry {
            class: DURATION,
            name,
            sig,
            instance,
            f,
        })?;
    }
    for (name, sig, instance, f) in [
        (
            "now",
            "()Ljava/time/Instant;",
            false,
            now as dexvm::vm::NativeFn,
        ),
        (
            "ofEpochSecond",
            "(J)Ljava/time/Instant;",
            false,
            epoch_seconds,
        ),
        (
            "ofEpochSecond",
            "(JJ)Ljava/time/Instant;",
            false,
            epoch_seconds,
        ),
        (
            "ofEpochMilli",
            "(J)Ljava/time/Instant;",
            false,
            epoch_millis,
        ),
        (
            "parse",
            "(Ljava/lang/CharSequence;)Ljava/time/Instant;",
            false,
            parse_instant,
        ),
        ("getEpochSecond", "()J", true, instant_seconds),
        ("getNano", "()I", true, instant_nano),
        (
            "plus",
            "(Ljava/time/temporal/TemporalAmount;)Ljava/time/Instant;",
            true,
            instant_plus,
        ),
        (
            "minus",
            "(Ljava/time/temporal/TemporalAmount;)Ljava/time/Instant;",
            true,
            instant_minus,
        ),
    ] {
        vm.register_native(NativeEntry {
            class: INSTANT,
            name,
            sig,
            instance,
            f,
        })?;
    }
    let amount = super::kotlin_type_compat::marker(vm, "Ljava/time/temporal/TemporalAmount;");
    let class = vm.ensure_class_by_desc(DURATION)?;
    vm.classes[class as usize].interfaces.push(amount);
    let zero = new_duration(vm, 0)
        .map_err(|_| JvmError::Fatal("Cannot initialize Duration.ZERO".into()))?;
    super::multipart_compat::static_value(vm, DURATION, "ZERO", DURATION, zero)?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn relative_dates_preserve_negative_fractional_instants_and_overflows() {
        let mut vm = Vm::new(vec![], Box::new(std::io::sink())).unwrap();
        install(&mut vm).unwrap();
        let d = of_seconds(&mut vm, &[JValue::Long(-1), JValue::Long(999_999_999)]).unwrap();
        assert_eq!(seconds(&mut vm, &[d]).unwrap(), JValue::Long(-1));
        assert_eq!(nano(&mut vm, &[d]).unwrap(), JValue::Int(999_999_999));
        assert_eq!(to_millis(&mut vm, &[d]).unwrap(), JValue::Long(0));
        let instant = epoch_seconds(&mut vm, &[JValue::Long(0), JValue::Long(-1)]).unwrap();
        assert_eq!(
            instant_seconds(&mut vm, &[instant]).unwrap(),
            JValue::Long(-1)
        );
        assert_eq!(
            instant_nano(&mut vm, &[instant]).unwrap(),
            JValue::Int(999_999_999)
        );
        let minute = of_minutes(&mut vm, &[JValue::Long(1)]).unwrap();
        let eight = multiplied(&mut vm, &[minute, JValue::Long(8)]).unwrap();
        let older = instant_minus(&mut vm, &[instant, eight]).unwrap();
        assert_eq!(instant_nanos(&mut vm, older).unwrap(), -480_000_000_001);
        let diff = between(&mut vm, &[older, instant]).unwrap();
        assert_eq!(to_millis(&mut vm, &[diff]).unwrap(), JValue::Long(480_000));
        assert!(matches!(
            of_days(&mut vm, &[JValue::Long(i64::MAX)]),
            Err(NatErr::Throw(_))
        ));
        let huge = of_seconds(&mut vm, &[JValue::Long(i64::MAX)]).unwrap();
        assert!(matches!(
            multiplied(&mut vm, &[huge, JValue::Long(i64::MAX)]),
            Err(NatErr::Throw(_))
        ));
        let text = vm.alloc_string("1969-12-31T23:59:59.999999999Z");
        let parsed = parse_instant(&mut vm, &[text]).unwrap();
        assert_eq!(instant_nanos(&mut vm, parsed).unwrap(), -1);
        vm.gc(&[parsed.as_obj(), d.as_obj()]);
        assert_eq!(
            instant_nano(&mut vm, &[parsed]).unwrap(),
            JValue::Int(999_999_999)
        );
    }
}
