//! Compiler-produced DEX exercises real suspend/resume and reflection call sites.
use super::*;
const CLASS: &str = "Lapp/animecompanion/probe/SharedJvmProbe;";
fn vm() -> Vm {
    let dex =
        dexvm::dex::DexFile::parse(include_bytes!("../test-support/shared-jvm-probe.dex")).unwrap();
    let mut vm = Vm::new(vec![dex], Box::new(std::io::sink())).unwrap();
    java_compat::install(&mut vm).unwrap();
    kotlin_runtime_compat::install(&mut vm).unwrap();
    array_compat::install(&mut vm).unwrap();
    method_reflection_compat::install(&mut vm).unwrap();
    property_reference_compat::install(&mut vm).unwrap();
    coroutine_compat::install(&mut vm).unwrap();
    vm
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
