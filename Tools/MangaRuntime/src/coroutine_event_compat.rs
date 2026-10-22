//! Cooperative events for one guest thread. Only the monotonic clock is shared
//! with the process; every guest reference is in the VM's traced static queue.
//! No host threads, global guest handles, or fabricated completed results.
use dexvm::vm::{error::JvmError, object::Native, FieldRef, NatErr, NativeEntry, Vm};
use dexvm::JValue;
use std::sync::OnceLock;
type R = Result<JValue, NatErr>;
const ROOT: &str = "Lapp/animecompanion/CoroutineEvents;";
const LIMIT: usize = 10_000;
pub(super) const DELAY: i32 = 0;
pub(super) const AWAIT: i32 = 1;
pub(super) const JOIN: i32 = 2;
pub(super) const ALL: i32 = 3;
pub(super) const CHILDREN: i32 = 4;

fn now() -> i64 {
    static ORIGIN: OnceLock<std::time::Instant> = OnceLock::new();
    ORIGIN
        .get_or_init(std::time::Instant::now)
        .elapsed()
        .as_millis()
        .min(i64::MAX as u128) as i64
}
fn charge(vm: &mut Vm, count: usize) -> Result<(), NatErr> {
    if count > LIMIT || vm.budget <= count as i64 {
        return Err(NatErr::Fatal(JvmError::BudgetExceeded));
    }
    vm.budget -= count as i64 + 1;
    Ok(())
}
fn queue(vm: &mut Vm) -> R {
    let field = FieldRef {
        class_desc: vm.intern(ROOT),
        name: vm.intern("queue"),
        ty: vm.intern("Ljava/util/ArrayList;"),
    };
    vm.static_field_get(field).map_err(NatErr::Fatal)
}
pub(super) fn checkpoint(vm: &mut Vm) -> Result<i64, NatErr> {
    let q = queue(vm)?;
    Ok(vm.arena.objects[q.as_obj() as usize].fields[0].as_long())
}
pub(super) fn driving(vm: &mut Vm) -> Result<bool, NatErr> {
    // The embedding's synchronous source entry points cannot return a token to
    // Swift. They pump waits inline. Managed child blocks/runBlocking instead
    // have a real completion collector and can suspend their guest frame.
    let q = queue(vm)?;
    Ok(vm.arena.objects[q.as_obj() as usize].fields[2].as_int() > 0)
}
pub(super) fn enter_driver(vm: &mut Vm) -> Result<i32, NatErr> {
    let q = queue(vm)?;
    let previous = vm.arena.objects[q.as_obj() as usize].fields[2].as_int();
    vm.arena.objects[q.as_obj() as usize].fields[2] = JValue::Int(previous + 1);
    Ok(previous)
}
pub(super) fn restore_driver(vm: &mut Vm, value: i32) -> Result<(), NatErr> {
    let q = queue(vm)?;
    vm.arena.objects[q.as_obj() as usize].fields[2] = JValue::Int(value);
    Ok(())
}
pub(super) fn discard_since(vm: &mut Vm, checkpoint: i64) -> Result<(), NatErr> {
    let q = queue(vm)?;
    let Some(Native::List(events)) = vm.payload_of(q) else {
        unreachable!()
    };
    let kept = events
        .into_iter()
        .filter(|event| vm.arena.objects[event.as_obj() as usize].fields[7].as_long() < checkpoint)
        .collect();
    vm.arena.objects[q.as_obj() as usize].native = Some(Native::List(kept));
    let pending = vm.arena.objects[q.as_obj() as usize].fields[1];
    let Some(Native::List(tasks)) = vm.payload_of(pending) else {
        unreachable!()
    };
    let mut kept = Vec::new();
    for task in tasks {
        if vm.arena.objects[task.as_obj() as usize].fields[6].as_long() < checkpoint {
            kept.push(task);
            continue;
        }
        let error = JValue::Obj(vm.throwable_of(
            "Ljava/util/concurrent/CancellationException;",
            "Coroutine operation aborted",
        ));
        let object = &mut vm.arena.objects[task.as_obj() as usize];
        object.fields[1] = JValue::Int(1);
        object.fields[2] = error;
        object.fields[4] = JValue::Null;
        object.fields[5] = JValue::Null;
        object.native = Some(Native::Deferred {
            value: JValue::Null,
            error,
        });
    }
    vm.arena.objects[pending.as_obj() as usize].native = Some(Native::List(kept));
    Ok(())
}
pub(super) fn track(vm: &mut Vm, task: JValue) -> Result<(), NatErr> {
    let q = queue(vm)?;
    let pending = vm.arena.objects[q.as_obj() as usize].fields[1];
    let Some(Native::List(tasks)) = &vm.arena.objects[pending.as_obj() as usize].native else {
        unreachable!()
    };
    charge(vm, tasks.len() + 1)?;
    let generation = checkpoint(vm)?;
    vm.arena.objects[task.as_obj() as usize].fields[6] = JValue::Long(generation);
    vm.arena.objects[q.as_obj() as usize].fields[0] = JValue::Long(generation.saturating_add(1));
    let Some(Native::List(tasks)) = &mut vm.arena.objects[pending.as_obj() as usize].native else {
        unreachable!()
    };
    tasks.push(task);
    Ok(())
}
pub(super) fn untrack(vm: &mut Vm, task: JValue) -> Result<(), NatErr> {
    let q = queue(vm)?;
    let pending = vm.arena.objects[q.as_obj() as usize].fields[1];
    let Some(Native::List(tasks)) = &mut vm.arena.objects[pending.as_obj() as usize].native else {
        unreachable!()
    };
    tasks.retain(|value| *value != task);
    Ok(())
}
pub(super) fn has_children(vm: &mut Vm, context: JValue) -> Result<bool, NatErr> {
    let job = super::coroutine_compat::context_job(vm, context)?;
    if job.is_null_ref() {
        return Ok(false);
    }
    let q = queue(vm)?;
    let pending = vm.arena.objects[q.as_obj() as usize].fields[1];
    let Some(Native::List(tasks)) = vm.payload_of(pending) else {
        unreachable!()
    };
    charge(vm, tasks.len() + 1)?;
    for task in tasks {
        let mut parent = vm.arena.objects[task.as_obj() as usize].fields[0];
        for _ in 0..256 {
            charge(vm, 1)?;
            if parent.is_null_ref() {
                break;
            }
            if parent == job {
                return Ok(true);
            }
            parent = vm.arena.objects[parent.as_obj() as usize]
                .fields
                .first()
                .copied()
                .unwrap_or(JValue::Null);
        }
    }
    Ok(false)
}
pub(super) fn schedule(
    vm: &mut Vm,
    continuation: JValue,
    kind: i32,
    target: JValue,
    millis: i64,
) -> R {
    if continuation.is_null_ref() {
        return Err(NatErr::Throw(vm.err_npe()));
    }
    let q = queue(vm)?;
    let count = match &vm.arena.objects[q.as_obj() as usize].native {
        Some(Native::List(events)) => events.len(),
        _ => unreachable!(),
    };
    charge(vm, count + 1)?;
    let context = super::coroutine_compat::current(vm)?;
    let (deadline, main) = super::browser_compat::coroutine_event_state(vm)?;
    let generation = checkpoint(vm)?;
    let event = vm
        .alloc_native(ROOT, Native::Opaque)
        .map_err(NatErr::Fatal)?;
    vm.arena.objects[event.as_obj() as usize].fields = vec![
        continuation,
        context,
        JValue::Int(kind),
        target,
        JValue::Long(now().saturating_add(millis.max(0))),
        deadline,
        main,
        JValue::Long(generation),
    ];
    vm.arena.objects[q.as_obj() as usize].fields[0] = JValue::Long(generation.saturating_add(1));
    let Some(Native::List(events)) = &mut vm.arena.objects[q.as_obj() as usize].native else {
        unreachable!()
    };
    events.push(event);
    super::continuation_compat::suspended(vm, &[])
}
fn failure(vm: &mut Vm, error: NatErr) -> R {
    match error {
        NatErr::Throw(id) => vm
            .alloc_native(
                "Lkotlin/Result$Failure;",
                Native::ResultFailure(JValue::Obj(id)),
            )
            .map_err(NatErr::Fatal),
        error => Err(error),
    }
}
fn ready(vm: &mut Vm, fields: &[JValue]) -> Result<Option<JValue>, NatErr> {
    if fields[2].as_int() == CHILDREN {
        let scope = vm.arena.objects[fields[3].as_obj() as usize].fields[3];
        let context = super::coroutine_compat::scope_context(vm, scope)?;
        return if has_children(vm, context)? {
            Ok(None)
        } else {
            super::coroutine_compat::unit(vm).map(Some)
        };
    }
    let scope = super::coroutine_compat::scope(vm, fields[1])?;
    if let Err(error) = super::coroutine_compat::ensure_active(vm, scope) {
        return failure(vm, error).map(Some);
    }
    if let Err(error) = super::browser_compat::check_deadline(vm) {
        return failure(vm, error).map(Some);
    }
    let result = match fields[2].as_int() {
        DELAY if now() < fields[4].as_long() => return Ok(None),
        DELAY => super::coroutine_compat::unit(vm),
        AWAIT => {
            let result = super::coroutine_compat::task_result(vm, fields[3]);
            match result {
                Ok(None) => return Ok(None),
                Ok(Some(value)) => Ok(value),
                Err(error) => Err(error),
            }
        }
        JOIN => {
            if super::coroutine_compat::join_ready(vm, fields[3])? {
                super::coroutine_compat::unit(vm)
            } else {
                return Ok(None);
            }
        }
        ALL => match super::coroutine_compat::all_results(vm, fields[3]) {
            Ok(None) => return Ok(None),
            Ok(Some(value)) => Ok(value),
            Err(error) => Err(error),
        },
        _ => {
            return Err(NatErr::Fatal(JvmError::Fatal(
                "Invalid coroutine event".into(),
            )))
        }
    };
    match result {
        Ok(value) => Ok(Some(value)),
        Err(error) => failure(vm, error).map(Some),
    }
}
/// Resume one ready event, or wait only a small slice. False means there is no
/// completion source, not that a suspended coroutine succeeded with null.
pub(super) fn pump(vm: &mut Vm) -> Result<bool, NatErr> {
    let q = queue(vm)?;
    let Some(Native::List(events)) = vm.payload_of(q) else {
        unreachable!()
    };
    charge(vm, events.len() + 1)?;
    if events.is_empty() {
        let pending = super::browser_compat::poll_coroutine_events(vm)?;
        if pending {
            std::thread::sleep(std::time::Duration::from_millis(1));
        }
        return Ok(pending);
    }
    let timers = events
        .iter()
        .any(|event| vm.arena.objects[event.as_obj() as usize].fields[2] == JValue::Int(DELAY));
    for event in events {
        let fields = vm.arena.objects[event.as_obj() as usize].fields.clone();
        let previous = super::coroutine_compat::enter(vm, fields[1])?;
        let browser =
            super::browser_compat::replace_coroutine_event_state(vm, (fields[5], fields[6]))?;
        let result = ready(vm, &fields);
        let result = match result {
            Ok(Some(result)) => {
                let Some(Native::List(events)) = &mut vm.arena.objects[q.as_obj() as usize].native
                else {
                    unreachable!()
                };
                events.retain(|value| *value != event);
                super::continuation_compat::resume_value(vm, fields[0], result).map(|_| true)
            }
            Ok(None) => Ok(false),
            Err(error) => Err(error),
        };
        super::browser_compat::replace_coroutine_event_state(vm, browser)?;
        super::coroutine_compat::restore(vm, previous)?;
        if result? {
            return Ok(true);
        }
    }
    // Queue scans, cancellation, deadlines and the VM instruction budget bound
    // every wait, including waits on a guest continuation without a timer.
    if !super::browser_compat::poll_coroutine_events(vm)? && !timers {
        return Ok(false);
    }
    std::thread::sleep(std::time::Duration::from_millis(1));
    Ok(true)
}
pub(super) fn install(vm: &mut Vm) -> Result<(), JvmError> {
    vm.register_native(NativeEntry {
        class: ROOT,
        name: "__marker",
        sig: "()V",
        instance: true,
        f: super::abstract_function,
    })?;
    let q = vm.alloc_native("Ljava/util/ArrayList;", Native::List(vec![]))?;
    let pending = vm.alloc_native("Ljava/util/ArrayList;", Native::List(vec![]))?;
    vm.arena.objects[q.as_obj() as usize].fields = vec![JValue::Long(0), pending, JValue::Int(0)];
    super::multipart_compat::static_value(vm, ROOT, "queue", "Ljava/util/ArrayList;", q)?;
    Ok(())
}
