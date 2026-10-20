//! Bounded Java date patterns used by source chapter timestamps. Preserve
//! optional sections, English month names and case-insensitive builders.
use dexvm::vm::object::Native;
use dexvm::vm::{error::JvmError, NatErr, NativeEntry, Vm};
use dexvm::JValue;

type R = Result<JValue, NatErr>;
const INSENSITIVE: &str = "ac:case-insensitive";
const MONTHS: [&str; 12] = [
    "January",
    "February",
    "March",
    "April",
    "May",
    "June",
    "July",
    "August",
    "September",
    "October",
    "November",
    "December",
];

fn case_insensitive(vm: &mut Vm, args: &[JValue]) -> R {
    let Some(Native::DateFormatter { zone, .. }) =
        vm.arena.objects[args[0].as_obj() as usize].native.as_mut()
    else {
        return Err(NatErr::Throw(vm.err_npe()));
    };
    *zone = INSENSITIVE.to_owned();
    Ok(args[0])
}
fn to_formatter(vm: &mut Vm, args: &[JValue]) -> R {
    let Some(value @ Native::DateFormatter { .. }) = vm.payload_of(args[0]) else {
        return Err(NatErr::Throw(vm.err_npe()));
    };
    vm.alloc_native("Ljava/time/format/DateTimeFormatter;", value)
        .map_err(NatErr::Fatal)
}
fn formatter_zone(vm: &mut Vm, args: &[JValue]) -> R {
    let Some(Native::DateFormatter { zone, .. }) = vm.payload_of(args[0]) else {
        return Err(NatErr::Throw(vm.err_npe()));
    };
    if zone.is_empty() || zone == INSENSITIVE {
        return Ok(JValue::Null);
    }
    Err(NatErr::Throw(vm.err_iae("Unsupported formatter zone")))
}
fn start_of_day(vm: &mut Vm, args: &[JValue]) -> R {
    let Some(Native::LocalDay(day)) = vm.payload_of(args[0]) else {
        return Err(NatErr::Throw(vm.err_npe()));
    };
    let offset = match vm.payload_of(args[1]) {
        Some(Native::IntBox(seconds)) => i64::from(seconds),
        // Unknown region rules must not become a fabricated timestamp. Explicit
        // ZoneOffset values must not inherit the old unconditional +07:00 offset.
        _ => return Err(NatErr::Throw(vm.err_iae("A fixed zone offset is required"))),
    };
    vm.alloc_native(
        "Ljava/time/ZonedDateTime;",
        Native::EpochMillis(i64::from(day) * 86_400_000 - offset * 1000),
    )
    .map_err(NatErr::Fatal)
}
fn parse(text: &str, pattern: &str, insensitive: bool) -> Option<(i64, i32)> {
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
    while index < chars.len() {
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
        while chars.get(index) == Some(&c) {
            count += 1;
            index += 1;
        }
        let expression = match (c, count) {
            ('y' | 'u', 2) => "[0-9]{2}".to_owned(),
            ('y' | 'u', 1..=4) => "[0-9]{4}".to_owned(),
            ('M' | 'L', 3 | 4) => MONTHS
                .iter()
                .map(|s| if count == 3 { &s[..3] } else { s })
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
        fields.push((c, count));
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
    let (mut year, mut month, mut day, mut hour, mut minute, mut second, mut millis) =
        (1970, 1, 1, 0, 0, 0, 0);
    let (mut twelve_hour, mut pm) = (false, None);
    for (index, (c, count)) in fields.into_iter().enumerate() {
        let Some(value) = captures.get(index + 1).map(|v| v.as_str()) else {
            continue;
        };
        match c {
            'y' | 'u' => {
                year = value.parse::<i32>().ok()?;
                if count == 2 {
                    year += 2000;
                }
            }
            'M' | 'L' if count >= 3 => {
                month = MONTHS.iter().position(|m| {
                    m.eq_ignore_ascii_case(value)
                        || (count == 3 && m[..3].eq_ignore_ascii_case(value))
                })? as u8
                    + 1
            }
            'M' | 'L' => month = value.parse().ok()?,
            'd' => day = value.parse().ok()?,
            'h' => {
                hour = value.parse().ok()?;
                twelve_hour = true;
            }
            'H' => hour = value.parse().ok()?,
            'm' => minute = value.parse().ok()?,
            's' => second = value.parse().ok()?,
            'S' => millis = format!("{value}000")[..3].parse::<u32>().ok()?,
            'a' => pm = Some(value.eq_ignore_ascii_case("pm")),
            _ => return None,
        }
    }
    if twelve_hour {
        if !(1..=12).contains(&hour) {
            return None;
        }
        hour = hour % 12 + if pm? { 12 } else { 0 };
    }
    let date =
        time::Date::from_calendar_date(year, time::Month::try_from(month).ok()?, day).ok()?;
    let moment = date
        .with_hms_milli(hour, minute, second, millis as u16)
        .ok()?
        .assume_utc();
    Some((
        i64::try_from(moment.unix_timestamp_nanos() / 1_000_000).ok()?,
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
    parse(&text, &pattern, zone == INSENSITIVE).ok_or_else(|| {
        NatErr::Throw(vm.throwable_of(
            "Ljava/time/format/DateTimeParseException;",
            "Unsupported pattern or invalid date",
        ))
    })
}
fn local_date(vm: &mut Vm, args: &[JValue]) -> R {
    let (_, day) = parsed(vm, args)?;
    let day = u32::try_from(day)
        .map_err(|_| NatErr::Throw(vm.err_iae("LocalDate before runtime epoch is unsupported")))?;
    vm.alloc_native("Ljava/time/LocalDate;", Native::LocalDay(day))
        .map_err(NatErr::Fatal)
}
fn local_datetime(vm: &mut Vm, args: &[JValue]) -> R {
    let (millis, _) = parsed(vm, args)?;
    vm.alloc_native("Ljava/time/LocalDateTime;", Native::EpochMillis(millis))
        .map_err(NatErr::Fatal)
}
fn exception_init(vm: &mut Vm, args: &[JValue]) -> R {
    let message = vm.str_of_jvalue(args[1]);
    vm.arena.objects[args[0].as_obj() as usize].native = Some(Native::Throwable {
        message,
        cause: JValue::Null,
    });
    Ok(JValue::Null)
}
pub(super) fn install(vm: &mut Vm) -> Result<(), JvmError> {
    for (class, name, sig, instance, f) in [
        ("Ljava/time/format/DateTimeFormatterBuilder;", "parseCaseInsensitive", "()Ljava/time/format/DateTimeFormatterBuilder;", true, case_insensitive as dexvm::vm::NativeFn),
        ("Ljava/time/format/DateTimeFormatterBuilder;", "toFormatter", "(Ljava/util/Locale;)Ljava/time/format/DateTimeFormatter;", true, to_formatter),
        ("Ljava/time/format/DateTimeFormatterBuilder;", "toFormatter", "()Ljava/time/format/DateTimeFormatter;", true, to_formatter),
        ("Ljava/time/LocalDate;", "parse", "(Ljava/lang/CharSequence;Ljava/time/format/DateTimeFormatter;)Ljava/time/LocalDate;", false, local_date),
        ("Ljava/time/LocalDate;", "atStartOfDay", "(Ljava/time/ZoneId;)Ljava/time/ZonedDateTime;", true, start_of_day),
        ("Ljava/time/LocalDateTime;", "parse", "(Ljava/lang/CharSequence;Ljava/time/format/DateTimeFormatter;)Ljava/time/LocalDateTime;", false, local_datetime),
        ("Ljava/time/format/DateTimeFormatter;", "getZone", "()Ljava/time/ZoneId;", true, formatter_zone),
        ("Ljava/time/DateTimeException;", "<init>", "(Ljava/lang/String;)V", true, exception_init),
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
