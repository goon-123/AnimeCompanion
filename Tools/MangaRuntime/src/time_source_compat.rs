//! Steady-clock readings are nanoseconds; elapsed durations follow the pinned
//! runtime's millisecond ABI. No wall clock or guest environment is involved.
use dexvm::vm::{error::JvmError, object::Native, NatErr, NativeEntry, Vm};
use dexvm::JValue;
use std::{sync::OnceLock, time::Instant};
type R = Result<JValue, NatErr>;
const SOURCE: &str = "Lkotlin/time/TimeSource$Monotonic;";
const MARK: &str = "Lkotlin/time/TimeSource$Monotonic$ValueTimeMark;";
static ORIGIN: OnceLock<Instant> = OnceLock::new();
fn charge(vm: &mut Vm) -> Result<(), NatErr> {
    if vm.budget <= 0 {
        return Err(NatErr::Fatal(JvmError::BudgetExceeded));
    }
    vm.budget -= 1;
    Ok(())
}
fn now() -> i64 {
    ORIGIN
        .get_or_init(Instant::now)
        .elapsed()
        .as_nanos()
        .min(i64::MAX as u128) as i64
}
fn reading(vm: &mut Vm, _: &[JValue]) -> R {
    charge(vm)?;
    Ok(JValue::Long(now()))
}
fn boxed(vm: &mut Vm, args: &[JValue]) -> R {
    charge(vm)?;
    vm.alloc_native(MARK, Native::LongBox(args[0].as_long()))
        .map_err(NatErr::Fatal)
}
fn unboxed(vm: &mut Vm, args: &[JValue]) -> R {
    charge(vm)?;
    match vm.payload_of(args[0]) {
        Some(Native::LongBox(v)) => Ok(JValue::Long(v)),
        _ => Err(NatErr::Throw(vm.err_npe())),
    }
}
fn elapsed(vm: &mut Vm, args: &[JValue]) -> R {
    charge(vm)?;
    let mark = if matches!(args[0], JValue::Long(_)) {
        args[0].as_long()
    } else {
        unboxed(vm, args)?.as_long()
    };
    Ok(JValue::Long(now().saturating_sub(mark) / 1_000_000))
}
fn mark(vm: &mut Vm, _: &[JValue]) -> R {
    let v = reading(vm, &[])?;
    boxed(vm, &[v])
}
fn cancellation_init(vm: &mut Vm, args: &[JValue]) -> R {
    charge(vm)?;
    let message = args.get(1).and_then(|v| vm.str_of_jvalue(*v));
    vm.arena.objects[args[0].as_obj() as usize].native = Some(Native::Throwable {
        message,
        cause: JValue::Null,
    });
    Ok(JValue::Null)
}
pub(super) fn install(vm: &mut Vm) -> Result<(), JvmError> {
    for sig in ["()V", "(Ljava/lang/String;)V"] {
        vm.register_native(NativeEntry {
            class: "Ljava/util/concurrent/CancellationException;",
            name: "<init>",
            sig,
            instance: true,
            f: cancellation_init,
        })?;
    }
    let cancellation = vm.ensure_class_by_desc("Ljava/util/concurrent/CancellationException;")?;
    vm.classes[cancellation as usize].superclass =
        Some(vm.ensure_class_by_desc("Ljava/lang/IllegalStateException;")?);
    for (class, name, sig, instance, f) in [
        (
            SOURCE,
            "markNow-z9LOYto",
            "()J",
            true,
            reading as dexvm::vm::NativeFn,
        ),
        (SOURCE, "markNow", "()Lkotlin/time/TimeMark;", true, mark),
        (
            MARK,
            "box-impl",
            "(J)Lkotlin/time/TimeSource$Monotonic$ValueTimeMark;",
            false,
            boxed,
        ),
        (MARK, "unbox-impl", "()J", true, unboxed),
        (MARK, "elapsedNow-UwyO8pc", "()J", true, elapsed),
        (MARK, "elapsedNow-UwyO8pc", "(J)J", false, elapsed),
    ] {
        vm.register_native(NativeEntry {
            class,
            name,
            sig,
            instance,
            f,
        })?;
    }
    let source = super::kotlin_type_compat::marker(vm, "Lkotlin/time/TimeSource;");
    let mark = super::kotlin_type_compat::marker(vm, "Lkotlin/time/TimeMark;");
    let class = vm.ensure_class_by_desc(SOURCE)?;
    vm.classes[class as usize].interfaces.push(source);
    let class = vm.ensure_class_by_desc(MARK)?;
    vm.classes[class as usize].interfaces.push(mark);
    let value = vm.alloc_native(SOURCE, Native::Opaque)?;
    super::multipart_compat::static_value(vm, SOURCE, "INSTANCE", SOURCE, value)
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn monotonic_boxed_marks_preserve_milliseconds_negative_elapsed_and_limits() {
        let mut vm = Vm::new(vec![], Box::new(std::io::sink())).unwrap();
        install(&mut vm).unwrap();
        let before = reading(&mut vm, &[]).unwrap().as_long();
        let after = reading(&mut vm, &[]).unwrap().as_long();
        assert!(after >= before);
        let past = boxed(&mut vm, &[JValue::Long(after - 2_000_000_000)]).unwrap();
        vm.gc(&[past.as_obj()]);
        let duration = vm
            .invoke_virtual_args(past, "elapsedNow-UwyO8pc", "()J", vec![])
            .unwrap()
            .as_long();
        assert!((2000..3000).contains(&duration));
        let future = JValue::Long(now() + 2_000_000_000);
        assert!((-2000..=-1000).contains(&elapsed(&mut vm, &[future]).unwrap().as_long()));
        vm.budget = 0;
        assert!(matches!(
            elapsed(&mut vm, &[future]),
            Err(NatErr::Fatal(JvmError::BudgetExceeded))
        ));
    }
}
