//! Typed Java collection arrays and Kotlin indexed-value components.
use dexvm::vm::object::{ArrayData, ClassOrPrim, Native};
use dexvm::vm::{error::JvmError, NatErr, NativeEntry, Vm};
use dexvm::JValue;

type R = Result<JValue, NatErr>;

fn array_store(vm: &mut Vm) -> NatErr {
    NatErr::Throw(vm.throwable_of(
        "Ljava/lang/ArrayStoreException;",
        "Incompatible collection element",
    ))
}

fn charge(vm: &mut Vm, count: usize) -> Result<(), NatErr> {
    if count > 1_000_000 || vm.budget <= count as i64 {
        return Err(NatErr::Fatal(JvmError::BudgetExceeded));
    }
    vm.budget -= count as i64 + 1;
    Ok(())
}

fn descriptor(vm: &mut Vm, array: JValue) -> Result<String, NatErr> {
    let JValue::Obj(id) = array else {
        return Err(NatErr::Throw(vm.err_npe()));
    };
    let object = &vm.arena.objects[id as usize];
    if !matches!(object.native, Some(Native::Array(_))) {
        return Err(NatErr::Throw(vm.err_iae("Expected an array")));
    }
    Ok(vm
        .str_of(vm.classes[object.class as usize].descriptor)
        .to_owned())
}

fn check_elements(vm: &mut Vm, desc: &str, values: &[JValue]) -> Result<(), NatErr> {
    let target = vm.ensure_class_by_desc(&desc[1..]).map_err(NatErr::Fatal)?;
    for value in values {
        if value.is_null_ref() {
            continue;
        }
        let JValue::Obj(id) = value else {
            return Err(array_store(vm));
        };
        if !vm
            .is_assignable(vm.arena.objects[*id as usize].class, target)
            .map_err(NatErr::Fatal)?
        {
            return Err(array_store(vm));
        }
    }
    Ok(())
}

// Object array payloads do not carry their component type. Always consult the
// arena class, including for nested arrays; elem_desc() would erase it.
fn copy_array(vm: &mut Vm, args: &[JValue], range: bool) -> R {
    let original = descriptor(vm, args[0])?;
    let Some(Native::Array(source)) = vm.payload_of(args[0]) else {
        unreachable!()
    };
    let (from, to, type_index) = if range {
        (args[1].as_int(), args[2].as_int(), 3)
    } else {
        (0, args[1].as_int(), 2)
    };
    if !range && to < 0 {
        return Err(NatErr::Throw(vm.err_neg_arr_size()));
    }
    if range && from > to {
        return Err(NatErr::Throw(vm.err_iae("Array range is reversed")));
    }
    if from < 0 || from as usize > source.len() {
        return Err(NatErr::Throw(vm.err_aioobe(from, source.len() as i32)));
    }
    let length = (i64::from(to) - i64::from(from)) as usize;
    charge(vm, length)?;
    let desc = if let Some(class) = args.get(type_index) {
        if class.is_null_ref() {
            return Err(NatErr::Throw(vm.err_npe()));
        }
        match vm.payload_of(*class) {
            Some(Native::ClassObj(ClassOrPrim::Class(id))) => {
                let d = vm.str_of(vm.classes[id as usize].descriptor).to_owned();
                if !d.starts_with("[L") && !d.starts_with("[[") {
                    return Err(NatErr::Throw(
                        vm.err_iae("Expected a reference array class"),
                    ));
                }
                d
            }
            _ if class.is_null_ref() => return Err(NatErr::Throw(vm.err_npe())),
            _ => return Err(NatErr::Throw(vm.err_iae("Expected an array class"))),
        }
    } else {
        original
    };
    let mut output = ArrayData::new(&desc[1..], length);
    let copied = length.min(source.len() - from as usize);
    if let ArrayData::Obj(values) = &source {
        check_elements(vm, &desc, &values[from as usize..from as usize + copied])?;
    }
    for i in 0..copied {
        output.set(i, source.get(from as usize + i));
    }
    vm.alloc_native(&desc, Native::Array(output))
        .map_err(NatErr::Fatal)
}
fn copy_of(vm: &mut Vm, args: &[JValue]) -> R {
    copy_array(vm, args, false)
}
fn copy_range(vm: &mut Vm, args: &[JValue]) -> R {
    copy_array(vm, args, true)
}

fn concat(vm: &mut Vm, args: &[JValue], element: bool) -> R {
    let desc = descriptor(vm, args[0])?;
    let Some(Native::Array(ArrayData::Obj(mut left))) = vm.payload_of(args[0]) else {
        return Err(NatErr::Throw(vm.err_iae("Expected a reference array")));
    };
    let right = if element {
        vec![args[1]]
    } else {
        if args[1].is_null_ref() {
            return Err(NatErr::Throw(vm.err_npe()));
        }
        match vm.payload_of(args[1]) {
            Some(Native::Array(ArrayData::Obj(v)) | Native::List(v) | Native::Set(v)) => v,
            _ => return Err(NatErr::Throw(vm.err_npe())),
        }
    };
    charge(vm, left.len().saturating_add(right.len()))?;
    check_elements(vm, &desc, &right)?;
    left.extend(right);
    vm.alloc_native(&desc, Native::Array(ArrayData::Obj(left)))
        .map_err(NatErr::Fatal)
}
fn plus(vm: &mut Vm, args: &[JValue]) -> R {
    concat(vm, args, false)
}
fn plus_element(vm: &mut Vm, args: &[JValue]) -> R {
    concat(vm, args, true)
}
fn set_serializer_init(vm: &mut Vm, args: &[JValue]) -> R {
    if args[1].is_null_ref() {
        return Err(NatErr::Throw(vm.err_npe()));
    }
    let object = &mut vm.arena.objects[args[0].as_obj() as usize];
    object.native = Some(Native::Opaque);
    object.fields = vec![args[1]];
    Ok(JValue::Null)
}
fn set_descriptor(vm: &mut Vm, args: &[JValue]) -> R {
    let child = vm.arena.objects[args[0].as_obj() as usize].fields[0];
    let value = vm
        .alloc_native(
            "Lkotlinx/serialization/internal/PluginGeneratedSerialDescriptor;",
            Native::SerialDescriptor {
                name: "kotlin.collections.LinkedHashSet".into(),
                elements: vec!["0".into()],
                element_annotations: vec![vec![]],
            },
        )
        .map_err(NatErr::Fatal)?;
    vm.arena.objects[value.as_obj() as usize].fields = vec![child];
    Ok(value)
}
fn set_deserialize(vm: &mut Vm, args: &[JValue]) -> R {
    if let Some(Native::JsonDecoder { element, .. }) = vm.payload_of(args[1]) {
        match vm.payload_of(element) {
            Some(Native::Json(dexvm::vm::object::JsonVal::Array(values)))
                if values.len() <= 10_000 => {}
            _ => {
                return Err(NatErr::Throw(vm.throwable_of(
                    "Lkotlinx/serialization/SerializationException;",
                    "Expected a bounded JSON set array",
                )))
            }
        }
    }
    let child = vm.arena.objects[args[0].as_obj() as usize].fields[0];
    let serializer = vm
        .alloc_native(
            "Lkotlinx/serialization/internal/ArrayListSerializer;",
            Native::ArrayListSerializer { child },
        )
        .map_err(NatErr::Fatal)?;
    let list = super::serialization_compat::list_deserialize(vm, &[serializer, args[1]])?;
    let Some(Native::List(values)) = vm.payload_of(list) else {
        return Err(NatErr::Throw(vm.err_iae("Expected decoded list")));
    };
    charge(vm, values.len())?;
    let set = vm
        .alloc_native("Ljava/util/LinkedHashSet;", Native::Set(vec![]))
        .map_err(NatErr::Fatal)?;
    for value in values {
        let length = match vm.payload_of(set) {
            Some(Native::Set(v)) => v.len(),
            _ => unreachable!(),
        };
        charge(vm, length)?;
        vm.invoke_virtual_args(set, "add", "(Ljava/lang/Object;)Z", vec![value])
            .map_err(|e| match e {
                JvmError::Uncaught(id) => NatErr::Throw(id),
                e => NatErr::Fatal(e),
            })?;
    }
    Ok(set)
}

fn typed_array(vm: &mut Vm, args: &[JValue]) -> R {
    if args[0].is_null_ref() || args[1].is_null_ref() {
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
    for (name, sig, f) in [
        (
            "<init>",
            "(Lkotlinx/serialization/KSerializer;)V",
            set_serializer_init as dexvm::vm::NativeFn,
        ),
        (
            "getDescriptor",
            "()Lkotlinx/serialization/descriptors/SerialDescriptor;",
            set_descriptor,
        ),
        (
            "deserialize",
            "(Lkotlinx/serialization/encoding/Decoder;)Ljava/lang/Object;",
            set_deserialize,
        ),
    ] {
        vm.register_native(NativeEntry {
            class: "Lkotlinx/serialization/internal/LinkedHashSetSerializer;",
            name,
            sig,
            instance: true,
            f,
        })?;
    }
    for sig in [
        "([Ljava/lang/Object;[Ljava/lang/Object;)[Ljava/lang/Object;",
        "([Ljava/lang/Object;Ljava/util/Collection;)[Ljava/lang/Object;",
    ] {
        vm.register_native(NativeEntry {
            class: "Lkotlin/collections/ArraysKt;",
            name: "plus",
            sig,
            instance: false,
            f: plus,
        })?;
    }
    vm.register_native(NativeEntry {
        class: "Lkotlin/collections/ArraysKt;",
        name: "plus",
        sig: "([Ljava/lang/Object;Ljava/lang/Object;)[Ljava/lang/Object;",
        instance: false,
        f: plus_element,
    })?;
    for (name, sig, f) in [
        (
            "copyOf",
            "([Ljava/lang/Object;I)[Ljava/lang/Object;",
            copy_of as dexvm::vm::NativeFn,
        ),
        (
            "copyOf",
            "([Ljava/lang/Object;ILjava/lang/Class;)[Ljava/lang/Object;",
            copy_of,
        ),
        (
            "copyOfRange",
            "([Ljava/lang/Object;II)[Ljava/lang/Object;",
            copy_range,
        ),
        (
            "copyOfRange",
            "([Ljava/lang/Object;IILjava/lang/Class;)[Ljava/lang/Object;",
            copy_range,
        ),
    ] {
        vm.register_native(NativeEntry {
            class: "Ljava/util/Arrays;",
            name,
            sig,
            instance: false,
            f,
        })?;
    }
    {
        let sig = "(Ljava/util/Collection;[Ljava/lang/Object;)[Ljava/lang/Object;";
        vm.register_native(NativeEntry {
            class: "Lkotlin/jvm/internal/CollectionToArray;",
            name: "toArray",
            sig,
            instance: false,
            f: typed_array,
        })?;
    }
    vm.register_native(NativeEntry {
        class: "Lkotlin/jvm/internal/SpreadBuilder;",
        name: "toArray",
        sig: "([Ljava/lang/Object;)[Ljava/lang/Object;",
        instance: true,
        f: typed_array,
    })?;
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

    #[test]
    fn kotlin_array_concatenation_and_java_copies_keep_runtime_component_types() {
        let mut vm = Vm::new(vec![], Box::new(std::io::sink())).unwrap();
        install(&mut vm).unwrap();
        let a = vm.alloc_string("alpha");
        let b = vm.alloc_string("beta");
        let array = vm
            .alloc_native(
                "[Ljava/lang/String;",
                Native::Array(ArrayData::Obj(vec![a])),
            )
            .unwrap();
        let list = vm
            .alloc_native("Ljava/util/ArrayList;", Native::List(vec![b, JValue::Null]))
            .unwrap();
        let combined = plus(&mut vm, &[array, list]).unwrap();
        assert_eq!(
            descriptor(&mut vm, combined).unwrap(),
            "[Ljava/lang/String;"
        );
        assert!(
            matches!(vm.payload_of(combined),Some(Native::Array(ArrayData::Obj(v))) if v==[a,b,JValue::Null])
        );
        let copy = copy_of(&mut vm, &[combined, JValue::Int(5)]).unwrap();
        assert_eq!(descriptor(&mut vm, copy).unwrap(), "[Ljava/lang/String;");
        assert!(
            matches!(vm.payload_of(copy),Some(Native::Array(ArrayData::Obj(v))) if v==[a,b,JValue::Null,JValue::Null,JValue::Null])
        );
        let range = copy_range(&mut vm, &[array, JValue::Int(1), JValue::Int(3)]).unwrap();
        assert!(
            matches!(vm.payload_of(range),Some(Native::Array(ArrayData::Obj(v))) if v==[JValue::Null,JValue::Null])
        );
        let clazz = vm.ensure_class_by_desc("[Ljava/lang/Object;").unwrap();
        let clazz = vm.class_obj(clazz).unwrap();
        let widened = copy_of(&mut vm, &[combined, JValue::Int(2), clazz]).unwrap();
        assert_eq!(descriptor(&mut vm, widened).unwrap(), "[Ljava/lang/Object;");
        let number = vm
            .alloc_native("Ljava/lang/Integer;", Native::IntBox(7))
            .unwrap();
        assert!(matches!(
            plus_element(&mut vm, &[array, number]),
            Err(NatErr::Throw(_))
        ));
        assert!(matches!(
            plus(&mut vm, &[array, JValue::Int(0)]),
            Err(NatErr::Throw(_))
        ));
        assert!(matches!(
            copy_of(&mut vm, &[array, JValue::Int(-1)]),
            Err(NatErr::Throw(_))
        ));
        assert!(matches!(
            copy_range(&mut vm, &[array, JValue::Int(2), JValue::Int(3)]),
            Err(NatErr::Throw(_))
        ));
        vm.budget = 1;
        assert!(matches!(
            copy_of(&mut vm, &[array, JValue::Int(i32::MAX)]),
            Err(NatErr::Fatal(JvmError::BudgetExceeded))
        ));
    }

    #[test]
    fn nested_array_copies_retain_dimensions_and_reject_incompatible_narrowing() {
        let mut vm = Vm::new(vec![], Box::new(std::io::sink())).unwrap();
        install(&mut vm).unwrap();
        let text = vm.alloc_string("owned");
        let inner = vm
            .alloc_native(
                "[Ljava/lang/String;",
                Native::Array(ArrayData::Obj(vec![text])),
            )
            .unwrap();
        let outer = vm
            .alloc_native(
                "[[Ljava/lang/String;",
                Native::Array(ArrayData::Obj(vec![inner])),
            )
            .unwrap();
        let copied = copy_of(&mut vm, &[outer, JValue::Int(2)]).unwrap();
        assert_eq!(descriptor(&mut vm, copied).unwrap(), "[[Ljava/lang/String;");
        assert!(
            matches!(vm.payload_of(copied),Some(Native::Array(ArrayData::Obj(v))) if v==[inner,JValue::Null])
        );
        let wrong = vm.ensure_class_by_desc("[Ljava/lang/Integer;").unwrap();
        let wrong = vm.class_obj(wrong).unwrap();
        assert!(matches!(
            copy_of(&mut vm, &[inner, JValue::Int(1), wrong]),
            Err(NatErr::Throw(_))
        ));
    }

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
