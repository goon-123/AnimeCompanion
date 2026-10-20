//! Typed Java collection arrays and Kotlin indexed-value components.
use dexvm::vm::object::{ArrayData, Native};
use dexvm::vm::{error::JvmError, NatErr, NativeEntry, Vm};
use dexvm::JValue;

type R = Result<JValue, NatErr>;

fn array_store(vm: &mut Vm) -> NatErr {
    NatErr::Throw(vm.throwable_of(
        "Ljava/lang/ArrayStoreException;",
        "Incompatible collection element",
    ))
}

fn typed_array(vm: &mut Vm, args: &[JValue]) -> R {
    if args[0].is_null() || args[1].is_null() {
        return Err(NatErr::Throw(vm.err_npe()));
    }
    let values = match vm.payload_of(args[0]) {
        Some(Native::List(values) | Native::Set(values)) => values,
        _ => {
            return Err(NatErr::Throw(
                vm.err_iae("Unsupported collection representation"),
            ))
        }
    };
    let Some(Native::Array(ArrayData::Obj(buffer))) = vm.payload_of(args[1]) else {
        return Err(array_store(vm));
    };
    if values.len() > 10_000 || vm.budget <= values.len() as i64 {
        return Err(NatErr::Fatal(JvmError::BudgetExceeded));
    }
    vm.budget -= values.len() as i64;
    let owner = vm.arena.objects[args[1].as_obj() as usize].class;
    let descriptor = vm.str_of(vm.classes[owner as usize].descriptor).to_owned();
    let component = descriptor
        .strip_prefix('[')
        .ok_or_else(|| array_store(vm))?;
    let target = vm.ensure_class_by_desc(component).map_err(NatErr::Fatal)?;
    for value in &values {
        if value.is_null() {
            continue;
        }
        let JValue::Obj(object) = value else {
            return Err(array_store(vm));
        };
        let class = vm.arena.objects[*object as usize].class;
        if !vm.is_assignable(class, target).map_err(NatErr::Fatal)? {
            return Err(array_store(vm));
        }
    }
    if buffer.len() < values.len() {
        return vm
            .alloc_native(&descriptor, Native::Array(ArrayData::Obj(values)))
            .map_err(NatErr::Fatal);
    }
    let Some(Native::Array(ArrayData::Obj(buffer))) =
        vm.arena.objects[args[1].as_obj() as usize].native.as_mut()
    else {
        return Err(array_store(vm));
    };
    buffer[..values.len()].copy_from_slice(&values);
    if buffer.len() > values.len() {
        buffer[values.len()] = JValue::Null;
    }
    Ok(args[1])
}

fn component_index(vm: &mut Vm, args: &[JValue]) -> R {
    match vm.payload_of(args[0]) {
        Some(Native::Pair(index, _)) => Ok(index),
        _ => Err(NatErr::Throw(vm.err_npe())),
    }
}

fn component_value(vm: &mut Vm, args: &[JValue]) -> R {
    match vm.payload_of(args[0]) {
        Some(Native::Pair(_, value)) => Ok(value),
        _ => Err(NatErr::Throw(vm.err_npe())),
    }
}

fn remove_all(vm: &mut Vm, args: &[JValue]) -> R {
    let Some(Native::List(values)) = vm.payload_of(args[0]) else {
        return Err(NatErr::Throw(vm.err_iae("Expected a mutable list")));
    };
    if args[1].is_null_ref() {
        return Err(NatErr::Throw(vm.err_npe()));
    }
    if values.len() > 100_000 {
        return Err(NatErr::Fatal(JvmError::BudgetExceeded));
    }
    let mut kept = Vec::with_capacity(values.len());
    let mut changed = false;
    for value in values {
        if vm.budget <= 0 {
            return Err(NatErr::Fatal(JvmError::BudgetExceeded));
        }
        vm.budget -= 1;
        let result = vm
            .invoke_virtual_args(
                args[1],
                "invoke",
                "(Ljava/lang/Object;)Ljava/lang/Object;",
                vec![value],
            )
            .map_err(|e| match e {
                JvmError::Uncaught(o) => NatErr::Throw(o),
                other => NatErr::Fatal(other),
            })?;
        let payload = if matches!(result, JValue::Obj(_)) {
            vm.payload_of(result)
        } else {
            None
        };
        let remove = match payload {
            Some(Native::BoolBox(value)) => value,
            _ if result.is_null_ref() => return Err(NatErr::Throw(vm.err_npe())),
            _ => {
                return Err(NatErr::Throw(vm.throwable_of(
                    "Ljava/lang/ClassCastException;",
                    "Predicate must return Boolean",
                )))
            }
        };
        if remove {
            changed = true;
        } else {
            kept.push(value);
        }
    }
    if let Some(Native::List(values)) = &mut vm.arena.objects[args[0].as_obj() as usize].native {
        *values = kept;
    }
    Ok(JValue::Int(i32::from(changed)))
}

fn array_store_init(vm: &mut Vm, args: &[JValue]) -> R {
    let message = args.get(1).and_then(|value| vm.str_of_jvalue(*value));
    vm.arena.objects[args[0].as_obj() as usize].native = Some(Native::Throwable {
        message,
        cause: JValue::Null,
    });
    Ok(JValue::Null)
}

pub(super) fn install(vm: &mut Vm) -> Result<(), JvmError> {
    vm.register_native(NativeEntry {
        class: "Lkotlin/collections/CollectionsKt;",
        name: "removeAll",
        sig: "(Ljava/util/List;Lkotlin/jvm/functions/Function1;)Z",
        instance: false,
        f: remove_all,
    })?;
    for sig in ["()V", "(Ljava/lang/String;)V"] {
        vm.register_native(NativeEntry {
            class: "Ljava/lang/ArrayStoreException;",
            name: "<init>",
            sig,
            instance: true,
            f: array_store_init,
        })?;
    }
    let exception = vm.ensure_class_by_desc("Ljava/lang/ArrayStoreException;")?;
    vm.classes[exception as usize].superclass =
        Some(vm.ensure_class_by_desc("Ljava/lang/RuntimeException;")?);
    for class in [
        "Ljava/util/Collection;",
        "Ljava/util/List;",
        "Ljava/util/Set;",
        "Ljava/util/ArrayList;",
        "Ljava/util/LinkedList;",
        "Ljava/util/HashSet;",
        "Ljava/util/LinkedHashSet;",
    ] {
        vm.register_native(NativeEntry {
            class,
            name: "toArray",
            sig: "([Ljava/lang/Object;)[Ljava/lang/Object;",
            instance: true,
            f: typed_array,
        })?;
    }
    for (name, sig, f) in [
        ("component1", "()I", component_index as dexvm::vm::NativeFn),
        ("component2", "()Ljava/lang/Object;", component_value),
    ] {
        vm.register_native(NativeEntry {
            class: "Lkotlin/collections/IndexedValue;",
            name,
            sig,
            instance: true,
            f,
        })?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn predicate(vm: &mut Vm, args: &[JValue]) -> R {
        vm.alloc_native(
            "Ljava/lang/Boolean;",
            Native::BoolBox(args[1] == JValue::Int(2)),
        )
        .map_err(NatErr::Fatal)
    }
    #[test]
    fn remove_all_unboxes_guest_predicate_booleans_and_mutates_the_list() {
        let mut vm = Vm::new(vec![], Box::new(std::io::sink())).unwrap();
        install(&mut vm).unwrap();
        vm.register_native(NativeEntry {
            class: "LOwnedPredicate;",
            name: "invoke",
            sig: "(Ljava/lang/Object;)Ljava/lang/Object;",
            instance: true,
            f: predicate,
        })
        .unwrap();
        let predicate = vm.alloc_native("LOwnedPredicate;", Native::Opaque).unwrap();
        let list = vm
            .alloc_native(
                "Ljava/util/ArrayList;",
                Native::List(vec![JValue::Int(1), JValue::Int(2), JValue::Int(3)]),
            )
            .unwrap();
        assert_eq!(
            remove_all(&mut vm, &[list, predicate]).unwrap(),
            JValue::Int(1)
        );
        assert!(
            matches!(vm.payload_of(list),Some(Native::List(v)) if v == vec![JValue::Int(1),JValue::Int(3)])
        );
        assert_eq!(
            remove_all(&mut vm, &[list, predicate]).unwrap(),
            JValue::Int(0)
        );
    }

    #[test]
    fn typed_collection_arrays_reuse_or_allocate_and_check_component_types() {
        let mut vm = Vm::new(vec![], Box::new(std::io::sink())).unwrap();
        install(&mut vm).unwrap();
        let first = vm.alloc_string("Owned first");
        let last = vm.alloc_string("Owned last");
        let set = vm
            .alloc_native("Ljava/util/HashSet;", Native::Set(vec![first, last]))
            .unwrap();
        let empty = vm
            .alloc_native("[Ljava/lang/String;", Native::Array(ArrayData::Obj(vec![])))
            .unwrap();
        let result = vm
            .invoke_virtual_args(
                set,
                "toArray",
                "([Ljava/lang/Object;)[Ljava/lang/Object;",
                vec![empty],
            )
            .unwrap();
        assert_ne!(result, empty);
        assert!(
            matches!(vm.payload_of(result), Some(Native::Array(ArrayData::Obj(items))) if items == [first, last])
        );
        let class = vm.arena.objects[result.as_obj() as usize].class;
        assert_eq!(
            vm.str_of(vm.classes[class as usize].descriptor),
            "[Ljava/lang/String;"
        );
        let target = vm
            .alloc_native(
                "[Ljava/lang/String;",
                Native::Array(ArrayData::Obj(vec![last; 4])),
            )
            .unwrap();
        assert_eq!(typed_array(&mut vm, &[set, target]).unwrap(), target);
        assert!(
            matches!(vm.payload_of(target), Some(Native::Array(ArrayData::Obj(items))) if items == [first, last, JValue::Null, last])
        );
        let number = vm
            .alloc_native("Ljava/lang/Integer;", Native::IntBox(7))
            .unwrap();
        let mixed = vm
            .alloc_native("Ljava/util/ArrayList;", Native::List(vec![number]))
            .unwrap();
        let Err(NatErr::Throw(error)) = typed_array(&mut vm, &[mixed, empty]) else {
            panic!("Incompatible elements must throw ArrayStoreException");
        };
        let actual = vm.arena.objects[error as usize].class;
        assert_eq!(vm.class_desc_str(actual), "java.lang.ArrayStoreException");
        let parent = vm
            .ensure_class_by_desc("Ljava/lang/RuntimeException;")
            .unwrap();
        assert!(vm.is_assignable(actual, parent).unwrap());
        assert!(typed_array(&mut vm, &[set, JValue::Null]).is_err());
    }

    #[test]
    fn indexed_components_preserve_unboxed_index_and_object_identity() {
        let mut vm = Vm::new(vec![], Box::new(std::io::sink())).unwrap();
        install(&mut vm).unwrap();
        let text = vm.alloc_string("Owned value");
        let indexed = vm
            .alloc_native(
                "Lkotlin/collections/IndexedValue;",
                Native::Pair(JValue::Int(3), text),
            )
            .unwrap();
        assert_eq!(
            vm.invoke_virtual(indexed, "component1", "()I").unwrap(),
            JValue::Int(3)
        );
        assert_eq!(
            vm.invoke_virtual(indexed, "component2", "()Ljava/lang/Object;")
                .unwrap(),
            text
        );
    }
}
