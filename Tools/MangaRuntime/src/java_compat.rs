//! Shared Java contracts used by many independently published source families.
//! These are host APIs, not source-specific request builders or parsers.
use dexvm::vm::error::JvmError;
use dexvm::vm::object::{IterKind, Native};
use dexvm::vm::{NatErr, NativeEntry, Vm};
use dexvm::JValue;

type ResultValue = Result<JValue, NatErr>;

fn exception(vm: &mut Vm, class: &str, message: &str) -> NatErr {
    NatErr::Throw(vm.throwable_of(class, message))
}

fn iterator_position(vm: &mut Vm, value: JValue) -> Result<(u32, usize), NatErr> {
    match vm.payload_of(value) {
        Some(Native::Iter(IterKind::List { list, idx })) => Ok((list, idx)),
        _ => Err(exception(
            vm,
            "Ljava/lang/IllegalStateException;",
            "Invalid list iterator",
        )),
    }
}

fn has_previous(vm: &mut Vm, args: &[JValue]) -> ResultValue {
    Ok(JValue::Int(i32::from(
        iterator_position(vm, args[0])?.1 > 0,
    )))
}

fn previous(vm: &mut Vm, args: &[JValue]) -> ResultValue {
    let (list, index) = iterator_position(vm, args[0])?;
    let value = index
        .checked_sub(1)
        .and_then(|index| match vm.payload_of(JValue::Obj(list)) {
            Some(Native::List(values)) | Some(Native::SFilterList(values)) => {
                values.get(index).copied()
            }
            _ => None,
        })
        .ok_or_else(|| exception(vm, "Ljava/util/NoSuchElementException;", "Start of list"))?;
    vm.arena.objects[args[0].as_obj() as usize].native = Some(Native::Iter(IterKind::List {
        list,
        idx: index - 1,
    }));
    Ok(value)
}

fn next_index(vm: &mut Vm, args: &[JValue]) -> ResultValue {
    Ok(JValue::Int(iterator_position(vm, args[0])?.1 as i32))
}
fn previous_index(vm: &mut Vm, args: &[JValue]) -> ResultValue {
    Ok(JValue::Int(iterator_position(vm, args[0])?.1 as i32 - 1))
}

fn zone_offset(vm: &mut Vm, seconds: i32) -> ResultValue {
    if !(-64_800..=64_800).contains(&seconds) {
        return Err(exception(
            vm,
            "Ljava/lang/IllegalArgumentException;",
            "Offset outside +/-18 hours",
        ));
    }
    vm.alloc_native("Ljava/time/ZoneOffset;", Native::IntBox(seconds))
        .map_err(NatErr::Fatal)
}
fn offset_seconds(vm: &mut Vm, args: &[JValue]) -> ResultValue {
    match vm.payload_of(args[0]) {
        Some(Native::IntBox(seconds)) => Ok(JValue::Int(seconds)),
        _ => Err(exception(
            vm,
            "Ljava/lang/IllegalArgumentException;",
            "Invalid zone offset",
        )),
    }
}
fn offset_of_seconds(vm: &mut Vm, args: &[JValue]) -> ResultValue {
    zone_offset(vm, args[0].as_int())
}
fn offset_of_hours(vm: &mut Vm, args: &[JValue]) -> ResultValue {
    let hours = args[0].as_int();
    if !(-18..=18).contains(&hours) {
        return Err(exception(
            vm,
            "Ljava/lang/IllegalArgumentException;",
            "Invalid offset hours",
        ));
    }
    zone_offset(vm, hours * 3600)
}
fn offset_of(vm: &mut Vm, args: &[JValue]) -> ResultValue {
    let text = vm.str_of_jvalue(args[0]).unwrap_or_default();
    if text == "Z" {
        return zone_offset(vm, 0);
    }
    let (sign, rest) = match text.as_bytes().first() {
        Some(b'+') => (1, &text[1..]),
        Some(b'-') => (-1, &text[1..]),
        _ => {
            return Err(exception(
                vm,
                "Ljava/lang/IllegalArgumentException;",
                "Invalid zone offset",
            ))
        }
    };
    let digits: String = rest.chars().filter(|c| *c != ':').collect();
    let parsed = (|| {
        if ![2, 4, 6].contains(&digits.len()) || !digits.bytes().all(|c| c.is_ascii_digit()) {
            return None;
        }
        let hours: i32 = digits[..2].parse().ok()?;
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
        if minutes > 59 || seconds > 59 {
            return None;
        }
        Some(sign * (hours * 3600 + minutes * 60 + seconds))
    })();
    match parsed {
        Some(seconds) => zone_offset(vm, seconds),
        None => Err(exception(
            vm,
            "Ljava/lang/IllegalArgumentException;",
            "Invalid zone offset",
        )),
    }
}
fn local_epoch_seconds(vm: &mut Vm, args: &[JValue]) -> ResultValue {
    let millis = match vm.payload_of(args[0]) {
        Some(Native::EpochMillis(value)) => value,
        _ => {
            return Err(exception(
                vm,
                "Ljava/lang/IllegalArgumentException;",
                "Invalid local date",
            ))
        }
    };
    let offset = offset_seconds(vm, &args[1..])?.as_int();
    Ok(JValue::Long(millis.div_euclid(1000) - i64::from(offset)))
}
fn local_instant(vm: &mut Vm, args: &[JValue]) -> ResultValue {
    let Some(Native::EpochMillis(millis)) = vm.payload_of(args[0]) else {
        return Err(exception(
            vm,
            "Ljava/lang/IllegalArgumentException;",
            "Invalid local date",
        ));
    };
    let offset = i64::from(offset_seconds(vm, &args[1..])?.as_int()) * 1000;
    let instant = millis
        .checked_sub(offset)
        .ok_or_else(|| exception(vm, "Ljava/lang/ArithmeticException;", "Instant overflow"))?;
    vm.alloc_native("Ljava/time/Instant;", Native::EpochMillis(instant))
        .map_err(NatErr::Fatal)
}
fn date_format(vm: &mut Vm, args: &[JValue]) -> ResultValue {
    vm.invoke_virtual_args(
        args[1],
        "format",
        "(Ljava/time/temporal/TemporalAccessor;)Ljava/lang/String;",
        vec![args[0]],
    )
    .map_err(NatErr::Fatal)
}
fn json_quote(vm: &mut Vm, args: &[JValue]) -> ResultValue {
    // JSONObject.quote is static: there is no receiver at args[0].
    let text = vm.str_of_jvalue(args[0]).unwrap_or_default();
    let quoted = serde_json::to_string(&text)
        .map_err(|e| NatErr::Fatal(JvmError::Resolution(e.to_string())))?;
    Ok(vm.alloc_string(&quoted))
}
fn string_builder_append(vm: &mut Vm, args: &[JValue]) -> ResultValue {
    let text = if args[1].is_null_ref() {
        "null".into()
    } else {
        vm.str_of_jvalue(args[1]).ok_or_else(|| {
            exception(vm, "Ljava/lang/IllegalArgumentException;", "Invalid string")
        })?
    };
    let Some(Native::StringBuilder(value)) =
        vm.arena.objects[args[0].as_obj() as usize].native.as_mut()
    else {
        return Err(exception(
            vm,
            "Ljava/lang/IllegalStateException;",
            "Invalid string builder",
        ));
    };
    value.push_str(&text);
    Ok(args[0])
}
fn app_version(vm: &mut Vm, _args: &[JValue]) -> ResultValue {
    Ok(vm.alloc_string("0.22.0"))
}
fn duration_infinite(_vm: &mut Vm, _args: &[JValue]) -> ResultValue {
    Ok(JValue::Long(i64::MAX))
}
fn mutex_lock(vm: &mut Vm, args: &[JValue]) -> ResultValue {
    let acquired = mutex_try_lock(vm, args)?;
    if acquired.as_int() == 0 {
        return Err(exception(
            vm,
            "Ljava/lang/IllegalStateException;",
            "Mutex would suspend the single guest thread",
        ));
    }
    let field = dexvm::vm::FieldRef {
        class_desc: vm.intern("Lkotlin/Unit;"),
        name: vm.intern("INSTANCE"),
        ty: vm.intern("Lkotlin/Unit;"),
    };
    vm.static_field_get(field).map_err(NatErr::Fatal)
}
fn mutex_try_lock(vm: &mut Vm, args: &[JValue]) -> ResultValue {
    let id = args[0].as_obj() as usize;
    let held = match vm.arena.objects[id].native {
        Some(Native::Mutex { locked }) => locked,
        _ => {
            return Err(exception(
                vm,
                "Ljava/lang/IllegalStateException;",
                "Invalid mutex",
            ))
        }
    };
    let owner = args.get(1).copied().unwrap_or(JValue::Null);
    if held {
        if !owner.is_null_ref() && vm.arena.objects[id].fields.first() == Some(&owner) {
            return Err(exception(
                vm,
                "Ljava/lang/IllegalStateException;",
                "Mutex is already locked by this owner",
            ));
        }
        return Ok(JValue::Int(0));
    }
    vm.arena.objects[id].native = Some(Native::Mutex { locked: true });
    vm.arena.objects[id].fields = vec![owner];
    Ok(JValue::Int(1))
}
fn mutex_unlock(vm: &mut Vm, args: &[JValue]) -> ResultValue {
    let id = args[0].as_obj() as usize;
    let held = matches!(
        vm.arena.objects[id].native,
        Some(Native::Mutex { locked: true })
    );
    let owner = args.get(1).copied().unwrap_or(JValue::Null);
    if !held || (!owner.is_null_ref() && vm.arena.objects[id].fields.first() != Some(&owner)) {
        return Err(exception(
            vm,
            "Ljava/lang/IllegalStateException;",
            "Mutex is not locked by this owner",
        ));
    }
    vm.arena.objects[id].native = Some(Native::Mutex { locked: false });
    vm.arena.objects[id].fields.clear();
    Ok(JValue::Null)
}
fn webview_class_loader(vm: &mut Vm, _args: &[JValue]) -> ResultValue {
    // Guest classes/resources only; never JNI or the native iOS class loader.
    vm.alloc_native("Ljava/lang/ClassLoader;", Native::Opaque)
        .map_err(NatErr::Fatal)
}
fn class_for_name(vm: &mut Vm, args: &[JValue]) -> ResultValue {
    use dexvm::vm::object::ClassOrPrim;
    let name = vm
        .str_of_jvalue(args[0])
        .ok_or_else(|| exception(vm, "Ljava/lang/NullPointerException;", "Missing class name"))?;
    let primitive = match name.as_str() {
        "boolean" => Some(b'Z'),
        "byte" => Some(b'B'),
        "char" => Some(b'C'),
        "short" => Some(b'S'),
        "int" => Some(b'I'),
        "long" => Some(b'J'),
        "float" => Some(b'F'),
        "double" => Some(b'D'),
        "void" => Some(b'V'),
        _ => None,
    };
    if let Some(code) = primitive {
        return vm
            .alloc_native(
                "Ljava/lang/Class;",
                Native::ClassObj(ClassOrPrim::Primitive(code)),
            )
            .map_err(NatErr::Fatal);
    }
    let desc = if name.starts_with('[') {
        name.replace('.', "/")
    } else {
        format!("L{};", name.replace('.', "/"))
    };
    match vm.ensure_class_by_desc(&desc) {
        Ok(class) => {
            if args.get(1).map(|value| value.as_int() != 0).unwrap_or(true) {
                vm.ensure_class_initialized(class).map_err(NatErr::Fatal)?;
            }
            vm.class_obj(class).map_err(NatErr::Fatal)
        }
        Err(JvmError::Resolution(error)) if error.starts_with("class not found:") => {
            // Library capability detection catches this Java exception. A
            // missing optional class must not abort the entire interpreter.
            Err(exception(vm, "Ljava/lang/ClassNotFoundException;", &name))
        }
        Err(error) => Err(NatErr::Fatal(error)),
    }
}
fn class_loader_load(vm: &mut Vm, args: &[JValue]) -> ResultValue {
    class_for_name(vm, &[args[1], JValue::Int(0), JValue::Null])
}
fn regex_escape(vm: &mut Vm, args: &[JValue]) -> ResultValue {
    let text = vm.str_of_jvalue(args[1]).ok_or_else(|| {
        exception(
            vm,
            "Ljava/lang/NullPointerException;",
            "Missing regex literal",
        )
    })?;
    Ok(vm.alloc_string(&fancy_regex::escape(&text)))
}
fn atomic_init(vm: &mut Vm, args: &[JValue]) -> ResultValue {
    vm.arena.objects[args[0].as_obj() as usize].native = Some(Native::LongBox(
        args.get(1).map(JValue::as_long).unwrap_or(0),
    ));
    Ok(JValue::Null)
}
fn atomic_get(vm: &mut Vm, args: &[JValue]) -> ResultValue {
    match vm.payload_of(args[0]) {
        Some(Native::LongBox(n)) => Ok(JValue::Long(n)),
        _ => Err(exception(
            vm,
            "Ljava/lang/IllegalStateException;",
            "Invalid atomic long",
        )),
    }
}
fn atomic_set(vm: &mut Vm, args: &[JValue]) -> ResultValue {
    vm.arena.objects[args[0].as_obj() as usize].native = Some(Native::LongBox(args[1].as_long()));
    Ok(JValue::Null)
}
fn atomic_swap(vm: &mut Vm, args: &[JValue]) -> ResultValue {
    let old = atomic_get(vm, args)?;
    atomic_set(vm, args)?;
    Ok(old)
}
fn atomic_add(vm: &mut Vm, args: &[JValue]) -> ResultValue {
    let old = atomic_get(vm, args)?.as_long();
    let updated = old.wrapping_add(args.get(1).map(JValue::as_long).unwrap_or(1));
    atomic_set(vm, &[args[0], JValue::Long(updated)])?;
    Ok(JValue::Long(updated))
}
fn atomic_get_add(vm: &mut Vm, args: &[JValue]) -> ResultValue {
    let old = atomic_get(vm, args)?;
    atomic_add(vm, args)?;
    Ok(old)
}
fn atomic_compare_set(vm: &mut Vm, args: &[JValue]) -> ResultValue {
    let matches = atomic_get(vm, args)? == args[1];
    if matches {
        atomic_set(vm, &[args[0], args[2]])?;
    }
    Ok(JValue::Int(i32::from(matches)))
}
fn default_preferences(vm: &mut Vm, _args: &[JValue]) -> ResultValue {
    vm.shared_preferences
        .entry("anime-runtime-default".into())
        .or_default();
    vm.alloc_native(
        "Landroid/content/SharedPreferences;",
        Native::SharedPreferences("anime-runtime-default".into()),
    )
    .map_err(NatErr::Fatal)
}
fn build_sdk(_vm: &mut Vm, _args: &[JValue]) -> ResultValue {
    Ok(JValue::Int(35))
}
fn local_now(vm: &mut Vm, _args: &[JValue]) -> ResultValue {
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as i64;
    vm.alloc_native("Ljava/time/LocalDateTime;", Native::EpochMillis(now))
        .map_err(NatErr::Fatal)
}
fn local_minus_days(vm: &mut Vm, args: &[JValue]) -> ResultValue {
    let Some(Native::EpochMillis(millis)) = vm.payload_of(args[0]) else {
        return Err(exception(
            vm,
            "Ljava/lang/IllegalArgumentException;",
            "Invalid local date",
        ));
    };
    let updated = args[1]
        .as_long()
        .checked_mul(86_400_000)
        .and_then(|n| millis.checked_sub(n))
        .ok_or_else(|| exception(vm, "Ljava/lang/ArithmeticException;", "Date overflow"))?;
    vm.alloc_native("Ljava/time/LocalDateTime;", Native::EpochMillis(updated))
        .map_err(NatErr::Fatal)
}
fn local_truncated(vm: &mut Vm, args: &[JValue]) -> ResultValue {
    let Some(Native::EpochMillis(millis)) = vm.payload_of(args[0]) else {
        return Err(exception(
            vm,
            "Ljava/lang/IllegalArgumentException;",
            "Invalid local date",
        ));
    };
    let unit = vm.str_of_jvalue(args[1]).unwrap_or_default();
    let step = match unit.as_str() {
        "DAYS" => 86_400_000,
        "HOURS" => 3_600_000,
        "MINUTES" => 60_000,
        "SECONDS" => 1000,
        "MILLIS" | "MICROS" | "NANOS" => 1,
        _ => {
            return Err(exception(
                vm,
                "Ljava/lang/IllegalArgumentException;",
                "Unsupported truncation unit",
            ))
        }
    };
    vm.alloc_native(
        "Ljava/time/LocalDateTime;",
        Native::EpochMillis(millis.div_euclid(step) * step),
    )
    .map_err(NatErr::Fatal)
}

// A VM executes one guest thread; coroutine network operations complete inline.
// Keep real reentrant hold counts and ownership within that thread, not a host
// OS lock (holding an OS lock across a guest callback would deadlock the host).
fn rw_init(vm: &mut Vm, args: &[JValue]) -> ResultValue {
    vm.arena.objects[args[0].as_obj() as usize].native =
        Some(Native::List(vec![JValue::Int(0), JValue::Int(0)]));
    Ok(JValue::Null)
}
fn child_lock(vm: &mut Vm, args: &[JValue], mode: i32) -> ResultValue {
    let class = if mode == 0 {
        "Ljava/util/concurrent/locks/ReentrantReadWriteLock$ReadLock;"
    } else {
        "Ljava/util/concurrent/locks/ReentrantReadWriteLock$WriteLock;"
    };
    vm.alloc_native(class, Native::List(vec![args[0], JValue::Int(mode)]))
        .map_err(NatErr::Fatal)
}
fn read_lock(vm: &mut Vm, args: &[JValue]) -> ResultValue {
    child_lock(vm, args, 0)
}
fn write_lock(vm: &mut Vm, args: &[JValue]) -> ResultValue {
    child_lock(vm, args, 1)
}
fn change_hold(vm: &mut Vm, lock: JValue, delta: i32) -> Result<bool, NatErr> {
    let Some(Native::List(lock)) = vm.payload_of(lock) else {
        return Err(exception(
            vm,
            "Ljava/lang/IllegalStateException;",
            "Invalid lock",
        ));
    };
    let [owner, JValue::Int(mode)] = lock.as_slice() else {
        return Err(exception(
            vm,
            "Ljava/lang/IllegalStateException;",
            "Invalid lock owner",
        ));
    };
    let owner = owner.as_obj() as usize;
    let Some(Native::List(counts)) = vm.arena.objects[owner].native.as_mut() else {
        return Err(exception(
            vm,
            "Ljava/lang/IllegalStateException;",
            "Invalid lock counts",
        ));
    };
    let current = counts[*mode as usize].as_int();
    // Java does not permit upgrading a held read lock to a write lock.
    if delta > 0 && *mode == 1 && current == 0 && counts[0].as_int() > 0 {
        return Ok(false);
    }
    if delta < 0 && current == 0 {
        return Err(exception(
            vm,
            "Ljava/lang/IllegalStateException;",
            "Unlock without ownership",
        ));
    }
    counts[*mode as usize] = JValue::Int(current + delta);
    Ok(true)
}
fn lock(vm: &mut Vm, args: &[JValue]) -> ResultValue {
    if !change_hold(vm, args[0], 1)? {
        return Err(exception(
            vm,
            "Ljava/lang/IllegalStateException;",
            "Read-to-write upgrade would deadlock",
        ));
    }
    Ok(JValue::Null)
}
fn try_lock(vm: &mut Vm, args: &[JValue]) -> ResultValue {
    Ok(JValue::Int(i32::from(change_hold(vm, args[0], 1)?)))
}
fn unlock(vm: &mut Vm, args: &[JValue]) -> ResultValue {
    change_hold(vm, args[0], -1)?;
    Ok(JValue::Null)
}

fn close_abstract(_vm: &mut Vm, _args: &[JValue]) -> ResultValue {
    Err(NatErr::Fatal(JvmError::Resolution(
        "Abstract Closeable.close".into(),
    )))
}

macro_rules! entry {
    ($class:expr, $name:expr, $sig:expr, $instance:expr, $f:expr) => {
        NativeEntry {
            class: $class,
            name: $name,
            sig: $sig,
            instance: $instance,
            f: $f,
        }
    };
}
const TABLE: &[NativeEntry] = &[
    entry!(
        "Lkotlinx/coroutines/sync/Mutex;",
        "tryLock",
        "(Ljava/lang/Object;)Z",
        true,
        mutex_try_lock
    ),
    entry!(
        "Lkotlinx/coroutines/sync/Mutex;",
        "unlock",
        "(Ljava/lang/Object;)V",
        true,
        mutex_unlock
    ),
    entry!(
        "Lkotlinx/coroutines/sync/Mutex;",
        "lock",
        "(Ljava/lang/Object;Lkotlin/coroutines/Continuation;)Ljava/lang/Object;",
        true,
        mutex_lock
    ),
    entry!(
        "Ljava/lang/Class;",
        "forName",
        "(Ljava/lang/String;)Ljava/lang/Class;",
        false,
        class_for_name
    ),
    entry!(
        "Ljava/lang/Class;",
        "forName",
        "(Ljava/lang/String;ZLjava/lang/ClassLoader;)Ljava/lang/Class;",
        false,
        class_for_name
    ),
    entry!(
        "Ljava/lang/ClassLoader;",
        "loadClass",
        "(Ljava/lang/String;)Ljava/lang/Class;",
        true,
        class_loader_load
    ),
    entry!(
        "Landroid/webkit/WebView;",
        "getWebViewClassLoader",
        "()Ljava/lang/ClassLoader;",
        false,
        webview_class_loader
    ),
    entry!(
        "Lkotlin/time/Duration$Companion;",
        "getINFINITE-UwyO8pc",
        "()J",
        true,
        duration_infinite
    ),
    entry!(
        "Ljava/lang/StringBuilder;",
        "append",
        "(Ljava/lang/String;)Ljava/lang/StringBuilder;",
        true,
        string_builder_append
    ),
    entry!(
        "Leu/kanade/tachiyomi/AppInfo;",
        "getVersionName",
        "()Ljava/lang/String;",
        true,
        app_version
    ),
    entry!(
        "Ljava/util/ListIterator;",
        "hasPrevious",
        "()Z",
        true,
        has_previous
    ),
    entry!(
        "Ljava/util/ListIterator;",
        "previous",
        "()Ljava/lang/Object;",
        true,
        previous
    ),
    entry!(
        "Ljava/util/ListIterator;",
        "nextIndex",
        "()I",
        true,
        next_index
    ),
    entry!(
        "Ljava/util/ListIterator;",
        "previousIndex",
        "()I",
        true,
        previous_index
    ),
    entry!(
        "Ljava/time/ZoneOffset;",
        "of",
        "(Ljava/lang/String;)Ljava/time/ZoneOffset;",
        false,
        offset_of
    ),
    entry!(
        "Ljava/time/ZoneOffset;",
        "ofHours",
        "(I)Ljava/time/ZoneOffset;",
        false,
        offset_of_hours
    ),
    entry!(
        "Ljava/time/ZoneOffset;",
        "ofTotalSeconds",
        "(I)Ljava/time/ZoneOffset;",
        false,
        offset_of_seconds
    ),
    entry!(
        "Ljava/time/ZoneOffset;",
        "getTotalSeconds",
        "()I",
        true,
        offset_seconds
    ),
    entry!(
        "Ljava/time/LocalDateTime;",
        "toEpochSecond",
        "(Ljava/time/ZoneOffset;)J",
        true,
        local_epoch_seconds
    ),
    entry!(
        "Ljava/time/LocalDateTime;",
        "toInstant",
        "(Ljava/time/ZoneOffset;)Ljava/time/Instant;",
        true,
        local_instant
    ),
    entry!(
        "Ljava/time/ZonedDateTime;",
        "format",
        "(Ljava/time/format/DateTimeFormatter;)Ljava/lang/String;",
        true,
        date_format
    ),
    entry!(
        "Ljava/time/LocalDateTime;",
        "format",
        "(Ljava/time/format/DateTimeFormatter;)Ljava/lang/String;",
        true,
        date_format
    ),
    entry!(
        "Lorg/json/JSONObject;",
        "quote",
        "(Ljava/lang/String;)Ljava/lang/String;",
        false,
        json_quote
    ),
    entry!(
        "Lkotlin/text/Regex$Companion;",
        "escape",
        "(Ljava/lang/String;)Ljava/lang/String;",
        true,
        regex_escape
    ),
    entry!(
        "Landroid/os/Build$VERSION;",
        "getSdkInt",
        "()I",
        false,
        build_sdk
    ),
    entry!(
        "Landroid/preference/PreferenceManager;",
        "getDefaultSharedPreferences",
        "(Landroid/content/Context;)Landroid/content/SharedPreferences;",
        false,
        default_preferences
    ),
    entry!(
        "Ljava/time/LocalDateTime;",
        "now",
        "(Ljava/time/ZoneId;)Ljava/time/LocalDateTime;",
        false,
        local_now
    ),
    entry!(
        "Ljava/time/LocalDateTime;",
        "minusDays",
        "(J)Ljava/time/LocalDateTime;",
        true,
        local_minus_days
    ),
    entry!(
        "Ljava/time/LocalDateTime;",
        "truncatedTo",
        "(Ljava/time/temporal/TemporalUnit;)Ljava/time/LocalDateTime;",
        true,
        local_truncated
    ),
    entry!(
        "Ljava/util/concurrent/atomic/AtomicLong;",
        "<init>",
        "()V",
        true,
        atomic_init
    ),
    entry!(
        "Ljava/util/concurrent/atomic/AtomicLong;",
        "<init>",
        "(J)V",
        true,
        atomic_init
    ),
    entry!(
        "Ljava/util/concurrent/atomic/AtomicLong;",
        "get",
        "()J",
        true,
        atomic_get
    ),
    entry!(
        "Ljava/util/concurrent/atomic/AtomicLong;",
        "set",
        "(J)V",
        true,
        atomic_set
    ),
    entry!(
        "Ljava/util/concurrent/atomic/AtomicLong;",
        "lazySet",
        "(J)V",
        true,
        atomic_set
    ),
    entry!(
        "Ljava/util/concurrent/atomic/AtomicLong;",
        "getAndSet",
        "(J)J",
        true,
        atomic_swap
    ),
    entry!(
        "Ljava/util/concurrent/atomic/AtomicLong;",
        "getAndIncrement",
        "()J",
        true,
        atomic_get_add
    ),
    entry!(
        "Ljava/util/concurrent/atomic/AtomicLong;",
        "incrementAndGet",
        "()J",
        true,
        atomic_add
    ),
    entry!(
        "Ljava/util/concurrent/atomic/AtomicLong;",
        "getAndAdd",
        "(J)J",
        true,
        atomic_get_add
    ),
    entry!(
        "Ljava/util/concurrent/atomic/AtomicLong;",
        "addAndGet",
        "(J)J",
        true,
        atomic_add
    ),
    entry!(
        "Ljava/util/concurrent/atomic/AtomicLong;",
        "compareAndSet",
        "(JJ)Z",
        true,
        atomic_compare_set
    ),
    entry!(
        "Ljava/lang/AutoCloseable;",
        "close",
        "()V",
        true,
        close_abstract
    ),
    entry!(
        "Ljava/util/concurrent/locks/ReentrantReadWriteLock;",
        "<init>",
        "()V",
        true,
        rw_init
    ),
    entry!(
        "Ljava/util/concurrent/locks/ReentrantReadWriteLock;",
        "<init>",
        "(Z)V",
        true,
        rw_init
    ),
    entry!(
        "Ljava/util/concurrent/locks/ReentrantReadWriteLock;",
        "readLock",
        "()Ljava/util/concurrent/locks/ReentrantReadWriteLock$ReadLock;",
        true,
        read_lock
    ),
    entry!(
        "Ljava/util/concurrent/locks/ReentrantReadWriteLock;",
        "writeLock",
        "()Ljava/util/concurrent/locks/ReentrantReadWriteLock$WriteLock;",
        true,
        write_lock
    ),
    entry!(
        "Ljava/util/concurrent/locks/ReentrantReadWriteLock$ReadLock;",
        "lock",
        "()V",
        true,
        lock
    ),
    entry!(
        "Ljava/util/concurrent/locks/ReentrantReadWriteLock$ReadLock;",
        "tryLock",
        "()Z",
        true,
        try_lock
    ),
    entry!(
        "Ljava/util/concurrent/locks/ReentrantReadWriteLock$ReadLock;",
        "unlock",
        "()V",
        true,
        unlock
    ),
    entry!(
        "Ljava/util/concurrent/locks/ReentrantReadWriteLock$WriteLock;",
        "lock",
        "()V",
        true,
        lock
    ),
    entry!(
        "Ljava/util/concurrent/locks/ReentrantReadWriteLock$WriteLock;",
        "tryLock",
        "()Z",
        true,
        try_lock
    ),
    entry!(
        "Ljava/util/concurrent/locks/ReentrantReadWriteLock$WriteLock;",
        "unlock",
        "()V",
        true,
        unlock
    ),
];

pub(super) fn install(vm: &mut Vm) -> Result<(), JvmError> {
    for &entry in TABLE {
        vm.register_native(entry)?;
    }
    let build = vm.ensure_class_by_desc("Landroid/os/Build$VERSION;")?;
    let key = (vm.intern("SDK_INT"), vm.intern("I"));
    vm.classes[build as usize]
        .static_fields
        .insert(key, (build, 0));
    vm.classes[build as usize].statics.push(JValue::Int(35));
    vm.classes[build as usize].statics_lazy.push(None);
    let release = vm.alloc_string("15");
    let key = (vm.intern("RELEASE"), vm.intern("Ljava/lang/String;"));
    vm.classes[build as usize]
        .static_fields
        .insert(key, (build, 1));
    vm.classes[build as usize].statics.push(release);
    vm.classes[build as usize].statics_lazy.push(None);
    let random = vm.ensure_class_by_desc("Lkotlin/random/Random;")?;
    let value = vm.alloc_native("Lkotlin/random/Random$Default;", Native::Opaque)?;
    let key = (
        vm.intern("Default"),
        vm.intern("Lkotlin/random/Random$Default;"),
    );
    let offset = vm.classes[random as usize].statics.len() as u32;
    vm.classes[random as usize]
        .static_fields
        .insert(key, (random, offset));
    vm.classes[random as usize].statics.push(value);
    vm.classes[random as usize].statics_lazy.push(None);
    let app_info = vm.ensure_class_by_desc("Leu/kanade/tachiyomi/AppInfo;")?;
    let value = vm.alloc_native("Leu/kanade/tachiyomi/AppInfo;", Native::Opaque)?;
    let key = (
        vm.intern("INSTANCE"),
        vm.intern("Leu/kanade/tachiyomi/AppInfo;"),
    );
    let offset = vm.classes[app_info as usize].statics.len() as u32;
    vm.classes[app_info as usize]
        .static_fields
        .insert(key, (app_info, offset));
    vm.classes[app_info as usize].statics.push(value);
    vm.classes[app_info as usize].statics_lazy.push(None);
    let zone = vm.ensure_class_by_desc("Ljava/time/ZoneOffset;")?;
    vm.classes[zone as usize].superclass = Some(vm.ensure_class_by_desc("Ljava/time/ZoneId;")?);
    for (name, seconds) in [("UTC", 0), ("MIN", -64_800), ("MAX", 64_800)] {
        let value = vm.alloc_native("Ljava/time/ZoneOffset;", Native::IntBox(seconds))?;
        let key = (vm.intern(name), vm.intern("Ljava/time/ZoneOffset;"));
        let class = &mut vm.classes[zone as usize];
        let offset = class.statics.len() as u32;
        class.static_fields.insert(key, (zone, offset));
        class.statics.push(value);
        class.statics_lazy.push(None);
    }
    let auto = vm.ensure_class_by_desc("Ljava/lang/AutoCloseable;")?;
    vm.classes[auto as usize].is_interface = true;
    vm.classes[auto as usize].is_abstract = true;
    let closeable = vm.ensure_class_by_desc("Ljava/io/Closeable;")?;
    vm.classes[closeable as usize].interfaces.push(auto);
    for name in [
        "Lokhttp3/Response;",
        "Lokhttp3/ResponseBody;",
        "Lokio/Source;",
        "Lokio/Sink;",
        "Lokio/BufferedSource;",
        "Lokio/BufferedSink;",
    ] {
        let class = vm.ensure_class_by_desc(name)?;
        if !vm.classes[class as usize].interfaces.contains(&closeable) {
            vm.classes[class as usize].interfaces.push(closeable);
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    fn vm() -> Vm {
        let mut vm = Vm::new(vec![], Box::new(std::io::sink())).unwrap();
        install(&mut vm).unwrap();
        vm
    }
    #[test]
    fn list_iterator_moves_backwards_and_does_not_advance_on_failure() {
        let mut vm = vm();
        let list = vm
            .alloc_native(
                "Ljava/util/ArrayList;",
                Native::List(vec![JValue::Int(7), JValue::Int(9)]),
            )
            .unwrap();
        let iter = vm
            .alloc_native(
                "Ljava/util/ListIterator;",
                Native::Iter(IterKind::List {
                    list: list.as_obj(),
                    idx: 2,
                }),
            )
            .unwrap();
        assert_eq!(previous(&mut vm, &[iter]).unwrap(), JValue::Int(9));
        assert_eq!(next_index(&mut vm, &[iter]).unwrap(), JValue::Int(1));
        assert_eq!(previous(&mut vm, &[iter]).unwrap(), JValue::Int(7));
        assert_eq!(has_previous(&mut vm, &[iter]).unwrap(), JValue::Int(0));
        assert_eq!(previous_index(&mut vm, &[iter]).unwrap(), JValue::Int(-1));
        assert!(previous(&mut vm, &[iter]).is_err());
        assert_eq!(next_index(&mut vm, &[iter]).unwrap(), JValue::Int(0));
    }
    #[test]
    fn static_json_quote_and_instance_regex_escape_use_the_correct_arguments() {
        let mut vm = vm();
        let text = vm.alloc_string("a\"b\n[.*]");
        let quoted = json_quote(&mut vm, &[text]).unwrap();
        assert_eq!(vm.str_of_jvalue(quoted).unwrap(), "\"a\\\"b\\n[.*]\"");
        let companion = vm
            .alloc_native("Lkotlin/text/Regex$Companion;", Native::Opaque)
            .unwrap();
        let escaped = regex_escape(&mut vm, &[companion, text]).unwrap();
        let pattern = vm.str_of_jvalue(escaped).unwrap();
        assert!(fancy_regex::Regex::new(&pattern)
            .unwrap()
            .is_match("a\"b\n[.*]")
            .unwrap());
    }
    #[test]
    fn offset_conversion_is_not_assumed_to_be_utc() {
        let mut vm = vm();
        let offset_text = vm.alloc_string("+05:30");
        let offset = offset_of(&mut vm, &[offset_text]).unwrap();
        let date = vm
            .alloc_native("Ljava/time/LocalDateTime;", Native::EpochMillis(19_800_000))
            .unwrap();
        assert_eq!(
            local_epoch_seconds(&mut vm, &[date, offset]).unwrap(),
            JValue::Long(0)
        );
        assert!(offset_of_hours(&mut vm, &[JValue::Int(19)]).is_err());
        let negative = vm
            .alloc_native("Ljava/time/LocalDateTime;", Native::EpochMillis(-1))
            .unwrap();
        let utc = zone_offset(&mut vm, 0).unwrap();
        assert_eq!(
            local_epoch_seconds(&mut vm, &[negative, utc]).unwrap(),
            JValue::Long(-1)
        );
    }
    #[test]
    fn atomic_long_preserves_64_bits_and_java_overflow() {
        let mut vm = vm();
        let value = vm
            .alloc_native(
                "Ljava/util/concurrent/atomic/AtomicLong;",
                Native::LongBox(i64::MAX),
            )
            .unwrap();
        assert_eq!(
            atomic_get_add(&mut vm, &[value]).unwrap(),
            JValue::Long(i64::MAX)
        );
        assert_eq!(
            atomic_get(&mut vm, &[value]).unwrap(),
            JValue::Long(i64::MIN)
        );
        assert_eq!(
            atomic_compare_set(&mut vm, &[value, JValue::Long(i64::MIN), JValue::Long(1)]).unwrap(),
            JValue::Int(1)
        );
        assert_eq!(
            atomic_compare_set(&mut vm, &[value, JValue::Long(0), JValue::Long(7)]).unwrap(),
            JValue::Int(0)
        );
        assert_eq!(atomic_get(&mut vm, &[value]).unwrap(), JValue::Long(1));
    }
    #[test]
    fn read_write_locks_reenter_and_reject_an_impossible_upgrade() {
        let mut vm = vm();
        let owner = vm
            .alloc_native(
                "Ljava/util/concurrent/locks/ReentrantReadWriteLock;",
                Native::Opaque,
            )
            .unwrap();
        rw_init(&mut vm, &[owner]).unwrap();
        let read = read_lock(&mut vm, &[owner]).unwrap();
        let write = write_lock(&mut vm, &[owner]).unwrap();
        lock(&mut vm, &[write]).unwrap();
        lock(&mut vm, &[write]).unwrap();
        lock(&mut vm, &[read]).unwrap();
        unlock(&mut vm, &[read]).unwrap();
        unlock(&mut vm, &[write]).unwrap();
        unlock(&mut vm, &[write]).unwrap();
        assert!(unlock(&mut vm, &[write]).is_err());
        lock(&mut vm, &[read]).unwrap();
        assert_eq!(try_lock(&mut vm, &[write]).unwrap(), JValue::Int(0));
        unlock(&mut vm, &[read]).unwrap();
        assert_eq!(try_lock(&mut vm, &[write]).unwrap(), JValue::Int(1));
    }
    #[test]
    fn okhttp_resources_really_implement_closeable() {
        let mut vm = vm();
        let closeable = vm.ensure_class_by_desc("Ljava/io/Closeable;").unwrap();
        for name in [
            "Lokhttp3/Response;",
            "Lokhttp3/ResponseBody;",
            "Lokio/BufferedSource;",
        ] {
            let class = vm.ensure_class_by_desc(name).unwrap();
            assert!(vm.is_assignable(class, closeable).unwrap(), "{name}");
        }
    }
    #[test]
    fn generic_character_collections_box_elements_and_bound_range_expansion() {
        let mut vm = vm();
        let chars = vm
            .alloc_native("Lkotlin/ranges/CharRange;", Native::CharRange(97, 99))
            .unwrap();
        let list = vm
            .invoke_static(
                "Lkotlin/collections/CollectionsKt;",
                "toList",
                "(Ljava/lang/Iterable;)Ljava/util/List;",
                vec![chars],
            )
            .unwrap();
        let Some(Native::List(values)) = vm.payload_of(list) else {
            panic!("Expected list")
        };
        assert_eq!(values.len(), 3);
        for (value, char) in values.iter().zip([97, 98, 99]) {
            assert!(matches!(vm.payload_of(*value), Some(Native::CharBox(c)) if c == char));
        }
        let enormous = vm
            .alloc_native(
                "Lkotlin/ranges/IntRange;",
                Native::IntRange(i32::MIN, i32::MAX),
            )
            .unwrap();
        assert!(vm
            .invoke_static(
                "Lkotlin/collections/CollectionsKt;",
                "toList",
                "(Ljava/lang/Iterable;)Ljava/util/List;",
                vec![enormous]
            )
            .is_err());
    }
    #[test]
    fn repeated_native_entries_do_not_consume_reentry_depth() {
        let mut vm = vm();
        for _ in 0..1000 {
            vm.invoke_static("Ljava/lang/System;", "currentTimeMillis", "()J", vec![])
                .unwrap();
        }
        assert_eq!(vm.recursion_depth, 0);
    }
    #[test]
    fn unavailable_optional_platform_classes_throw_catchable_java_exceptions() {
        let mut vm = vm();
        let missing = vm.alloc_string("org.example.UnavailablePlatformFeature");
        let Err(NatErr::Throw(id)) = class_for_name(&mut vm, &[missing]) else {
            panic!("Expected a Java exception")
        };
        let expected = vm
            .ensure_class_by_desc("Ljava/lang/ClassNotFoundException;")
            .unwrap();
        assert!(vm
            .is_assignable(vm.arena.objects[id as usize].class, expected)
            .unwrap());
        let available = vm.alloc_string("java.lang.String");
        assert!(class_for_name(&mut vm, &[available]).is_ok());
    }
    #[test]
    fn suspend_mutex_lock_runs_inline_without_claiming_reentrancy() {
        let mut vm = vm();
        let mutex = vm
            .alloc_native(
                "Lkotlinx/coroutines/sync/Mutex;",
                Native::Mutex { locked: false },
            )
            .unwrap();
        let result = mutex_lock(&mut vm, &[mutex, JValue::Null, JValue::Null]).unwrap();
        assert!(matches!(result, JValue::Obj(_)));
        assert!(mutex_lock(&mut vm, &[mutex, JValue::Null, JValue::Null]).is_err());
        vm.invoke_virtual_args(mutex, "unlock", "(Ljava/lang/Object;)V", vec![JValue::Null])
            .unwrap();
        assert!(mutex_lock(&mut vm, &[mutex, JValue::Null, JValue::Null]).is_ok());
    }
    #[test]
    fn instance_of_preserves_the_full_16_bit_type_index() {
        use dexvm::dex::insn::{decode_all, Insn};
        for index in [255, 256, 257, 1024, 65_535] {
            let decoded = decode_all(&[0x2320, index]).unwrap();
            assert!(
                matches!(decoded.insns[0], Insn::InstanceOf(3, 2, value) if value == u32::from(index))
            );
        }
    }
    #[test]
    fn generic_join_converts_boxed_characters_and_string_builder_accepts_null() {
        let mut vm = vm();
        let a = vm
            .alloc_native("Ljava/lang/Character;", Native::CharBox(65))
            .unwrap();
        let b = vm
            .alloc_native("Ljava/lang/Character;", Native::CharBox(66))
            .unwrap();
        let list = vm
            .alloc_native("Ljava/util/ArrayList;", Native::List(vec![a, b]))
            .unwrap();
        let separator = vm.alloc_string("");
        let joined = vm.invoke_static("Lkotlin/collections/CollectionsKt;", "joinToString$default",
            "(Ljava/lang/Iterable;Ljava/lang/CharSequence;Ljava/lang/CharSequence;Ljava/lang/CharSequence;ILjava/lang/CharSequence;Lkotlin/jvm/functions/Function1;ILjava/lang/Object;)Ljava/lang/String;",
            vec![list, separator, JValue::Null, JValue::Null, JValue::Int(0), JValue::Null, JValue::Null, JValue::Int(62), JValue::Null]).unwrap();
        assert_eq!(vm.str_of_jvalue(joined).unwrap(), "AB");
        let builder = vm
            .alloc_native(
                "Ljava/lang/StringBuilder;",
                Native::StringBuilder(String::new()),
            )
            .unwrap();
        string_builder_append(&mut vm, &[builder, JValue::Null]).unwrap();
        assert!(
            matches!(vm.payload_of(builder), Some(Native::StringBuilder(value)) if value == "null")
        );
    }
}
