//! Shared Kotlin collection contracts. Wrappers retain the real backing map;
//! callbacks run as guest bytecode and never hide VM limits or guest failures.
use dexvm::vm::object::{ArrayData, IterKind, Native};
use dexvm::vm::{error::JvmError, NatErr, NativeEntry, Vm};
use dexvm::JValue;
type R = Result<JValue, NatErr>;
const DEQUE: &str = "Lkotlin/collections/ArrayDeque;";
const MAP: &str = "Lkotlin/collections/MapWithDefaultImpl;";
const MUTABLE_MAP: &str = "Lkotlin/collections/MutableMapWithDefaultImpl;";
const LIMIT: usize = 100_000;

pub(super) fn charge(vm: &mut Vm, count: usize) -> Result<(), NatErr> {
    super::browser_compat::check_deadline(vm)?;
    if count > LIMIT || vm.budget <= count as i64 {
        return Err(NatErr::Fatal(JvmError::BudgetExceeded));
    }
    vm.budget -= count as i64 + 1;
    Ok(())
}
pub(super) fn invoke(vm: &mut Vm, value: JValue, name: &str, sig: &str, args: Vec<JValue>) -> R {
    charge(vm, 1)?;
    if value.is_null_ref() {
        return Err(NatErr::Throw(vm.err_npe()));
    }
    if vm.recursion_depth >= vm.depth_limit {
        return Err(NatErr::Fatal(JvmError::StackOverflow));
    }
    vm.recursion_depth += 1;
    let result = vm.invoke_virtual_args(value, name, sig, args);
    vm.recursion_depth -= 1;
    result.map_err(|e| match e {
        JvmError::Uncaught(id) => NatErr::Throw(id),
        e => NatErr::Fatal(e),
    })
}
pub(super) fn equals(vm: &mut Vm, left: JValue, right: JValue) -> Result<bool, NatErr> {
    if left.is_null_ref() || right.is_null_ref() {
        return Ok(left.is_null_ref() && right.is_null_ref());
    }
    if left == right {
        return Ok(true);
    }
    Ok(invoke(vm, left, "equals", "(Ljava/lang/Object;)Z", vec![right])?.as_int() != 0)
}
fn missing(vm: &mut Vm) -> NatErr {
    NatErr::Throw(vm.throwable_of("Ljava/util/NoSuchElementException;", "Collection is empty"))
}
fn array(vm: &mut Vm, value: JValue) -> Result<Vec<JValue>, NatErr> {
    if value.is_null_ref() {
        return Err(NatErr::Throw(vm.err_npe()));
    }
    let Some(Native::Array(ArrayData::Obj(values))) =
        vm.arena.objects[value.as_obj() as usize].native.as_ref()
    else {
        return Err(NatErr::Throw(vm.err_iae("Expected a reference array")));
    };
    let count = values.len();
    charge(vm, count)?;
    let Some(Native::Array(ArrayData::Obj(values))) = vm.payload_of(value) else {
        unreachable!()
    };
    Ok(values)
}
fn array_first(vm: &mut Vm, args: &[JValue]) -> R {
    array(vm, args[0])?
        .first()
        .copied()
        .ok_or_else(|| missing(vm))
}
fn array_last(vm: &mut Vm, args: &[JValue]) -> R {
    array(vm, args[0])?
        .last()
        .copied()
        .ok_or_else(|| missing(vm))
}
fn array_index(vm: &mut Vm, args: &[JValue]) -> R {
    for (i, value) in array(vm, args[0])?.into_iter().enumerate() {
        // Kotlin indexOf compares the search value to each array element.
        if equals(vm, args[1], value)? {
            return Ok(JValue::Int(i as i32));
        }
    }
    Ok(JValue::Int(-1))
}

fn wrapper_fields(vm: &Vm, value: JValue) -> Option<(JValue, JValue)> {
    let JValue::Obj(id) = value else {
        return None;
    };
    let object = &vm.arena.objects[id as usize];
    let desc = vm.str_of(vm.classes[object.class as usize].descriptor);
    if [MAP, MUTABLE_MAP].contains(&desc) && object.fields.len() == 2 {
        Some((object.fields[0], object.fields[1]))
    } else {
        None
    }
}
pub(super) fn is_default_map(vm: &Vm, value: JValue) -> bool {
    wrapper_fields(vm, value).is_some()
}
fn with_default(vm: &mut Vm, args: &[JValue], mutable: bool) -> R {
    charge(vm, 1)?;
    if args[0].is_null_ref() || args[1].is_null_ref() {
        return Err(NatErr::Throw(vm.err_npe()));
    }
    let backing = wrapper_fields(vm, args[0]).map_or(args[0], |p| p.0);
    let result = vm
        .alloc_native(if mutable { MUTABLE_MAP } else { MAP }, Native::Opaque)
        .map_err(NatErr::Fatal)?;
    vm.arena.objects[result.as_obj() as usize].fields = vec![backing, args[1]];
    Ok(result)
}
fn readonly_default(vm: &mut Vm, args: &[JValue]) -> R {
    with_default(vm, args, false)
}
fn mutable_default(vm: &mut Vm, args: &[JValue]) -> R {
    with_default(vm, args, true)
}
fn backing(vm: &mut Vm, args: &[JValue]) -> R {
    wrapper_fields(vm, args[0])
        .map(|p| p.0)
        .ok_or_else(|| NatErr::Throw(vm.err_iae("Invalid default map")))
}
fn implicit_default(vm: &mut Vm, args: &[JValue]) -> R {
    let (map, default) = wrapper_fields(vm, args[0])
        .ok_or_else(|| NatErr::Throw(vm.err_iae("Invalid default map")))?;
    let value = invoke(
        vm,
        map,
        "get",
        "(Ljava/lang/Object;)Ljava/lang/Object;",
        vec![args[1]],
    )?;
    if !value.is_null_ref()
        || invoke(
            vm,
            map,
            "containsKey",
            "(Ljava/lang/Object;)Z",
            vec![args[1]],
        )?
        .as_int()
            != 0
    {
        return Ok(value);
    }
    invoke(
        vm,
        default,
        "invoke",
        "(Ljava/lang/Object;)Ljava/lang/Object;",
        vec![args[1]],
    )
}
macro_rules! delegate {
    ($f:ident,$name:literal,$sig:literal) => {
        fn $f(vm: &mut Vm, args: &[JValue]) -> R {
            let map = backing(vm, args)?;
            invoke(vm, map, $name, $sig, args[1..].to_vec())
        }
    };
}
delegate!(map_get, "get", "(Ljava/lang/Object;)Ljava/lang/Object;");
delegate!(map_contains, "containsKey", "(Ljava/lang/Object;)Z");
delegate!(map_contains_value, "containsValue", "(Ljava/lang/Object;)Z");
delegate!(map_size, "size", "()I");
delegate!(map_empty, "isEmpty", "()Z");
delegate!(map_keys, "keySet", "()Ljava/util/Set;");
delegate!(map_values, "values", "()Ljava/util/Collection;");
delegate!(map_entries, "entrySet", "()Ljava/util/Set;");
delegate!(map_equals, "equals", "(Ljava/lang/Object;)Z");
delegate!(map_hash, "hashCode", "()I");
delegate!(map_string, "toString", "()Ljava/lang/String;");
delegate!(
    map_or_default,
    "getOrDefault",
    "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;"
);
delegate!(
    map_put,
    "put",
    "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;"
);
delegate!(map_put_all, "putAll", "(Ljava/util/Map;)V");
delegate!(
    map_remove,
    "remove",
    "(Ljava/lang/Object;)Ljava/lang/Object;"
);
delegate!(map_clear, "clear", "()V");
fn map_to_list(vm: &mut Vm, args: &[JValue]) -> R {
    let entries = invoke(vm, args[0], "entrySet", "()Ljava/util/Set;", vec![])?;
    let iterator = invoke(vm, entries, "iterator", "()Ljava/util/Iterator;", vec![])?;
    let mut pairs = vec![];
    while invoke(vm, iterator, "hasNext", "()Z", vec![])?.as_int() != 0 {
        if pairs.len() >= LIMIT {
            return Err(NatErr::Fatal(JvmError::BudgetExceeded));
        }
        let entry = invoke(vm, iterator, "next", "()Ljava/lang/Object;", vec![])?;
        let key = invoke(vm, entry, "getKey", "()Ljava/lang/Object;", vec![])?;
        let value = invoke(vm, entry, "getValue", "()Ljava/lang/Object;", vec![])?;
        pairs.push(
            vm.alloc_native("Lkotlin/Pair;", Native::Pair(key, value))
                .map_err(NatErr::Fatal)?,
        );
    }
    vm.alloc_native("Ljava/util/ArrayList;", Native::List(pairs))
        .map_err(NatErr::Fatal)
}
fn readonly_mutation(vm: &mut Vm, _args: &[JValue]) -> R {
    Err(NatErr::Throw(vm.throwable_of(
        "Ljava/lang/UnsupportedOperationException;",
        "Read-only map",
    )))
}

fn deque_values(vm: &mut Vm, value: JValue) -> Result<Vec<JValue>, NatErr> {
    if value.is_null_ref() {
        return Err(NatErr::Throw(vm.err_npe()));
    }
    let count = match vm.arena.objects[value.as_obj() as usize].native.as_ref() {
        Some(Native::List(v)) => v.len(),
        _ => return Err(NatErr::Throw(vm.err_iae("Expected a Kotlin deque"))),
    };
    charge(vm, count)?;
    let Some(Native::List(v)) = vm.payload_of(value) else {
        unreachable!()
    };
    Ok(v)
}
fn collect(vm: &mut Vm, value: JValue) -> Result<Vec<JValue>, NatErr> {
    let iterator = invoke(vm, value, "iterator", "()Ljava/util/Iterator;", vec![])?;
    let mut values = vec![];
    while invoke(vm, iterator, "hasNext", "()Z", vec![])?.as_int() != 0 {
        if values.len() >= LIMIT {
            return Err(NatErr::Fatal(JvmError::BudgetExceeded));
        }
        charge(vm, 1)?;
        values.push(invoke(
            vm,
            iterator,
            "next",
            "()Ljava/lang/Object;",
            vec![],
        )?);
    }
    Ok(values)
}
fn list_equals(vm: &mut Vm, args: &[JValue]) -> R {
    if args[0] == args[1] {
        return Ok(JValue::Int(1));
    }
    if args[1].is_null_ref() {
        return Ok(JValue::Int(0));
    }
    let target = vm
        .ensure_class_by_desc("Ljava/util/List;")
        .map_err(NatErr::Fatal)?;
    let JValue::Obj(right) = args[1] else {
        return Ok(JValue::Int(0));
    };
    if !vm
        .is_assignable(vm.arena.objects[right as usize].class, target)
        .map_err(NatErr::Fatal)?
    {
        return Ok(JValue::Int(0));
    }
    let left = invoke(vm, args[0], "iterator", "()Ljava/util/Iterator;", vec![])?;
    let right = invoke(vm, args[1], "iterator", "()Ljava/util/Iterator;", vec![])?;
    while invoke(vm, left, "hasNext", "()Z", vec![])?.as_int() != 0 {
        if invoke(vm, right, "hasNext", "()Z", vec![])?.as_int() == 0 {
            return Ok(JValue::Int(0));
        }
        let a = invoke(vm, left, "next", "()Ljava/lang/Object;", vec![])?;
        let b = invoke(vm, right, "next", "()Ljava/lang/Object;", vec![])?;
        if !equals(vm, a, b)? {
            return Ok(JValue::Int(0));
        }
    }
    Ok(JValue::Int(i32::from(
        invoke(vm, right, "hasNext", "()Z", vec![])?.as_int() == 0,
    )))
}
fn list_hash(vm: &mut Vm, args: &[JValue]) -> R {
    let it = invoke(vm, args[0], "iterator", "()Ljava/util/Iterator;", vec![])?;
    let mut hash = 1_i32;
    while invoke(vm, it, "hasNext", "()Z", vec![])?.as_int() != 0 {
        let value = invoke(vm, it, "next", "()Ljava/lang/Object;", vec![])?;
        let h = if value.is_null_ref() {
            0
        } else {
            invoke(vm, value, "hashCode", "()I", vec![])?.as_int()
        };
        hash = hash.wrapping_mul(31).wrapping_add(h);
    }
    Ok(JValue::Int(hash))
}
fn store(vm: &mut Vm, value: JValue, values: Vec<JValue>) -> R {
    vm.arena.objects[value.as_obj() as usize].native = Some(Native::List(values));
    Ok(JValue::Null)
}
fn deque_init(vm: &mut Vm, args: &[JValue]) -> R {
    charge(vm, 1)?;
    store(vm, args[0], vec![])
}
fn deque_capacity(vm: &mut Vm, args: &[JValue]) -> R {
    if args[1].as_int() < 0 {
        return Err(NatErr::Throw(vm.err_iae("Negative initial capacity")));
    }
    charge(vm, args[1].as_int() as usize)?;
    store(vm, args[0], vec![])
}
fn deque_collection(vm: &mut Vm, args: &[JValue]) -> R {
    let values = collect(vm, args[1])?;
    store(vm, args[0], values)
}
fn deque_size(vm: &mut Vm, args: &[JValue]) -> R {
    Ok(JValue::Int(deque_values(vm, args[0])?.len() as i32))
}
fn deque_empty(vm: &mut Vm, args: &[JValue]) -> R {
    Ok(JValue::Int(i32::from(
        deque_values(vm, args[0])?.is_empty(),
    )))
}
fn deque_get(vm: &mut Vm, args: &[JValue]) -> R {
    let values = deque_values(vm, args[0])?;
    values
        .get(args[1].as_int() as usize)
        .copied()
        .ok_or_else(|| {
            NatErr::Throw(vm.throwable_of(
                "Ljava/lang/IndexOutOfBoundsException;",
                "Deque index outside list",
            ))
        })
}
fn deque_set(vm: &mut Vm, args: &[JValue]) -> R {
    let mut values = deque_values(vm, args[0])?;
    let slot = values.get_mut(args[1].as_int() as usize).ok_or_else(|| {
        NatErr::Throw(vm.throwable_of(
            "Ljava/lang/IndexOutOfBoundsException;",
            "Deque index outside list",
        ))
    })?;
    let old = *slot;
    *slot = args[2];
    store(vm, args[0], values)?;
    Ok(old)
}
fn insert(vm: &mut Vm, args: &[JValue], index: usize, items: Vec<JValue>) -> R {
    let mut values = deque_values(vm, args[0])?;
    if index > values.len() {
        return Err(NatErr::Throw(vm.throwable_of(
            "Ljava/lang/IndexOutOfBoundsException;",
            "Deque insertion outside list",
        )));
    }
    charge(vm, values.len().saturating_add(items.len()))?;
    values.splice(index..index, items);
    store(vm, args[0], values)
}
fn deque_add(vm: &mut Vm, args: &[JValue]) -> R {
    let n = deque_values(vm, args[0])?.len();
    insert(vm, args, n, vec![args[1]])?;
    Ok(JValue::Int(1))
}
fn deque_add_last(vm: &mut Vm, args: &[JValue]) -> R {
    deque_add(vm, args)?;
    Ok(JValue::Null)
}
fn deque_add_first(vm: &mut Vm, args: &[JValue]) -> R {
    insert(vm, args, 0, vec![args[1]])
}
fn deque_add_at(vm: &mut Vm, args: &[JValue]) -> R {
    insert(vm, args, args[1].as_int() as usize, vec![args[2]])
}
fn deque_add_all(vm: &mut Vm, args: &[JValue]) -> R {
    let items = collect(vm, args[1])?;
    let changed = !items.is_empty();
    let n = deque_values(vm, args[0])?.len();
    insert(vm, args, n, items)?;
    Ok(JValue::Int(i32::from(changed)))
}
fn deque_add_all_at(vm: &mut Vm, args: &[JValue]) -> R {
    let items = collect(vm, args[2])?;
    let changed = !items.is_empty();
    insert(vm, args, args[1].as_int() as usize, items)?;
    Ok(JValue::Int(i32::from(changed)))
}
fn deque_first_null(vm: &mut Vm, args: &[JValue]) -> R {
    Ok(deque_values(vm, args[0])?
        .first()
        .copied()
        .unwrap_or(JValue::Null))
}
fn deque_last_null(vm: &mut Vm, args: &[JValue]) -> R {
    Ok(deque_values(vm, args[0])?
        .last()
        .copied()
        .unwrap_or(JValue::Null))
}
fn deque_first(vm: &mut Vm, args: &[JValue]) -> R {
    deque_values(vm, args[0])?
        .first()
        .copied()
        .ok_or_else(|| missing(vm))
}
fn deque_last(vm: &mut Vm, args: &[JValue]) -> R {
    deque_values(vm, args[0])?
        .last()
        .copied()
        .ok_or_else(|| missing(vm))
}
fn remove_at(vm: &mut Vm, value: JValue, index: usize, empty_error: bool) -> R {
    let mut values = deque_values(vm, value)?;
    if index >= values.len() {
        return Err(if empty_error {
            missing(vm)
        } else {
            NatErr::Throw(vm.throwable_of(
                "Ljava/lang/IndexOutOfBoundsException;",
                "Deque removal outside list",
            ))
        });
    }
    let old = values.remove(index);
    store(vm, value, values)?;
    Ok(old)
}
fn deque_remove_first(vm: &mut Vm, args: &[JValue]) -> R {
    remove_at(vm, args[0], 0, true)
}
fn deque_remove_last(vm: &mut Vm, args: &[JValue]) -> R {
    let n = deque_values(vm, args[0])?.len();
    remove_at(vm, args[0], n.wrapping_sub(1), true)
}
fn deque_remove_first_null(vm: &mut Vm, args: &[JValue]) -> R {
    if deque_values(vm, args[0])?.is_empty() {
        Ok(JValue::Null)
    } else {
        deque_remove_first(vm, args)
    }
}
fn deque_remove_last_null(vm: &mut Vm, args: &[JValue]) -> R {
    if deque_values(vm, args[0])?.is_empty() {
        Ok(JValue::Null)
    } else {
        deque_remove_last(vm, args)
    }
}
fn deque_remove_at(vm: &mut Vm, args: &[JValue]) -> R {
    remove_at(vm, args[0], args[1].as_int() as usize, false)
}
fn deque_clear(vm: &mut Vm, args: &[JValue]) -> R {
    charge(vm, 1)?;
    store(vm, args[0], vec![])
}

fn deque_iterator(vm: &mut Vm, args: &[JValue]) -> R {
    charge(vm, 1)?;
    vm.alloc_native(
        "Ljava/util/Iterator;",
        Native::Iter(IterKind::List {
            list: args[0].as_obj(),
            idx: 0,
        }),
    )
    .map_err(NatErr::Fatal)
}
pub(super) fn install(vm: &mut Vm) -> Result<(), JvmError> {
    vm.register_native(NativeEntry {
        class: "Lkotlin/collections/MapsKt;",
        name: "toList",
        sig: "(Ljava/util/Map;)Ljava/util/List;",
        instance: false,
        f: map_to_list,
    })?;
    vm.register_native(NativeEntry {
        class: DEQUE,
        name: "iterator",
        sig: "()Ljava/util/Iterator;",
        instance: true,
        f: deque_iterator,
    })?;
    vm.register_native(NativeEntry {
        class: "Ljava/util/AbstractList;",
        name: "equals",
        sig: "(Ljava/lang/Object;)Z",
        instance: true,
        f: list_equals,
    })?;
    vm.register_native(NativeEntry {
        class: "Ljava/util/AbstractList;",
        name: "hashCode",
        sig: "()I",
        instance: true,
        f: list_hash,
    })?;
    for (name, sig, f) in [
        (
            "first",
            "([Ljava/lang/Object;)Ljava/lang/Object;",
            array_first as dexvm::vm::NativeFn,
        ),
        (
            "last",
            "([Ljava/lang/Object;)Ljava/lang/Object;",
            array_last,
        ),
        (
            "indexOf",
            "([Ljava/lang/Object;Ljava/lang/Object;)I",
            array_index,
        ),
    ] {
        vm.register_native(NativeEntry {
            class: "Lkotlin/collections/ArraysKt;",
            name,
            sig,
            instance: false,
            f,
        })?;
    }
    for (name, f) in [
        ("withDefault", readonly_default as dexvm::vm::NativeFn),
        ("withDefaultMutable", mutable_default),
    ] {
        vm.register_native(NativeEntry {
            class: "Lkotlin/collections/MapsKt;",
            name,
            sig: "(Ljava/util/Map;Lkotlin/jvm/functions/Function1;)Ljava/util/Map;",
            instance: false,
            f,
        })?;
    }
    let interface = super::kotlin_type_compat::marker(vm, "Lkotlin/collections/MapWithDefault;");
    let map = vm.ensure_class_by_desc("Ljava/util/Map;")?;
    vm.classes[interface as usize].interfaces = vec![map];
    for class in [MAP, MUTABLE_MAP] {
        for (name, sig, f) in [
            (
                "getMap",
                "()Ljava/util/Map;",
                backing as dexvm::vm::NativeFn,
            ),
            (
                "getOrImplicitDefault",
                "(Ljava/lang/Object;)Ljava/lang/Object;",
                implicit_default,
            ),
            ("get", "(Ljava/lang/Object;)Ljava/lang/Object;", map_get),
            ("containsKey", "(Ljava/lang/Object;)Z", map_contains),
            ("containsValue", "(Ljava/lang/Object;)Z", map_contains_value),
            ("size", "()I", map_size),
            ("isEmpty", "()Z", map_empty),
            ("keySet", "()Ljava/util/Set;", map_keys),
            ("values", "()Ljava/util/Collection;", map_values),
            ("entrySet", "()Ljava/util/Set;", map_entries),
            ("equals", "(Ljava/lang/Object;)Z", map_equals),
            ("hashCode", "()I", map_hash),
            ("toString", "()Ljava/lang/String;", map_string),
            (
                "getOrDefault",
                "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;",
                map_or_default,
            ),
        ] {
            vm.register_native(NativeEntry {
                class,
                name,
                sig,
                instance: true,
                f,
            })?;
        }
        for (name, sig, f) in [
            (
                "put",
                "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;",
                map_put as dexvm::vm::NativeFn,
            ),
            ("putAll", "(Ljava/util/Map;)V", map_put_all),
            (
                "remove",
                "(Ljava/lang/Object;)Ljava/lang/Object;",
                map_remove,
            ),
            ("clear", "()V", map_clear),
        ] {
            vm.register_native(NativeEntry {
                class,
                name,
                sig,
                instance: true,
                f: if class == MAP { readonly_mutation } else { f },
            })?;
        }
        let id = vm.ensure_class_by_desc(class)?;
        vm.classes[id as usize].interfaces.push(interface);
        let marker = super::kotlin_type_compat::marker(
            vm,
            if class == MAP {
                "Lkotlin/jvm/internal/markers/KMappedMarker;"
            } else {
                "Lkotlin/jvm/internal/markers/KMutableMap;"
            },
        );
        vm.classes[id as usize].interfaces.push(marker);
    }
    for (name, sig, f) in [
        ("<init>", "()V", deque_init as dexvm::vm::NativeFn),
        ("<init>", "(I)V", deque_capacity),
        ("<init>", "(Ljava/util/Collection;)V", deque_collection),
        ("size", "()I", deque_size),
        ("getSize", "()I", deque_size),
        ("isEmpty", "()Z", deque_empty),
        ("get", "(I)Ljava/lang/Object;", deque_get),
        ("set", "(ILjava/lang/Object;)Ljava/lang/Object;", deque_set),
        ("add", "(Ljava/lang/Object;)Z", deque_add),
        ("add", "(ILjava/lang/Object;)V", deque_add_at),
        ("addAll", "(Ljava/util/Collection;)Z", deque_add_all),
        ("addAll", "(ILjava/util/Collection;)Z", deque_add_all_at),
        ("addLast", "(Ljava/lang/Object;)V", deque_add_last),
        ("addFirst", "(Ljava/lang/Object;)V", deque_add_first),
        ("first", "()Ljava/lang/Object;", deque_first),
        ("last", "()Ljava/lang/Object;", deque_last),
        ("firstOrNull", "()Ljava/lang/Object;", deque_first_null),
        ("lastOrNull", "()Ljava/lang/Object;", deque_last_null),
        ("removeFirst", "()Ljava/lang/Object;", deque_remove_first),
        ("removeLast", "()Ljava/lang/Object;", deque_remove_last),
        (
            "removeFirstOrNull",
            "()Ljava/lang/Object;",
            deque_remove_first_null,
        ),
        (
            "removeLastOrNull",
            "()Ljava/lang/Object;",
            deque_remove_last_null,
        ),
        ("removeAt", "(I)Ljava/lang/Object;", deque_remove_at),
        ("remove", "(I)Ljava/lang/Object;", deque_remove_at),
        ("clear", "()V", deque_clear),
    ] {
        vm.register_native(NativeEntry {
            class: DEQUE,
            name,
            sig,
            instance: true,
            f,
        })?;
    }
    // Kotlin's deque is a MutableList, not a Java ArrayDeque/ArrayList.
    let parent = vm.ensure_class_by_desc("Ljava/util/AbstractList;")?;
    let descriptor = vm.intern("Lkotlin/collections/AbstractMutableList;");
    let parent = if let Some(id) = vm.class_by_desc.get(&descriptor) {
        *id
    } else {
        let id = vm.classes.len() as u32;
        vm.classes.push(dexvm::vm::class::Class {
            id,
            descriptor,
            superclass: Some(parent),
            access_flags: dexvm::vm::class::ACC_PUBLIC | dexvm::vm::class::ACC_ABSTRACT,
            is_abstract: true,
            ..Default::default()
        });
        vm.class_by_desc.insert(descriptor, id);
        id
    };
    let id = vm.ensure_class_by_desc(DEQUE)?;
    vm.classes[id as usize].superclass = Some(parent);
    let marker =
        super::kotlin_type_compat::marker(vm, "Lkotlin/jvm/internal/markers/KMutableList;");
    vm.classes[id as usize].interfaces.push(marker);
    // FunctionAdapter has a real abstract method, used by compiler SAM wrappers.
    super::kotlin_type_compat::marker(vm, "Lkotlin/jvm/internal/FunctionAdapter;");
    vm.register_native(NativeEntry {
        class: "Lkotlin/jvm/internal/FunctionAdapter;",
        name: "getFunctionDelegate",
        sig: "()Lkotlin/Function;",
        instance: true,
        f: super::abstract_function,
    })?;
    Ok(())
}
