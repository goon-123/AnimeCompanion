//! Compiler-produced DEX exercises real suspend/resume and reflection call sites.
use super::*;
const CLASS: &str = "Lapp/animecompanion/probe/SharedJvmProbe;";
fn call(vm: &mut Vm, name: &str, sig: &str) -> JValue {
    vm.invoke_static(CLASS, name, sig, vec![])
        .unwrap_or_else(|error| {
            if let dexvm::vm::error::JvmError::Uncaught(id) = error {
                let message = match vm.payload_of(JValue::Obj(id)) {
                    Some(dexvm::vm::object::Native::Throwable { message, .. }) => message,
                    _ => None,
                };
                panic!(
                    "{name}: {} {message:?}",
                    vm.class_desc_str(vm.arena.objects[id as usize].class)
                );
            }
            panic!("{name}: {error}")
        })
}
fn vm() -> Vm {
    let dex =
        dexvm::dex::DexFile::parse(include_bytes!("../test-support/shared-jvm-probe.dex")).unwrap();
    let mut vm = Vm::new(vec![dex], Box::new(std::io::sink())).unwrap();
    java_compat::install(&mut vm).unwrap();
    kotlin_runtime_compat::install(&mut vm).unwrap();
    array_compat::install(&mut vm).unwrap();
    collection_compat::install(&mut vm).unwrap();
    kotlin_collection_compat::install(&mut vm).unwrap();
    kotlin_text_compat::install(&mut vm).unwrap();
    sequence_compat::install(&mut vm).unwrap();
    method_reflection_compat::install(&mut vm).unwrap();
    reflection_compat::install(&mut vm).unwrap();
    date_amount_compat::install(&mut vm).unwrap();
    time_unit_compat::install(&mut vm).unwrap();
    property_reference_compat::install(&mut vm).unwrap();
    browser_compat::install(&mut vm).unwrap();
    coroutine_compat::install(&mut vm).unwrap();
    for entry in COROUTINE_BRIDGE {
        vm.register_native(*entry).unwrap();
    }
    vm
}
#[test]
fn guest_field_reflection_and_time_unit_contracts_execute_real_call_sites() {
    for name in [
        "fieldContracts",
        "timeUnitContracts",
        "preciseTimeContracts",
    ] {
        let mut vm = vm();
        assert_eq!(call(&mut vm, name, "()Z"), JValue::Int(1));
    }
}

const COROUTINE_BRIDGE: &[NativeEntry] = &[
    NativeEntry { class: "Lkotlinx/coroutines/BuildersKt;", name: "async$default", sig: "(Lkotlinx/coroutines/CoroutineScope;Lkotlin/coroutines/CoroutineContext;Lkotlinx/coroutines/CoroutineStart;Lkotlin/jvm/functions/Function2;ILjava/lang/Object;)Lkotlinx/coroutines/Deferred;", instance: false, f: coroutine_async },
    NativeEntry { class: "Lkotlinx/coroutines/Deferred;", name: "await", sig: "(Lkotlin/coroutines/Continuation;)Ljava/lang/Object;", instance: true, f: coroutine_await },
];

#[test]
fn guest_cooperative_tasks_suspend_interleave_order_results_and_survive_gc() {
    let mut vm = vm();
    call(&mut vm, "prepareScheduled", "()V");
    vm.gc(&[]);
    let result = call(&mut vm, "finishScheduled", "()Ljava/lang/String;");
    assert_eq!(vm.str_of_jvalue(result).as_deref(), Some("one|two"));
    assert_eq!(
        call(&mut vm, "waitsForLaunchedChild", "()Z"),
        JValue::Int(1)
    );
    let result = call(&mut vm, "launchedChildResult", "()Ljava/lang/String;");
    assert_eq!(vm.str_of_jvalue(result).as_deref(), Some("child finished"));
    let result = call(&mut vm, "nestedChildCompletion", "()Ljava/lang/String;");
    assert_eq!(vm.str_of_jvalue(result).as_deref(), Some("outer"));
    let result = call(&mut vm, "nestedChildFailure", "()Ljava/lang/String;");
    assert_eq!(
        vm.str_of_jvalue(result).as_deref(),
        Some("owned nested failure")
    );
    let result = call(&mut vm, "completableResults", "()Ljava/lang/String;");
    assert_eq!(
        vm.str_of_jvalue(result).as_deref(),
        Some("owned completion")
    );
}
#[test]
fn unresumable_coroutines_and_fatal_limits_restore_state_and_discard_owned_events() {
    let mut vm = vm();
    let context = coroutine_compat::current(&mut vm).unwrap();
    assert!(matches!(
        vm.invoke_static(CLASS, "nonCompletingTask", "()V", vec![]),
        Err(dexvm::vm::error::JvmError::Uncaught(_))
    ));
    assert_eq!(coroutine_compat::current(&mut vm).unwrap(), context);
    assert!(!coroutine_event_compat::driving(&mut vm).unwrap());
    assert!(!coroutine_event_compat::pump(&mut vm).unwrap());
    call(&mut vm, "prepareScheduled", "()V");
    vm.budget = 0;
    assert!(matches!(
        coroutine_event_compat::pump(&mut vm),
        Err(NatErr::Fatal(dexvm::vm::error::JvmError::BudgetExceeded))
    ));
    assert_eq!(coroutine_compat::current(&mut vm).unwrap(), context);
}
#[test]
fn guest_scheduled_failures_cancellation_finally_and_timeouts_are_not_empty_successes() {
    for name in ["cancellationFinally", "timeoutAfterSuspension"] {
        let mut vm = vm();
        assert_eq!(call(&mut vm, name, "()Z"), JValue::Int(1));
    }
    let mut vm = vm();
    let result = call(&mut vm, "scheduledFailure", "()Ljava/lang/String;");
    assert_eq!(
        vm.str_of_jvalue(result).as_deref(),
        Some("owned scheduled failure")
    );
}

#[test]
fn guest_arrays_and_deques_preserve_values_types_order_and_failures() {
    for name in [
        "arrayContracts",
        "dequeContracts",
        "sequenceConsumerContracts",
    ] {
        let mut vm = vm();
        assert_eq!(call(&mut vm, name, "()Z"), JValue::Int(1));
    }
}
#[test]
fn guest_default_maps_and_lazy_lines_survive_gc_without_eager_callbacks() {
    for (prepare, check) in [
        ("prepareDefaultMap", "defaultMapContracts"),
        ("prepareLines", "lineContracts"),
    ] {
        let mut vm = vm();
        call(&mut vm, prepare, "()V");
        vm.gc(&[]);
        assert_eq!(call(&mut vm, check, "()Z"), JValue::Int(1));
    }
}
#[test]
fn guest_utf16_character_iteration_and_random_use_the_actual_guest_contracts() {
    let mut vm = vm();
    assert_eq!(call(&mut vm, "characterContracts", "()Z"), JValue::Int(1));
}
#[test]
fn collection_callback_failures_and_vm_limits_propagate_without_results() {
    use dexvm::vm::error::JvmError;
    use dexvm::vm::object::{ArrayData, Native};
    fn fail(vm: &mut Vm, _args: &[JValue]) -> Result<JValue, NatErr> {
        Err(NatErr::Throw(vm.throwable_of(
            "Ljava/lang/IllegalArgumentException;",
            "Owned callback failure",
        )))
    }
    fn limit(_vm: &mut Vm, _args: &[JValue]) -> Result<JValue, NatErr> {
        Err(NatErr::Fatal(JvmError::BudgetExceeded))
    }
    for (method, sig, f) in [
        (
            "equals",
            "(Ljava/lang/Object;)Z",
            fail as dexvm::vm::NativeFn,
        ),
        ("invoke", "(Ljava/lang/Object;)Ljava/lang/Object;", limit),
    ] {
        let mut vm = vm();
        vm.register_native(NativeEntry {
            class: "Lapp/OwnedCollectionFailure;",
            name: method,
            sig,
            instance: true,
            f,
        })
        .unwrap();
        let callback = vm
            .alloc_native("Lapp/OwnedCollectionFailure;", Native::Opaque)
            .unwrap();
        if method == "equals" {
            let element = vm.alloc_string("owned");
            let array = vm
                .alloc_native(
                    "[Ljava/lang/Object;",
                    Native::Array(ArrayData::Obj(vec![element])),
                )
                .unwrap();
            assert!(matches!(
                vm.invoke_static(
                    "Lkotlin/collections/ArraysKt;",
                    "indexOf",
                    "([Ljava/lang/Object;Ljava/lang/Object;)I",
                    vec![array, callback]
                ),
                Err(JvmError::Uncaught(_))
            ));
        } else {
            let map = vm
                .alloc_native("Ljava/util/LinkedHashMap;", Native::Map(vec![]))
                .unwrap();
            let wrapper = vm
                .invoke_static(
                    "Lkotlin/collections/MapsKt;",
                    "withDefault",
                    "(Ljava/util/Map;Lkotlin/jvm/functions/Function1;)Ljava/util/Map;",
                    vec![map, callback],
                )
                .unwrap();
            let key = vm.alloc_string("missing");
            assert!(matches!(
                vm.invoke_static(
                    "Lkotlin/collections/MapsKt;",
                    "getValue",
                    "(Ljava/util/Map;Ljava/lang/Object;)Ljava/lang/Object;",
                    vec![wrapper, key]
                ),
                Err(JvmError::BudgetExceeded)
            ));
            let sequence = vm
                .alloc_native("Lkotlin/sequences/Sequence;", Native::List(vec![key]))
                .unwrap();
            let mapped=vm.invoke_static("Lkotlin/sequences/SequencesKt;","map","(Lkotlin/sequences/Sequence;Lkotlin/jvm/functions/Function1;)Lkotlin/sequences/Sequence;",vec![sequence,callback]).unwrap();
            assert!(matches!(
                vm.invoke_static(
                    "Lkotlin/sequences/SequencesKt;",
                    "count",
                    "(Lkotlin/sequences/Sequence;)I",
                    vec![mapped]
                ),
                Err(JvmError::BudgetExceeded)
            ));
        }
        assert_eq!(vm.recursion_depth, 0);
    }
    let mut vm = vm();
    let array = vm
        .alloc_native(
            "[Ljava/lang/Object;",
            Native::Array(ArrayData::Obj(vec![JValue::Null; 16])),
        )
        .unwrap();
    vm.budget = 1;
    assert!(matches!(
        vm.invoke_static(
            "Lkotlin/collections/ArraysKt;",
            "last",
            "([Ljava/lang/Object;)Ljava/lang/Object;",
            vec![array]
        ),
        Err(JvmError::BudgetExceeded)
    ));
}
#[test]
fn dex_string_decoder_rejects_malformed_modified_utf8_in_the_real_fixture() {
    let original = include_bytes!("../test-support/shared-jvm-probe.dex");
    let start = original
        .windows(6)
        .position(|b| b == [0xed, 0xa0, 0xbd, 0xed, 0xb8, 0x80])
        .expect("Owned emoji literal");
    for malformed in [
        [0xf0, 0xa0, 0xbd],
        [0xed, 0x41, 0xbd],
        [0xe0, 0x80, 0x81],
        [0xed, 0, 0xbd],
    ] {
        let mut bytes = original.to_vec();
        bytes[start..start + 3].copy_from_slice(&malformed);
        let Err(error) = dexvm::dex::DexFile::parse(&bytes) else {
            panic!("Invalid string must fail");
        };
        assert!(error.to_string().contains("modified UTF-8"), "{error}");
    }
}
#[test]
fn guest_continuations_suspend_resume_after_gc_and_propagate_failures() {
    for (fail, expected) in [(false, "owned done"), (true, "failure:owned")] {
        let mut vm = vm();
        vm.invoke_static(CLASS, "begin", "()V", vec![]).unwrap();
        vm.gc(&[]);
        let value = vm
            .invoke_static(
                CLASS,
                "finish",
                "(Z)Ljava/lang/String;",
                vec![JValue::Int(i32::from(fail))],
            )
            .unwrap();
        assert_eq!(vm.str_of_jvalue(value).as_deref(), Some(expected));
    }
    let mut vm = vm();
    vm.invoke_static(CLASS, "begin", "()V", vec![]).unwrap();
    assert_eq!(
        vm.invoke_static(CLASS, "doubleResume", "()Z", vec![])
            .unwrap(),
        JValue::Int(1)
    );
}
#[test]
fn guest_method_reflection_dispatches_overrides_widens_and_wraps_guest_errors() {
    let mut vm = vm();
    for (name, expected) in [
        ("reflectVirtual", "child:owned"),
        ("reflectFailure", "owned method failure"),
    ] {
        let value = vm
            .invoke_static(CLASS, name, "()Ljava/lang/String;", vec![])
            .unwrap();
        assert_eq!(vm.str_of_jvalue(value).as_deref(), Some(expected));
    }
    assert_eq!(
        vm.invoke_static(CLASS, "reflectWiden", "()J", vec![])
            .unwrap(),
        JValue::Long(42)
    );
    assert_eq!(
        vm.invoke_static(CLASS, "reflectPrivate", "()I", vec![])
            .unwrap(),
        JValue::Int(42)
    );
}
