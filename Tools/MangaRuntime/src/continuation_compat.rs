//! Bounded continuation state machines on the single interpreted thread.
//! Suspension tokens are VM-local static roots; completion/receiver references
//! live in traced object fields, never in a process-global native side table.
use dexvm::vm::{error::JvmError, object::Native, NatErr, NativeEntry, Vm};
use dexvm::JValue;
type R = Result<JValue, NatErr>;
const BASE: &str = "Lkotlin/coroutines/jvm/internal/BaseContinuationImpl;";
const COLLECTOR: &str = "Lapp/animecompanion/CoroutineCompletion;";
const SAFE: &str = "Lkotlin/coroutines/SafeContinuation;";
fn failure(error: JvmError) -> NatErr {
    match error {
        JvmError::Uncaught(id) => NatErr::Throw(id),
        e => NatErr::Fatal(e),
    }
}
pub(super) fn invoke(vm: &mut Vm, receiver: JValue, name: &str, sig: &str, args: Vec<JValue>) -> R {
    if receiver.is_null_ref() {
        return Err(NatErr::Throw(vm.err_npe()));
    }
    if vm.budget <= 0 {
        return Err(NatErr::Fatal(JvmError::BudgetExceeded));
    }
    if vm.recursion_depth >= vm.depth_limit {
        return Err(NatErr::Fatal(JvmError::StackOverflow));
    }
    vm.budget -= 1;
    vm.recursion_depth += 1;
    let result = vm.invoke_virtual_args(receiver, name, sig, args);
    vm.recursion_depth -= 1;
    result.map_err(failure)
}
fn field(vm: &mut Vm, value: JValue, name: &str) -> R {
    if value.is_null_ref() {
        return Err(NatErr::Throw(vm.err_npe()));
    }
    vm.instance_field(value.as_obj(), name)
        .ok_or_else(|| NatErr::Throw(vm.err_iae("Invalid continuation")))
}
pub(super) fn suspended(vm: &mut Vm, _: &[JValue]) -> R {
    let key = dexvm::vm::FieldRef {
        class_desc: vm.intern(BASE),
        name: vm.intern("__acSuspended"),
        ty: vm.intern("Ljava/lang/Object;"),
    };
    vm.static_field_get(key).map_err(NatErr::Fatal)
}
fn init(vm: &mut Vm, args: &[JValue]) -> R {
    let completion = args[1];
    let context = if args.len() == 3 {
        args[2]
    } else if !completion.is_null_ref() {
        invoke(
            vm,
            completion,
            "getContext",
            "()Lkotlin/coroutines/CoroutineContext;",
            vec![],
        )?
    } else {
        super::coroutine_compat::current(vm)?
    };
    if !vm.instance_field_set(args[0].as_obj(), "completion", completion)
        || !vm.instance_field_set(args[0].as_obj(), "_context", context)
    {
        return Err(NatErr::Throw(vm.err_iae("Invalid continuation fields")));
    }
    Ok(JValue::Null)
}
fn lambda_init(vm: &mut Vm, args: &[JValue]) -> R {
    init(vm, &[args[0], args[2]])
}
fn get_completion(vm: &mut Vm, args: &[JValue]) -> R {
    field(vm, args[0], "completion")
}
fn get_context(vm: &mut Vm, args: &[JValue]) -> R {
    field(vm, args[0], "_context")
}
fn identity(_vm: &mut Vm, args: &[JValue]) -> R {
    Ok(args[0])
}
fn debug_probe(_vm: &mut Vm, _args: &[JValue]) -> R {
    Ok(JValue::Null)
}
fn unit(vm: &mut Vm) -> R {
    let key = dexvm::vm::FieldRef {
        class_desc: vm.intern("Lkotlin/Unit;"),
        name: vm.intern("INSTANCE"),
        ty: vm.intern("Lkotlin/Unit;"),
    };
    vm.static_field_get(key).map_err(NatErr::Fatal)
}
fn resume(vm: &mut Vm, args: &[JValue]) -> R {
    let (mut receiver, mut result) = (args[0], args[1]);
    let base = vm.ensure_class_by_desc(BASE).map_err(NatErr::Fatal)?;
    for _ in 0..256 {
        let completion = field(vm, receiver, "completion")?;
        let context = field(vm, receiver, "_context")?;
        let previous = super::coroutine_compat::enter(vm, context)?;
        let resumed = invoke(
            vm,
            receiver,
            "invokeSuspend",
            "(Ljava/lang/Object;)Ljava/lang/Object;",
            vec![result],
        );
        super::coroutine_compat::restore(vm, previous)?;
        result = match resumed {
            Ok(value) => value,
            Err(NatErr::Throw(id)) => vm
                .alloc_native(
                    "Lkotlin/Result$Failure;",
                    Native::ResultFailure(JValue::Obj(id)),
                )
                .map_err(NatErr::Fatal)?,
            Err(error) => return Err(error),
        };
        if result == suspended(vm, &[])? {
            return Ok(JValue::Null);
        }
        if completion.is_null_ref() {
            return Err(NatErr::Throw(vm.throwable_of(
                "Ljava/lang/IllegalStateException;",
                "Coroutine has no completion",
            )));
        }
        let class = vm
            .object_class(completion)
            .ok_or_else(|| NatErr::Throw(vm.err_npe()))?;
        if vm.is_assignable(class, base).map_err(NatErr::Fatal)? {
            receiver = completion;
        } else {
            return invoke(
                vm,
                completion,
                "resumeWith",
                "(Ljava/lang/Object;)V",
                vec![result],
            );
        }
    }
    Err(NatErr::Fatal(JvmError::BudgetExceeded))
}
fn collector_context(vm: &mut Vm, args: &[JValue]) -> R {
    Ok(vm.arena.objects[args[0].as_obj() as usize].fields[0])
}
fn collect(vm: &mut Vm, args: &[JValue]) -> R {
    if !vm.arena.objects[args[0].as_obj() as usize].fields[1].is_zero() {
        return Err(NatErr::Throw(vm.throwable_of(
            "Ljava/lang/IllegalStateException;",
            "Coroutine already completed",
        )));
    }
    let fields = &mut vm.arena.objects[args[0].as_obj() as usize].fields;
    fields[1] = JValue::Int(1);
    fields[2] = args[1];
    let task = fields.get(3).copied().unwrap_or(JValue::Null);
    if !task.is_null_ref() {
        super::coroutine_compat::complete_task(vm, task, args[1])?;
    }
    Ok(JValue::Null)
}
fn unwrap(vm: &mut Vm, value: JValue) -> R {
    if let Some(Native::ResultFailure(error)) = vm.payload_of(value) {
        Err(NatErr::Throw(error.as_obj()))
    } else {
        Ok(value)
    }
}
pub(super) fn resume_value(vm: &mut Vm, continuation: JValue, result: JValue) -> R {
    invoke(
        vm,
        continuation,
        "resumeWith",
        "(Ljava/lang/Object;)V",
        vec![result],
    )
}
pub(super) fn begin_block(
    vm: &mut Vm,
    block: JValue,
    scope: JValue,
    context: JValue,
    task: JValue,
) -> R {
    let completion = vm
        .alloc_native(COLLECTOR, Native::Opaque)
        .map_err(NatErr::Fatal)?;
    vm.arena.objects[completion.as_obj() as usize].fields =
        vec![context, JValue::Int(0), JValue::Null, task];
    if !task.is_null_ref() {
        vm.arena.objects[task.as_obj() as usize].fields[5] = completion;
    }
    let value = match invoke(
        vm,
        block,
        "invoke",
        "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;",
        vec![scope, completion],
    ) {
        Ok(value) => value,
        Err(NatErr::Throw(id)) => vm
            .alloc_native(
                "Lkotlin/Result$Failure;",
                Native::ResultFailure(JValue::Obj(id)),
            )
            .map_err(NatErr::Fatal)?,
        Err(error) => return Err(error),
    };
    if value != suspended(vm, &[])? {
        collect(vm, &[completion, value])?;
    }
    Ok(completion)
}
pub(super) fn run_block(vm: &mut Vm, block: JValue, scope: JValue, context: JValue) -> R {
    let checkpoint = super::coroutine_event_compat::checkpoint(vm)?;
    let driver = super::coroutine_event_compat::enter_driver(vm)?;
    let result = (|| {
        let completion = begin_block(vm, block, scope, context, JValue::Null)?;
        loop {
            let fields = &vm.arena.objects[completion.as_obj() as usize].fields;
            if !fields[1].is_zero() {
                let value = fields[2];
                if let Some(Native::ResultFailure(error)) = vm.payload_of(value) {
                    super::coroutine_compat::cancel_context(vm, context, error)?;
                }
                if !super::coroutine_event_compat::has_children(vm, context)? {
                    if let Some(error) = super::coroutine_compat::context_failure(vm, context)? {
                        return Err(NatErr::Throw(error.as_obj()));
                    }
                    return unwrap(vm, value);
                }
            }
            if !super::coroutine_event_compat::pump(vm)? {
                return Err(NatErr::Throw(vm.throwable_of(
                    "Ljava/lang/IllegalStateException;",
                    "Coroutine suspended without an available completion event",
                )));
            }
        }
    })();
    super::coroutine_event_compat::restore_driver(vm, driver)?;
    if result.is_err() {
        super::coroutine_event_compat::discard_since(vm, checkpoint)?;
    }
    result
}
fn safe_init(vm: &mut Vm, args: &[JValue]) -> R {
    let (state, result) = if args.len() == 3 && args[2] == suspended(vm, &[])? {
        (1, JValue::Null)
    } else {
        (0, JValue::Null)
    };
    vm.arena.objects[args[0].as_obj() as usize].fields = vec![args[1], JValue::Int(state), result];
    Ok(JValue::Null)
}
fn safe_context(vm: &mut Vm, args: &[JValue]) -> R {
    let delegate = vm.arena.objects[args[0].as_obj() as usize].fields[0];
    invoke(
        vm,
        delegate,
        "getContext",
        "()Lkotlin/coroutines/CoroutineContext;",
        vec![],
    )
}
fn safe_resume(vm: &mut Vm, args: &[JValue]) -> R {
    let fields = &mut vm.arena.objects[args[0].as_obj() as usize].fields;
    let previous = fields[1].as_int();
    if previous >= 2 {
        return Err(NatErr::Throw(vm.throwable_of(
            "Ljava/lang/IllegalStateException;",
            "Continuation already resumed",
        )));
    }
    fields[1] = JValue::Int(if previous == 1 { 3 } else { 2 });
    fields[2] = args[1];
    let delegate = fields[0];
    if previous == 1 {
        invoke(
            vm,
            delegate,
            "resumeWith",
            "(Ljava/lang/Object;)V",
            vec![args[1]],
        )?;
    }
    Ok(JValue::Null)
}
fn safe_result(vm: &mut Vm, args: &[JValue]) -> R {
    let fields = &mut vm.arena.objects[args[0].as_obj() as usize].fields;
    if fields[1].is_zero() {
        fields[1] = JValue::Int(1);
        return suspended(vm, &[]);
    }
    if matches!(fields[1], JValue::Int(1 | 3)) {
        return suspended(vm, &[]);
    }
    let result = fields[2];
    unwrap(vm, result)
}
fn start_coroutine(vm: &mut Vm, args: &[JValue]) -> R {
    let (block, completion) = (args[0], *args.last().unwrap());
    let result = invoke(
        vm,
        block,
        "invoke",
        if args.len() == 2 {
            "(Ljava/lang/Object;)Ljava/lang/Object;"
        } else {
            "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;"
        },
        args[1..].to_vec(),
    );
    let result = match result {
        Ok(value) if value == suspended(vm, &[])? => return Ok(JValue::Null),
        Ok(value) => value,
        Err(NatErr::Throw(error)) => vm
            .alloc_native(
                "Lkotlin/Result$Failure;",
                Native::ResultFailure(JValue::Obj(error)),
            )
            .map_err(NatErr::Fatal)?,
        Err(e) => return Err(e),
    };
    invoke(
        vm,
        completion,
        "resumeWith",
        "(Ljava/lang/Object;)V",
        vec![result],
    )?;
    Ok(JValue::Null)
}
pub(super) fn install(vm: &mut Vm) -> Result<(), JvmError> {
    for name in ["probeCoroutineSuspended", "probeCoroutineResumed"] {
        vm.register_native(NativeEntry {
            class: "Lkotlin/coroutines/jvm/internal/DebugProbesKt;",
            name,
            sig: "(Lkotlin/coroutines/Continuation;)V",
            instance: false,
            f: debug_probe,
        })?;
    }
    vm.register_native(NativeEntry {
        class: "Lkotlin/coroutines/jvm/internal/DebugProbesKt;",
        name: "probeCoroutineCreated",
        sig: "(Lkotlin/coroutines/Continuation;)Lkotlin/coroutines/Continuation;",
        instance: false,
        f: identity,
    })?;
    for (class, parent, signature) in [
        (
            BASE,
            "Ljava/lang/Object;",
            "(Lkotlin/coroutines/Continuation;)V",
        ),
        (
            "Lkotlin/coroutines/jvm/internal/ContinuationImpl;",
            BASE,
            "(Lkotlin/coroutines/Continuation;)V",
        ),
        (
            "Lkotlin/coroutines/jvm/internal/SuspendLambda;",
            "Lkotlin/coroutines/jvm/internal/ContinuationImpl;",
            "(ILkotlin/coroutines/Continuation;)V",
        ),
        (
            "Lkotlin/coroutines/jvm/internal/RestrictedContinuationImpl;",
            BASE,
            "(Lkotlin/coroutines/Continuation;)V",
        ),
        (
            "Lkotlin/coroutines/jvm/internal/RestrictedSuspendLambda;",
            "Lkotlin/coroutines/jvm/internal/RestrictedContinuationImpl;",
            "(ILkotlin/coroutines/Continuation;)V",
        ),
    ] {
        vm.register_native(NativeEntry {
            class,
            name: "<init>",
            sig: signature,
            instance: true,
            f: if class.contains("SuspendLambda") {
                lambda_init
            } else {
                init
            },
        })?;
        let parent = vm.ensure_class_by_desc(parent)?;
        let id = vm.ensure_class_by_desc(class)?;
        vm.classes[id as usize].superclass = Some(parent);
        let fields = if class == BASE {
            [
                ("completion", "Lkotlin/coroutines/Continuation;"),
                ("_context", "Lkotlin/coroutines/CoroutineContext;"),
            ]
            .into_iter()
            .map(|(n, t)| (vm.intern(n), vm.intern(t), 1))
            .collect()
        } else {
            vm.classes[parent as usize].instance_fields.clone()
        };
        let offsets = fields
            .iter()
            .enumerate()
            .map(|(i, (n, t, _))| ((*n, *t), i as u32))
            .collect();
        vm.classes[id as usize].instance_fields = fields;
        vm.classes[id as usize].field_offsets = offsets;
        let interface = vm.ensure_class_by_desc("Lkotlin/coroutines/Continuation;")?;
        vm.classes[id as usize].interfaces.push(interface);
    }
    for (class, name, sig, f) in [
        (
            BASE,
            "resumeWith",
            "(Ljava/lang/Object;)V",
            resume as dexvm::vm::NativeFn,
        ),
        (
            BASE,
            "getCompletion",
            "()Lkotlin/coroutines/Continuation;",
            get_completion,
        ),
        (
            BASE,
            "getContext",
            "()Lkotlin/coroutines/CoroutineContext;",
            get_context,
        ),
        (
            "Lkotlin/coroutines/jvm/internal/ContinuationImpl;",
            "<init>",
            "(Lkotlin/coroutines/Continuation;Lkotlin/coroutines/CoroutineContext;)V",
            init,
        ),
        (
            "Lkotlin/coroutines/jvm/internal/ContinuationImpl;",
            "intercepted",
            "()Lkotlin/coroutines/Continuation;",
            identity,
        ),
        (COLLECTOR, "resumeWith", "(Ljava/lang/Object;)V", collect),
        (
            COLLECTOR,
            "getContext",
            "()Lkotlin/coroutines/CoroutineContext;",
            collector_context,
        ),
        (
            SAFE,
            "<init>",
            "(Lkotlin/coroutines/Continuation;)V",
            safe_init,
        ),
        (
            SAFE,
            "<init>",
            "(Lkotlin/coroutines/Continuation;Ljava/lang/Object;)V",
            safe_init,
        ),
        (
            SAFE,
            "getContext",
            "()Lkotlin/coroutines/CoroutineContext;",
            safe_context,
        ),
        (SAFE, "resumeWith", "(Ljava/lang/Object;)V", safe_resume),
        (SAFE, "getOrThrow", "()Ljava/lang/Object;", safe_result),
    ] {
        vm.register_native(NativeEntry {
            class,
            name,
            sig,
            instance: true,
            f,
        })?;
    }
    for class in [
        "Lkotlin/coroutines/intrinsics/IntrinsicsKt;",
        "Lkotlin/coroutines/intrinsics/IntrinsicsKt__IntrinsicsKt;",
    ] {
        vm.register_native(NativeEntry {
            class,
            name: "getCOROUTINE_SUSPENDED",
            sig: "()Ljava/lang/Object;",
            instance: false,
            f: suspended,
        })?;
        vm.register_native(NativeEntry {
            class,
            name: "intercepted",
            sig: "(Lkotlin/coroutines/Continuation;)Lkotlin/coroutines/Continuation;",
            instance: false,
            f: identity,
        })?;
    }
    for sig in [
        "(Lkotlin/jvm/functions/Function1;Lkotlin/coroutines/Continuation;)V",
        "(Lkotlin/jvm/functions/Function2;Ljava/lang/Object;Lkotlin/coroutines/Continuation;)V",
    ] {
        vm.register_native(NativeEntry {
            class: "Lkotlin/coroutines/ContinuationKt;",
            name: "startCoroutine",
            sig,
            instance: false,
            f: start_coroutine,
        })?;
    }
    let value = vm.alloc_native("Ljava/lang/Object;", Native::Opaque)?;
    super::multipart_compat::static_value(vm, BASE, "__acSuspended", "Ljava/lang/Object;", value)?;
    let continuation = vm.ensure_class_by_desc("Lkotlin/coroutines/Continuation;")?;
    for class in [COLLECTOR, SAFE] {
        let id = vm.ensure_class_by_desc(class)?;
        vm.classes[id as usize].interfaces.push(continuation);
    }
    // Materialize Unit once; every resume uses the same rooted singleton.
    unit(vm).map_err(|_| JvmError::Fatal("Cannot initialize coroutine Unit".into()))?;
    Ok(())
}
