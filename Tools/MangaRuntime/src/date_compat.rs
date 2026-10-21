//! Bounded Java date patterns used by source chapter timestamps. Preserve
//! optional sections, localized month text and case-insensitive builders.
use dexvm::vm::object::Native;
use dexvm::vm::{error::JvmError, NatErr, NativeEntry, Vm};
use dexvm::JValue;

type R = Result<JValue, NatErr>;
const INSENSITIVE: &str = "ac:case-insensitive";
fn month_names(locale: chrono::Locale, short: bool) -> Vec<String> {
    (1..=12)
        .map(|month| {
            chrono::NaiveDate::from_ymd_opt(2000, month, 1)
                .unwrap()
                .format_localized(if short { "%b" } else { "%B" }, locale)
                .to_string()
        })
        .collect()
}

fn of_pattern(vm: &mut Vm, args: &[JValue]) -> R {
    let pattern = vm
        .str_of_jvalue(args[0])
        .ok_or_else(|| NatErr::Throw(vm.err_npe()))?;
    if pattern.len() > 256 {
        return Err(NatErr::Throw(
            vm.err_iae("Date pattern exceeds the host limit"),
        ));
    }
    let value = vm
        .alloc_native(
            "Ljava/time/format/DateTimeFormatter;",
            Native::DateFormatter {
                pattern,
                zone: String::new(),
            },
        )
        .map_err(NatErr::Fatal)?;
    if let Some(locale) = args.get(1) {
        set_locale(vm, value, *locale)?;
    }
    Ok(value)
}
fn case_insensitive(vm: &mut Vm, args: &[JValue]) -> R {
    initialize_state(vm, args[0])?;
    vm.arena.objects[args[0].as_obj() as usize].fields[0] = JValue::Int(1);
    Ok(args[0])
}
// Header: case flag, overriding ZoneId, Locale. Remaining triples record a default's
// pattern position, ChronoField ordinal and long value, preserving parse order.
fn initialize_state(vm: &mut Vm, value: JValue) -> R {
    let Some(Native::DateFormatter { zone, .. }) = vm.payload_of(value) else {
        return Err(NatErr::Throw(vm.err_npe()));
    };
    if vm.arena.objects[value.as_obj() as usize].fields.is_empty() {
        let zone_value = if zone.is_empty() || zone == INSENSITIVE {
            JValue::Null
        } else {
            super::date_zone_compat::of_id(vm, &zone)?
        };
        vm.arena.objects[value.as_obj() as usize].fields = vec![
            JValue::Int(i32::from(zone == INSENSITIVE)),
            zone_value,
            JValue::Null,
        ];
    }
    Ok(value)
}
fn append_pattern(vm: &mut Vm, args: &[JValue]) -> R {
    let extra = vm
        .str_of_jvalue(args[1])
        .ok_or_else(|| NatErr::Throw(vm.err_npe()))?;
    let Some(Native::DateFormatter { pattern, .. }) =
        &mut vm.arena.objects[args[0].as_obj() as usize].native
    else {
        return Err(NatErr::Throw(vm.err_npe()));
    };
    if pattern.len() + extra.len() > 256 {
        return Err(NatErr::Throw(
            vm.err_iae("Date pattern exceeds the host limit"),
        ));
    }
    pattern.push_str(&extra);
    Ok(args[0])
}
fn defaulting(vm: &mut Vm, args: &[JValue]) -> R {
    initialize_state(vm, args[0])?;
    let field = match vm.payload_of(args[1]) {
        Some(Native::Enum { ordinal, .. }) if (0..30).contains(&ordinal) => ordinal,
        _ => return Err(NatErr::Throw(vm.err_iae("Unsupported temporal field"))),
    };
    let Some(Native::DateFormatter { pattern, .. }) = vm.payload_of(args[0]) else {
        return Err(NatErr::Throw(vm.err_npe()));
    };
    let fields = &mut vm.arena.objects[args[0].as_obj() as usize].fields;
    if fields.len() >= 3 + 32 * 3 {
        return Err(NatErr::Fatal(JvmError::BudgetExceeded));
    }
    fields.extend([
        JValue::Int(pattern.chars().count() as i32),
        JValue::Int(field),
        args[2],
    ]);
    Ok(args[0])
}
fn to_formatter(vm: &mut Vm, args: &[JValue]) -> R {
    let Some(value @ Native::DateFormatter { .. }) = vm.payload_of(args[0]) else {
        return Err(NatErr::Throw(vm.err_npe()));
    };
    let fields = vm.arena.objects[args[0].as_obj() as usize].fields.clone();
    let result = vm
        .alloc_native("Ljava/time/format/DateTimeFormatter;", value)
        .map_err(NatErr::Fatal)?;
    vm.arena.objects[result.as_obj() as usize].fields = fields;
    if let Some(locale) = args.get(1) {
        set_locale(vm, result, *locale)?;
    }
    Ok(result)
}
fn set_locale(vm: &mut Vm, value: JValue, locale: JValue) -> R {
    if locale.is_null_ref() {
        return Err(NatErr::Throw(vm.err_npe()));
    }
    super::locale_compat::calendar_locale(vm, locale)?;
    initialize_state(vm, value)?;
    vm.arena.objects[value.as_obj() as usize].fields[2] = locale;
    Ok(value)
}
fn with_locale(vm: &mut Vm, args: &[JValue]) -> R {
    initialize_state(vm, args[0])?;
    let value = to_formatter(vm, &args[..1])?;
    set_locale(vm, value, args[1])
}
fn formatter_locale(vm: &mut Vm, args: &[JValue]) -> R {
    initialize_state(vm, args[0])?;
    let locale = vm.arena.objects[args[0].as_obj() as usize].fields[2];
    if !locale.is_null_ref() {
        return Ok(locale);
    }
    let field = dexvm::vm::FieldRef {
        class_desc: vm.intern("Ljava/util/Locale;"),
        name: vm.intern("ROOT"),
        ty: vm.intern("Ljava/util/Locale;"),
    };
    vm.static_field_get(field).map_err(NatErr::Fatal)
}
fn formatter_zone(vm: &mut Vm, args: &[JValue]) -> R {
    initialize_state(vm, args[0])?;
    Ok(vm.arena.objects[args[0].as_obj() as usize].fields[1])
}
fn with_zone(vm: &mut Vm, args: &[JValue]) -> R {
    initialize_state(vm, args[0])?;
    let Some(Native::DateFormatter { pattern, .. }) = vm.payload_of(args[0]) else {
        return Err(NatErr::Throw(vm.err_npe()));
    };
    let zone = if args[1].is_null_ref() {
        String::new()
    } else {
        super::date_zone_compat::zone_id(vm, args[1])?
    };
    let mut fields = vm.arena.objects[args[0].as_obj() as usize].fields.clone();
    fields[1] = args[1];
    let result = vm
        .alloc_native(
            "Ljava/time/format/DateTimeFormatter;",
            Native::DateFormatter { pattern, zone },
        )
        .map_err(NatErr::Fatal)?;
    vm.arena.objects[result.as_obj() as usize].fields = fields;
    Ok(result)
}
fn start_of_day(vm: &mut Vm, args: &[JValue]) -> R {
    let day = super::local_date_compat::day(vm, args[0])?;
    let millis =
        super::date_zone_compat::local_to_epoch(vm, args[1], day * 86_400_000, true, None)?;
    super::date_zone_compat::zoned(vm, millis, args[1])
}
#[cfg(test)]
fn parse(text: &str, pattern: &str, insensitive: bool) -> Option<(i64, i32)> {
    parse_defaults(text, pattern, insensitive, &[])
}
#[derive(Clone, Copy)]
enum ParsedField {
    Part(char, usize),
    Default(i32, i64),
}
#[cfg(test)]
fn parse_defaults(
    text: &str,
    pattern: &str,
    insensitive: bool,
    defaults: &[(usize, i32, i64)],
) -> Option<(i64, i32)> {
    parse_localized(
        text,
        pattern,
        insensitive,
        defaults,
        Some(chrono::Locale::POSIX),
    )
}
fn parse_localized(
    text: &str,
    pattern: &str,
    insensitive: bool,
    defaults: &[(usize, i32, i64)],
    locale: Option<chrono::Locale>,
) -> Option<(i64, i32)> {
    if text.len() > 512 || pattern.len() > 256 {
        return None;
    }
    let chars: Vec<char> = pattern.chars().collect();
    let mut regex = if insensitive {
        "(?i)\\A".to_owned()
    } else {
        "\\A".to_owned()
    };
    let mut fields = vec![];
    let (mut index, mut depth) = (0, 0usize);
    while index <= chars.len() {
        for &(_, field, value) in defaults.iter().filter(|(pos, _, _)| *pos == index) {
            regex.push_str("()");
            fields.push(ParsedField::Default(field, value));
        }
        if index == chars.len() {
            break;
        }
        let c = chars[index];
        index += 1;
        if c == '\'' {
            let mut literal = String::new();
            if chars.get(index) == Some(&'\'') {
                literal.push('\'');
                index += 1;
            } else {
                loop {
                    let c = *chars.get(index)?;
                    index += 1;
                    if c == '\'' {
                        if chars.get(index) == Some(&'\'') {
                            literal.push('\'');
                            index += 1;
                        } else {
                            break;
                        }
                    } else {
                        literal.push(c);
                    }
                }
            }
            regex.push_str(&fancy_regex::escape(&literal));
            continue;
        }
        if c == '[' {
            depth += 1;
            if depth > 16 {
                return None;
            }
            regex.push_str("(?:");
            continue;
        }
        if c == ']' {
            depth = depth.checked_sub(1)?;
            regex.push_str(")?");
            continue;
        }
        if !c.is_ascii_alphabetic() {
            regex.push_str(&fancy_regex::escape(&c.to_string()));
            continue;
        }
        let mut count = 1;
        while chars.get(index) == Some(&c) && !defaults.iter().any(|(pos, _, _)| *pos == index) {
            count += 1;
            index += 1;
        }
        let expression = match (c, count) {
            ('y' | 'u', 2) => "[0-9]{2}".to_owned(),
            ('y' | 'u', 1..=4) => "[0-9]{4}".to_owned(),
            ('M' | 'L', 3 | 4) => month_names(locale?, count == 3)
                .iter()
                .map(|s| fancy_regex::escape(s))
                .collect::<Vec<_>>()
                .join("|"),
            ('M' | 'L' | 'd' | 'H' | 'h' | 'm' | 's', 1) => "[0-9]{1,2}".to_owned(),
            ('M' | 'L' | 'd' | 'H' | 'h' | 'm' | 's', 2) => "[0-9]{2}".to_owned(),
            ('a', 1) => "AM|PM".to_owned(),
            ('S', 1..=9) => format!("[0-9]{{{count}}}"),
            _ => return None,
        };
        regex.push('(');
        regex.push_str(&expression);
        regex.push(')');
        fields.push(ParsedField::Part(c, count));
    }
    if depth != 0 {
        return None;
    }
    regex.push_str("\\z");
    let captures = fancy_regex::RegexBuilder::new(&regex)
        .backtrack_limit(10_000)
        .build()
        .ok()?
        .captures(text)
        .ok()??;
    let mut values = [None; 30];
    for (index, field) in fields.into_iter().enumerate() {
        let Some(value) = captures.get(index + 1).map(|v| v.as_str()) else {
            continue;
        };
        let (c, count) = match field {
            ParsedField::Default(field, value) => {
                if values[field as usize].is_none() {
                    values[field as usize] = Some(value);
                }
                continue;
            }
            ParsedField::Part(c, count) => (c, count),
        };
        let (field, value) = match c {
            'y' | 'u' => {
                let mut year = value.parse::<i64>().ok()?;
                if count == 2 {
                    year += 2000;
                }
                (if c == 'y' { 25 } else { 26 }, year)
            }
            'M' | 'L' if count >= 3 => {
                let month = month_names(locale?, count == 3).iter().position(|m| {
                    if insensitive {
                        m.to_lowercase() == value.to_lowercase()
                    } else {
                        m == value
                    }
                })? as i64
                    + 1;
                (23, month)
            }
            'M' | 'L' => (23, value.parse().ok()?),
            'd' => (18, value.parse().ok()?),
            'h' => (11, value.parse().ok()?),
            'H' => (12, value.parse().ok()?),
            'm' => (8, value.parse().ok()?),
            's' => (6, value.parse().ok()?),
            'S' => (0, format!("{value}000000000")[..9].parse().ok()?),
            'a' => (14, i64::from(value.eq_ignore_ascii_case("pm"))),
            _ => return None,
        };
        if values[field].is_some_and(|old| old != value) {
            return None;
        }
        values[field] = Some(value);
    }
    let year = values[26].or(values[25])?;
    if values[25].is_some_and(|era_year| era_year != year) {
        return None;
    }
    let month = u8::try_from(values[23]?).ok()?;
    let day = u8::try_from(values[18]?).ok()?;
    let mut hour = values[12].unwrap_or(0);
    if let Some(twelve) = values[11] {
        if !(1..=12).contains(&twelve) {
            return None;
        }
        let converted = twelve % 12 + 12 * values[14]?;
        if values[12].is_some_and(|h| h != converted) {
            return None;
        }
        hour = converted;
    }
    let minute = values[8].unwrap_or(0);
    let second = values[6].unwrap_or(0);
    let nanos = values[0].unwrap_or(0);
    if !(0..1_000_000_000).contains(&nanos) {
        return None;
    }
    for (field, value) in values.iter().enumerate() {
        if value.is_some() && ![0, 6, 8, 11, 12, 14, 18, 23, 25, 26].contains(&field) {
            return None;
        }
    }
    let date = time::Date::from_calendar_date(
        i32::try_from(year).ok()?,
        time::Month::try_from(month).ok()?,
        day,
    )
    .ok()?;
    let moment = date
        .with_hms_nano(
            u8::try_from(hour).ok()?,
            u8::try_from(minute).ok()?,
            u8::try_from(second).ok()?,
            nanos as u32,
        )
        .ok()?
        .assume_utc();
    Some((
        i64::try_from(moment.unix_timestamp_nanos().div_euclid(1_000_000)).ok()?,
        date.to_julian_day().checked_sub(2_440_588)?,
    ))
}
fn parsed(vm: &mut Vm, args: &[JValue]) -> Result<(i64, i32), NatErr> {
    let text = vm
        .str_of_jvalue(args[0])
        .ok_or_else(|| NatErr::Throw(vm.err_npe()))?;
    let Some(Native::DateFormatter { pattern, zone }) = vm.payload_of(args[1]) else {
        return Err(NatErr::Throw(vm.err_npe()));
    };
    vm.budget -= (text.len() + pattern.len()) as i64;
    if vm.budget <= 0 {
        return Err(NatErr::Fatal(JvmError::BudgetExceeded));
    }
    let fields = &vm.arena.objects[args[1].as_obj() as usize].fields;
    let insensitive = fields
        .first()
        .map(|v| v.as_int() != 0)
        .unwrap_or(zone == INSENSITIVE);
    let defaults: Vec<_> = fields
        .get(3..)
        .unwrap_or_default()
        .as_chunks::<3>()
        .0
        .iter()
        .map(|v| (v[0].as_int() as usize, v[1].as_int(), v[2].as_long()))
        .collect();
    let locale = fields.get(2).copied().unwrap_or(JValue::Null);
    let locale = super::locale_compat::calendar_locale(vm, locale)?;
    parse_localized(&text, &pattern, insensitive, &defaults, locale).ok_or_else(|| {
        NatErr::Throw(vm.throwable_of(
            "Ljava/time/format/DateTimeParseException;",
            "Unsupported pattern or invalid date",
        ))
    })
}
fn local_date(vm: &mut Vm, args: &[JValue]) -> R {
    let (_, day) = parsed(vm, args)?;
    super::local_date_compat::from_day(vm, i64::from(day))
}
fn local_datetime(vm: &mut Vm, args: &[JValue]) -> R {
    let (millis, _) = parsed(vm, args)?;
    vm.alloc_native("Ljava/time/LocalDateTime;", Native::EpochMillis(millis))
        .map_err(NatErr::Fatal)
}
fn zoned_datetime(vm: &mut Vm, args: &[JValue]) -> R {
    let (wall, _) = parsed(vm, args)?;
    let zone = formatter_zone(vm, &args[1..2])?;
    if zone.is_null_ref() {
        return Err(NatErr::Throw(vm.throwable_of(
            "Ljava/time/format/DateTimeParseException;",
            "Zoned parsing requires a formatter zone",
        )));
    }
    let instant = super::date_zone_compat::local_to_epoch(vm, zone, wall, false, None)?;
    super::date_zone_compat::zoned(vm, instant, zone)
}
fn format_date(vm: &mut Vm, args: &[JValue]) -> R {
    use chrono::{Datelike, Timelike};
    let Some(Native::DateFormatter { pattern, .. }) = vm.payload_of(args[0]) else {
        return Err(NatErr::Throw(vm.err_npe()));
    };
    if pattern.len() > 256 {
        return Err(NatErr::Fatal(JvmError::BudgetExceeded));
    }
    let overriding = formatter_zone(vm, &args[..1])?;
    let locale = vm.arena.objects[args[0].as_obj() as usize].fields[2];
    let locale = super::locale_compat::calendar_locale(vm, locale)?;
    let class = vm
        .object_class(args[1])
        .ok_or_else(|| NatErr::Throw(vm.err_npe()))?;
    let desc = vm.str_of(vm.classes[class as usize].descriptor).to_owned();
    let (wall, has_time, offset) = match vm.payload_of(args[1]) {
        Some(Native::LocalDay(day)) => (i64::from(day) * 86_400_000, false, None),
        Some(Native::LongBox(day)) if desc == "Ljava/time/LocalDate;" => {
            (day * 86_400_000, false, None)
        }
        Some(Native::EpochMillis(millis)) if desc == "Ljava/time/LocalDateTime;" => {
            (millis, true, None)
        }
        Some(Native::EpochMillis(millis)) => {
            let zone = if !overriding.is_null_ref() {
                overriding
            } else if desc == "Ljava/time/ZonedDateTime;" {
                super::date_zone_compat::object_zone(vm, args[1])?
            } else {
                return Err(NatErr::Throw(vm.throwable_of(
                    "Ljava/time/DateTimeException;",
                    "An instant needs a formatter zone",
                )));
            };
            let offset = super::date_zone_compat::offset_at(vm, zone, millis)?;
            (
                super::date_zone_compat::local_millis(vm, zone, millis)?,
                true,
                Some(offset),
            )
        }
        _ => return Err(NatErr::Throw(vm.err_iae("Unsupported date representation"))),
    };
    let date = chrono::DateTime::<chrono::Utc>::from_timestamp_millis(wall).ok_or_else(|| {
        NatErr::Throw(vm.throwable_of(
            "Ljava/time/DateTimeException;",
            "Date exceeds supported range",
        ))
    })?;
    let chars: Vec<_> = pattern.chars().collect();
    let mut stack = vec![Some(String::new())];
    let mut i = 0;
    while i < chars.len() {
        if vm.budget <= 0 {
            return Err(NatErr::Fatal(JvmError::BudgetExceeded));
        }
        vm.budget -= 1;
        let c = chars[i];
        i += 1;
        if c == '[' {
            if stack.len() > 16 {
                return Err(NatErr::Fatal(JvmError::BudgetExceeded));
            }
            stack.push(Some(String::new()));
            continue;
        }
        if c == ']' {
            if stack.len() == 1 {
                return Err(NatErr::Throw(vm.err_iae("Unmatched optional section")));
            }
            let part = stack.pop().unwrap();
            if let (Some(parent), Some(part)) = (stack.last_mut().unwrap(), part) {
                parent.push_str(&part);
            }
            continue;
        }
        let text = if c == '\'' {
            let mut text = String::new();
            if chars.get(i) == Some(&'\'') {
                text.push('\'');
                i += 1;
            } else {
                loop {
                    let Some(&c) = chars.get(i) else {
                        return Err(NatErr::Throw(vm.err_iae("Unclosed date literal")));
                    };
                    i += 1;
                    if c == '\'' {
                        if chars.get(i) == Some(&'\'') {
                            text.push('\'');
                            i += 1;
                        } else {
                            break;
                        }
                    } else {
                        text.push(c);
                    }
                }
            }
            Some(text)
        } else if !c.is_ascii_alphabetic() {
            Some(c.to_string())
        } else {
            let mut count = 1;
            while chars.get(i) == Some(&c) {
                count += 1;
                i += 1;
            }
            let padded = |v: i32| format!("{v:0width$}", width = count);
            match (c, count) {
                ('y' | 'u', 1..=9) => Some(if count == 2 {
                    format!("{:02}", date.year().rem_euclid(100))
                } else {
                    padded(date.year())
                }),
                ('M' | 'L', 1 | 2) => Some(padded(date.month() as i32)),
                ('M' | 'L', 3 | 4) if locale.is_some() => {
                    Some(month_names(locale.unwrap(), count == 3)[date.month0() as usize].clone())
                }
                ('d', 1 | 2) => Some(padded(date.day() as i32)),
                ('D', 1..=3) => Some(padded(date.ordinal() as i32)),
                ('E', 1..=5) if locale.is_some() => {
                    let name = date
                        .format_localized(if count <= 3 { "%a" } else { "%A" }, locale.unwrap())
                        .to_string();
                    Some(if count == 5 {
                        name.chars().take(1).collect()
                    } else {
                        name
                    })
                }
                ('H' | 'h' | 'k' | 'K' | 'm' | 's', 1 | 2) if has_time => Some(padded(match c {
                    'H' => date.hour() as i32,
                    'h' => (date.hour() + 11) as i32 % 12 + 1,
                    'k' => (date.hour() + 23) as i32 % 24 + 1,
                    'K' => date.hour() as i32 % 12,
                    'm' => date.minute() as i32,
                    _ => date.second() as i32,
                })),
                ('a', 1) if has_time => Some(if date.hour() < 12 { "AM" } else { "PM" }.into()),
                ('S', 1..=9) if has_time => {
                    Some(format!("{:09}", date.nanosecond())[..count].into())
                }
                ('X' | 'x' | 'Z', 1..=5) if offset.is_some() => {
                    Some(render_offset(offset.unwrap(), c, count))
                }
                ('H' | 'h' | 'k' | 'K' | 'm' | 's' | 'a' | 'S' | 'X' | 'x' | 'Z', _) => None,
                _ => {
                    return Err(NatErr::Throw(vm.throwable_of(
                        "Ljava/time/DateTimeException;",
                        "Unsupported date pattern",
                    )))
                }
            }
        };
        match text {
            Some(text) => {
                if let Some(out) = stack.last_mut().unwrap() {
                    out.push_str(&text);
                }
            }
            None => *stack.last_mut().unwrap() = None,
        }
    }
    if stack.len() != 1 {
        return Err(NatErr::Throw(vm.err_iae("Unclosed optional section")));
    }
    let result = stack.pop().unwrap().ok_or_else(|| {
        NatErr::Throw(vm.throwable_of(
            "Ljava/time/DateTimeException;",
            "Temporal value does not contain the requested fields",
        ))
    })?;
    Ok(vm.alloc_string(&result))
}
fn render_offset(seconds: i32, kind: char, count: usize) -> String {
    if seconds == 0 && (kind == 'X' || kind == 'Z' && count == 5) {
        return "Z".into();
    }
    let sign = if seconds < 0 { '-' } else { '+' };
    let abs = seconds.abs();
    let (h, m, s) = (abs / 3600, abs % 3600 / 60, abs % 60);
    if kind == 'Z' && count == 4 {
        return if seconds == 0 {
            "GMT".into()
        } else if s != 0 {
            format!("GMT{sign}{h:02}:{m:02}:{s:02}")
        } else {
            format!("GMT{sign}{h:02}:{m:02}")
        };
    }
    if kind == 'Z' && count <= 3 {
        return format!("{sign}{h:02}{m:02}");
    }
    match count {
        1 if m == 0 => format!("{sign}{h:02}"),
        1 | 2 => format!("{sign}{h:02}{m:02}"),
        3 => format!("{sign}{h:02}:{m:02}"),
        4 if s != 0 => format!("{sign}{h:02}{m:02}{s:02}"),
        4 => format!("{sign}{h:02}{m:02}"),
        _ if s != 0 => format!("{sign}{h:02}:{m:02}:{s:02}"),
        _ => format!("{sign}{h:02}:{m:02}"),
    }
}
fn format_value(vm: &mut Vm, args: &[JValue]) -> R {
    format_date(vm, &[args[1], args[0]])
}
fn exception_init(vm: &mut Vm, args: &[JValue]) -> R {
    let message = vm.str_of_jvalue(args[1]);
    vm.arena.objects[args[0].as_obj() as usize].native = Some(Native::Throwable {
        message,
        cause: JValue::Null,
    });
    Ok(JValue::Null)
}
const CHRONO_FIELDS: &[&str] = &[
    "NANO_OF_SECOND",
    "NANO_OF_DAY",
    "MICRO_OF_SECOND",
    "MICRO_OF_DAY",
    "MILLI_OF_SECOND",
    "MILLI_OF_DAY",
    "SECOND_OF_MINUTE",
    "SECOND_OF_DAY",
    "MINUTE_OF_HOUR",
    "MINUTE_OF_DAY",
    "HOUR_OF_AMPM",
    "CLOCK_HOUR_OF_AMPM",
    "HOUR_OF_DAY",
    "CLOCK_HOUR_OF_DAY",
    "AMPM_OF_DAY",
    "DAY_OF_WEEK",
    "ALIGNED_DAY_OF_WEEK_IN_MONTH",
    "ALIGNED_DAY_OF_WEEK_IN_YEAR",
    "DAY_OF_MONTH",
    "DAY_OF_YEAR",
    "EPOCH_DAY",
    "ALIGNED_WEEK_OF_MONTH",
    "ALIGNED_WEEK_OF_YEAR",
    "MONTH_OF_YEAR",
    "PROLEPTIC_MONTH",
    "YEAR_OF_ERA",
    "YEAR",
    "ERA",
    "INSTANT_SECONDS",
    "OFFSET_SECONDS",
];
const WEEKDAYS: &[&str] = &[
    "MONDAY",
    "TUESDAY",
    "WEDNESDAY",
    "THURSDAY",
    "FRIDAY",
    "SATURDAY",
    "SUNDAY",
];
fn enum_name(vm: &mut Vm, args: &[JValue]) -> R {
    let Some(Native::Enum { name, .. }) = vm.payload_of(args[0]) else {
        return Err(NatErr::Throw(vm.err_npe()));
    };
    Ok(vm.alloc_string(&name))
}
fn enum_constant(vm: &mut Vm, class: &str, name: &str) -> R {
    let field = dexvm::vm::FieldRef {
        class_desc: vm.intern(class),
        name: vm.intern(name),
        ty: vm.intern(class),
    };
    vm.static_field_get(field).map_err(NatErr::Fatal)
}
fn enum_values(vm: &mut Vm, class: &str, names: &[&str]) -> R {
    let values = names
        .iter()
        .map(|name| enum_constant(vm, class, name))
        .collect::<Result<Vec<_>, _>>()?;
    vm.alloc_native(
        &format!("[{class}"),
        Native::Array(dexvm::vm::object::ArrayData::Obj(values)),
    )
    .map_err(NatErr::Fatal)
}
fn chrono_values(vm: &mut Vm, _: &[JValue]) -> R {
    enum_values(vm, "Ljava/time/temporal/ChronoField;", CHRONO_FIELDS)
}
fn weekday_values(vm: &mut Vm, _: &[JValue]) -> R {
    enum_values(vm, "Ljava/time/DayOfWeek;", WEEKDAYS)
}
fn weekday_of(vm: &mut Vm, args: &[JValue]) -> R {
    let day = args[0].as_int();
    let name = WEEKDAYS.get(day.wrapping_sub(1) as usize).ok_or_else(|| {
        NatErr::Throw(vm.throwable_of("Ljava/time/DateTimeException;", "Invalid weekday"))
    })?;
    enum_constant(vm, "Ljava/time/DayOfWeek;", name)
}
fn weekday_value(vm: &mut Vm, args: &[JValue]) -> R {
    let Some(Native::Enum { ordinal, .. }) = vm.payload_of(args[0]) else {
        return Err(NatErr::Throw(vm.err_npe()));
    };
    Ok(JValue::Int(ordinal + 1))
}
fn weekday(vm: &mut Vm, args: &[JValue]) -> R {
    let day = match vm.payload_of(args[0]) {
        Some(Native::LocalDay(day)) => i64::from(day),
        Some(Native::LongBox(day)) => day,
        Some(Native::EpochMillis(millis)) => {
            let zone = super::date_zone_compat::object_zone(vm, args[0])?;
            super::date_zone_compat::local_millis(vm, zone, millis)?.div_euclid(86_400_000)
        }
        _ => return Err(NatErr::Throw(vm.err_iae("Expected a calendar date"))),
    };
    weekday_of(vm, &[JValue::Int((day + 3).rem_euclid(7) as i32 + 1)])
}
fn install_enums(vm: &mut Vm) -> Result<(), JvmError> {
    for (class, names, values) in [
        (
            "Ljava/time/temporal/ChronoField;",
            CHRONO_FIELDS,
            chrono_values as dexvm::vm::NativeFn,
        ),
        (
            "Ljava/time/DayOfWeek;",
            WEEKDAYS,
            weekday_values as dexvm::vm::NativeFn,
        ),
    ] {
        vm.register_native(NativeEntry {
            class,
            name: "name",
            sig: "()Ljava/lang/String;",
            instance: true,
            f: enum_name,
        })?;
        let sig = if class.contains("ChronoField") {
            "()[Ljava/time/temporal/ChronoField;"
        } else {
            "()[Ljava/time/DayOfWeek;"
        };
        vm.register_native(NativeEntry {
            class,
            name: "values",
            sig,
            instance: false,
            f: values,
        })?;
        let owner = vm.ensure_class_by_desc(class)?;
        vm.classes[owner as usize].superclass = Some(vm.ensure_class_by_desc("Ljava/lang/Enum;")?);
        if class.contains("ChronoField") {
            let field = vm.ensure_class_by_desc("Ljava/time/temporal/TemporalField;")?;
            if !vm.classes[owner as usize].interfaces.contains(&field) {
                vm.classes[owner as usize].interfaces.push(field);
            }
        }
        for (ordinal, &name) in names.iter().enumerate() {
            let key = (vm.intern(name), vm.intern(class));
            if vm.classes[owner as usize].static_fields.contains_key(&key) {
                continue;
            }
            let value = vm.alloc_native(
                class,
                Native::Enum {
                    name: name.into(),
                    ordinal: ordinal as i32,
                },
            )?;
            let class = &mut vm.classes[owner as usize];
            let offset = class.statics.len() as u32;
            class.statics.push(value);
            class.statics_lazy.push(None);
            class.static_fields.insert(key, (owner, offset));
        }
    }
    Ok(())
}
pub(super) fn install(vm: &mut Vm) -> Result<(), JvmError> {
    install_enums(vm)?;
    for (class, name, sig, instance, f) in [
        ("Ljava/time/format/DateTimeFormatter;", "ofPattern", "(Ljava/lang/String;)Ljava/time/format/DateTimeFormatter;", false, of_pattern as dexvm::vm::NativeFn),
        ("Ljava/time/format/DateTimeFormatter;", "ofPattern", "(Ljava/lang/String;Ljava/util/Locale;)Ljava/time/format/DateTimeFormatter;", false, of_pattern),
        ("Ljava/time/format/DateTimeFormatter;", "withZone", "(Ljava/time/ZoneId;)Ljava/time/format/DateTimeFormatter;", true, with_zone),
        ("Ljava/time/format/DateTimeFormatter;", "withLocale", "(Ljava/util/Locale;)Ljava/time/format/DateTimeFormatter;", true, with_locale),
        ("Ljava/time/format/DateTimeFormatter;", "getLocale", "()Ljava/util/Locale;", true, formatter_locale),
        ("Ljava/time/format/DateTimeFormatter;", "format", "(Ljava/time/temporal/TemporalAccessor;)Ljava/lang/String;", true, format_date),
        ("Ljava/time/LocalDate;", "format", "(Ljava/time/format/DateTimeFormatter;)Ljava/lang/String;", true, format_value),
        ("Ljava/time/LocalDateTime;", "format", "(Ljava/time/format/DateTimeFormatter;)Ljava/lang/String;", true, format_value),
        ("Ljava/time/ZonedDateTime;", "format", "(Ljava/time/format/DateTimeFormatter;)Ljava/lang/String;", true, format_value),
        ("Ljava/time/format/DateTimeFormatterBuilder;", "appendPattern", "(Ljava/lang/String;)Ljava/time/format/DateTimeFormatterBuilder;", true, append_pattern),
        ("Ljava/time/format/DateTimeFormatterBuilder;", "parseDefaulting", "(Ljava/time/temporal/TemporalField;J)Ljava/time/format/DateTimeFormatterBuilder;", true, defaulting),
        ("Ljava/time/format/DateTimeFormatterBuilder;", "parseCaseInsensitive", "()Ljava/time/format/DateTimeFormatterBuilder;", true, case_insensitive as dexvm::vm::NativeFn),
        ("Ljava/time/format/DateTimeFormatterBuilder;", "toFormatter", "(Ljava/util/Locale;)Ljava/time/format/DateTimeFormatter;", true, to_formatter),
        ("Ljava/time/format/DateTimeFormatterBuilder;", "toFormatter", "()Ljava/time/format/DateTimeFormatter;", true, to_formatter),
        ("Ljava/time/LocalDate;", "parse", "(Ljava/lang/CharSequence;Ljava/time/format/DateTimeFormatter;)Ljava/time/LocalDate;", false, local_date),
        ("Ljava/time/LocalDate;", "atStartOfDay", "(Ljava/time/ZoneId;)Ljava/time/ZonedDateTime;", true, start_of_day),
        ("Ljava/time/LocalDateTime;", "parse", "(Ljava/lang/CharSequence;Ljava/time/format/DateTimeFormatter;)Ljava/time/LocalDateTime;", false, local_datetime),
        ("Ljava/time/ZonedDateTime;", "parse", "(Ljava/lang/CharSequence;Ljava/time/format/DateTimeFormatter;)Ljava/time/ZonedDateTime;", false, zoned_datetime),
        ("Ljava/time/format/DateTimeFormatter;", "getZone", "()Ljava/time/ZoneId;", true, formatter_zone),
        ("Ljava/time/DateTimeException;", "<init>", "(Ljava/lang/String;)V", true, exception_init),
        ("Ljava/time/LocalDate;", "getDayOfWeek", "()Ljava/time/DayOfWeek;", true, weekday),
        ("Ljava/time/ZonedDateTime;", "getDayOfWeek", "()Ljava/time/DayOfWeek;", true, weekday),
        ("Ljava/time/DayOfWeek;", "of", "(I)Ljava/time/DayOfWeek;", false, weekday_of),
        ("Ljava/time/DayOfWeek;", "getValue", "()I", true, weekday_value),
        ("Ljava/time/format/DateTimeParseException;", "<init>", "(Ljava/lang/String;Ljava/lang/CharSequence;I)V", true, exception_init),
    ] { vm.register_native(NativeEntry { class, name, sig, instance, f })?; }
    let exception = vm.ensure_class_by_desc("Ljava/time/format/DateTimeParseException;")?;
    let parent = vm.ensure_class_by_desc("Ljava/time/DateTimeException;")?;
    vm.classes[exception as usize].superclass = Some(parent);
    vm.classes[parent as usize].superclass =
        Some(vm.ensure_class_by_desc("Ljava/lang/RuntimeException;")?);
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    fn host_vm() -> Vm {
        let mut vm = Vm::new(vec![], Box::new(std::io::sink())).unwrap();
        super::super::java_compat::install(&mut vm).unwrap();
        super::super::locale_compat::install(&mut vm).unwrap();
        install(&mut vm).unwrap();
        super::super::date_zone_compat::install(&mut vm, "UTC").unwrap();
        vm
    }
    #[test]
    fn localized_months_keep_accents_punctuation_and_calendar_validation() {
        let french = Some(chrono::Locale::fr_FR);
        let expected = parse("2024-02-29", "yyyy-MM-dd", false);
        for (text, pattern, insensitive) in [
            ("29 févr. 2024", "d MMM yyyy", false),
            ("29 FÉVRIER 2024", "d MMMM yyyy", true),
        ] {
            assert_eq!(
                parse_localized(text, pattern, insensitive, &[], french),
                expected
            );
        }
        for text in [
            "29 févrX 2024",
            "29 févr. 2023",
            "30 février 2024",
            "29 February 2024",
        ] {
            assert!(parse_localized(text, "d [MMM][MMMM] yyyy", true, &[], french).is_none());
        }
        assert!(parse_localized("29 février 2024", "d MMMM yyyy", false, &[], None).is_none());
        assert_eq!(
            parse_localized("2024-02-29", "yyyy-MM-dd", false, &[], None),
            expected
        );
    }
    #[test]
    fn formatter_locale_copies_keep_defaults_zones_and_gc_references() {
        let mut vm = host_vm();
        let french = vm
            .alloc_native("Ljava/util/Locale;", Native::Str("fr-FR".into()))
            .unwrap();
        let japanese = vm
            .alloc_native("Ljava/util/Locale;", Native::Str("ja-JP".into()))
            .unwrap();
        let builder = vm
            .alloc_native(
                "Ljava/time/format/DateTimeFormatterBuilder;",
                Native::DateFormatter {
                    pattern: "d MMMM".into(),
                    zone: String::new(),
                },
            )
            .unwrap();
        case_insensitive(&mut vm, &[builder]).unwrap();
        let year = enum_constant(&mut vm, "Ljava/time/temporal/ChronoField;", "YEAR").unwrap();
        defaulting(&mut vm, &[builder, year, JValue::Long(2024)]).unwrap();
        let original = to_formatter(&mut vm, &[builder, french]).unwrap();
        let zone = super::super::date_zone_compat::of_id(&mut vm, "Europe/Paris").unwrap();
        let zoned = with_zone(&mut vm, &[original, zone]).unwrap();
        let copied = with_locale(&mut vm, &[zoned, japanese]).unwrap();
        vm.gc(&[original.as_obj(), zoned.as_obj(), copied.as_obj()]);
        assert_eq!(formatter_locale(&mut vm, &[original]).unwrap(), french);
        assert_eq!(formatter_locale(&mut vm, &[copied]).unwrap(), japanese);
        assert_eq!(formatter_zone(&mut vm, &[copied]).unwrap(), zone);
        assert_eq!(formatter_zone(&mut vm, &[original]).unwrap(), JValue::Null);
        let text = vm.alloc_string("29 FÉVRIER");
        let date = local_date(&mut vm, &[text, zoned]).unwrap();
        assert!(local_date(&mut vm, &[text, copied]).is_err());
        let pattern = vm.alloc_string("EEEE d MMMM yyyy");
        let formatter = of_pattern(&mut vm, &[pattern, french]).unwrap();
        let text = format_date(&mut vm, &[formatter, date]).unwrap();
        assert_eq!(
            vm.str_of_jvalue(text).as_deref(),
            Some("jeudi 29 février 2024")
        );
        let pattern = vm.alloc_string("EEEEE MMMM");
        let formatter = of_pattern(&mut vm, &[pattern, japanese]).unwrap();
        let text = format_date(&mut vm, &[formatter, date]).unwrap();
        assert_eq!(vm.str_of_jvalue(text).as_deref(), Some("木 2月"));
        assert!(with_locale(&mut vm, &[zoned, JValue::Null]).is_err());
    }
    #[test]
    fn calendar_defaults_keep_parse_order_and_formatter_snapshots() {
        let mut vm = host_vm();
        let builder = vm
            .alloc_native(
                "Ljava/time/format/DateTimeFormatterBuilder;",
                Native::DateFormatter {
                    pattern: "MM-dd".into(),
                    zone: String::new(),
                },
            )
            .unwrap();
        let year = enum_constant(&mut vm, "Ljava/time/temporal/ChronoField;", "YEAR").unwrap();
        defaulting(&mut vm, &[builder, year, JValue::Long(2024)]).unwrap();
        let snapshot = to_formatter(&mut vm, &[builder]).unwrap();
        let suffix = vm.alloc_string(" yyyy");
        append_pattern(&mut vm, &[builder, suffix]).unwrap();
        let later = to_formatter(&mut vm, &[builder]).unwrap();
        vm.gc(&[snapshot.as_obj(), later.as_obj()]);
        let text = vm.alloc_string("02-29");
        assert!(local_date(&mut vm, &[text, snapshot]).is_ok());
        assert!(matches!(
            local_date(&mut vm, &[text, later]),
            Err(NatErr::Throw(_))
        ));
        let conflicting = vm.alloc_string("02-29 2023");
        assert!(matches!(
            local_date(&mut vm, &[conflicting, later]),
            Err(NatErr::Throw(_))
        ));
        assert!(parse_defaults(
            "2026",
            "uuuu",
            false,
            &[(0, 26, 1970), (4, 23, 1), (4, 18, 1)]
        )
        .is_none());
        assert_eq!(
            parse_defaults(
                "2026",
                "uuuu",
                false,
                &[(4, 26, 1970), (4, 23, 1), (4, 18, 1)]
            ),
            parse("2026-01-01", "yyyy-MM-dd", false)
        );
        assert!(parse("02-29", "MM-dd", false).is_none());
        assert!(parse_defaults("02-29", "MM-dd", false, &[(5, 26, 2023)]).is_none());
        vm.budget = 0;
        assert!(matches!(
            local_date(&mut vm, &[text, snapshot]),
            Err(NatErr::Fatal(JvmError::BudgetExceeded))
        ));
    }
    #[test]
    fn formatter_zones_are_immutable_rooted_and_preserve_case_options() {
        let mut vm = host_vm();
        let builder = vm
            .alloc_native(
                "Ljava/time/format/DateTimeFormatterBuilder;",
                Native::DateFormatter {
                    pattern: "d MMMM yyyy".into(),
                    zone: String::new(),
                },
            )
            .unwrap();
        case_insensitive(&mut vm, &[builder]).unwrap();
        let original = to_formatter(&mut vm, &[builder]).unwrap();
        let zone = super::super::date_zone_compat::of_id(&mut vm, "Asia/Kolkata").unwrap();
        let formatter = with_zone(&mut vm, &[original, zone]).unwrap();
        assert_eq!(formatter_zone(&mut vm, &[original]).unwrap(), JValue::Null);
        vm.gc(&[formatter.as_obj()]);
        assert_eq!(formatter_zone(&mut vm, &[formatter]).unwrap(), zone);
        let text = vm.alloc_string("20 october 2026");
        assert!(local_date(&mut vm, &[text, formatter]).is_ok());
        let cleared = with_zone(&mut vm, &[formatter, JValue::Null]).unwrap();
        assert_eq!(formatter_zone(&mut vm, &[cleared]).unwrap(), JValue::Null);
        assert_eq!(formatter_zone(&mut vm, &[formatter]).unwrap(), zone);
    }
    #[test]
    fn formatting_applies_zone_offsets_and_optional_temporal_fields() {
        let mut vm = host_vm();
        let pattern = vm.alloc_string("EEE, d MMMM yyyy['T'HH:mm:ss.SSS XXX]");
        let formatter = of_pattern(&mut vm, &[pattern]).unwrap();
        let zone = super::super::date_zone_compat::of_id(&mut vm, "Asia/Tokyo").unwrap();
        let formatter = with_zone(&mut vm, &[formatter, zone]).unwrap();
        let utc = chrono::DateTime::parse_from_rfc3339("2026-10-20T23:45:30.123Z")
            .unwrap()
            .timestamp_millis();
        let instant = vm
            .alloc_native("Ljava/time/Instant;", Native::EpochMillis(utc))
            .unwrap();
        let text = format_date(&mut vm, &[formatter, instant]).unwrap();
        assert_eq!(
            vm.str_of_jvalue(text).as_deref(),
            Some("Wed, 21 October 2026T08:45:30.123 +09:00")
        );
        let input = vm.alloc_string("2026-10-20");
        let pattern = vm.alloc_string("yyyy-MM-dd");
        let date_formatter = of_pattern(&mut vm, &[pattern]).unwrap();
        let date = local_date(&mut vm, &[input, date_formatter]).unwrap();
        let text = format_date(&mut vm, &[formatter, date]).unwrap();
        assert_eq!(
            vm.str_of_jvalue(text).as_deref(),
            Some("Tue, 20 October 2026")
        );
        let pattern = vm.alloc_string("HH:mm");
        let strict = of_pattern(&mut vm, &[pattern]).unwrap();
        assert!(matches!(
            format_date(&mut vm, &[strict, date]),
            Err(NatErr::Throw(_))
        ));
        vm.budget = 0;
        assert!(matches!(
            format_date(&mut vm, &[formatter, instant]),
            Err(NatErr::Fatal(JvmError::BudgetExceeded))
        ));
    }
    #[test]
    fn zoned_parsing_retains_formatter_rules_and_rejects_an_absent_zone() {
        let mut vm = host_vm();
        let pattern = vm.alloc_string("yyyy-MM-dd HH:mm");
        let formatter = of_pattern(&mut vm, &[pattern]).unwrap();
        let text = vm.alloc_string("2024-03-31 01:30");
        assert!(matches!(
            zoned_datetime(&mut vm, &[text, formatter]),
            Err(NatErr::Throw(_))
        ));
        let zone = super::super::date_zone_compat::of_id(&mut vm, "Europe/London").unwrap();
        let formatter = with_zone(&mut vm, &[formatter, zone]).unwrap();
        let parsed = zoned_datetime(&mut vm, &[text, formatter]).unwrap();
        assert!(
            matches!(vm.payload_of(parsed), Some(Native::EpochMillis(m)) if m == 1_711_848_600_000)
        );
        let formatted = format_date(&mut vm, &[formatter, parsed]).unwrap();
        assert_eq!(
            vm.str_of_jvalue(formatted).as_deref(),
            Some("2024-03-31 02:30")
        );
        assert_eq!(
            super::super::date_zone_compat::object_zone(&mut vm, parsed).unwrap(),
            zone
        );
    }
    #[test]
    fn default_locale_pattern_overload_parses_owned_dates_and_keeps_errors() {
        let mut vm = Vm::new(vec![], Box::new(std::io::sink())).unwrap();
        install(&mut vm).unwrap();
        let pattern = vm.alloc_string("yyyy-MM-dd");
        let formatter = vm
            .invoke_static(
                "Ljava/time/format/DateTimeFormatter;",
                "ofPattern",
                "(Ljava/lang/String;)Ljava/time/format/DateTimeFormatter;",
                vec![pattern],
            )
            .unwrap();
        let text = vm.alloc_string("2026-10-20");
        let date = vm.invoke_static(
            "Ljava/time/LocalDate;",
            "parse",
            "(Ljava/lang/CharSequence;Ljava/time/format/DateTimeFormatter;)Ljava/time/LocalDate;",
            vec![text, formatter],
        ).unwrap();
        assert!(matches!(vm.payload_of(date), Some(Native::LocalDay(day)) if day == 20_746));
        let text = vm.alloc_string("2026-02-30");
        assert!(local_date(&mut vm, &[text, formatter]).is_err());
        assert!(of_pattern(&mut vm, &[JValue::Null]).is_err());
        let huge = vm.alloc_string(&"y".repeat(257));
        assert!(of_pattern(&mut vm, &[huge]).is_err());
    }
    #[test]
    fn builders_retain_case_rules_and_midnight_respects_fixed_offsets() {
        let mut vm = Vm::new(vec![], Box::new(std::io::sink())).unwrap();
        super::super::java_compat::install(&mut vm).unwrap();
        install(&mut vm).unwrap();
        let builder = vm
            .alloc_native(
                "Ljava/time/format/DateTimeFormatterBuilder;",
                Native::DateFormatter {
                    pattern: "d MMMM yyyy".into(),
                    zone: String::new(),
                },
            )
            .unwrap();
        case_insensitive(&mut vm, &[builder]).unwrap();
        let formatter = to_formatter(&mut vm, &[builder]).unwrap();
        assert_eq!(formatter_zone(&mut vm, &[formatter]).unwrap(), JValue::Null);
        let text = vm.alloc_string("19 october 2026");
        let date = local_date(&mut vm, &[text, formatter]).unwrap();
        let offset = vm
            .alloc_native("Ljava/time/ZoneOffset;", Native::IntBox(19_800))
            .unwrap();
        let instant = start_of_day(&mut vm, &[date, offset]).unwrap();
        let expected = parse("2026-10-19", "yyyy-MM-dd", false).unwrap().0 - 19_800_000;
        assert!(matches!(vm.payload_of(instant),Some(Native::EpochMillis(v)) if v == expected));
    }
    #[test]
    fn optional_month_patterns_case_and_calendar_validation() {
        let expected = parse("2026-10-19T23:45:00", "yyyy-MM-dd'T'HH:mm:ss", false)
            .unwrap()
            .0;
        assert_eq!(
            parse(
                "19 october 2026 11:45 pm",
                "d [MMMM][MMM] yyyy h:mm a",
                true
            )
            .unwrap()
            .0,
            expected
        );
        assert!(parse("19 october 2026", "d MMMM yyyy", false).is_none());
        for text in ["October 19, 2026", "Oct 19, 2026"] {
            assert_eq!(
                parse(text, "[MMMM d, yyyy][MMM d, yyyy]", false).unwrap().0,
                expected - 85_500_000
            );
        }
        for (text, pattern) in [
            ("2026-02-30", "yyyy-MM-dd"),
            ("2026-13-01", "yyyy-MM-dd"),
            ("2026-10-19junk", "yyyy-MM-dd"),
            ("bad", "[yyyy-MM-dd"),
            ("2026-10-19 24:00", "yyyy-MM-dd HH:mm"),
        ] {
            assert!(parse(text, pattern, false).is_none());
        }
        assert!(parse("2024-02-29", "yyyy-MM-dd", false).is_some());
    }
}
