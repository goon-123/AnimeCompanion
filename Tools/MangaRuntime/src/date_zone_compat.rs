//! IANA zone rules are compiled in. Guest code never reads host zone files or
//! environment variables; the Swift host supplies the device's default ID.
use chrono::{DateTime, Datelike, LocalResult, Offset, TimeZone, Utc};
use chrono_tz::{GapInfo, Tz};
use dexvm::vm::error::JvmError;
use dexvm::vm::object::Native;
use dexvm::vm::{NatErr, NativeEntry, Vm};
use dexvm::JValue;

type R = Result<JValue, NatErr>;
const ZONE: &str = "Ljava/time/ZoneId;";
const ZONED: &str = "Ljava/time/ZonedDateTime;";
const DAY_MS: i64 = 86_400_000;

#[derive(Clone, Copy)]
enum Zone {
    Fixed(i32),
    Region(Tz),
}
fn error(vm: &mut Vm, message: &str) -> NatErr {
    NatErr::Throw(vm.throwable_of("Ljava/time/DateTimeException;", message))
}
fn offset(text: &str) -> Option<i32> {
    if matches!(text, "Z" | "UTC" | "GMT" | "UT") {
        return Some(0);
    }
    let text = text
        .strip_prefix("UTC")
        .or_else(|| text.strip_prefix("GMT"))
        .or_else(|| text.strip_prefix("UT"))
        .unwrap_or(text);
    let sign = match text.as_bytes().first()? {
        b'+' => 1,
        b'-' => -1,
        _ => return None,
    };
    let rest = &text[1..];
    let digits = if rest.contains(':') {
        let parts: Vec<_> = rest.split(':').collect();
        if !(2..=3).contains(&parts.len()) || parts.iter().any(|p| p.len() != 2) {
            return None;
        }
        parts.concat()
    } else {
        rest.to_owned()
    };
    if ![1, 2, 4, 6].contains(&digits.len()) || !digits.bytes().all(|c| c.is_ascii_digit()) {
        return None;
    }
    let hours: i32 = digits[..digits.len().min(2)].parse().ok()?;
    let minutes: i32 = if digits.len() >= 4 {
        digits[2..4].parse().ok()?
    } else {
        0
    };
    let seconds: i32 = if digits.len() == 6 {
        digits[4..6].parse().ok()?
    } else {
        0
    };
    let value = hours * 3600 + minutes * 60 + seconds;
    (hours <= 18 && minutes < 60 && seconds < 60 && value <= 64_800).then_some(sign * value)
}
fn parse_zone(text: &str) -> Option<Zone> {
    if text.len() > 128 {
        return None;
    }
    offset(text)
        .map(Zone::Fixed)
        .or_else(|| text.parse::<Tz>().ok().map(Zone::Region))
}
pub(super) fn zone_id(vm: &mut Vm, value: JValue) -> Result<String, NatErr> {
    match vm.payload_of(value) {
        Some(Native::Str(id)) if parse_zone(&id).is_some() => Ok(id),
        Some(Native::IntBox(seconds)) if (-64_800..=64_800).contains(&seconds) => {
            if seconds == 0 {
                return Ok("Z".into());
            }
            let sign = if seconds < 0 { '-' } else { '+' };
            let abs = seconds.abs();
            let mut id = format!("{sign}{:02}:{:02}", abs / 3600, abs % 3600 / 60);
            if abs % 60 != 0 {
                id.push_str(&format!(":{:02}", abs % 60));
            }
            Ok(id)
        }
        _ => Err(error(vm, "Invalid zone ID")),
    }
}
fn zone(vm: &mut Vm, value: JValue) -> Result<Zone, NatErr> {
    let id = zone_id(vm, value)?;
    parse_zone(&id).ok_or_else(|| error(vm, "Unknown zone ID"))
}
pub(super) fn of_id(vm: &mut Vm, id: &str) -> R {
    let parsed = parse_zone(id).ok_or_else(|| error(vm, "Unknown zone ID"))?;
    if id.starts_with(['+', '-']) || id == "Z" {
        let Zone::Fixed(seconds) = parsed else {
            return Err(error(vm, "Invalid zone offset"));
        };
        vm.alloc_native("Ljava/time/ZoneOffset;", Native::IntBox(seconds))
            .map_err(NatErr::Fatal)
    } else {
        vm.alloc_native(ZONE, Native::Str(id.into()))
            .map_err(NatErr::Fatal)
    }
}
fn of(vm: &mut Vm, args: &[JValue]) -> R {
    let id = vm
        .str_of_jvalue(args[0])
        .ok_or_else(|| NatErr::Throw(vm.err_npe()))?;
    of_id(vm, &id)
}
pub(super) fn system_default(vm: &mut Vm, _: &[JValue]) -> R {
    let field = dexvm::vm::FieldRef {
        class_desc: vm.intern(ZONE),
        name: vm.intern("__acDefaultZone"),
        ty: vm.intern(ZONE),
    };
    vm.static_field_get(field).map_err(NatErr::Fatal)
}
fn get_id(vm: &mut Vm, args: &[JValue]) -> R {
    let id = zone_id(vm, args[0])?;
    Ok(vm.alloc_string(&id))
}
pub(super) fn offset_at(vm: &mut Vm, value: JValue, millis: i64) -> Result<i32, NatErr> {
    match zone(vm, value)? {
        Zone::Fixed(seconds) => Ok(seconds),
        Zone::Region(tz) => {
            let instant = DateTime::<Utc>::from_timestamp_millis(millis)
                .ok_or_else(|| error(vm, "Date exceeds supported range"))?;
            Ok(instant.with_timezone(&tz).offset().fix().local_minus_utc())
        }
    }
}
pub(super) fn local_millis(vm: &mut Vm, value: JValue, millis: i64) -> Result<i64, NatErr> {
    let seconds = i64::from(offset_at(vm, value, millis)?);
    millis
        .checked_add(seconds * 1000)
        .ok_or_else(|| error(vm, "Date overflow"))
}
pub(super) fn local_to_epoch(
    vm: &mut Vm,
    value: JValue,
    wall: i64,
    midnight: bool,
    preferred: Option<i32>,
) -> Result<i64, NatErr> {
    match zone(vm, value)? {
        Zone::Fixed(seconds) => wall
            .checked_sub(i64::from(seconds) * 1000)
            .ok_or_else(|| error(vm, "Date overflow")),
        Zone::Region(tz) => {
            let local = DateTime::<Utc>::from_timestamp_millis(wall)
                .ok_or_else(|| error(vm, "Date exceeds supported range"))?
                .naive_utc();
            match tz.from_local_datetime(&local) {
                LocalResult::Single(v) => Ok(v.timestamp_millis()),
                LocalResult::Ambiguous(a, b) => {
                    Ok(if preferred == Some(b.offset().fix().local_minus_utc()) {
                        b
                    } else {
                        a
                    }
                    .timestamp_millis())
                }
                LocalResult::None => {
                    let gap = GapInfo::new(&local, &tz)
                        .ok_or_else(|| error(vm, "Date exceeds zone rules"))?;
                    if midnight {
                        return gap
                            .end
                            .map(|v| v.timestamp_millis())
                            .ok_or_else(|| error(vm, "Date exceeds zone rules"));
                    }
                    let (_, before) = gap
                        .begin
                        .ok_or_else(|| error(vm, "Date exceeds zone rules"))?;
                    wall.checked_sub(i64::from(before.fix().local_minus_utc()) * 1000)
                        .ok_or_else(|| error(vm, "Date overflow"))
                }
            }
        }
    }
}
pub(super) fn zoned(vm: &mut Vm, millis: i64, zone: JValue) -> R {
    let value = vm
        .alloc_native(ZONED, Native::EpochMillis(millis))
        .map_err(NatErr::Fatal)?;
    vm.arena.objects[value.as_obj() as usize].fields = vec![zone];
    Ok(value)
}
pub(super) fn object_zone(vm: &mut Vm, value: JValue) -> R {
    if let Some(zone) = vm.arena.objects[value.as_obj() as usize]
        .fields
        .first()
        .copied()
    {
        return Ok(zone);
    }
    system_default(vm, &[])
}
fn get_zone(vm: &mut Vm, args: &[JValue]) -> R {
    object_zone(vm, args[0])
}
fn now_millis() -> Result<i64, NatErr> {
    let duration = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_err(|_| NatErr::Fatal(JvmError::Fatal("Host clock precedes epoch".into())))?;
    i64::try_from(duration.as_millis())
        .map_err(|_| NatErr::Fatal(JvmError::Fatal("Host clock overflow".into())))
}
fn local_now(vm: &mut Vm, args: &[JValue]) -> R {
    let zone = if args.is_empty() {
        system_default(vm, &[])?
    } else {
        args[0]
    };
    let day = local_millis(vm, zone, now_millis()?)?.div_euclid(DAY_MS);
    let day = u32::try_from(day).map_err(|_| error(vm, "LocalDate precedes supported epoch"))?;
    vm.alloc_native("Ljava/time/LocalDate;", Native::LocalDay(day))
        .map_err(NatErr::Fatal)
}
fn zoned_now(vm: &mut Vm, args: &[JValue]) -> R {
    let zone = if args.is_empty() {
        system_default(vm, &[])?
    } else {
        args[0]
    };
    zone_id(vm, zone)?;
    zoned(vm, now_millis()?, zone)
}
fn datetime_now(vm: &mut Vm, args: &[JValue]) -> R {
    let zone = if args.is_empty() {
        system_default(vm, &[])?
    } else {
        args[0]
    };
    let wall = local_millis(vm, zone, now_millis()?)?;
    vm.alloc_native("Ljava/time/LocalDateTime;", Native::EpochMillis(wall))
        .map_err(NatErr::Fatal)
}
fn at_zone(vm: &mut Vm, args: &[JValue]) -> R {
    let Some(Native::EpochMillis(wall)) = vm.payload_of(args[0]) else {
        return Err(error(vm, "Expected local date-time"));
    };
    let millis = local_to_epoch(vm, args[1], wall, false, None)?;
    zoned(vm, millis, args[1])
}
fn legacy_default(vm: &mut Vm, _: &[JValue]) -> R {
    let zone = system_default(vm, &[])?;
    let id = zone_id(vm, zone)?;
    vm.alloc_native("Ljava/util/TimeZone;", Native::TimeZone(id))
        .map_err(NatErr::Fatal)
}
fn legacy_to_zone(vm: &mut Vm, args: &[JValue]) -> R {
    let Some(Native::TimeZone(id)) = vm.payload_of(args[0]) else {
        return Err(error(vm, "Expected TimeZone"));
    };
    of_id(vm, &id)
}
fn zoned_get_year(vm: &mut Vm, args: &[JValue]) -> R {
    let Some(Native::EpochMillis(millis)) = vm.payload_of(args[0]) else {
        return Err(error(vm, "Expected zoned date-time"));
    };
    let zone = object_zone(vm, args[0])?;
    let wall = local_millis(vm, zone, millis)?;
    let value = DateTime::<Utc>::from_timestamp_millis(wall)
        .ok_or_else(|| error(vm, "Date exceeds supported range"))?;
    Ok(JValue::Int(value.year()))
}
fn zoned_delta(vm: &mut Vm, args: &[JValue], unit: i64, sign: i64, calendar: bool) -> R {
    let Some(Native::EpochMillis(millis)) = vm.payload_of(args[0]) else {
        return Err(error(vm, "Expected zoned date-time"));
    };
    let zone = object_zone(vm, args[0])?;
    let amount = args[1]
        .as_long()
        .checked_mul(sign)
        .and_then(|v| v.checked_mul(unit))
        .ok_or_else(|| error(vm, "Date arithmetic overflow"))?;
    let result = if calendar {
        let wall = local_millis(vm, zone, millis)?
            .checked_add(amount)
            .ok_or_else(|| error(vm, "Date arithmetic overflow"))?;
        let preferred = offset_at(vm, zone, millis)?;
        local_to_epoch(vm, zone, wall, false, Some(preferred))?
    } else {
        millis
            .checked_add(amount)
            .ok_or_else(|| error(vm, "Date arithmetic overflow"))?
    };
    zoned(vm, result, zone)
}
fn plus_days(vm: &mut Vm, args: &[JValue]) -> R {
    zoned_delta(vm, args, DAY_MS, 1, true)
}
fn minus_days(vm: &mut Vm, args: &[JValue]) -> R {
    zoned_delta(vm, args, DAY_MS, -1, true)
}
fn minus_hours(vm: &mut Vm, args: &[JValue]) -> R {
    zoned_delta(vm, args, 3_600_000, -1, false)
}
fn minus_minutes(vm: &mut Vm, args: &[JValue]) -> R {
    zoned_delta(vm, args, 60_000, -1, false)
}
fn minus_seconds(vm: &mut Vm, args: &[JValue]) -> R {
    zoned_delta(vm, args, 1000, -1, false)
}
fn truncated(vm: &mut Vm, args: &[JValue]) -> R {
    let unit = match vm.payload_of(args[1]) {
        Some(Native::Str(name)) => name,
        _ => return Err(error(vm, "Unsupported truncation unit")),
    };
    let size = match unit.as_str() {
        "DAYS" => DAY_MS,
        "HOURS" => 3_600_000,
        "MINUTES" => 60_000,
        "SECONDS" => 1000,
        "MILLIS" => 1,
        _ => return Err(error(vm, "Unsupported truncation unit")),
    };
    let Some(Native::EpochMillis(millis)) = vm.payload_of(args[0]) else {
        return Err(error(vm, "Expected zoned date-time"));
    };
    let zone = object_zone(vm, args[0])?;
    let preferred = offset_at(vm, zone, millis)?;
    let wall = local_millis(vm, zone, millis)?
        .div_euclid(size)
        .checked_mul(size)
        .ok_or_else(|| error(vm, "Date truncation overflow"))?;
    let instant = local_to_epoch(vm, zone, wall, false, Some(preferred))?;
    zoned(vm, instant, zone)
}
pub(super) fn install(vm: &mut Vm, default_id: &str) -> Result<(), JvmError> {
    for (class, name, sig, instance, f) in [
        (
            ZONE,
            "of",
            "(Ljava/lang/String;)Ljava/time/ZoneId;",
            false,
            of as dexvm::vm::NativeFn,
        ),
        (
            ZONE,
            "systemDefault",
            "()Ljava/time/ZoneId;",
            false,
            system_default,
        ),
        (ZONE, "getId", "()Ljava/lang/String;", true, get_id),
        (ZONE, "toString", "()Ljava/lang/String;", true, get_id),
        (
            "Ljava/util/TimeZone;",
            "getDefault",
            "()Ljava/util/TimeZone;",
            false,
            legacy_default,
        ),
        (
            "Ljava/util/TimeZone;",
            "toZoneId",
            "()Ljava/time/ZoneId;",
            true,
            legacy_to_zone,
        ),
        (
            "Ljava/time/LocalDate;",
            "now",
            "()Ljava/time/LocalDate;",
            false,
            local_now,
        ),
        (
            "Ljava/time/LocalDate;",
            "now",
            "(Ljava/time/ZoneId;)Ljava/time/LocalDate;",
            false,
            local_now,
        ),
        (
            ZONED,
            "now",
            "()Ljava/time/ZonedDateTime;",
            false,
            zoned_now,
        ),
        (
            "Ljava/time/LocalDateTime;",
            "now",
            "()Ljava/time/LocalDateTime;",
            false,
            datetime_now,
        ),
        (
            "Ljava/time/LocalDateTime;",
            "now",
            "(Ljava/time/ZoneId;)Ljava/time/LocalDateTime;",
            false,
            datetime_now,
        ),
        (
            ZONED,
            "now",
            "(Ljava/time/ZoneId;)Ljava/time/ZonedDateTime;",
            false,
            zoned_now,
        ),
        (ZONED, "getZone", "()Ljava/time/ZoneId;", true, get_zone),
        (ZONED, "getYear", "()I", true, zoned_get_year),
        (
            ZONED,
            "plusDays",
            "(J)Ljava/time/ZonedDateTime;",
            true,
            plus_days,
        ),
        (
            ZONED,
            "minusDays",
            "(J)Ljava/time/ZonedDateTime;",
            true,
            minus_days,
        ),
        (
            ZONED,
            "minusHours",
            "(J)Ljava/time/ZonedDateTime;",
            true,
            minus_hours,
        ),
        (
            ZONED,
            "minusMinutes",
            "(J)Ljava/time/ZonedDateTime;",
            true,
            minus_minutes,
        ),
        (
            ZONED,
            "minusSeconds",
            "(J)Ljava/time/ZonedDateTime;",
            true,
            minus_seconds,
        ),
        (
            ZONED,
            "truncatedTo",
            "(Ljava/time/temporal/TemporalUnit;)Ljava/time/ZonedDateTime;",
            true,
            truncated,
        ),
        (
            "Ljava/time/LocalDateTime;",
            "atZone",
            "(Ljava/time/ZoneId;)Ljava/time/ZonedDateTime;",
            true,
            at_zone,
        ),
    ] {
        vm.register_native(NativeEntry {
            class,
            name,
            sig,
            instance,
            f,
        })?;
    }
    let value = of_id(vm, default_id).map_err(|e| match e {
        NatErr::Fatal(e) => e,
        NatErr::Throw(o) => JvmError::Uncaught(o),
    })?;
    let owner = vm.ensure_class_by_desc(ZONE)?;
    let key = (vm.intern("__acDefaultZone"), vm.intern(ZONE));
    let class = &mut vm.classes[owner as usize];
    if let Some((_, offset)) = class.static_fields.get(&key) {
        class.statics[*offset as usize] = value;
    } else {
        let offset = class.statics.len() as u32;
        class.statics.push(value);
        class.statics_lazy.push(None);
        class.static_fields.insert(key, (owner, offset));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    fn millis(text: &str) -> i64 {
        DateTime::parse_from_rfc3339(text)
            .unwrap()
            .timestamp_millis()
    }
    fn vm(id: &str) -> Vm {
        let mut vm = Vm::new(vec![], Box::new(std::io::sink())).unwrap();
        crate::java_compat::install(&mut vm).unwrap();
        crate::date_compat::install(&mut vm).unwrap();
        install(&mut vm, id).unwrap();
        vm
    }
    #[test]
    fn iana_rules_resolve_gaps_overlaps_and_skipped_midnights() {
        let mut vm = vm("UTC");
        let london = of_id(&mut vm, "Europe/London").unwrap();
        assert_eq!(
            offset_at(&mut vm, london, millis("2024-01-15T12:00:00Z")).unwrap(),
            0
        );
        assert_eq!(
            offset_at(&mut vm, london, millis("2024-07-15T12:00:00Z")).unwrap(),
            3600
        );
        let gap = millis("2024-03-31T01:30:00Z");
        assert_eq!(
            local_to_epoch(&mut vm, london, gap, false, None).unwrap(),
            millis("2024-03-31T01:30:00Z")
        );
        let overlap = millis("2024-10-27T01:30:00Z");
        assert_eq!(
            local_to_epoch(&mut vm, london, overlap, false, None).unwrap(),
            millis("2024-10-27T00:30:00Z")
        );
        assert_eq!(
            local_to_epoch(&mut vm, london, overlap, false, Some(0)).unwrap(),
            overlap
        );
        let apia = of_id(&mut vm, "Pacific/Apia").unwrap();
        assert_eq!(
            local_to_epoch(&mut vm, apia, millis("2011-12-30T00:00:00Z"), true, None).unwrap(),
            millis("2011-12-30T10:00:00Z")
        );
        let fixed = of_id(&mut vm, "+05:30:45").unwrap();
        assert_eq!(
            local_to_epoch(&mut vm, fixed, 0, false, None).unwrap(),
            -19_845_000
        );
        for id in [
            "No/Such_Region",
            "+18:01",
            "GMT+19",
            "+01::02",
            &"X".repeat(129),
        ] {
            assert!(matches!(of_id(&mut vm, id), Err(NatErr::Throw(_))));
        }
    }
    #[test]
    fn zoned_calendar_arithmetic_keeps_local_midnight_across_dst() {
        let mut vm = vm("Europe/London");
        let london = system_default(&mut vm, &[]).unwrap();
        let first = millis("2024-03-30T12:00:00Z");
        let value = zoned(&mut vm, first, london).unwrap();
        let next = plus_days(&mut vm, &[value, JValue::Long(1)]).unwrap();
        assert!(
            matches!(vm.payload_of(next),Some(Native::EpochMillis(n)) if n-first==23*3_600_000)
        );
        assert_eq!(object_zone(&mut vm, next).unwrap(), london);
        let unit = vm
            .alloc_native(
                "Ljava/time/temporal/ChronoUnit;",
                Native::Str("DAYS".into()),
            )
            .unwrap();
        let start = truncated(&mut vm, &[next, unit]).unwrap();
        assert!(
            matches!(vm.payload_of(start),Some(Native::EpochMillis(n)) if n==millis("2024-03-31T00:00:00Z"))
        );
        let overflow = minus_days(&mut vm, &[value, JValue::Long(i64::MIN)]);
        assert!(matches!(overflow, Err(NatErr::Throw(_))));
        let utc = of_id(&mut vm, "UTC").unwrap();
        let earliest = zoned(&mut vm, i64::MIN, utc).unwrap();
        assert!(matches!(
            truncated(&mut vm, &[earliest, unit]),
            Err(NatErr::Throw(_))
        ));
    }
    #[test]
    fn host_default_zone_is_rooted_and_legacy_mapping_preserves_it() {
        let mut vm = vm("America/Los_Angeles");
        let zone = system_default(&mut vm, &[]).unwrap();
        vm.gc(&[]);
        assert_eq!(zone_id(&mut vm, zone).unwrap(), "America/Los_Angeles");
        let legacy = legacy_default(&mut vm, &[]).unwrap();
        let mapped = legacy_to_zone(&mut vm, &[legacy]).unwrap();
        assert_eq!(zone_id(&mut vm, mapped).unwrap(), "America/Los_Angeles");
        let wall = millis("2024-01-02T00:30:00Z");
        assert_eq!(
            local_millis(&mut vm, zone, wall).unwrap(),
            millis("2024-01-01T16:30:00Z")
        );
        assert_eq!(
            offset_at(&mut vm, zone, millis("2024-07-01T00:00:00Z")).unwrap(),
            -25_200
        );
        let fixed = of_id(&mut vm, "+18:00").unwrap();
        let before = now_millis().unwrap() + 64_800_000;
        let local = datetime_now(&mut vm, &[fixed]).unwrap();
        let after = now_millis().unwrap() + 64_800_000;
        assert!(
            matches!(vm.payload_of(local), Some(Native::EpochMillis(m)) if (before..=after).contains(&m))
        );
    }
}
