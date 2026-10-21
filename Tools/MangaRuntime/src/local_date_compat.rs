//! Signed Gregorian dates. Keep existing positive LocalDay payloads compatible;
//! negative epoch days use a traced, class-qualified LongBox rather than u32 wrap.
use chrono::{Datelike, Days, Months, NaiveDate};
use dexvm::vm::{error::JvmError, object::Native, NatErr, NativeEntry, Vm};
use dexvm::JValue;
type R = Result<JValue, NatErr>;
const DATE: &str = "Ljava/time/LocalDate;";
fn error(vm: &mut Vm) -> NatErr {
    NatErr::Throw(vm.throwable_of(
        "Ljava/time/DateTimeException;",
        "Date outside supported calendar range",
    ))
}
fn epoch() -> NaiveDate {
    NaiveDate::from_ymd_opt(1970, 1, 1).unwrap()
}
pub(super) fn day(vm: &mut Vm, value: JValue) -> Result<i64, NatErr> {
    match vm.payload_of(value) {
        Some(Native::LocalDay(d)) => Ok(i64::from(d)),
        Some(Native::LongBox(d)) => Ok(d),
        _ => Err(NatErr::Throw(vm.err_npe())),
    }
}
pub(super) fn from_day(vm: &mut Vm, day: i64) -> R {
    if epoch()
        .checked_add_signed(chrono::Duration::try_days(day).ok_or_else(|| error(vm))?)
        .is_none()
    {
        return Err(error(vm));
    }
    let payload = match u32::try_from(day) {
        Ok(d) => Native::LocalDay(d),
        Err(_) => Native::LongBox(day),
    };
    vm.alloc_native(DATE, payload).map_err(NatErr::Fatal)
}
fn calendar(vm: &mut Vm, value: JValue) -> Result<NaiveDate, NatErr> {
    let day = day(vm, value)?;
    epoch()
        .checked_add_signed(chrono::Duration::try_days(day).ok_or_else(|| error(vm))?)
        .ok_or_else(|| error(vm))
}
fn of(vm: &mut Vm, args: &[JValue]) -> R {
    let date = NaiveDate::from_ymd_opt(
        args[0].as_int(),
        args[1].as_int() as u32,
        args[2].as_int() as u32,
    )
    .ok_or_else(|| error(vm))?;
    from_day(vm, (date - epoch()).num_days())
}
fn parse_iso(vm: &mut Vm, args: &[JValue]) -> R {
    let text = vm
        .str_of_jvalue(args[0])
        .ok_or_else(|| NatErr::Throw(vm.err_npe()))?;
    if text.len() > 32 {
        return Err(error(vm));
    }
    let date = NaiveDate::parse_from_str(&text, "%Y-%m-%d").map_err(|_| {
        NatErr::Throw(vm.throwable_of(
            "Ljava/time/format/DateTimeParseException;",
            "Invalid ISO date",
        ))
    })?;
    // Java rejects lenient widths and whitespace.
    if date.to_string() != text {
        return Err(NatErr::Throw(vm.throwable_of(
            "Ljava/time/format/DateTimeParseException;",
            "Invalid ISO date",
        )));
    }
    from_day(vm, (date - epoch()).num_days())
}
fn of_epoch(vm: &mut Vm, args: &[JValue]) -> R {
    from_day(vm, args[0].as_long())
}
fn epoch_day(vm: &mut Vm, args: &[JValue]) -> R {
    Ok(JValue::Long(day(vm, args[0])?))
}
fn text(vm: &mut Vm, args: &[JValue]) -> R {
    let date = calendar(vm, args[0])?;
    Ok(vm.alloc_string(&date.to_string()))
}
fn plus_days(vm: &mut Vm, args: &[JValue]) -> R {
    let d = calendar(vm, args[0])?.checked_add_days(Days::new(args[1].as_long().unsigned_abs()));
    let date = if args[1].as_long() < 0 {
        calendar(vm, args[0])?.checked_sub_days(Days::new(args[1].as_long().unsigned_abs()))
    } else {
        d
    }
    .ok_or_else(|| error(vm))?;
    from_day(vm, (date - epoch()).num_days())
}
fn minus_days(vm: &mut Vm, args: &[JValue]) -> R {
    let amount = args[1].as_long().checked_neg().ok_or_else(|| error(vm))?;
    plus_days(vm, &[args[0], JValue::Long(amount)])
}
fn months(vm: &mut Vm, args: &[JValue], years: bool) -> R {
    let amount = args[1]
        .as_long()
        .checked_mul(if years { 12 } else { 1 })
        .ok_or_else(|| error(vm))?;
    let count = u32::try_from(amount.unsigned_abs()).map_err(|_| error(vm))?;
    let date = calendar(vm, args[0])?;
    let date = if amount < 0 {
        date.checked_sub_months(Months::new(count))
    } else {
        date.checked_add_months(Months::new(count))
    }
    .ok_or_else(|| error(vm))?;
    from_day(vm, (date - epoch()).num_days())
}
fn plus_months(vm: &mut Vm, args: &[JValue]) -> R {
    months(vm, args, false)
}
fn plus_years(vm: &mut Vm, args: &[JValue]) -> R {
    months(vm, args, true)
}
fn year(vm: &mut Vm, args: &[JValue]) -> R {
    Ok(JValue::Int(calendar(vm, args[0])?.year()))
}
fn month(vm: &mut Vm, args: &[JValue]) -> R {
    Ok(JValue::Int(calendar(vm, args[0])?.month() as i32))
}
fn day_month(vm: &mut Vm, args: &[JValue]) -> R {
    Ok(JValue::Int(calendar(vm, args[0])?.day() as i32))
}
fn start(vm: &mut Vm, args: &[JValue]) -> R {
    let millis = day(vm, args[0])?
        .checked_mul(86_400_000)
        .ok_or_else(|| error(vm))?;
    vm.alloc_native("Ljava/time/LocalDateTime;", Native::EpochMillis(millis))
        .map_err(NatErr::Fatal)
}
pub(super) fn install(vm: &mut Vm) -> Result<(), JvmError> {
    for (name, sig, instance, f) in [
        (
            "of",
            "(III)Ljava/time/LocalDate;",
            false,
            of as dexvm::vm::NativeFn,
        ),
        (
            "parse",
            "(Ljava/lang/CharSequence;)Ljava/time/LocalDate;",
            false,
            parse_iso,
        ),
        ("ofEpochDay", "(J)Ljava/time/LocalDate;", false, of_epoch),
        ("toEpochDay", "()J", true, epoch_day),
        ("toString", "()Ljava/lang/String;", true, text),
        ("plusDays", "(J)Ljava/time/LocalDate;", true, plus_days),
        ("minusDays", "(J)Ljava/time/LocalDate;", true, minus_days),
        ("plusMonths", "(J)Ljava/time/LocalDate;", true, plus_months),
        ("plusYears", "(J)Ljava/time/LocalDate;", true, plus_years),
        ("getYear", "()I", true, year),
        ("getMonthValue", "()I", true, month),
        ("getDayOfMonth", "()I", true, day_month),
        ("atStartOfDay", "()Ljava/time/LocalDateTime;", true, start),
    ] {
        vm.register_native(NativeEntry {
            class: DATE,
            name,
            sig,
            instance,
            f,
        })?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn signed_dates_cross_epoch_and_month_year_math_clamps_leap_days() {
        let mut vm = Vm::new(vec![], Box::new(std::io::sink())).unwrap();
        install(&mut vm).unwrap();
        let date = of(
            &mut vm,
            &[JValue::Int(1969), JValue::Int(12), JValue::Int(31)],
        )
        .unwrap();
        assert_eq!(epoch_day(&mut vm, &[date]).unwrap(), JValue::Long(-1));
        let rendered = text(&mut vm, &[date]).unwrap();
        assert_eq!(vm.str_of_jvalue(rendered).unwrap(), "1969-12-31");
        let next = plus_days(&mut vm, &[date, JValue::Long(1)]).unwrap();
        assert_eq!(day(&mut vm, next).unwrap(), 0);
        let leap = of(
            &mut vm,
            &[JValue::Int(2024), JValue::Int(2), JValue::Int(29)],
        )
        .unwrap();
        let next = plus_years(&mut vm, &[leap, JValue::Long(1)]).unwrap();
        let rendered = text(&mut vm, &[next]).unwrap();
        assert_eq!(vm.str_of_jvalue(rendered).unwrap(), "2025-02-28");
        let jan = of(
            &mut vm,
            &[JValue::Int(2024), JValue::Int(1), JValue::Int(31)],
        )
        .unwrap();
        let feb = plus_months(&mut vm, &[jan, JValue::Long(1)]).unwrap();
        assert_eq!(day(&mut vm, feb).unwrap(), day(&mut vm, leap).unwrap());
        assert!(of(
            &mut vm,
            &[JValue::Int(2023), JValue::Int(2), JValue::Int(29)]
        )
        .is_err());
        assert!(plus_days(&mut vm, &[date, JValue::Long(i64::MAX)]).is_err());
        assert!(minus_days(&mut vm, &[date, JValue::Long(i64::MIN)]).is_err());
        for invalid in ["2024-02-30", "2024-2-9", "2024-02-29 "] {
            let value = vm.alloc_string(invalid);
            assert!(parse_iso(&mut vm, &[value]).is_err());
        }
    }
    #[test]
    fn pre_epoch_dates_keep_formatter_zone_and_day_of_week_semantics() {
        let mut vm = Vm::new(vec![], Box::new(std::io::sink())).unwrap();
        super::super::locale_compat::install(&mut vm).unwrap();
        super::super::date_compat::install(&mut vm).unwrap();
        super::super::date_zone_compat::install(&mut vm, "America/Los_Angeles").unwrap();
        install(&mut vm).unwrap();
        let pattern = vm.alloc_string("yyyy-MM-dd");
        let fmt = vm
            .invoke_static(
                "Ljava/time/format/DateTimeFormatter;",
                "ofPattern",
                "(Ljava/lang/String;)Ljava/time/format/DateTimeFormatter;",
                vec![pattern],
            )
            .unwrap();
        let text = vm.alloc_string("1969-12-31");
        let date=vm.invoke_static(DATE,"parse","(Ljava/lang/CharSequence;Ljava/time/format/DateTimeFormatter;)Ljava/time/LocalDate;",vec![text,fmt]).unwrap();
        let rendered = vm
            .invoke_virtual_args(
                date,
                "format",
                "(Ljava/time/format/DateTimeFormatter;)Ljava/lang/String;",
                vec![fmt],
            )
            .unwrap();
        assert_eq!(vm.str_of_jvalue(rendered).unwrap(), "1969-12-31");
        let zone = super::super::date_zone_compat::of_id(&mut vm, "America/Los_Angeles").unwrap();
        let zoned = vm
            .invoke_virtual_args(
                date,
                "atStartOfDay",
                "(Ljava/time/ZoneId;)Ljava/time/ZonedDateTime;",
                vec![zone],
            )
            .unwrap();
        assert!(matches!(vm.payload_of(zoned),Some(Native::EpochMillis(m)) if m == -57_600_000));
        let weekday = vm
            .invoke_virtual(date, "getDayOfWeek", "()Ljava/time/DayOfWeek;")
            .unwrap();
        assert_eq!(
            vm.invoke_virtual(weekday, "getValue", "()I").unwrap(),
            JValue::Int(3)
        );
    }
}
