//! Bounded coroutine contexts for the single guest thread. Elements and job
//! parents are arena-traced; no process-global guest references or OS threads.
use dexvm::vm::{
    error::JvmError,
    object::{ArrayData, Native},
    FieldRef, NatErr, NativeEntry, Vm,
};
use dexvm::JValue;
type R = Result<JValue, NatErr>;
const CONTEXT: &str = "Lkotlin/coroutines/CoroutineContext;";
const ELEMENT: &str = "Lkotlin/coroutines/CoroutineContext$Element;";
const KEY: &str = "Lkotlin/coroutines/CoroutineContext$Key;";
const EMPTY: &str = "Lkotlin/coroutines/EmptyCoroutineContext;";
const COMBINED: &str = "Lkotlin/coroutines/CombinedContext;";
const SCOPE: &str = "Lkotlinx/coroutines/CoroutineScope;";
const JOB: &str = "Lkotlinx/coroutines/Job;";
const DISPATCHER: &str = "Lkotlinx/coroutines/CoroutineDispatcher;";
const INTERCEPTOR: &str = "Lkotlin/coroutines/ContinuationInterceptor;";

fn charge(vm: &mut Vm, n: usize) -> Result<(), NatErr> {
    if n > 256 || vm.budget <= n as i64 {
        return Err(NatErr::Fatal(JvmError::BudgetExceeded));
    }
    vm.budget -= n as i64 + 1;
    Ok(())
}
fn java(_vm: &mut Vm, e: JvmError) -> NatErr {
    match e {
        JvmError::Uncaught(id) => NatErr::Throw(id),
        e => NatErr::Fatal(e),
    }
}
fn singleton(vm: &mut Vm, class: &str, name: &str, ty: &str) -> R {
    let field = FieldRef {
        class_desc: vm.intern(class),
        name: vm.intern(name),
        ty: vm.intern(ty),
    };
    vm.static_field_get(field).map_err(NatErr::Fatal)
}
fn empty(vm: &mut Vm) -> R {
    singleton(vm, EMPTY, "INSTANCE", EMPTY)
}
pub(super) fn current(vm: &mut Vm) -> R {
    singleton(vm, CONTEXT, "__acCurrent", CONTEXT)
}
pub(super) fn enter(vm: &mut Vm, context: JValue) -> R {
    let previous = current(vm)?;
    restore(vm, context)?;
    Ok(previous)
}
pub(super) fn restore(vm: &mut Vm, context: JValue) -> Result<(), NatErr> {
    let field = FieldRef {
        class_desc: vm.intern(CONTEXT),
        name: vm.intern("__acCurrent"),
        ty: vm.intern(CONTEXT),
    };
    vm.static_field_put(field, context).map_err(NatErr::Fatal)
}
pub(super) fn merged_current(vm: &mut Vm, context: JValue) -> R {
    let previous = current(vm)?;
    if context.is_null_ref() {
        Ok(previous)
    } else {
        plus(vm, &[previous, context])
    }
}
fn elements(vm: &mut Vm, value: JValue) -> Result<Vec<JValue>, NatErr> {
    if value.is_null_ref() {
        return Err(NatErr::Throw(vm.err_npe()));
    }
    match vm.payload_of(value) {
        Some(Native::List(values)) => {
            charge(vm, values.len())?;
            Ok(values)
        }
        _ => {
            charge(vm, 1)?;
            Ok(vec![value])
        }
    }
}
fn is_type(vm: &mut Vm, value: JValue, desc: &str) -> Result<bool, NatErr> {
    let JValue::Obj(id) = value else {
        return Ok(false);
    };
    let class = vm.ensure_class_by_desc(desc).map_err(NatErr::Fatal)?;
    vm.is_assignable(vm.arena.objects[id as usize].class, class)
        .map_err(NatErr::Fatal)
}
fn key(vm: &mut Vm, value: JValue) -> R {
    if is_type(vm, value, DISPATCHER)? {
        return singleton(
            vm,
            INTERCEPTOR,
            "Key",
            "Lkotlin/coroutines/ContinuationInterceptor$Key;",
        );
    }
    if is_type(vm, value, JOB)? {
        return singleton(vm, JOB, "Key", "Lkotlinx/coroutines/Job$Key;");
    }
    vm.invoke_virtual(
        value,
        "getKey",
        "()Lkotlin/coroutines/CoroutineContext$Key;",
    )
    .map_err(|e| java(vm, e))
}
fn get_key(vm: &mut Vm, args: &[JValue]) -> R {
    key(vm, args[0])
}
fn pack(vm: &mut Vm, values: Vec<JValue>) -> R {
    match values.len() {
        0 => empty(vm),
        1 => Ok(values[0]),
        _ => vm
            .alloc_native(COMBINED, Native::List(values))
            .map_err(NatErr::Fatal),
    }
}
fn plus(vm: &mut Vm, args: &[JValue]) -> R {
    let mut result = elements(vm, args[0])?;
    for value in elements(vm, args[1])? {
        let k = key(vm, value)?;
        let mut kept = Vec::new();
        for old in result {
            if key(vm, old)? != k {
                kept.push(old);
            }
        }
        kept.push(value);
        result = kept;
    }
    // Kotlin keeps the continuation interceptor at the right of the context.
    let mut interceptor = None;
    for (i, value) in result.iter().enumerate() {
        if is_type(vm, *value, DISPATCHER)? {
            interceptor = Some(i);
            break;
        }
    }
    if let Some(i) = interceptor {
        let dispatcher = result.remove(i);
        result.push(dispatcher);
    }
    charge(vm, result.len())?;
    pack(vm, result)
}
fn get(vm: &mut Vm, args: &[JValue]) -> R {
    if args[1].is_null_ref() {
        return Err(NatErr::Throw(vm.err_npe()));
    }
    for value in elements(vm, args[0])? {
        if key(vm, value)? == args[1] {
            return Ok(value);
        }
    }
    Ok(JValue::Null)
}
fn minus(vm: &mut Vm, args: &[JValue]) -> R {
    if args[1].is_null_ref() {
        return Err(NatErr::Throw(vm.err_npe()));
    }
    let mut result = Vec::new();
    let mut removed = false;
    for value in elements(vm, args[0])? {
        if key(vm, value)? == args[1] {
            removed = true;
        } else {
            result.push(value);
        }
    }
    if removed {
        pack(vm, result)
    } else {
        Ok(args[0])
    }
}
fn fold(vm: &mut Vm, args: &[JValue]) -> R {
    let mut result = args[1];
    for value in elements(vm, args[0])? {
        result = vm
            .invoke_virtual_args(
                args[2],
                "invoke",
                "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;",
                vec![result, value],
            )
            .map_err(|e| java(vm, e))?;
    }
    Ok(result)
}
pub(super) fn scope(vm: &mut Vm, context: JValue) -> R {
    let value = vm
        .alloc_native(SCOPE, Native::Opaque)
        .map_err(NatErr::Fatal)?;
    vm.arena.objects[value.as_obj() as usize].fields = vec![context];
    Ok(value)
}
fn create_scope(vm: &mut Vm, args: &[JValue]) -> R {
    let context = if args[0].is_null_ref() {
        return Err(NatErr::Throw(vm.err_npe()));
    } else {
        args[0]
    };
    let job_key = singleton(vm, JOB, "Key", "Lkotlinx/coroutines/Job$Key;")?;
    let context = if get(vm, &[context, job_key])?.is_null_ref() {
        let job = new_job(vm, JValue::Null)?;
        plus(vm, &[context, job])?
    } else {
        context
    };
    scope(vm, context)
}
pub(super) fn scope_context(vm: &mut Vm, value: JValue) -> R {
    if value.is_null_ref() {
        return empty(vm);
    }
    let JValue::Obj(id) = value else {
        return Err(NatErr::Throw(vm.err_npe()));
    };
    match vm.arena.objects[id as usize].fields.first().copied() {
        Some(context) => Ok(context),
        None => empty(vm),
    }
}
pub(super) fn task_scope(vm: &mut Vm, args: &[JValue]) -> R {
    let context = scope_context(vm, args[0])?;
    let default = args.get(4).is_some_and(|v| v.as_int() & 1 != 0);
    let context = if default || args[1].is_null_ref() {
        context
    } else {
        plus(vm, &[context, args[1]])?
    };
    let s = scope(vm, context)?;
    ensure_active(vm, s)?;
    Ok(s)
}
fn get_context(vm: &mut Vm, args: &[JValue]) -> R {
    scope_context(vm, args[0])
}
fn new_job(vm: &mut Vm, parent: JValue) -> R {
    let value = vm
        .alloc_native("Lkotlinx/coroutines/CompletableJob;", Native::Opaque)
        .map_err(NatErr::Fatal)?;
    vm.arena.objects[value.as_obj() as usize].fields = vec![parent, JValue::Int(0), JValue::Null];
    Ok(value)
}
fn supervisor(vm: &mut Vm, args: &[JValue]) -> R {
    let parent = if args.get(1).is_some_and(|mask| mask.as_int() & 1 != 0) {
        JValue::Null
    } else {
        args[0]
    };
    new_job(vm, parent)
}
fn job_active(vm: &mut Vm, value: JValue) -> Result<bool, NatErr> {
    let mut value = value;
    for _ in 0..256 {
        if value.is_null_ref() {
            return Ok(true);
        }
        charge(vm, 1)?;
        let JValue::Obj(id) = value else {
            return Err(NatErr::Throw(vm.err_npe()));
        };
        let fields = &vm.arena.objects[id as usize].fields;
        if fields.get(1).is_some_and(|v| !v.is_zero()) {
            return Ok(false);
        }
        value = fields.first().copied().unwrap_or(JValue::Null);
    }
    Err(NatErr::Fatal(JvmError::BudgetExceeded))
}
fn job_is_active(vm: &mut Vm, args: &[JValue]) -> R {
    Ok(JValue::Int(i32::from(job_active(vm, args[0])?)))
}
fn job_cancel(vm: &mut Vm, args: &[JValue]) -> R {
    let JValue::Obj(id) = args[0] else {
        return Err(NatErr::Throw(vm.err_npe()));
    };
    let cause = if args.get(2).is_some_and(|mask| mask.as_int() & 1 != 0) {
        JValue::Null
    } else {
        args.get(1).copied().unwrap_or(JValue::Null)
    };
    let object = &mut vm.arena.objects[id as usize];
    if object.fields.get(1) == Some(&JValue::Int(2)) {
        return Ok(JValue::Null);
    }
    object.fields.resize(3, JValue::Null);
    object.fields[1] = JValue::Int(1);
    object.fields[2] = cause;
    Ok(JValue::Null)
}
fn active(vm: &mut Vm, args: &[JValue]) -> R {
    let ctx = scope_context(vm, args[0])?;
    let k = singleton(vm, JOB, "Key", "Lkotlinx/coroutines/Job$Key;")?;
    let job = get(vm, &[ctx, k])?;
    Ok(JValue::Int(i32::from(job_active(vm, job)?)))
}
pub(super) fn ensure_active(vm: &mut Vm, value: JValue) -> Result<(), NatErr> {
    if active(vm, &[value])?.is_zero() {
        return Err(NatErr::Throw(vm.throwable_of(
            "Ljava/util/concurrent/CancellationException;",
            "Coroutine scope cancelled",
        )));
    }
    Ok(())
}
pub(super) fn contains_main(vm: &mut Vm, context: JValue) -> Result<bool, NatErr> {
    for value in elements(vm, context)? {
        if is_type(vm, value, "Lkotlinx/coroutines/MainCoroutineDispatcher;")? {
            return Ok(true);
        }
    }
    Ok(false)
}
fn coroutine_scope(vm: &mut Vm, args: &[JValue]) -> R {
    let ctx = current(vm)?;
    let s = scope(vm, ctx)?;
    ensure_active(vm, s)?;
    vm.invoke_virtual_args(
        args[0],
        "invoke",
        "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;",
        vec![s, args[1]],
    )
    .map_err(|e| java(vm, e))
}
fn launch(vm: &mut Vm, args: &[JValue]) -> R {
    let task = async_task(vm, args)?;
    if let Some(Native::Deferred { error, .. }) = vm.payload_of(task) {
        if !error.is_null_ref() {
            return Err(NatErr::Throw(error.as_obj()));
        }
    }
    Ok(task)
}
// App async fields: parent, state (-1 lazy, 0 running, 1 cancelled, 2 done),
// cause, child scope, block. Native::Deferred retains the value/exception.
pub(super) fn async_task(vm: &mut Vm, args: &[JValue]) -> R {
    let scope = task_scope(vm, args)?;
    let context = scope_context(vm, scope)?;
    let k = singleton(vm, JOB, "Key", "Lkotlinx/coroutines/Job$Key;")?;
    let parent = get(vm, &[context, k])?;
    let default = args.get(4).is_some_and(|v| v.as_int() & 2 != 0);
    let lazy = if default {
        false
    } else {
        matches!(
            vm.payload_of(args[2]),
            Some(Native::Enum { ordinal: 1, .. })
        )
    };
    let task = vm
        .alloc_native(
            "Lkotlinx/coroutines/Deferred;",
            Native::Deferred {
                value: JValue::Null,
                error: JValue::Null,
            },
        )
        .map_err(NatErr::Fatal)?;
    let child = plus(vm, &[context, task])?;
    let scope = super::coroutine_compat::scope(vm, child)?;
    vm.arena.objects[task.as_obj() as usize].fields =
        vec![parent, JValue::Int(-1), JValue::Null, scope, args[3]];
    if !lazy {
        start_task(vm, &[task])?;
    }
    Ok(task)
}
fn start_task(vm: &mut Vm, args: &[JValue]) -> R {
    if args[0].is_null_ref() {
        return Err(NatErr::Throw(vm.err_npe()));
    }
    let fields = vm.arena.objects[args[0].as_obj() as usize].fields.clone();
    if fields.len() != 5 || fields[1] != JValue::Int(-1) {
        return Ok(JValue::Int(0));
    }
    vm.arena.objects[args[0].as_obj() as usize].fields[1] = JValue::Int(0);
    let scope = fields[3];
    if !job_active(vm, fields[0])? {
        let cause = JValue::Obj(vm.throwable_of(
            "Ljava/util/concurrent/CancellationException;",
            "Coroutine parent cancelled",
        ));
        let object = &mut vm.arena.objects[args[0].as_obj() as usize];
        object.fields[1] = JValue::Int(1);
        object.fields[2] = cause;
        object.fields[4] = JValue::Null;
        object.native = Some(Native::Deferred {
            value: JValue::Null,
            error: cause,
        });
        return Ok(JValue::Int(0));
    }
    let context = scope_context(vm, scope)?;
    let previous = enter(vm, context)?;
    let result = super::continuation_compat::run_block(vm, fields[4], scope, context);
    restore(vm, previous)?;
    let (value, error) = match result {
        Ok(value) => (value, JValue::Null),
        Err(NatErr::Throw(id)) => (JValue::Null, JValue::Obj(id)),
        Err(error) => return Err(error),
    };
    let object = &mut vm.arena.objects[args[0].as_obj() as usize];
    if object.fields[1] != JValue::Int(1) {
        object.fields[1] = JValue::Int(2);
        object.fields[2] = error;
        object.native = Some(Native::Deferred { value, error });
    }
    object.fields[4] = JValue::Null;
    Ok(JValue::Int(1))
}
pub(super) fn await_task(vm: &mut Vm, args: &[JValue]) -> R {
    start_task(vm, &args[..1])?;
    let fields = &vm.arena.objects[args[0].as_obj() as usize].fields;
    if fields.len() == 5 && fields[1] == JValue::Int(1) {
        let cause = fields[2];
        return Err(NatErr::Throw(if cause.is_null_ref() {
            vm.throwable_of(
                "Ljava/util/concurrent/CancellationException;",
                "Task cancelled",
            )
        } else {
            cause.as_obj()
        }));
    }
    if fields.len() == 5 && fields[1] != JValue::Int(2) {
        return Err(NatErr::Throw(vm.throwable_of(
            "Ljava/lang/IllegalStateException;",
            "Task is still running",
        )));
    }
    match vm.payload_of(args[0]) {
        Some(Native::Deferred { value, error }) if error.is_null_ref() => Ok(value),
        Some(Native::Deferred { error, .. }) => Err(NatErr::Throw(error.as_obj())),
        _ => Err(NatErr::Throw(vm.err_iae("Invalid deferred result"))),
    }
}
pub(super) fn is_app_task(vm: &Vm, value: JValue) -> bool {
    matches!(value,JValue::Obj(id) if vm.arena.objects[id as usize].fields.len()==5 && matches!(vm.arena.objects[id as usize].native,Some(Native::Deferred{..})))
}
fn completed(vm: &mut Vm, args: &[JValue]) -> R {
    if args[0].is_null_ref() {
        return Err(NatErr::Throw(vm.err_npe()));
    }
    Ok(JValue::Int(i32::from(
        vm.arena.objects[args[0].as_obj() as usize]
            .fields
            .get(1)
            .is_some_and(|v| matches!(v, JValue::Int(1 | 2))),
    )))
}
fn cancelled(vm: &mut Vm, args: &[JValue]) -> R {
    if args[0].is_null_ref() {
        return Err(NatErr::Throw(vm.err_npe()));
    }
    let fields = &vm.arena.objects[args[0].as_obj() as usize].fields;
    Ok(JValue::Int(i32::from(
        fields.get(1) == Some(&JValue::Int(1)) || fields.get(2).is_some_and(|v| !v.is_null_ref()),
    )))
}
fn join(vm: &mut Vm, args: &[JValue]) -> R {
    start_task(vm, &args[..1])?;
    unit(vm)
}
fn unit(vm: &mut Vm) -> R {
    singleton(vm, "Lkotlin/Unit;", "INSTANCE", "Lkotlin/Unit;")
}
fn run_blocking(vm: &mut Vm, args: &[JValue]) -> R {
    let context = if args[0].is_null_ref() || args.get(2).is_some_and(|v| v.as_int() & 1 != 0) {
        empty(vm)?
    } else {
        args[0]
    };
    let scope = create_scope(vm, &[context])?;
    let context = scope_context(vm, scope)?;
    let previous = enter(vm, context)?;
    let result = super::continuation_compat::run_block(vm, args[1], scope, context);
    restore(vm, previous)?;
    result
}
fn delay(vm: &mut Vm, args: &[JValue]) -> R {
    let duration = args[0].as_long();
    if duration <= 0 {
        return unit(vm);
    }
    let start = std::time::Instant::now();
    let context = current(vm)?;
    let scope = scope(vm, context)?;
    loop {
        charge(vm, 1)?;
        ensure_active(vm, scope)?;
        super::browser_compat::check_deadline(vm)?;
        let elapsed = start.elapsed().as_millis();
        if elapsed >= duration as u128 {
            break;
        }
        // No guest timers are skipped. The operation deadline bounds the wait,
        // and cancellation/budget checks run between short sleeping slices.
        std::thread::sleep(std::time::Duration::from_millis(
            (duration as u128 - elapsed).min(5) as u64,
        ));
    }
    unit(vm)
}
fn await_all(vm: &mut Vm, args: &[JValue]) -> R {
    let values = match vm.payload_of(args[0]) {
        Some(Native::List(v) | Native::Set(v) | Native::Array(ArrayData::Obj(v))) => v,
        _ => return Err(NatErr::Throw(vm.err_npe())),
    };
    charge(vm, values.len())?;
    let mut results = Vec::new();
    for value in values {
        results.push(
            vm.invoke_virtual_args(
                value,
                "await",
                "(Lkotlin/coroutines/Continuation;)Ljava/lang/Object;",
                vec![args[1]],
            )
            .map_err(|e| java(vm, e))?,
        );
    }
    vm.alloc_native("Ljava/util/ArrayList;", Native::List(results))
        .map_err(NatErr::Fatal)
}
pub(super) fn install(vm: &mut Vm) -> Result<(), JvmError> {
    let marker = super::kotlin_type_compat::marker;
    let context = marker(vm, CONTEXT);
    let element = marker(vm, ELEMENT);
    let key_type = marker(vm, KEY);
    vm.classes[element as usize].interfaces = vec![context];
    let interceptor = marker(vm, INTERCEPTOR);
    vm.classes[interceptor as usize].interfaces = vec![element];
    let job = vm.ensure_class_by_desc(JOB)?;
    vm.classes[job as usize].is_interface = true;
    vm.classes[job as usize].interfaces = vec![element];
    for (class, parent) in [
        (DISPATCHER, interceptor),
        ("Lkotlinx/coroutines/CompletableJob;", job),
        ("Lkotlinx/coroutines/Deferred;", job),
    ] {
        let id = vm.ensure_class_by_desc(class)?;
        vm.classes[id as usize].interfaces.push(parent);
    }
    let dispatcher = vm.ensure_class_by_desc(DISPATCHER)?;
    let main = vm.ensure_class_by_desc("Lkotlinx/coroutines/MainCoroutineDispatcher;")?;
    vm.classes[main as usize].superclass = Some(dispatcher);
    for class in [EMPTY, COMBINED] {
        vm.register_native(NativeEntry {
            class,
            name: "plus",
            sig: "(Lkotlin/coroutines/CoroutineContext;)Lkotlin/coroutines/CoroutineContext;",
            instance: true,
            f: plus,
        })?;
        let id = vm.ensure_class_by_desc(class)?;
        vm.classes[id as usize].interfaces.push(context);
    }
    for class in [CONTEXT, ELEMENT, DISPATCHER, JOB] {
        for (name,sig,f) in [
            ("plus","(Lkotlin/coroutines/CoroutineContext;)Lkotlin/coroutines/CoroutineContext;",plus as dexvm::vm::NativeFn),
            ("get","(Lkotlin/coroutines/CoroutineContext$Key;)Lkotlin/coroutines/CoroutineContext$Element;",get),
            ("minusKey","(Lkotlin/coroutines/CoroutineContext$Key;)Lkotlin/coroutines/CoroutineContext;",minus),
            ("fold","(Ljava/lang/Object;Lkotlin/jvm/functions/Function2;)Ljava/lang/Object;",fold),
        ] {vm.register_native(NativeEntry {class,name,sig,instance:true,f})?;}
    }
    for class in [DISPATCHER, JOB] {
        vm.register_native(NativeEntry {
            class,
            name: "getKey",
            sig: "()Lkotlin/coroutines/CoroutineContext$Key;",
            instance: true,
            f: get_key,
        })?;
    }
    let value = vm.alloc_native(EMPTY, Native::List(vec![]))?;
    super::multipart_compat::static_value(vm, EMPTY, "INSTANCE", EMPTY, value)?;
    super::multipart_compat::static_value(vm, CONTEXT, "__acCurrent", CONTEXT, value)?;
    for (owner, desc) in [
        (JOB, "Lkotlinx/coroutines/Job$Key;"),
        (
            INTERCEPTOR,
            "Lkotlin/coroutines/ContinuationInterceptor$Key;",
        ),
    ] {
        let id = marker(vm, desc);
        vm.classes[id as usize].is_interface = false;
        vm.classes[id as usize].is_abstract = false;
        vm.classes[id as usize].interfaces.push(key_type);
        let value = vm.alloc_native(desc, Native::Opaque)?;
        super::multipart_compat::static_value(vm, owner, "Key", desc, value)?;
    }
    for (class,name,sig,instance,f) in [
        ("Lkotlinx/coroutines/CoroutineScopeKt;","CoroutineScope","(Lkotlin/coroutines/CoroutineContext;)Lkotlinx/coroutines/CoroutineScope;",false,create_scope as dexvm::vm::NativeFn),
        (SCOPE,"getCoroutineContext","()Lkotlin/coroutines/CoroutineContext;",true,get_context),
        ("Lkotlinx/coroutines/SupervisorKt;","SupervisorJob$default","(Lkotlinx/coroutines/Job;ILjava/lang/Object;)Lkotlinx/coroutines/CompletableJob;",false,supervisor),
        (JOB,"isActive","()Z",true,job_is_active),
        (JOB,"isCompleted","()Z",true,completed),
        (JOB,"isCancelled","()Z",true,cancelled),
        (JOB,"start","()Z",true,start_task),
        (JOB,"join","(Lkotlin/coroutines/Continuation;)Ljava/lang/Object;",true,join),
        (JOB,"cancel$default","(Lkotlinx/coroutines/Job;Ljava/util/concurrent/CancellationException;ILjava/lang/Object;)V",false,job_cancel),
        (JOB,"cancel","(Ljava/util/concurrent/CancellationException;)V",true,job_cancel),
        ("Lkotlinx/coroutines/CoroutineScopeKt;","isActive","(Lkotlinx/coroutines/CoroutineScope;)Z",false,active),
        ("Lkotlinx/coroutines/CoroutineScopeKt;","coroutineScope","(Lkotlin/jvm/functions/Function2;Lkotlin/coroutines/Continuation;)Ljava/lang/Object;",false,coroutine_scope),
        ("Lkotlinx/coroutines/AwaitKt;","awaitAll","(Ljava/util/Collection;Lkotlin/coroutines/Continuation;)Ljava/lang/Object;",false,await_all),
        ("Lkotlinx/coroutines/AwaitKt;","awaitAll","([Lkotlinx/coroutines/Deferred;Lkotlin/coroutines/Continuation;)Ljava/lang/Object;",false,await_all),
        ("Lkotlinx/coroutines/DelayKt;","delay","(JLkotlin/coroutines/Continuation;)Ljava/lang/Object;",false,delay),
        ("Lkotlinx/coroutines/DelayKt;","delay-VtjQ1oo","(JLkotlin/coroutines/Continuation;)Ljava/lang/Object;",false,delay),
        ("Lkotlinx/coroutines/BuildersKt;","runBlockingK","(Lkotlin/coroutines/CoroutineContext;Lkotlin/jvm/functions/Function2;)Ljava/lang/Object;",false,run_blocking),
        ("Lkotlinx/coroutines/BuildersKt;","runBlockingK$default","(Lkotlin/coroutines/CoroutineContext;Lkotlin/jvm/functions/Function2;ILjava/lang/Object;)Ljava/lang/Object;",false,run_blocking),
        ("Lkotlinx/coroutines/BuildersKt;","runBlocking","(Lkotlin/coroutines/CoroutineContext;Lkotlin/jvm/functions/Function2;)Ljava/lang/Object;",false,run_blocking),
        ("Lkotlinx/coroutines/BuildersKt;","runBlocking$default","(Lkotlin/coroutines/CoroutineContext;Lkotlin/jvm/functions/Function2;ILjava/lang/Object;)Ljava/lang/Object;",false,run_blocking),
        ("Lkotlinx/coroutines/BuildersKt;","launch$default","(Lkotlinx/coroutines/CoroutineScope;Lkotlin/coroutines/CoroutineContext;Lkotlinx/coroutines/CoroutineStart;Lkotlin/jvm/functions/Function2;ILjava/lang/Object;)Lkotlinx/coroutines/Job;",false,launch),
    ] {vm.register_native(NativeEntry {class,name,sig,instance,f})?;}
    let class = "Lkotlinx/coroutines/CoroutineStart;";
    super::kotlin_type_compat::marker(vm, class);
    for (ordinal, name) in ["DEFAULT", "LAZY", "ATOMIC", "UNDISPATCHED"]
        .into_iter()
        .enumerate()
    {
        let value = vm.alloc_native(
            class,
            Native::Enum {
                name: name.into(),
                ordinal: ordinal as i32,
            },
        )?;
        super::multipart_compat::static_value(vm, class, name, class, value)?;
    }
    super::continuation_compat::install(vm)?;
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
    fn counting_block(vm: &mut Vm, args: &[JValue]) -> R {
        let Some(Native::IntBox(n)) = &mut vm.arena.objects[args[0].as_obj() as usize].native
        else {
            unreachable!()
        };
        *n += 1;
        assert!(!args[1].is_null_ref());
        assert!(!args[2].is_null_ref());
        Ok(vm.alloc_string("owned"))
    }
    fn delayed_block(vm: &mut Vm, args: &[JValue]) -> R {
        delay(vm, &[JValue::Long(50), args[2]])
    }
    fn block(vm: &mut Vm, f: dexvm::vm::NativeFn) -> JValue {
        vm.register_native(NativeEntry {
            class: "Lapp/CoroutineBlock;",
            name: "invoke",
            sig: "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;",
            instance: true,
            f,
        })
        .unwrap();
        vm.alloc_native("Lapp/CoroutineBlock;", Native::IntBox(0))
            .unwrap()
    }
    #[test]
    fn lazy_tasks_start_once_retain_results_and_observe_parent_cancellation() {
        let mut vm = vm();
        let block = block(&mut vm, counting_block);
        let lazy = singleton(
            &mut vm,
            "Lkotlinx/coroutines/CoroutineStart;",
            "LAZY",
            "Lkotlinx/coroutines/CoroutineStart;",
        )
        .unwrap();
        let parent = new_job(&mut vm, JValue::Null).unwrap();
        let s = scope(&mut vm, parent).unwrap();
        let args = [s, JValue::Null, lazy, block, JValue::Int(1), JValue::Null];
        let task = async_task(&mut vm, &args).unwrap();
        assert!(matches!(vm.payload_of(block), Some(Native::IntBox(0))));
        assert_eq!(job_is_active(&mut vm, &[task]).unwrap(), JValue::Int(0));
        vm.gc(&[task.as_obj(), s.as_obj()]);
        let result = await_task(&mut vm, &[task]).unwrap();
        assert_eq!(vm.str_of_jvalue(result).as_deref(), Some("owned"));
        assert_eq!(await_task(&mut vm, &[task]).unwrap(), result);
        assert!(matches!(vm.payload_of(block), Some(Native::IntBox(1))));
        assert_eq!(completed(&mut vm, &[task]).unwrap(), JValue::Int(1));
        assert_eq!(cancelled(&mut vm, &[task]).unwrap(), JValue::Int(0));
        let cancelled_task = async_task(&mut vm, &args).unwrap();
        job_cancel(&mut vm, &[parent, JValue::Null]).unwrap();
        assert!(matches!(
            await_task(&mut vm, &[cancelled_task]),
            Err(NatErr::Throw(_))
        ));
        assert!(matches!(vm.payload_of(block), Some(Native::IntBox(1))));
        assert_eq!(
            cancelled(&mut vm, &[cancelled_task]).unwrap(),
            JValue::Int(1)
        );
    }
    #[test]
    fn delay_waits_and_checks_cancellation_timeout_and_instruction_budget() {
        let mut vm = vm();
        super::super::browser_compat::install(&mut vm).unwrap();
        let start = std::time::Instant::now();
        delay(&mut vm, &[JValue::Long(12), JValue::Null]).unwrap();
        assert!(start.elapsed() >= std::time::Duration::from_millis(12));
        let job = new_job(&mut vm, JValue::Null).unwrap();
        let old = enter(&mut vm, job).unwrap();
        job_cancel(&mut vm, &[job, JValue::Null]).unwrap();
        assert!(matches!(
            delay(&mut vm, &[JValue::Long(1), JValue::Null]),
            Err(NatErr::Throw(_))
        ));
        restore(&mut vm, old).unwrap();
        let b = block(&mut vm, delayed_block);
        let result = vm.invoke_static(
            "Lkotlinx/coroutines/TimeoutKt;",
            "withTimeout-KLykuaI",
            "(JLkotlin/jvm/functions/Function2;Lkotlin/coroutines/Continuation;)Ljava/lang/Object;",
            vec![JValue::Long(5), b, JValue::Null],
        );
        assert!(matches!(result, Err(JvmError::Uncaught(_))), "{result:?}");
        vm.budget = 0;
        assert!(matches!(
            delay(&mut vm, &[JValue::Long(1), JValue::Null]),
            Err(NatErr::Fatal(JvmError::BudgetExceeded))
        ));
    }
    fn dispatcher(vm: &mut Vm, main: bool) -> JValue {
        vm.invoke_static(
            "Lkotlinx/coroutines/Dispatchers;",
            if main { "getMain" } else { "getIO" },
            if main {
                "()Lkotlinx/coroutines/MainCoroutineDispatcher;"
            } else {
                "()Lkotlinx/coroutines/CoroutineDispatcher;"
            },
            vec![],
        )
        .unwrap()
    }
    #[test]
    fn combined_context_replaces_keys_preserves_jobs_and_survives_gc() {
        let mut vm = vm();
        let io = dispatcher(&mut vm, false);
        let main = dispatcher(&mut vm, true);
        let job = new_job(&mut vm, JValue::Null).unwrap();
        let first = plus(&mut vm, &[io, job]).unwrap();
        let combined = plus(&mut vm, &[first, main]).unwrap();
        let k = singleton(&mut vm, JOB, "Key", "Lkotlinx/coroutines/Job$Key;").unwrap();
        let dk = singleton(
            &mut vm,
            INTERCEPTOR,
            "Key",
            "Lkotlin/coroutines/ContinuationInterceptor$Key;",
        )
        .unwrap();
        assert_eq!(get(&mut vm, &[combined, k]).unwrap(), job);
        assert_eq!(get(&mut vm, &[combined, dk]).unwrap(), main);
        assert_eq!(elements(&mut vm, combined).unwrap(), [job, main]);
        assert!(contains_main(&mut vm, combined).unwrap());
        let s = create_scope(&mut vm, &[combined]).unwrap();
        vm.gc(&[s.as_obj()]);
        assert_eq!(scope_context(&mut vm, s).unwrap(), combined);
        assert_eq!(minus(&mut vm, &[combined, dk]).unwrap(), job);
        let empty = minus(&mut vm, &[job, k]).unwrap();
        assert!(elements(&mut vm, empty).unwrap().is_empty());
        let updated = plus(&mut vm, &[combined, io]).unwrap();
        assert!(!contains_main(&mut vm, updated).unwrap());
        vm.budget = 0;
        assert!(matches!(
            plus(&mut vm, &[combined, io]),
            Err(NatErr::Fatal(JvmError::BudgetExceeded))
        ));
    }
    fn fails(vm: &mut Vm, _: &[JValue]) -> R {
        Err(NatErr::Throw(
            vm.throwable_of("Ljava/io/IOException;", "Owned failure"),
        ))
    }
    fn limit(_: &mut Vm, _: &[JValue]) -> R {
        Err(NatErr::Fatal(JvmError::BudgetExceeded))
    }
    #[test]
    fn cancelled_parents_reject_tasks_and_default_masks_do_not_retain_parent_jobs() {
        let mut vm = vm();
        let parent = new_job(&mut vm, JValue::Null).unwrap();
        let child = supervisor(&mut vm, &[parent, JValue::Int(0)]).unwrap();
        let s = scope(&mut vm, child).unwrap();
        assert_eq!(active(&mut vm, &[s]).unwrap(), JValue::Int(1));
        job_cancel(&mut vm, &[parent, JValue::Null]).unwrap();
        assert!(matches!(ensure_active(&mut vm, s), Err(NatErr::Throw(_))));
        let detached = supervisor(&mut vm, &[parent, JValue::Int(1)]).unwrap();
        assert!(job_active(&mut vm, detached).unwrap());
        let args = [s, JValue::Null, JValue::Null, JValue::Null, JValue::Int(3)];
        assert!(matches!(task_scope(&mut vm, &args), Err(NatErr::Throw(_))));
    }
    #[test]
    fn launch_restores_context_and_never_swallows_exceptions_or_vm_limits() {
        for (f, fatal) in [(fails as dexvm::vm::NativeFn, false), (limit, true)] {
            let mut vm = vm();
            let original = current(&mut vm).unwrap();
            let io = dispatcher(&mut vm, false);
            let s = create_scope(&mut vm, &[io]).unwrap();
            vm.register_native(NativeEntry {
                class: "LOwnedTask;",
                name: "invoke",
                sig: "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;",
                instance: true,
                f,
            })
            .unwrap();
            let task = vm.alloc_native("LOwnedTask;", Native::Opaque).unwrap();
            let result = launch(
                &mut vm,
                &[s, JValue::Null, JValue::Null, task, JValue::Int(3)],
            );
            if fatal {
                assert!(matches!(
                    result,
                    Err(NatErr::Fatal(JvmError::BudgetExceeded))
                ));
            } else {
                assert!(matches!(result, Err(NatErr::Throw(_))));
            }
            assert_eq!(current(&mut vm).unwrap(), original);
        }
    }
    #[test]
    fn await_all_preserves_failed_deferred_results() {
        let mut vm = vm();
        vm.register_native(NativeEntry {
            class: "Lkotlinx/coroutines/Deferred;",
            name: "await",
            sig: "(Lkotlin/coroutines/Continuation;)Ljava/lang/Object;",
            instance: true,
            f: super::super::coroutine_await,
        })
        .unwrap();
        let error = vm.throwable_of("Ljava/io/IOException;", "Owned failure");
        let failed = vm
            .alloc_native(
                "Lkotlinx/coroutines/Deferred;",
                Native::Deferred {
                    value: JValue::Null,
                    error: JValue::Obj(error),
                },
            )
            .unwrap();
        let list = vm
            .alloc_native("Ljava/util/ArrayList;", Native::List(vec![failed]))
            .unwrap();
        assert!(
            matches!(await_all(&mut vm,&[list,JValue::Null]),Err(NatErr::Throw(id)) if id==error)
        );
    }
}
