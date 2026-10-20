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

pub(super) fn install(vm: &mut Vm) -> Result<(), JvmError> {
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
        assert!(typed_array(&mut vm, &[mixed, empty]).is_err());
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
