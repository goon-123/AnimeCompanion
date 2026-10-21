//! Localized weekday text and week fields use the actual calendar date.
use chrono::Datelike;
use dexvm::vm::{error::JvmError, object::Native, NatErr, NativeEntry, Vm};
use dexvm::JValue;
type R = Result<JValue, NatErr>;
const WEEK: &str = "Ljava/time/temporal/WeekFields;";
const FIELD: &str = "Ljava/time/temporal/WeekFields$ComputedDayOfField;";
fn invalid(vm: &mut Vm, message: &str) -> NatErr {
    NatErr::Throw(vm.throwable_of("Ljava/time/DateTimeException;", message))
}
fn day_number(vm: &mut Vm, value: JValue) -> Result<i32, NatErr> {
    match vm.payload_of(value) {
        Some(Native::Enum { ordinal, .. }) if (0..7).contains(&ordinal) => Ok(ordinal + 1),
        _ => Err(invalid(vm, "Invalid weekday")),
    }
}
fn display(vm: &mut Vm, args: &[JValue]) -> R {
    let weekday = day_number(vm, args[0])?;
    let style = match vm.payload_of(args[1]) {
        Some(Native::Enum { ordinal, .. }) if (0..6).contains(&ordinal) => ordinal,
        _ => return Err(NatErr::Throw(vm.err_npe())),
    };
    if args[2].is_null_ref() {
        return Err(NatErr::Throw(vm.err_npe()));
    }
    let locale = super::locale_compat::calendar_locale(vm, args[2])?
        .ok_or_else(|| invalid(vm, "Unsupported calendar locale"))?;
    let date = chrono::NaiveDate::from_ymd_opt(2024, 1, weekday as u32).unwrap(); // Jan 1 was Monday.
    let name = date
        .format_localized(if style < 2 { "%A" } else { "%a" }, locale)
        .to_string();
    let name = if style >= 4 {
        name.chars().take(1).collect()
    } else {
        name
    };
    Ok(vm.alloc_string(&name))
}
fn new_week(vm: &mut Vm, first: i32, min: i32) -> R {
    if !(1..=7).contains(&first) || !(1..=7).contains(&min) {
        return Err(NatErr::Throw(vm.err_iae("Invalid week definition")));
    }
    let value = vm
        .alloc_native(WEEK, Native::Opaque)
        .map_err(NatErr::Fatal)?;
    vm.arena.objects[value.as_obj() as usize].fields = vec![JValue::Int(first), JValue::Int(min)];
    Ok(value)
}
fn of(vm: &mut Vm, args: &[JValue]) -> R {
    let first = day_number(vm, args[0])?;
    new_week(vm, first, args[1].as_int())
}
fn definition(vm: &mut Vm, value: JValue) -> Result<(i32, i32), NatErr> {
    if value.is_null_ref() {
        return Err(NatErr::Throw(vm.err_npe()));
    }
    match vm.arena.objects[value.as_obj() as usize].fields.as_slice() {
        [first, min, ..]
            if (1..=7).contains(&first.as_int()) && (1..=7).contains(&min.as_int()) =>
        {
            Ok((first.as_int(), min.as_int()))
        }
        _ => Err(invalid(vm, "Invalid week definition")),
    }
}
fn computed(vm: &mut Vm, args: &[JValue], kind: i32) -> R {
    let (first, min) = definition(vm, args[0])?;
    let value = vm
        .alloc_native(FIELD, Native::Opaque)
        .map_err(NatErr::Fatal)?;
    vm.arena.objects[value.as_obj() as usize].fields =
        vec![JValue::Int(first), JValue::Int(min), JValue::Int(kind)];
    Ok(value)
}
fn day_of_week(vm: &mut Vm, args: &[JValue]) -> R {
    computed(vm, args, 0)
}
fn week_of_month(vm: &mut Vm, args: &[JValue]) -> R {
    computed(vm, args, 1)
}
fn week_of_year(vm: &mut Vm, args: &[JValue]) -> R {
    computed(vm, args, 2)
}
fn week_of_week_year(vm: &mut Vm, args: &[JValue]) -> R {
    computed(vm, args, 3)
}
fn week_year(vm: &mut Vm, args: &[JValue]) -> R {
    computed(vm, args, 4)
}
fn first_week(date: chrono::NaiveDate, first: i32, min: i32) -> Option<chrono::NaiveDate> {
    let offset = (date.weekday().number_from_monday() as i32 - first).rem_euclid(7);
    date.checked_add_signed(chrono::Duration::days(i64::from(if 7 - offset < min {
        7 - offset
    } else {
        -offset
    })))
}
fn get_long(vm: &mut Vm, args: &[JValue]) -> R {
    let day = super::local_date_compat::day(vm, args[0])?;
    let date = chrono::NaiveDate::from_ymd_opt(1970, 1, 1)
        .unwrap()
        .checked_add_signed(chrono::Duration::days(day))
        .ok_or_else(|| invalid(vm, "Date exceeds supported range"))?;
    let value = match vm.payload_of(args[1]) {
        Some(Native::Enum { ordinal, .. }) => match ordinal {
            15 => i64::from(date.weekday().number_from_monday()),
            18 => i64::from(date.day()),
            19 => i64::from(date.ordinal()),
            20 => day,
            23 => i64::from(date.month()),
            25 => i64::from(if date.year() > 0 {
                date.year()
            } else {
                1 - date.year()
            }),
            26 => i64::from(date.year()),
            27 => i64::from(date.year() > 0),
            _ => return Err(invalid(vm, "Unsupported date field")),
        },
        _ => {
            let (first, min) = definition(vm, args[1])?;
            let kind = vm.arena.objects[args[1].as_obj() as usize]
                .fields
                .get(2)
                .map_or(-1, |v| v.as_int());
            let start = chrono::NaiveDate::from_ymd_opt(date.year(), 1, 1).unwrap();
            match kind {
                0 => i64::from(
                    (date.weekday().number_from_monday() as i32 - first).rem_euclid(7) + 1,
                ),
                1 => {
                    let start =
                        chrono::NaiveDate::from_ymd_opt(date.year(), date.month(), 1).unwrap();
                    (date
                        - first_week(start, first, min)
                            .ok_or_else(|| invalid(vm, "Week exceeds supported range"))?)
                    .num_days()
                    .div_euclid(7)
                        + 1
                }
                2 => {
                    (date
                        - first_week(start, first, min)
                            .ok_or_else(|| invalid(vm, "Week exceeds supported range"))?)
                    .num_days()
                    .div_euclid(7)
                        + 1
                }
                3 | 4 => {
                    let mut year = date.year();
                    let next = chrono::NaiveDate::from_ymd_opt(year + 1, 1, 1)
                        .ok_or_else(|| invalid(vm, "Week year exceeds supported range"))?;
                    if date
                        < first_week(start, first, min)
                            .ok_or_else(|| invalid(vm, "Week exceeds supported range"))?
                    {
                        year -= 1;
                    } else if date
                        >= first_week(next, first, min)
                            .ok_or_else(|| invalid(vm, "Week exceeds supported range"))?
                    {
                        year += 1;
                    }
                    if kind == 4 {
                        i64::from(year)
                    } else {
                        let start = chrono::NaiveDate::from_ymd_opt(year, 1, 1)
                            .ok_or_else(|| invalid(vm, "Week year exceeds supported range"))?;
                        (date
                            - first_week(start, first, min)
                                .ok_or_else(|| invalid(vm, "Week exceeds supported range"))?)
                        .num_days()
                        .div_euclid(7)
                            + 1
                    }
                }
                _ => return Err(invalid(vm, "Unsupported date field")),
            }
        }
    };
    Ok(JValue::Long(value))
}
fn get(vm: &mut Vm, args: &[JValue]) -> R {
    let n = get_long(vm, args)?.as_long();
    let n = i32::try_from(n).map_err(|_| invalid(vm, "Field needs getLong"))?;
    Ok(JValue::Int(n))
}
fn get_from(vm: &mut Vm, args: &[JValue]) -> R {
    get_long(vm, &[args[1], args[0]])
}
pub(super) fn install(vm: &mut Vm) -> Result<(), JvmError> {
    for (class, name, sig, instance, f) in [
        (
            "Ljava/time/DayOfWeek;",
            "getDisplayName",
            "(Ljava/time/format/TextStyle;Ljava/util/Locale;)Ljava/lang/String;",
            true,
            display as dexvm::vm::NativeFn,
        ),
        (
            WEEK,
            "of",
            "(Ljava/time/DayOfWeek;I)Ljava/time/temporal/WeekFields;",
            false,
            of,
        ),
        (
            WEEK,
            "dayOfWeek",
            "()Ljava/time/temporal/TemporalField;",
            true,
            day_of_week,
        ),
        (
            WEEK,
            "weekOfMonth",
            "()Ljava/time/temporal/TemporalField;",
            true,
            week_of_month,
        ),
        (
            WEEK,
            "weekOfYear",
            "()Ljava/time/temporal/TemporalField;",
            true,
            week_of_year,
        ),
        (
            WEEK,
            "weekOfWeekBasedYear",
            "()Ljava/time/temporal/TemporalField;",
            true,
            week_of_week_year,
        ),
        (
            WEEK,
            "weekBasedYear",
            "()Ljava/time/temporal/TemporalField;",
            true,
            week_year,
        ),
        (
            "Ljava/time/LocalDate;",
            "get",
            "(Ljava/time/temporal/TemporalField;)I",
            true,
            get,
        ),
        (
            "Ljava/time/LocalDate;",
            "getLong",
            "(Ljava/time/temporal/TemporalField;)J",
            true,
            get_long,
        ),
        (
            FIELD,
            "getFrom",
            "(Ljava/time/temporal/TemporalAccessor;)J",
            true,
            get_from,
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
    let field = vm.ensure_class_by_desc(FIELD)?;
    let interface = vm.ensure_class_by_desc("Ljava/time/temporal/TemporalField;")?;
    vm.classes[field as usize].interfaces.push(interface);
    for (name, first, min) in [("ISO", 1, 4), ("SUNDAY_START", 7, 1)] {
        let value = new_week(vm, first, min)
            .map_err(|_| JvmError::Fatal("Cannot initialize week definition".into()))?;
        super::multipart_compat::static_value(vm, WEEK, name, WEEK, value)?;
    }
    Ok(())
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn localized_week_fields_cross_month_and_week_year_boundaries() {
        let mut vm = Vm::new(vec![], Box::new(std::io::sink())).unwrap();
        super::super::date_compat::install(&mut vm).unwrap();
        super::super::local_date_compat::install(&mut vm).unwrap();
        install(&mut vm).unwrap();
        let iso = new_week(&mut vm, 1, 4).unwrap();
        let sunday = new_week(&mut vm, 7, 1).unwrap();
        let year = week_year(&mut vm, &[iso]).unwrap();
        let week = week_of_week_year(&mut vm, &[iso]).unwrap();
        let dow = day_of_week(&mut vm, &[sunday]).unwrap();
        let date = super::super::local_date_compat::from_day(&mut vm, 18628).unwrap(); // 2021-01-01, Fri
        assert_eq!(get(&mut vm, &[date, year]).unwrap(), JValue::Int(2020));
        assert_eq!(get(&mut vm, &[date, week]).unwrap(), JValue::Int(53));
        assert_eq!(get(&mut vm, &[date, dow]).unwrap(), JValue::Int(6));
        let date = super::super::local_date_compat::from_day(&mut vm, 20087).unwrap(); // 2024-12-30
        assert_eq!(get(&mut vm, &[date, year]).unwrap(), JValue::Int(2025));
        assert_eq!(get(&mut vm, &[date, week]).unwrap(), JValue::Int(1));
    }
}
