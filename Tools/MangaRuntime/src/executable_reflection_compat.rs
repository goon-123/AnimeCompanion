//! Actual guest constructors and executable metadata. Never fabricate a DTO or
//! return an empty method list when lookup or resource limits fail.
use super::method_reflection_compat as methods;
use dexvm::{
    vm::{
        error::JvmError,
        object::{ArrayData, ClassOrPrim, Native},
        NatErr, NativeEntry, Vm,
    },
    JValue,
};
use std::collections::HashSet;
type R = Result<JValue, NatErr>;
const METHOD: &str = "Ljava/lang/reflect/Method;";
const CTOR: &str = "Ljava/lang/reflect/Constructor;";
pub(super) fn member(vm: &mut Vm, class: u32, slot: u32, constructor: bool) -> R {
    let value = vm
        .alloc_native(if constructor { CTOR } else { METHOD }, Native::Opaque)
        .map_err(NatErr::Fatal)?;
    vm.arena.objects[value.as_obj() as usize].fields = vec![
        JValue::Int(class as i32),
        JValue::Int(slot as i32),
        JValue::Int(0),
    ];
    Ok(value)
}
fn members(vm: &mut Vm, owner: JValue, inherited: bool, constructors: bool) -> R {
    if matches!(
        vm.payload_of(owner),
        Some(Native::ClassObj(ClassOrPrim::Primitive(_)))
    ) {
        return vm
            .alloc_native(
                if constructors {
                    "[Ljava/lang/reflect/Constructor;"
                } else {
                    "[Ljava/lang/reflect/Method;"
                },
                Native::Array(ArrayData::Obj(vec![])),
            )
            .map_err(NatErr::Fatal);
    }
    let owner = methods::class_id(vm, owner)?;
    let mut pending = vec![owner];
    let mut seen = HashSet::new();
    let mut signatures = HashSet::new();
    let mut found = Vec::new();
    while let Some(class) = pending.pop() {
        if !seen.insert(class) {
            continue;
        }
        if seen.len() > 512 {
            return Err(NatErr::Fatal(JvmError::BudgetExceeded));
        }
        methods::charge(vm, vm.classes[class as usize].methods.len() + 1)?;
        let mut slots: Vec<_> = vm.classes[class as usize]
            .dispatch
            .values()
            .copied()
            .collect();
        slots.sort_unstable();
        for slot in slots {
            let m = &vm.classes[class as usize].methods[slot as usize];
            let name = vm.str_of(m.name);
            if constructors && name != "<init>"
                || !constructors && name.starts_with('<')
                || m.code.is_none()
                    && m.native_key.is_some()
                    && (name.starts_with("__") || name == "unused")
            {
                continue;
            }
            if inherited && m.access_flags & 1 == 0 {
                continue;
            }
            if inherited
                && class != owner
                && vm.classes[class as usize].is_interface
                && m.static_method
            {
                continue;
            }
            if !signatures.insert((m.name, m.sig)) {
                continue;
            }
            found.push((class, slot));
            if found.len() > 10_000 {
                return Err(NatErr::Fatal(JvmError::BudgetExceeded));
            }
        }
        if inherited && !constructors {
            pending.extend(vm.classes[class as usize].interfaces.iter().rev().copied());
            pending.extend(vm.classes[class as usize].superclass);
        }
    }
    let objects = found
        .into_iter()
        .map(|(class, slot)| member(vm, class, slot, constructors))
        .collect::<Result<Vec<_>, _>>()?;
    vm.alloc_native(
        if constructors {
            "[Ljava/lang/reflect/Constructor;"
        } else {
            "[Ljava/lang/reflect/Method;"
        },
        Native::Array(ArrayData::Obj(objects)),
    )
    .map_err(NatErr::Fatal)
}
fn declared_methods(vm: &mut Vm, args: &[JValue]) -> R {
    members(vm, args[0], false, false)
}
fn public_methods(vm: &mut Vm, args: &[JValue]) -> R {
    members(vm, args[0], true, false)
}
fn declared_constructors(vm: &mut Vm, args: &[JValue]) -> R {
    members(vm, args[0], false, true)
}
fn public_constructors(vm: &mut Vm, args: &[JValue]) -> R {
    members(vm, args[0], true, true)
}
fn find_constructor(vm: &mut Vm, args: &[JValue], public: bool) -> R {
    if matches!(
        vm.payload_of(args[0]),
        Some(Native::ClassObj(ClassOrPrim::Primitive(_)))
    ) {
        return Err(NatErr::Throw(vm.throwable_of(
            "Ljava/lang/NoSuchMethodException;",
            "Primitive classes have no constructors",
        )));
    }
    let owner = methods::class_id(vm, args[0])?;
    let types = methods::array(vm, args[1])?
        .into_iter()
        .map(|v| methods::descriptor(vm, v))
        .collect::<Result<Vec<_>, _>>()?;
    let sig = format!("({})V", types.join(""));
    methods::charge(vm, vm.classes[owner as usize].methods.len() + 1)?;
    let key = (vm.intern("<init>"), vm.intern(&sig));
    if let Some(&slot) = vm.classes[owner as usize].dispatch.get(&key) {
        if !public || vm.classes[owner as usize].methods[slot as usize].access_flags & 1 != 0 {
            return member(vm, owner, slot, true);
        }
    }
    Err(NatErr::Throw(vm.throwable_of(
        "Ljava/lang/NoSuchMethodException;",
        "Constructor is not declared",
    )))
}
fn declared_constructor(vm: &mut Vm, args: &[JValue]) -> R {
    find_constructor(vm, args, false)
}
fn public_constructor(vm: &mut Vm, args: &[JValue]) -> R {
    find_constructor(vm, args, true)
}
pub(super) fn wrap_guest(vm: &mut Vm, result: Result<JValue, JvmError>) -> R {
    match result {
        Ok(value) => Ok(value),
        Err(JvmError::Uncaught(cause)) => {
            let error = vm
                .alloc_native(
                    "Ljava/lang/reflect/InvocationTargetException;",
                    Native::Throwable {
                        message: None,
                        cause: JValue::Obj(cause),
                    },
                )
                .map_err(NatErr::Fatal)?;
            Err(NatErr::Throw(error.as_obj()))
        }
        Err(error) => Err(NatErr::Fatal(error)),
    }
}
fn new_instance(vm: &mut Vm, args: &[JValue]) -> R {
    let (m, accessible) = methods::method(vm, args[0])?;
    if vm.str_of(m.name) != "<init>" {
        return Err(NatErr::Throw(vm.err_iae("Expected a constructor")));
    }
    if !accessible && m.access_flags & 1 == 0 {
        return Err(NatErr::Throw(vm.throwable_of(
            "Ljava/lang/IllegalAccessException;",
            "Constructor is not public",
        )));
    }
    let owner = &vm.classes[m.class as usize];
    if owner.is_abstract || owner.is_interface || owner.array_elem.is_some() {
        return Err(NatErr::Throw(vm.throwable_of(
            "Ljava/lang/InstantiationException;",
            "Class cannot be instantiated",
        )));
    }
    if owner.access_flags & 0x4000 != 0 {
        return Err(NatErr::Throw(
            vm.err_iae("Cannot create enum instances reflectively"),
        ));
    }
    let supplied = methods::array(vm, args[1])?;
    if supplied.len() != m.args.len() {
        return Err(NatErr::Throw(
            vm.err_iae("Wrong constructor argument count"),
        ));
    }
    let values = supplied
        .into_iter()
        .zip(&m.args)
        .map(|(v, ty)| {
            let ty = vm.str_of(*ty).to_owned();
            methods::unbox(vm, v, &ty)
        })
        .collect::<Result<Vec<_>, _>>()?;
    vm.ensure_class_initialized(m.class).map_err(|e| match e {
        JvmError::Uncaught(id) => NatErr::Throw(id),
        e => NatErr::Fatal(e),
    })?;
    let instance = JValue::Obj(vm.alloc_instance(m.class).map_err(NatErr::Fatal)?);
    let result = methods::call(vm, &m, instance, values);
    wrap_guest(vm, result)?;
    Ok(instance)
}
fn class_new_instance(vm: &mut Vm, args: &[JValue]) -> R {
    let constructor =
        declared_constructor(vm, &[args[0], JValue::Null]).map_err(|error| match error {
            NatErr::Throw(_) => NatErr::Throw(vm.throwable_of(
                "Ljava/lang/InstantiationException;",
                "No no-argument constructor",
            )),
            error => error,
        })?;
    match new_instance(vm, &[constructor, JValue::Null]) {
        Err(NatErr::Throw(id)) => match vm.payload_of(JValue::Obj(id)) {
            Some(Native::Throwable { cause, .. })
                if !cause.is_null_ref()
                    && vm.class_desc_str(vm.arena.objects[id as usize].class)
                        == "java.lang.reflect.InvocationTargetException" =>
            {
                Err(NatErr::Throw(cause.as_obj()))
            }
            _ => Err(NatErr::Throw(id)),
        },
        result => result,
    }
}
fn set_accessible(vm: &mut Vm, args: &[JValue]) -> R {
    methods::method(vm, args[0])?;
    vm.arena.objects[args[0].as_obj() as usize].fields[2] = args[1];
    Ok(JValue::Null)
}
fn is_accessible(vm: &mut Vm, args: &[JValue]) -> R {
    Ok(JValue::Int(i32::from(methods::method(vm, args[0])?.1)))
}
fn constructor_name(vm: &mut Vm, args: &[JValue]) -> R {
    let (m, _) = methods::method(vm, args[0])?;
    Ok(vm.alloc_string(&vm.class_desc_str(m.class)))
}
fn declaring_class(vm: &mut Vm, args: &[JValue]) -> R {
    let (m, _) = methods::method(vm, args[0])?;
    vm.class_obj(m.class).map_err(NatErr::Fatal)
}
fn modifiers(vm: &mut Vm, args: &[JValue]) -> R {
    let flags = methods::method(vm, args[0])?.0.access_flags;
    Ok(JValue::Int(
        ((flags & 0xffff) | if flags & 0x20000 != 0 { 0x20 } else { 0 }) as i32,
    ))
}
fn parameter_count(vm: &mut Vm, args: &[JValue]) -> R {
    Ok(JValue::Int(
        methods::method(vm, args[0])?.0.args.len() as i32
    ))
}
fn parameter_types(vm: &mut Vm, args: &[JValue]) -> R {
    let (m, _) = methods::method(vm, args[0])?;
    let values = m
        .args
        .iter()
        .map(|id| {
            let desc = vm.str_of(*id).to_owned();
            methods::class_object(vm, &desc)
        })
        .collect::<Result<Vec<_>, _>>()?;
    vm.alloc_native("[Ljava/lang/Class;", Native::Array(ArrayData::Obj(values)))
        .map_err(NatErr::Fatal)
}
fn exception_types(vm: &mut Vm, args: &[JValue]) -> R {
    let (m, _) = methods::method(vm, args[0])?;
    let types = super::reflection_annotations::throws(vm, &m)?;
    let values = types
        .iter()
        .map(|desc| methods::class_object(vm, desc))
        .collect::<Result<Vec<_>, _>>()?;
    vm.alloc_native("[Ljava/lang/Class;", Native::Array(ArrayData::Obj(values)))
        .map_err(NatErr::Fatal)
}
fn flag(vm: &mut Vm, args: &[JValue], mask: u32) -> R {
    Ok(JValue::Int(i32::from(
        methods::method(vm, args[0])?.0.access_flags & mask != 0,
    )))
}
fn synthetic(vm: &mut Vm, args: &[JValue]) -> R {
    flag(vm, args, 0x1000)
}
fn bridge(vm: &mut Vm, args: &[JValue]) -> R {
    flag(vm, args, 0x40)
}
fn varargs(vm: &mut Vm, args: &[JValue]) -> R {
    flag(vm, args, 0x80)
}
fn equal(vm: &mut Vm, args: &[JValue]) -> R {
    let (m, _) = methods::method(vm, args[0])?;
    let same_class = vm.object_class(args[0]) == vm.object_class(args[1]);
    let other = if same_class {
        Some(methods::method(vm, args[1])?.0)
    } else {
        None
    };
    Ok(JValue::Int(i32::from(other.is_some_and(|v| {
        v.class == m.class && v.name == m.name && v.sig == m.sig
    }))))
}
fn hash_code(vm: &mut Vm, args: &[JValue]) -> R {
    let (m, _) = methods::method(vm, args[0])?;
    let hash = |value: &str| {
        value
            .encode_utf16()
            .fold(0i32, |h, c| h.wrapping_mul(31).wrapping_add(i32::from(c)))
    };
    let owner = hash(&vm.class_desc_str(m.class));
    Ok(JValue::Int(if vm.str_of(m.name) == "<init>" {
        owner
    } else {
        owner ^ hash(vm.str_of(m.name))
    }))
}
pub(super) fn install(vm: &mut Vm) -> Result<(), JvmError> {
    vm.register_native(NativeEntry {
        class: "Ljava/lang/reflect/Executable;",
        name: "__marker",
        sig: "()V",
        instance: true,
        f: super::abstract_function,
    })?;
    let executable = vm.ensure_class_by_desc("Ljava/lang/reflect/Executable;")?;
    let accessible = vm.ensure_class_by_desc("Ljava/lang/reflect/AccessibleObject;")?;
    vm.classes[executable as usize].superclass = Some(accessible);
    vm.classes[executable as usize].is_abstract = true;
    for class in [METHOD, CTOR] {
        vm.register_native(NativeEntry {
            class,
            name: "__marker",
            sig: "()V",
            instance: true,
            f: super::abstract_function,
        })?;
        let id = vm.ensure_class_by_desc(class)?;
        vm.classes[id as usize].superclass = Some(executable);
    }
    vm.register_native(NativeEntry {
        class: "Ljava/lang/InstantiationException;",
        name: "__marker",
        sig: "()V",
        instance: true,
        f: super::abstract_function,
    })?;
    let error = vm.ensure_class_by_desc("Ljava/lang/InstantiationException;")?;
    vm.classes[error as usize].superclass =
        Some(vm.ensure_class_by_desc("Ljava/lang/ReflectiveOperationException;")?);
    for (name, sig, f) in [
        (
            "getDeclaredMethods",
            "()[Ljava/lang/reflect/Method;",
            declared_methods as dexvm::vm::NativeFn,
        ),
        (
            "getMethods",
            "()[Ljava/lang/reflect/Method;",
            public_methods,
        ),
        (
            "getDeclaredConstructors",
            "()[Ljava/lang/reflect/Constructor;",
            declared_constructors,
        ),
        (
            "getConstructors",
            "()[Ljava/lang/reflect/Constructor;",
            public_constructors,
        ),
        (
            "getDeclaredConstructor",
            "([Ljava/lang/Class;)Ljava/lang/reflect/Constructor;",
            declared_constructor,
        ),
        (
            "getConstructor",
            "([Ljava/lang/Class;)Ljava/lang/reflect/Constructor;",
            public_constructor,
        ),
        ("newInstance", "()Ljava/lang/Object;", class_new_instance),
    ] {
        vm.register_native(NativeEntry {
            class: "Ljava/lang/Class;",
            name,
            sig,
            instance: true,
            f,
        })?;
    }
    for class in [METHOD, CTOR] {
        for (name, sig, f) in [
            (
                "setAccessible",
                "(Z)V",
                set_accessible as dexvm::vm::NativeFn,
            ),
            ("isAccessible", "()Z", is_accessible),
            ("getDeclaringClass", "()Ljava/lang/Class;", declaring_class),
            ("getModifiers", "()I", modifiers),
            ("getParameterCount", "()I", parameter_count),
            ("getParameterTypes", "()[Ljava/lang/Class;", parameter_types),
            ("getExceptionTypes", "()[Ljava/lang/Class;", exception_types),
            ("isSynthetic", "()Z", synthetic),
            ("isVarArgs", "()Z", varargs),
            ("equals", "(Ljava/lang/Object;)Z", equal),
            ("hashCode", "()I", hash_code),
        ] {
            vm.register_native(NativeEntry {
                class,
                name,
                sig,
                instance: true,
                f,
            })?;
        }
    }
    vm.register_native(NativeEntry {
        class: METHOD,
        name: "isBridge",
        sig: "()Z",
        instance: true,
        f: bridge,
    })?;
    vm.register_native(NativeEntry {
        class: CTOR,
        name: "getName",
        sig: "()Ljava/lang/String;",
        instance: true,
        f: constructor_name,
    })?;
    vm.register_native(NativeEntry {
        class: CTOR,
        name: "newInstance",
        sig: "([Ljava/lang/Object;)Ljava/lang/Object;",
        instance: true,
        f: new_instance,
    })?;
    Ok(())
}
