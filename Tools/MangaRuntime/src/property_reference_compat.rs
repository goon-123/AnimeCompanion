//! Kotlin property references retain their bound receiver and dispatch the real
//! accessor, including accessors overridden by generated guest subclasses.
use dexvm::vm::{
    error::JvmError,
    object::{ClassOrPrim, Native},
    NatErr, NativeEntry, Vm,
};
use dexvm::JValue;
type R = Result<JValue, NatErr>;
const CALLABLE: &str = "Lkotlin/jvm/internal/CallableReference;";
const FIELDS: [(&str, &str); 5] = [
    ("receiver", "Ljava/lang/Object;"),
    ("owner", "Ljava/lang/Class;"),
    ("name", "Ljava/lang/String;"),
    ("signature", "Ljava/lang/String;"),
    ("flags", "I"),
];
fn field(vm: &mut Vm, value: JValue, name: &str) -> R {
    if value.is_null_ref() {
        return Err(NatErr::Throw(vm.err_npe()));
    }
    vm.instance_field(value.as_obj(), name)
        .ok_or_else(|| NatErr::Throw(vm.err_iae("Invalid property reference")))
}
fn no_receiver(vm: &mut Vm) -> R {
    let key = dexvm::vm::FieldRef {
        class_desc: vm.intern(CALLABLE),
        name: vm.intern("NO_RECEIVER"),
        ty: vm.intern("Ljava/lang/Object;"),
    };
    vm.static_field_get(key).map_err(NatErr::Fatal)
}
fn init(vm: &mut Vm, args: &[JValue]) -> R {
    let bound = args.len() == 6;
    let receiver = if bound { args[1] } else { no_receiver(vm)? };
    let offset = usize::from(bound);
    let values = [
        receiver,
        args[1 + offset],
        args[2 + offset],
        args[3 + offset],
        args[4 + offset],
    ];
    for ((name, _), value) in FIELDS.iter().zip(values) {
        if !vm.instance_field_set(args[0].as_obj(), name, value) {
            return Err(NatErr::Throw(
                vm.err_iae("Invalid property reference fields"),
            ));
        }
    }
    Ok(JValue::Null)
}
fn get_name(vm: &mut Vm, args: &[JValue]) -> R {
    field(vm, args[0], "name")
}
fn get_signature(vm: &mut Vm, args: &[JValue]) -> R {
    field(vm, args[0], "signature")
}
fn get_receiver(vm: &mut Vm, args: &[JValue]) -> R {
    field(vm, args[0], "receiver")
}
fn identity(_vm: &mut Vm, args: &[JValue]) -> R {
    Ok(args[0])
}
fn accessor(vm: &mut Vm, args: &[JValue], setter: bool) -> R {
    let owner = field(vm, args[0], "owner")?;
    let class = match vm.payload_of(owner) {
        Some(Native::ClassObj(ClassOrPrim::Class(class))) => class,
        _ => return Err(NatErr::Throw(vm.err_iae("Invalid property owner"))),
    };
    let signature = field(vm, args[0], "signature")?;
    let signature = vm
        .str_of_jvalue(signature)
        .ok_or_else(|| NatErr::Throw(vm.err_npe()))?;
    if signature.len() > 512 {
        return Err(NatErr::Fatal(JvmError::BudgetExceeded));
    }
    let (name, sig) = signature
        .split_once('(')
        .ok_or_else(|| NatErr::Throw(vm.err_iae("Invalid property accessor signature")))?;
    let getter_sig = format!("({sig}");
    let (_, return_type) = dexvm::vm::parse_sig(&getter_sig);
    let (name, sig) = if setter {
        let suffix = name
            .strip_prefix("get")
            .or_else(|| name.strip_prefix("is"))
            .ok_or_else(|| NatErr::Throw(vm.err_iae("Property has no JVM setter")))?;
        let (params, _) = dexvm::vm::parse_sig(&getter_sig);
        (
            format!("set{suffix}"),
            format!("({}{return_type})V", params.join("")),
        )
    } else {
        (name.to_owned(), getter_sig.clone())
    };
    let mut pending = Some(class);
    let mut found = None;
    for _ in 0..256 {
        let Some(id) = pending else {
            break;
        };
        if vm.budget <= 0 {
            return Err(NatErr::Fatal(JvmError::BudgetExceeded));
        }
        vm.budget -= 1;
        let key = (vm.intern(&name), vm.intern(&sig));
        if let Some(slot) = vm.classes[id as usize].dispatch.get(&key) {
            found = Some(vm.classes[id as usize].methods[*slot as usize].clone());
            break;
        }
        pending = vm.classes[id as usize].superclass;
    }
    let m = found.ok_or_else(|| {
        NatErr::Throw(vm.throwable_of(
            "Ljava/lang/NoSuchMethodException;",
            "Property accessor is absent",
        ))
    })?;
    let bound = field(vm, args[0], "receiver")?;
    let mut arguments = vec![];
    if bound != no_receiver(vm)? {
        arguments.push(bound);
    }
    arguments.extend_from_slice(&args[1..]);
    let receiver = if m.static_method {
        JValue::Null
    } else {
        if arguments.is_empty() {
            return Err(NatErr::Throw(vm.err_iae("Missing property receiver")));
        }
        arguments.remove(0)
    };
    if !m.static_method && receiver.is_null_ref() {
        return Err(NatErr::Throw(vm.err_npe()));
    }
    if arguments.len() != m.args.len() {
        return Err(NatErr::Throw(vm.err_iae("Wrong property argument count")));
    }
    let values = arguments
        .into_iter()
        .zip(&m.args)
        .map(|(value, ty)| {
            let ty = vm.str_of(*ty).to_owned();
            super::method_reflection_compat::unbox(vm, value, &ty)
        })
        .collect::<Result<Vec<_>, _>>()?;
    let value =
        super::method_reflection_compat::call(vm, &m, receiver, values).map_err(|e| match e {
            JvmError::Uncaught(id) => NatErr::Throw(id),
            e => NatErr::Fatal(e),
        })?;
    let ret = vm.str_of(m.ret).to_owned();
    super::method_reflection_compat::boxed(vm, value, &ret)
}
fn get(vm: &mut Vm, args: &[JValue]) -> R {
    accessor(vm, args, false)
}
fn set(vm: &mut Vm, args: &[JValue]) -> R {
    accessor(vm, args, true)
}
fn invoke0(vm: &mut Vm, args: &[JValue]) -> R {
    invoke(vm, args, "()Ljava/lang/Object;")
}
fn invoke1(vm: &mut Vm, args: &[JValue]) -> R {
    invoke(vm, args, "(Ljava/lang/Object;)Ljava/lang/Object;")
}
fn invoke(vm: &mut Vm, args: &[JValue], sig: &str) -> R {
    if vm.recursion_depth >= vm.depth_limit {
        return Err(NatErr::Fatal(JvmError::StackOverflow));
    }
    vm.recursion_depth += 1;
    let result = vm.invoke_virtual_args(args[0], "get", sig, args[1..].to_vec());
    vm.recursion_depth -= 1;
    result.map_err(|e| match e {
        JvmError::Uncaught(id) => NatErr::Throw(id),
        e => NatErr::Fatal(e),
    })
}
pub(super) fn install(vm: &mut Vm) -> Result<(), JvmError> {
    for (child, parents) in [
        (
            "Lkotlin/reflect/KProperty;",
            &["Lkotlin/reflect/KCallable;"][..],
        ),
        (
            "Lkotlin/reflect/KMutableProperty;",
            &["Lkotlin/reflect/KProperty;"][..],
        ),
        (
            "Lkotlin/reflect/KProperty0;",
            &[
                "Lkotlin/reflect/KProperty;",
                "Lkotlin/jvm/functions/Function0;",
            ][..],
        ),
        (
            "Lkotlin/reflect/KProperty1;",
            &[
                "Lkotlin/reflect/KProperty;",
                "Lkotlin/jvm/functions/Function1;",
            ][..],
        ),
        (
            "Lkotlin/reflect/KMutableProperty0;",
            &[
                "Lkotlin/reflect/KProperty0;",
                "Lkotlin/reflect/KMutableProperty;",
            ][..],
        ),
        (
            "Lkotlin/reflect/KMutableProperty1;",
            &[
                "Lkotlin/reflect/KProperty1;",
                "Lkotlin/reflect/KMutableProperty;",
            ][..],
        ),
    ] {
        let id = super::kotlin_type_compat::marker(vm, child);
        for parent in parents {
            let parent = super::kotlin_type_compat::marker(vm, parent);
            if !vm.classes[id as usize].interfaces.contains(&parent) {
                vm.classes[id as usize].interfaces.push(parent);
            }
        }
    }
    let interfaces = [
        "Lkotlin/reflect/KCallable;",
        "Lkotlin/reflect/KProperty;",
        "Lkotlin/reflect/KProperty0;",
        "Lkotlin/reflect/KMutableProperty0;",
        "Lkotlin/reflect/KProperty1;",
        "Lkotlin/reflect/KMutableProperty1;",
    ];
    for desc in interfaces {
        super::kotlin_type_compat::marker(vm, desc);
    }
    for (class, parent, interface) in [
        (CALLABLE, "Ljava/lang/Object;", "Lkotlin/reflect/KCallable;"),
        (
            "Lkotlin/jvm/internal/PropertyReference;",
            CALLABLE,
            "Lkotlin/reflect/KProperty;",
        ),
        (
            "Lkotlin/jvm/internal/PropertyReference0;",
            "Lkotlin/jvm/internal/PropertyReference;",
            "Lkotlin/reflect/KProperty0;",
        ),
        (
            "Lkotlin/jvm/internal/PropertyReference0Impl;",
            "Lkotlin/jvm/internal/PropertyReference0;",
            "Lkotlin/jvm/functions/Function0;",
        ),
        (
            "Lkotlin/jvm/internal/MutablePropertyReference0;",
            "Lkotlin/jvm/internal/PropertyReference0;",
            "Lkotlin/reflect/KMutableProperty0;",
        ),
        (
            "Lkotlin/jvm/internal/MutablePropertyReference0Impl;",
            "Lkotlin/jvm/internal/MutablePropertyReference0;",
            "Lkotlin/jvm/functions/Function0;",
        ),
        (
            "Lkotlin/jvm/internal/PropertyReference1;",
            "Lkotlin/jvm/internal/PropertyReference;",
            "Lkotlin/reflect/KProperty1;",
        ),
        (
            "Lkotlin/jvm/internal/PropertyReference1Impl;",
            "Lkotlin/jvm/internal/PropertyReference1;",
            "Lkotlin/jvm/functions/Function1;",
        ),
        (
            "Lkotlin/jvm/internal/MutablePropertyReference1;",
            "Lkotlin/jvm/internal/PropertyReference1;",
            "Lkotlin/reflect/KMutableProperty1;",
        ),
        (
            "Lkotlin/jvm/internal/MutablePropertyReference1Impl;",
            "Lkotlin/jvm/internal/MutablePropertyReference1;",
            "Lkotlin/jvm/functions/Function1;",
        ),
    ] {
        vm.register_native(NativeEntry {
            class,
            name: "<init>",
            sig: "(Ljava/lang/Class;Ljava/lang/String;Ljava/lang/String;I)V",
            instance: true,
            f: init,
        })?;
        vm.register_native(NativeEntry {
            class,
            name: "<init>",
            sig: "(Ljava/lang/Object;Ljava/lang/Class;Ljava/lang/String;Ljava/lang/String;I)V",
            instance: true,
            f: init,
        })?;
        let parent = vm.ensure_class_by_desc(parent)?;
        let id = vm.ensure_class_by_desc(class)?;
        vm.classes[id as usize].superclass = Some(parent);
        let iface = super::kotlin_type_compat::marker(vm, interface);
        vm.classes[id as usize].interfaces.push(iface);
        let fields = if class == CALLABLE {
            FIELDS
                .iter()
                .map(|(name, ty)| (vm.intern(name), vm.intern(ty), 1))
                .collect()
        } else {
            vm.classes[parent as usize].instance_fields.clone()
        };
        let offsets = fields
            .iter()
            .enumerate()
            .map(|(i, (name, ty, _))| ((*name, *ty), i as u32))
            .collect();
        vm.classes[id as usize].instance_fields = fields;
        vm.classes[id as usize].field_offsets = offsets;
    }
    for (class, name, sig, f) in [
        (
            CALLABLE,
            "getName",
            "()Ljava/lang/String;",
            get_name as dexvm::vm::NativeFn,
        ),
        (
            CALLABLE,
            "getSignature",
            "()Ljava/lang/String;",
            get_signature,
        ),
        (
            CALLABLE,
            "getBoundReceiver",
            "()Ljava/lang/Object;",
            get_receiver,
        ),
        (
            "Lkotlin/jvm/internal/PropertyReference0;",
            "get",
            "()Ljava/lang/Object;",
            get,
        ),
        (
            "Lkotlin/jvm/internal/PropertyReference0;",
            "invoke",
            "()Ljava/lang/Object;",
            invoke0,
        ),
        (
            "Lkotlin/jvm/internal/MutablePropertyReference0;",
            "set",
            "(Ljava/lang/Object;)V",
            set,
        ),
        (
            "Lkotlin/jvm/internal/PropertyReference1;",
            "get",
            "(Ljava/lang/Object;)Ljava/lang/Object;",
            get,
        ),
        (
            "Lkotlin/jvm/internal/PropertyReference1;",
            "invoke",
            "(Ljava/lang/Object;)Ljava/lang/Object;",
            invoke1,
        ),
        (
            "Lkotlin/jvm/internal/MutablePropertyReference1;",
            "set",
            "(Ljava/lang/Object;Ljava/lang/Object;)V",
            set,
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
    for (name, sig) in [
        (
            "property0",
            "(Lkotlin/jvm/internal/PropertyReference0;)Lkotlin/reflect/KProperty0;",
        ),
        (
            "mutableProperty0",
            "(Lkotlin/jvm/internal/MutablePropertyReference0;)Lkotlin/reflect/KMutableProperty0;",
        ),
        (
            "property1",
            "(Lkotlin/jvm/internal/PropertyReference1;)Lkotlin/reflect/KProperty1;",
        ),
        (
            "mutableProperty1",
            "(Lkotlin/jvm/internal/MutablePropertyReference1;)Lkotlin/reflect/KMutableProperty1;",
        ),
    ] {
        vm.register_native(NativeEntry {
            class: "Lkotlin/jvm/internal/Reflection;",
            name,
            sig,
            instance: false,
            f: identity,
        })?;
    }
    let value = vm.alloc_native("Ljava/lang/Object;", Native::Opaque)?;
    super::multipart_compat::static_value(
        vm,
        CALLABLE,
        "NO_RECEIVER",
        "Ljava/lang/Object;",
        value,
    )?;
    Ok(())
}
