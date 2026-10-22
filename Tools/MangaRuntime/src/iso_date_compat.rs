//! ISO_DATE_TIME is a resolver, not a literal pattern: an explicit offset wins
//! over a formatter's default zone. Keep sub-millisecond precision in VM fields.
use chrono::{Datelike, Timelike};
use dexvm::{
    vm::{error::JvmError, object::Native, NatErr, NativeEntry, Vm},
    JValue,
};
use std::sync::OnceLock;
type R = Result<JValue, NatErr>;
const FORMATTER: &str = "Ljava/time/format/DateTimeFormatter;";
const LOCAL: &str = "Ljava/time/LocalDateTime;";
const ZONED: &str = "Ljava/time/ZonedDateTime;";
pub(super) const PATTERN: &str = "ac:ISO_DATE_TIME";
struct Parsed {
    wall: i64,
    remainder: i32,
    offset: Option<i32>,
    zone: Option<String>,
}
fn parse_error(vm: &mut Vm) -> NatErr {
    NatErr::Throw(vm.throwable_of(
        "Ljava/time/format/DateTimeParseException;",
        "Invalid ISO date-time or missing zone",
    ))
}
fn parse(text: &str) -> Option<Parsed> {
    static RE: OnceLock<fancy_regex::Regex> = OnceLock::new();
    let re = RE.get_or_init(|| fancy_regex::RegexBuilder::new(r"\A([0-9]{4}|\+[0-9]{5,9}|-[0-9]{4,9})-([0-9]{2})-([0-9]{2})[Tt]([0-9]{2}):([0-9]{2})(?::([0-9]{2})(?:\.([0-9]{0,9}))?)?([Zz]|[+-][0-9]{2}:[0-9]{2}(?::[0-9]{2})?)?(?:\[([^\[\]]{1,128})\])?\z").backtrack_limit(10_000).build().unwrap());
    let c = re.captures(text).ok()??;
    if c[1].starts_with('-') && c[1][1..].bytes().all(|b| b == b'0') {
        return None;
    }
    let date = chrono::NaiveDate::from_ymd_opt(
        c[1].parse().ok()?,
        c[2].parse().ok()?,
        c[3].parse().ok()?,
    )?;
    let nanos: u32 = c
        .get(7)
        .map_or(Some(0), |v| format!("{:0<9}", v.as_str()).parse().ok())?;
    let moment = date
        .and_hms_nano_opt(
            c[4].parse().ok()?,
            c[5].parse().ok()?,
            c.get(6).map_or(Some(0), |v| v.as_str().parse().ok())?,
            nanos,
        )?
        .and_utc();
    // Chrono accepts leap seconds; java.time ISO_DATE_TIME rejects them.
    if moment.nanosecond() >= 1_000_000_000 {
        return None;
    }
    let offset = if let Some(v) = c.get(8) {
        let v = v.as_str();
        if v.eq_ignore_ascii_case("Z") {
            Some(0)
        } else {
            let parts = v[1..]
                .split(':')
                .map(str::parse::<i32>)
                .collect::<Result<Vec<_>, _>>()
                .ok()?;
            let hours = parts[0];
            let minutes = *parts.get(1).unwrap_or(&0);
            let seconds = *parts.get(2).unwrap_or(&0);
            let total = hours * 3600 + minutes * 60 + seconds;
            if hours > 18 || minutes > 59 || seconds > 59 || total > 64_800 {
                return None;
            }
            Some(if v.starts_with('-') { -total } else { total })
        }
    } else {
        None
    };
    let zone = c.get(9).map(|v| v.as_str().to_owned());
    // The bracketed region is nested inside the optional offset in the ISO
    // formatter; bare local timestamps cannot append a region without offset.
    if zone.is_some() && offset.is_none() {
        return None;
    }
    Some(Parsed {
        wall: moment.timestamp_millis(),
        remainder: (nanos % 1_000_000) as i32,
        offset,
        zone,
    })
}
fn parsed(vm: &mut Vm, text: JValue) -> Result<Parsed, NatErr> {
    let text = vm
        .str_of_jvalue(text)
        .ok_or_else(|| NatErr::Throw(vm.err_npe()))?;
    if vm.budget <= text.len() as i64 + 1 {
        return Err(NatErr::Fatal(JvmError::BudgetExceeded));
    }
    vm.budget -= text.len() as i64 + 1;
    if text.len() > 512 {
        return Err(parse_error(vm));
    }
    let value = parse(&text).ok_or_else(|| parse_error(vm))?;
    if let Some(zone) = &value.zone {
        super::date_zone_compat::of_id(vm, zone).map_err(|e| match e {
            NatErr::Throw(_) => parse_error(vm),
            e => e,
        })?;
    }
    Ok(value)
}
pub(super) fn is_iso(vm: &Vm, formatter: JValue) -> bool {
    matches!(vm.payload_of(formatter),Some(Native::DateFormatter{pattern,..}) if pattern == PATTERN)
}
pub(super) fn local_date(vm: &mut Vm, args: &[JValue]) -> R {
    let value = parsed(vm, args[0])?;
    super::local_date_compat::from_day(vm, value.wall.div_euclid(86_400_000))
}
pub(super) fn local_datetime(vm: &mut Vm, args: &[JValue]) -> R {
    let p = parsed(vm, args[0])?;
    local(vm, p.wall, p.remainder)
}
pub(super) fn local(vm: &mut Vm, wall: i64, remainder: i32) -> R {
    let result = vm
        .alloc_native(LOCAL, Native::EpochMillis(wall))
        .map_err(NatErr::Fatal)?;
    vm.arena.objects[result.as_obj() as usize].fields = vec![JValue::Int(remainder)];
    Ok(result)
}
pub(super) fn zoned_datetime(vm: &mut Vm, args: &[JValue]) -> R {
    let p = parsed(vm, args[0])?;
    let default_zone = vm.arena.objects[args[1].as_obj() as usize]
        .fields
        .get(1)
        .copied()
        .unwrap_or(JValue::Null);
    let zone = if let Some(id) = &p.zone {
        super::date_zone_compat::of_id(vm, id)?
    } else if !default_zone.is_null_ref() {
        default_zone
    } else if let Some(offset) = p.offset {
        vm.alloc_native("Ljava/time/ZoneOffset;", Native::IntBox(offset))
            .map_err(NatErr::Fatal)?
    } else {
        return Err(parse_error(vm));
    };
    let instant = if let Some(offset) = p.offset {
        p.wall
            .checked_sub(i64::from(offset) * 1000)
            .ok_or_else(|| parse_error(vm))?
    } else {
        super::date_zone_compat::local_to_epoch(vm, zone, p.wall, false, None)?
    };
    zoned(vm, instant, zone, p.remainder)
}
pub(super) fn remainder(vm: &Vm, value: JValue) -> i32 {
    let Some(class) = vm.object_class(value) else {
        return 0;
    };
    let index = usize::from(vm.str_of(vm.classes[class as usize].descriptor) == ZONED);
    vm.arena.objects[value.as_obj() as usize]
        .fields
        .get(index)
        .map_or(0, |v| v.as_int())
}
pub(super) fn zoned(vm: &mut Vm, millis: i64, zone: JValue, remainder: i32) -> R {
    let result = super::date_zone_compat::zoned(vm, millis, zone)?;
    vm.arena.objects[result.as_obj() as usize]
        .fields
        .push(JValue::Int(remainder));
    Ok(result)
}
pub(super) fn format(vm: &mut Vm, args: &[JValue]) -> R {
    let value = args[1];
    if value.is_null_ref() {
        return Err(NatErr::Throw(vm.err_npe()));
    }
    let Some(Native::EpochMillis(millis)) = vm.payload_of(value) else {
        return Err(NatErr::Throw(vm.throwable_of(
            "Ljava/time/temporal/UnsupportedTemporalTypeException;",
            "ISO date-time needs a time",
        )));
    };
    let class = vm
        .object_class(value)
        .ok_or_else(|| NatErr::Throw(vm.err_npe()))?;
    let desc = vm.str_of(vm.classes[class as usize].descriptor).to_owned();
    let overriding = vm.arena.objects[args[0].as_obj() as usize]
        .fields
        .get(1)
        .copied()
        .unwrap_or(JValue::Null);
    let zone = if !overriding.is_null_ref() && desc != LOCAL {
        overriding
    } else if desc == ZONED {
        super::date_zone_compat::object_zone(vm, value)?
    } else {
        JValue::Null
    };
    let (wall, offset) = if zone.is_null_ref() {
        if desc != LOCAL {
            return Err(NatErr::Throw(vm.throwable_of(
                "Ljava/time/temporal/UnsupportedTemporalTypeException;",
                "An instant needs a zone",
            )));
        }
        (millis, None)
    } else {
        (
            super::date_zone_compat::local_millis(vm, zone, millis)?,
            Some(super::date_zone_compat::offset_at(vm, zone, millis)?),
        )
    };
    let date = chrono::DateTime::from_timestamp_millis(wall).ok_or_else(|| parse_error(vm))?;
    let year = date.year();
    let year = if year < 0 {
        format!("-{:04}", year.unsigned_abs())
    } else if year > 9999 {
        format!("+{year}")
    } else {
        format!("{year:04}")
    };
    let mut text = format!(
        "{year}-{:02}-{:02}T{:02}:{:02}:{:02}",
        date.month(),
        date.day(),
        date.hour(),
        date.minute(),
        date.second()
    );
    let nano = date.nanosecond() + remainder(vm, value) as u32;
    if nano != 0 {
        text.push('.');
        text.push_str(format!("{nano:09}").trim_end_matches('0'));
    }
    if let Some(offset) = offset {
        if offset == 0 {
            text.push('Z');
        } else {
            let sign = if offset < 0 { '-' } else { '+' };
            let abs = offset.abs();
            text.push_str(&format!("{sign}{:02}:{:02}", abs / 3600, abs % 3600 / 60));
            if abs % 60 != 0 {
                text.push_str(&format!(":{:02}", abs % 60));
            }
        }
        let id = super::date_zone_compat::zone_id(vm, zone)?;
        if !id.starts_with(['+', '-']) && id != "Z" {
            text.push('[');
            text.push_str(&id);
            text.push(']');
        }
    }
    if vm.budget <= text.len() as i64 + 1 {
        return Err(NatErr::Fatal(JvmError::BudgetExceeded));
    }
    vm.budget -= text.len() as i64 + 1;
    Ok(vm.alloc_string(&text))
}
fn nano(vm: &mut Vm, args: &[JValue]) -> R {
    let Some(Native::EpochMillis(millis)) = vm.payload_of(args[0]) else {
        return Err(NatErr::Throw(vm.err_npe()));
    };
    Ok(JValue::Int(
        (millis.rem_euclid(1000) * 1_000_000) as i32 + remainder(vm, args[0]),
    ))
}
fn to_instant(vm: &mut Vm, args: &[JValue]) -> R {
    let Some(Native::EpochMillis(millis)) = vm.payload_of(args[0]) else {
        return Err(NatErr::Throw(vm.err_npe()));
    };
    super::date_amount_compat::new_instant(
        vm,
        i128::from(millis) * 1_000_000 + i128::from(remainder(vm, args[0])),
    )
}
fn instant_at_zone(vm: &mut Vm, args: &[JValue]) -> R {
    let nanos = super::date_amount_compat::instant_nanos(vm, args[0])?;
    super::date_zone_compat::zone_id(vm, args[1])?;
    zoned(
        vm,
        (nanos.div_euclid(1_000_000)) as i64,
        args[1],
        nanos.rem_euclid(1_000_000) as i32,
    )
}
fn to_local_datetime(vm: &mut Vm, args: &[JValue]) -> R {
    let Some(Native::EpochMillis(millis)) = vm.payload_of(args[0]) else {
        return Err(NatErr::Throw(vm.err_npe()));
    };
    let zone = super::date_zone_compat::object_zone(vm, args[0])?;
    let wall = super::date_zone_compat::local_millis(vm, zone, millis)?;
    local(vm, wall, remainder(vm, args[0]))
}
pub(super) fn install(vm: &mut Vm) -> Result<(), JvmError> {
    let accessor = "Ljava/time/temporal/TemporalAccessor;";
    vm.register_native(NativeEntry {
        class: accessor,
        name: "__marker",
        sig: "()V",
        instance: true,
        f: super::abstract_function,
    })?;
    let accessor = vm.ensure_class_by_desc(accessor)?;
    vm.classes[accessor as usize].is_interface = true;
    vm.classes[accessor as usize].is_abstract = true;
    vm.classes[accessor as usize].access_flags = 0x601;
    for desc in [LOCAL, ZONED, "Ljava/time/LocalDate;", "Ljava/time/Instant;"] {
        let class = vm.ensure_class_by_desc(desc)?;
        if !vm.classes[class as usize].interfaces.contains(&accessor) {
            vm.classes[class as usize].interfaces.push(accessor);
        }
    }
    let unsupported = "Ljava/time/temporal/UnsupportedTemporalTypeException;";
    vm.register_native(NativeEntry {
        class: unsupported,
        name: "__marker",
        sig: "()V",
        instance: true,
        f: super::abstract_function,
    })?;
    let id = vm.ensure_class_by_desc(unsupported)?;
    vm.classes[id as usize].superclass =
        Some(vm.ensure_class_by_desc("Ljava/time/DateTimeException;")?);
    let value = vm.alloc_native(
        FORMATTER,
        Native::DateFormatter {
            pattern: PATTERN.into(),
            zone: String::new(),
        },
    )?;
    vm.arena.objects[value.as_obj() as usize].fields =
        vec![JValue::Int(1), JValue::Null, JValue::Null];
    super::multipart_compat::static_value(vm, FORMATTER, "ISO_DATE_TIME", FORMATTER, value)?;
    for class in [LOCAL, ZONED] {
        vm.register_native(NativeEntry {
            class,
            name: "getNano",
            sig: "()I",
            instance: true,
            f: nano,
        })?;
    }
    for class in [ZONED, "Ljava/time/chrono/ChronoZonedDateTime;"] {
        vm.register_native(NativeEntry {
            class,
            name: "toInstant",
            sig: "()Ljava/time/Instant;",
            instance: true,
            f: to_instant,
        })?;
    }
    vm.register_native(NativeEntry {
        class: "Ljava/time/Instant;",
        name: "atZone",
        sig: "(Ljava/time/ZoneId;)Ljava/time/ZonedDateTime;",
        instance: true,
        f: instant_at_zone,
    })?;
    vm.register_native(NativeEntry {
        class: ZONED,
        name: "toLocalDateTime",
        sig: "()Ljava/time/LocalDateTime;",
        instance: true,
        f: to_local_datetime,
    })?;
    Ok(())
}
