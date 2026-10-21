//! Generic serializable elements have an Object ABI, including nullable numbers.
//! JsonNames annotations describe aliases; normalize only the decoder's private
//! object copy, keeping the caller's JsonElement unchanged.
use dexvm::vm::{
    error::JvmError,
    object::{ArrayData, JsonVal, Native},
    NatErr, NativeEntry, NativeFn, Vm,
};
use dexvm::JValue;
use std::sync::OnceLock;
type R = Result<JValue, NatErr>;
static ELEMENT: OnceLock<NativeFn> = OnceLock::new();
static NULLABLE: OnceLock<NativeFn> = OnceLock::new();
const CLASS: &str = "Lkotlinx/serialization/json/internal/StreamingJsonDecoder;";
const SIG:&str="(Lkotlinx/serialization/descriptors/SerialDescriptor;ILkotlinx/serialization/DeserializationStrategy;Ljava/lang/Object;)Ljava/lang/Object;";
fn wrap(vm: &mut Vm, value: JValue) -> R {
    let ty = match value {
        JValue::Int(_) => "I",
        JValue::Long(_) => "J",
        JValue::Float(_) => "F",
        JValue::Double(_) => "D",
        _ => return Ok(value),
    };
    super::method_reflection_compat::boxed(vm, value, ty)
}
fn element(vm: &mut Vm, args: &[JValue]) -> R {
    let value = ELEMENT.get().expect("Original element decoder")(vm, args)?;
    wrap(vm, value)
}
fn nullable(vm: &mut Vm, args: &[JValue]) -> R {
    let value = NULLABLE.get().expect("Original nullable decoder")(vm, args)?;
    wrap(vm, value)
}
pub(super) fn install(vm: &mut Vm) -> Result<(), JvmError> {
    for (name, slot, f) in [
        ("decodeSerializableElement", &ELEMENT, element as NativeFn),
        ("decodeNullableSerializableElement", &NULLABLE, nullable),
    ] {
        let key = (vm.intern(CLASS), vm.intern(name), vm.intern(SIG));
        let original = *vm
            .natives
            .get(&key)
            .ok_or_else(|| JvmError::Resolution("Missing JSON element decoder".into()))?;
        let _ = slot.set(original);
        vm.register_native(NativeEntry {
            class: CLASS,
            name,
            sig: SIG,
            instance: true,
            f,
        })?;
    }
    Ok(())
}
pub(super) fn normalize_aliases(vm: &mut Vm, args: &[JValue]) -> Result<(), NatErr> {
    let element = match vm.payload_of(args[0]) {
        Some(Native::JsonDecoder {
            element, index: 0, ..
        }) => element,
        _ => return Ok(()),
    };
    let (names, annotations) = match vm.payload_of(args[1]) {
        Some(Native::SerialDescriptor {
            elements,
            element_annotations,
            ..
        }) => (elements, element_annotations),
        _ => return Ok(()),
    };
    if annotations.iter().all(Vec::is_empty) {
        return Ok(());
    }
    let alias_type = vm
        .ensure_class_by_desc("Lkotlinx/serialization/json/JsonNames;")
        .map_err(NatErr::Fatal)?;
    let mut aliases = std::collections::HashMap::<String, String>::new();
    for (name, annotations) in names.iter().zip(annotations) {
        for annotation in annotations {
            let Some(class) = vm.object_class(annotation) else {
                continue;
            };
            if !vm.is_assignable(class, alias_type).map_err(NatErr::Fatal)? {
                continue;
            }
            if vm.budget <= 0 {
                return Err(NatErr::Fatal(JvmError::BudgetExceeded));
            }
            vm.budget -= 1;
            if vm.recursion_depth >= vm.depth_limit {
                return Err(NatErr::Fatal(JvmError::StackOverflow));
            }
            vm.recursion_depth += 1;
            let result = vm.invoke_virtual(annotation, "names", "()[Ljava/lang/String;");
            vm.recursion_depth -= 1;
            let array = result.map_err(|e| match e {
                JvmError::Uncaught(id) => NatErr::Throw(id),
                e => NatErr::Fatal(e),
            })?;
            let Some(Native::Array(ArrayData::Obj(values))) = vm.payload_of(array) else {
                continue;
            };
            for value in values {
                if aliases.len() >= 1000 || vm.budget <= 0 {
                    return Err(NatErr::Fatal(JvmError::BudgetExceeded));
                }
                vm.budget -= 1;
                let alias = vm
                    .str_of_jvalue(value)
                    .ok_or_else(|| NatErr::Throw(vm.err_npe()))?;
                if names.contains(&alias) || aliases.insert(alias, name.clone()).is_some() {
                    return Err(NatErr::Throw(
                        vm.err_iae("Conflicting serialized field alias"),
                    ));
                }
            }
        }
    }
    if aliases.is_empty() {
        return Ok(());
    }
    let Some(Native::Json(JsonVal::Object(mut members))) = vm.payload_of(element) else {
        return Ok(());
    };
    let original = members
        .iter()
        .map(|(name, _)| name.clone())
        .collect::<std::collections::HashSet<_>>();
    members.retain(|(name, _)| {
        !aliases
            .get(name)
            .is_some_and(|canonical| original.contains(canonical))
    });
    for (name, _) in &mut members {
        if let Some(canonical) = aliases.get(name) {
            *name = canonical.clone();
        }
    }
    let element = vm
        .alloc_native(
            "Lkotlinx/serialization/json/JsonObject;",
            Native::Json(JsonVal::Object(members)),
        )
        .map_err(NatErr::Fatal)?;
    if let Some(Native::JsonDecoder { element: slot, .. }) =
        &mut vm.arena.objects[args[0].as_obj() as usize].native
    {
        *slot = element;
    }
    Ok(())
}
