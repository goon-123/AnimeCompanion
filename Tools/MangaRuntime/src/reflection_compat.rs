//! Reflection stays inside the interpreted package. Enumerate real fields,
//! respecting public access and inheritance; never synthesize DTO properties.
use dexvm::vm::object::{ArrayData, ClassOrPrim, Native};
use dexvm::vm::{error::JvmError, NatErr, NativeEntry, Vm};
use dexvm::JValue;
use std::collections::HashSet;

type R = Result<JValue, NatErr>;
fn class_id(vm: &mut Vm, value: JValue) -> Result<u32, NatErr> {
    if value.is_null_ref() {
        return Err(NatErr::Throw(vm.err_npe()));
    }
    match vm.payload_of(value) {
        Some(Native::ClassObj(ClassOrPrim::Class(class))) => Ok(class),
        _ => Err(NatErr::Throw(vm.err_iae("Expected a class"))),
    }
}
fn fields(vm: &mut Vm, value: JValue, inherited: bool) -> R {
    let class = class_id(vm, value)?;
    let mut pending = vec![class];
    let mut visited = HashSet::new();
    let mut out = vec![];
    while let Some(class) = pending.pop() {
        if !visited.insert(class) {
            continue;
        }
        if visited.len() > 512 || out.len() > 10_000 || vm.budget <= 0 {
            return Err(NatErr::Fatal(JvmError::BudgetExceeded));
        }
        vm.budget -= 1 + vm
            .dexes
            .iter()
            .map(|dex| dex.classes.len() as i64)
            .sum::<i64>();
        if vm.budget <= 0 {
            return Err(NatErr::Fatal(JvmError::BudgetExceeded));
        }
        let descriptor = vm.str_of(vm.classes[class as usize].descriptor).to_owned();
        // DEX retains both public/private static access flags; the resolved VM
        // static table alone does not. Use the declaring package metadata.
        let declared = vm.dexes.iter().find_map(|dex| {
            let definition = dex
                .classes
                .iter()
                .find(|def| dex.type_descriptor(def.class_idx) == descriptor)?;
            let data = definition.class_data.as_ref()?;
            Some(
                data.static_fields
                    .iter()
                    .chain(&data.instance_fields)
                    .map(|field| {
                        let field_ref = &dex.fields[field.field_idx as usize];
                        (
                            dex.strings[field_ref.name as usize].to_string(),
                            field.access_flags,
                        )
                    })
                    .collect::<Vec<_>>(),
            )
        });
        let declarations = declared.unwrap_or_else(|| {
            let owner = &vm.classes[class as usize];
            let start = owner
                .superclass
                .map(|parent| vm.classes[parent as usize].instance_fields.len())
                .unwrap_or(0);
            let mut fields = owner.instance_fields[start..]
                .iter()
                .map(|(name, _, access)| (vm.str_of(*name).to_owned(), *access))
                .collect::<Vec<_>>();
            fields.extend(
                owner
                    .static_fields
                    .iter()
                    .filter(|(_, (declaring, _))| *declaring == class)
                    .map(|((name, _), _)| (vm.str_of(*name).to_owned(), 1)),
            );
            fields.sort_by(|a, b| a.0.cmp(&b.0));
            fields
        });
        for (name, access) in declarations {
            if inherited && access & 1 == 0 {
                continue;
            }
            if out.len() >= 10_000 || vm.budget <= 0 {
                return Err(NatErr::Fatal(JvmError::BudgetExceeded));
            }
            vm.budget -= 1;
            let name = vm.intern(&name);
            out.push(
                vm.alloc_native("Ljava/lang/reflect/Field;", Native::Field { class, name })
                    .map_err(NatErr::Fatal)?,
            );
        }
        if inherited {
            pending.extend(vm.classes[class as usize].interfaces.iter().copied());
            pending.extend(vm.classes[class as usize].superclass);
        }
    }
    vm.alloc_native(
        "[Ljava/lang/reflect/Field;",
        Native::Array(ArrayData::Obj(out)),
    )
    .map_err(NatErr::Fatal)
}
fn public_fields(vm: &mut Vm, args: &[JValue]) -> R {
    fields(vm, args[0], true)
}
fn declared_fields(vm: &mut Vm, args: &[JValue]) -> R {
    fields(vm, args[0], false)
}
fn field_name(vm: &mut Vm, args: &[JValue]) -> R {
    let Some(Native::Field { name, .. }) = vm.payload_of(args[0]) else {
        return Err(NatErr::Throw(vm.err_iae("Expected a field")));
    };
    let name = vm.str_of(name).to_owned();
    Ok(vm.alloc_string(&name))
}
fn declaring_class(vm: &mut Vm, args: &[JValue]) -> R {
    let Some(Native::Field { class, .. }) = vm.payload_of(args[0]) else {
        return Err(NatErr::Throw(vm.err_iae("Expected a field")));
    };
    vm.class_obj(class).map_err(NatErr::Fatal)
}
fn array_length(vm: &mut Vm, args: &[JValue]) -> R {
    if args[0].is_null_ref() {
        return Err(NatErr::Throw(vm.err_npe()));
    }
    match vm.payload_of(args[0]) {
        Some(Native::Array(values)) => Ok(JValue::Int(values.len() as i32)),
        _ if args[0].is_null_ref() => Err(NatErr::Throw(vm.err_npe())),
        _ => Err(NatErr::Throw(vm.err_iae("Expected an array"))),
    }
}
fn new_array(vm: &mut Vm, args: &[JValue]) -> R {
    if args[0].is_null_ref() {
        return Err(NatErr::Throw(vm.err_npe()));
    }
    let component = match vm.payload_of(args[0]) {
        Some(Native::ClassObj(ClassOrPrim::Class(id))) => {
            vm.str_of(vm.classes[id as usize].descriptor).to_owned()
        }
        Some(Native::ClassObj(ClassOrPrim::Primitive(b))) if b != b'V' => (b as char).to_string(),
        _ if args[0].is_null_ref() => return Err(NatErr::Throw(vm.err_npe())),
        _ => return Err(NatErr::Throw(vm.err_iae("Invalid array component class"))),
    };
    let length = args[1].as_int();
    if length < 0 {
        return Err(NatErr::Throw(vm.err_neg_arr_size()));
    }
    if length > 1_000_000 || vm.budget <= i64::from(length) {
        return Err(NatErr::Fatal(JvmError::BudgetExceeded));
    }
    if component.bytes().take_while(|c| *c == b'[').count() >= 255 {
        return Err(NatErr::Throw(vm.err_iae("Array has too many dimensions")));
    }
    vm.budget -= i64::from(length) + 1;
    vm.alloc_native(
        &format!("[{component}"),
        Native::Array(ArrayData::new(&component, length as usize)),
    )
    .map_err(NatErr::Fatal)
}
fn field_info(vm: &mut Vm, value: JValue) -> Result<(String, u32), NatErr> {
    let Some(Native::Field { class, name }) = vm.payload_of(value) else {
        return Err(NatErr::Throw(vm.err_iae("Expected a field")));
    };
    let descriptor = vm.str_of(vm.classes[class as usize].descriptor).to_owned();
    let name = vm.str_of(name).to_owned();
    let work = vm.dexes.iter().map(|d| d.classes.len()).sum::<usize>();
    if vm.budget <= work as i64 {
        return Err(NatErr::Fatal(JvmError::BudgetExceeded));
    }
    vm.budget -= work as i64 + 1;
    for dex in &vm.dexes {
        if let Some(data) = dex
            .classes
            .iter()
            .find(|c| dex.type_descriptor(c.class_idx) == descriptor)
            .and_then(|c| c.class_data.as_ref())
        {
            for field in data.static_fields.iter().chain(&data.instance_fields) {
                let f = &dex.fields[field.field_idx as usize];
                if dex.strings[f.name as usize].as_ref() == name {
                    return Ok((dex.type_descriptor(f.ty).to_owned(), field.access_flags));
                }
            }
        }
    }
    let owner = &vm.classes[class as usize];
    let start = owner
        .superclass
        .map(|p| vm.classes[p as usize].instance_fields.len())
        .unwrap_or(0);
    for (n, ty, flags) in &owner.instance_fields[start..] {
        if vm.str_of(*n) == name {
            return Ok((vm.str_of(*ty).to_owned(), *flags));
        }
    }
    for ((n, ty), (declaring, _)) in &owner.static_fields {
        if *declaring == class && vm.str_of(*n) == name {
            return Ok((vm.str_of(*ty).to_owned(), 9));
        }
    }
    Err(NatErr::Throw(vm.throwable_of(
        "Ljava/lang/NoSuchFieldException;",
        "Field is not declared by this class",
    )))
}
fn field_type(vm: &mut Vm, args: &[JValue]) -> R {
    let (desc, _) = field_info(vm, args[0])?;
    if desc.len() == 1 {
        // Reuse boxed TYPE singletons for primitive Class identity.
        let owner = match desc.as_str() {
            "Z" => "Ljava/lang/Boolean;",
            "B" => "Ljava/lang/Byte;",
            "C" => "Ljava/lang/Character;",
            "S" => "Ljava/lang/Short;",
            "I" => "Ljava/lang/Integer;",
            "J" => "Ljava/lang/Long;",
            "F" => "Ljava/lang/Float;",
            "D" => "Ljava/lang/Double;",
            _ => return Err(NatErr::Throw(vm.err_iae("Invalid field type"))),
        };
        let field = dexvm::vm::FieldRef {
            class_desc: vm.intern(owner),
            name: vm.intern("TYPE"),
            ty: vm.intern("Ljava/lang/Class;"),
        };
        return vm.static_field_get(field).map_err(NatErr::Fatal);
    }
    let class = vm.ensure_class_by_desc(&desc).map_err(NatErr::Fatal)?;
    vm.class_obj(class).map_err(NatErr::Fatal)
}
fn field_modifiers(vm: &mut Vm, args: &[JValue]) -> R {
    Ok(JValue::Int(field_info(vm, args[0])?.1 as i32 & 0xffff))
}
fn find_field(vm: &mut Vm, args: &[JValue], inherited: bool) -> R {
    let owner = class_id(vm, args[0])?;
    let name = vm
        .str_of_jvalue(args[1])
        .ok_or_else(|| NatErr::Throw(vm.err_npe()))?;
    let array = fields(vm, args[0], inherited)?;
    let Some(Native::Array(ArrayData::Obj(values))) = vm.payload_of(array) else {
        unreachable!()
    };
    for field in values {
        if let Some(Native::Field { name: id, .. }) = vm.payload_of(field) {
            if vm.str_of(id) == name {
                return Ok(field);
            }
        }
    }
    // Preserve the interpreter's existing fieldless host-shim injection ABI
    // (HttpSource delegate installation). Never synthesize fields for guest DEX.
    if !inherited && !vm.class_has_instance_fields(owner) && !guest_class(vm, owner) {
        let name = vm.intern(&name);
        return vm
            .alloc_native(
                "Ljava/lang/reflect/Field;",
                Native::Field { class: owner, name },
            )
            .map_err(NatErr::Fatal);
    }
    Err(NatErr::Throw(
        vm.throwable_of("Ljava/lang/NoSuchFieldException;", name),
    ))
}
fn guest_class(vm: &Vm, owner: u32) -> bool {
    let desc = vm.str_of(vm.classes[owner as usize].descriptor);
    vm.dexes.iter().any(|dex| {
        dex.classes
            .iter()
            .any(|class| dex.type_descriptor(class.class_idx) == desc)
    })
}
fn declared_field(vm: &mut Vm, args: &[JValue]) -> R {
    find_field(vm, args, false)
}
fn public_field(vm: &mut Vm, args: &[JValue]) -> R {
    find_field(vm, args, true)
}
fn accessible(vm: &mut Vm, args: &[JValue]) -> R {
    if !matches!(vm.payload_of(args[0]), Some(Native::Field { .. })) {
        return Err(NatErr::Throw(vm.err_iae("Expected a field")));
    }
    vm.arena.objects[args[0].as_obj() as usize].fields =
        vec![JValue::Int(i32::from(!args[1].is_zero()))];
    Ok(JValue::Null)
}
fn is_accessible(vm: &mut Vm, args: &[JValue]) -> R {
    if !matches!(vm.payload_of(args[0]), Some(Native::Field { .. })) {
        return Err(NatErr::Throw(vm.err_iae("Expected a field")));
    }
    Ok(vm.arena.objects[args[0].as_obj() as usize]
        .fields
        .first()
        .copied()
        .unwrap_or(JValue::Int(0)))
}
fn field_target(
    vm: &mut Vm,
    field: JValue,
    target: JValue,
    write: bool,
) -> Result<(u32, u32, String, u32), NatErr> {
    let Some(Native::Field { class, name }) = vm.payload_of(field) else {
        return Err(NatErr::Throw(vm.err_iae("Expected a field")));
    };
    let (ty, flags) = field_info(vm, field)?;
    let override_access = !is_accessible(vm, &[field])?.is_zero();
    if flags & 1 == 0 && !override_access
        || write && flags & 16 != 0 && (flags & 8 != 0 || !override_access)
    {
        return Err(NatErr::Throw(vm.throwable_of(
            "Ljava/lang/IllegalAccessException;",
            "Field access is not permitted",
        )));
    }
    if flags & 8 == 0 {
        let actual = vm
            .object_class(target)
            .ok_or_else(|| NatErr::Throw(vm.err_npe()))?;
        if !vm.is_assignable(actual, class).map_err(NatErr::Fatal)? {
            return Err(NatErr::Throw(vm.err_iae("Wrong field receiver")));
        }
    }
    Ok((class, name, ty, flags))
}
fn legacy_host_field(vm: &Vm, field: JValue) -> bool {
    match vm.payload_of(field) {
        Some(Native::Field { class, .. }) => {
            !vm.class_has_instance_fields(class)
                && !guest_class(vm, class)
                && vm.classes[class as usize].static_fields.is_empty()
        }
        _ => false,
    }
}
fn raw_get(vm: &mut Vm, field: JValue, target: JValue) -> Result<(JValue, String), NatErr> {
    let (class, name, ty, flags) = field_target(vm, field, target, false)?;
    let ty_id = vm.intern(&ty);
    let value = if flags & 8 != 0 {
        let fr = dexvm::vm::FieldRef {
            class_desc: vm.classes[class as usize].descriptor,
            name,
            ty: ty_id,
        };
        vm.static_field_get(fr).map_err(java_error)?
    } else {
        let slot = vm
            .field_offset(class, name, ty_id)
            .ok_or_else(|| NatErr::Throw(vm.err_iae("Invalid field slot")))?;
        vm.arena.objects[target.as_obj() as usize].fields[slot as usize]
    };
    Ok((value, ty))
}
fn java_error(error: JvmError) -> NatErr {
    match error {
        JvmError::Uncaught(id) => NatErr::Throw(id),
        error => NatErr::Fatal(error),
    }
}
fn field_get(vm: &mut Vm, args: &[JValue]) -> R {
    if legacy_host_field(vm, args[0]) {
        return Ok(JValue::Null);
    }
    let (value, ty) = raw_get(vm, args[0], args[1])?;
    super::method_reflection_compat::boxed(vm, value, &ty)
}
fn field_set(vm: &mut Vm, args: &[JValue]) -> R {
    if legacy_host_field(vm, args[0]) {
        return Ok(JValue::Null);
    }
    let (class, name, ty, flags) = field_target(vm, args[0], args[1], true)?;
    let value = super::method_reflection_compat::unbox(vm, args[2], &ty)?;
    let ty = vm.intern(&ty);
    if flags & 8 != 0 {
        let fr = dexvm::vm::FieldRef {
            class_desc: vm.classes[class as usize].descriptor,
            name,
            ty,
        };
        vm.static_field_put(fr, value).map_err(java_error)?;
    } else {
        let slot = vm
            .field_offset(class, name, ty)
            .ok_or_else(|| NatErr::Throw(vm.err_iae("Invalid field slot")))?;
        vm.arena.objects[args[1].as_obj() as usize].fields[slot as usize] = value;
    }
    Ok(JValue::Null)
}
fn primitive_get(vm: &mut Vm, args: &[JValue], wanted: &str) -> R {
    let (value, ty) = raw_get(vm, args[0], args[1])?;
    if ty.starts_with(['L', '[']) {
        return Err(NatErr::Throw(vm.err_iae("Expected primitive field")));
    }
    let boxed = super::method_reflection_compat::boxed(vm, value, &ty)?;
    super::method_reflection_compat::unbox(vm, boxed, wanted)
}
fn primitive_set(vm: &mut Vm, args: &[JValue], ty: &str) -> R {
    if field_info(vm, args[0])?.0.starts_with(['L', '[']) {
        return Err(NatErr::Throw(vm.err_iae("Expected primitive field")));
    }
    let boxed = super::method_reflection_compat::boxed(vm, args[2], ty)?;
    field_set(vm, &[args[0], args[1], boxed])
}
macro_rules! primitive_field {
    ($get:ident, $set:ident, $ty:literal) => {
        fn $get(vm: &mut Vm, args: &[JValue]) -> R {
            primitive_get(vm, args, $ty)
        }
        fn $set(vm: &mut Vm, args: &[JValue]) -> R {
            primitive_set(vm, args, $ty)
        }
    };
}
primitive_field!(get_boolean, set_boolean, "Z");
primitive_field!(get_byte, set_byte, "B");
primitive_field!(get_short, set_short, "S");
primitive_field!(get_char, set_char, "C");
primitive_field!(get_int, set_int, "I");
primitive_field!(get_long, set_long, "J");
primitive_field!(get_float, set_float, "F");
primitive_field!(get_double, set_double, "D");
pub(super) fn install(vm: &mut Vm) -> Result<(), JvmError> {
    for (class, parent) in [
        (
            "Ljava/lang/ReflectiveOperationException;",
            "Ljava/lang/Exception;",
        ),
        (
            "Ljava/lang/NoSuchFieldException;",
            "Ljava/lang/ReflectiveOperationException;",
        ),
        (
            "Ljava/lang/NoSuchMethodException;",
            "Ljava/lang/ReflectiveOperationException;",
        ),
        (
            "Ljava/lang/IllegalAccessException;",
            "Ljava/lang/ReflectiveOperationException;",
        ),
    ] {
        vm.register_native(NativeEntry {
            class,
            name: "__marker",
            sig: "()V",
            instance: true,
            f: super::abstract_function,
        })?;
        let id = vm.ensure_class_by_desc(class)?;
        vm.classes[id as usize].superclass = Some(vm.ensure_class_by_desc(parent)?);
    }
    for (name, sig, f) in [
        (
            "get",
            "(Ljava/lang/Object;)Ljava/lang/Object;",
            field_get as dexvm::vm::NativeFn,
        ),
        ("set", "(Ljava/lang/Object;Ljava/lang/Object;)V", field_set),
        ("setAccessible", "(Z)V", accessible),
        ("isAccessible", "()Z", is_accessible),
        ("getBoolean", "(Ljava/lang/Object;)Z", get_boolean),
        ("setBoolean", "(Ljava/lang/Object;Z)V", set_boolean),
        ("getByte", "(Ljava/lang/Object;)B", get_byte),
        ("setByte", "(Ljava/lang/Object;B)V", set_byte),
        ("getShort", "(Ljava/lang/Object;)S", get_short),
        ("setShort", "(Ljava/lang/Object;S)V", set_short),
        ("getChar", "(Ljava/lang/Object;)C", get_char),
        ("setChar", "(Ljava/lang/Object;C)V", set_char),
        ("getInt", "(Ljava/lang/Object;)I", get_int),
        ("setInt", "(Ljava/lang/Object;I)V", set_int),
        ("getLong", "(Ljava/lang/Object;)J", get_long),
        ("setLong", "(Ljava/lang/Object;J)V", set_long),
        ("getFloat", "(Ljava/lang/Object;)F", get_float),
        ("setFloat", "(Ljava/lang/Object;F)V", set_float),
        ("getDouble", "(Ljava/lang/Object;)D", get_double),
        ("setDouble", "(Ljava/lang/Object;D)V", set_double),
    ] {
        vm.register_native(NativeEntry {
            class: "Ljava/lang/reflect/Field;",
            name,
            sig,
            instance: true,
            f,
        })?;
    }
    for (name, f) in [
        ("getDeclaredField", declared_field as dexvm::vm::NativeFn),
        ("getField", public_field),
    ] {
        vm.register_native(NativeEntry {
            class: "Ljava/lang/Class;",
            name,
            sig: "(Ljava/lang/String;)Ljava/lang/reflect/Field;",
            instance: true,
            f,
        })?;
    }
    for (name, sig, f) in [
        (
            "getLength",
            "(Ljava/lang/Object;)I",
            array_length as dexvm::vm::NativeFn,
        ),
        (
            "newInstance",
            "(Ljava/lang/Class;I)Ljava/lang/Object;",
            new_array,
        ),
    ] {
        vm.register_native(NativeEntry {
            class: "Ljava/lang/reflect/Array;",
            name,
            sig,
            instance: false,
            f,
        })?;
    }
    for (class, name, sig, f) in [
        (
            "Ljava/lang/Class;",
            "getFields",
            "()[Ljava/lang/reflect/Field;",
            public_fields as dexvm::vm::NativeFn,
        ),
        (
            "Ljava/lang/Class;",
            "getDeclaredFields",
            "()[Ljava/lang/reflect/Field;",
            declared_fields,
        ),
        (
            "Ljava/lang/reflect/Field;",
            "getName",
            "()Ljava/lang/String;",
            field_name,
        ),
        (
            "Ljava/lang/reflect/Field;",
            "getDeclaringClass",
            "()Ljava/lang/Class;",
            declaring_class,
        ),
        (
            "Ljava/lang/reflect/Field;",
            "getType",
            "()Ljava/lang/Class;",
            field_type,
        ),
        (
            "Ljava/lang/reflect/Field;",
            "getModifiers",
            "()I",
            field_modifiers,
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
    vm.register_native(NativeEntry {
        class: "Lkotlin/properties/PropertyDelegateProvider;",
        name: "provideDelegate",
        sig: "(Ljava/lang/Object;Lkotlin/reflect/KProperty;)Ljava/lang/Object;",
        instance: true,
        f: super::abstract_function,
    })?;
    let class = vm.ensure_class_by_desc("Lkotlin/properties/PropertyDelegateProvider;")?;
    vm.classes[class as usize].is_interface = true;
    vm.classes[class as usize].is_abstract = true;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn reflected_array_allocation_keeps_component_classes_dimensions_and_limits() {
        let mut vm = Vm::new(vec![], Box::new(std::io::sink())).unwrap();
        install(&mut vm).unwrap();
        let component = vm.ensure_class_by_desc("[Ljava/lang/String;").unwrap();
        let component = vm.class_obj(component).unwrap();
        let array = new_array(&mut vm, &[component, JValue::Int(3)]).unwrap();
        assert_eq!(array_length(&mut vm, &[array]).unwrap(), JValue::Int(3));
        let owner = vm.arena.objects[array.as_obj() as usize].class;
        assert_eq!(
            vm.str_of(vm.classes[owner as usize].descriptor),
            "[[Ljava/lang/String;"
        );
        assert!(array_length(&mut vm, &[component]).is_err());
        assert!(array_length(&mut vm, &[JValue::Int(0)]).is_err());
        assert!(new_array(&mut vm, &[component, JValue::Int(-1)]).is_err());
        vm.budget = 1;
        assert!(matches!(
            new_array(&mut vm, &[component, JValue::Int(i32::MAX)]),
            Err(NatErr::Fatal(JvmError::BudgetExceeded))
        ));
    }
    #[test]
    fn public_fields_respect_access_inheritance_and_declaring_class() {
        let mut vm = Vm::new(vec![], Box::new(std::io::sink())).unwrap();
        install(&mut vm).unwrap();
        for name in ["LOwnedBase;", "LOwnedChild;"] {
            vm.register_native(NativeEntry {
                class: name,
                name: "owned",
                sig: "()V",
                instance: true,
                f: super::super::abstract_function,
            })
            .unwrap();
        }
        let base = vm.ensure_class_by_desc("LOwnedBase;").unwrap();
        let child = vm.ensure_class_by_desc("LOwnedChild;").unwrap();
        let ty = vm.intern("I");
        let public = vm.intern("publicBase");
        let private = vm.intern("privateBase");
        let own = vm.intern("publicChild");
        vm.classes[base as usize].instance_fields = vec![(public, ty, 1), (private, ty, 2)];
        vm.classes[child as usize].superclass = Some(base);
        vm.classes[child as usize].instance_fields =
            vec![(public, ty, 1), (private, ty, 2), (own, ty, 1)];
        let value = vm.class_obj(child).unwrap();
        let result = public_fields(&mut vm, &[value]).unwrap();
        let Some(Native::Array(ArrayData::Obj(fields))) = vm.payload_of(result) else {
            panic!("Missing field array")
        };
        assert_eq!(fields.len(), 2);
        let first = field_name(&mut vm, &[fields[0]]).unwrap();
        assert_eq!(vm.str_of_jvalue(first).unwrap(), "publicChild");
        assert_eq!(
            field_modifiers(&mut vm, &[fields[0]]).unwrap(),
            JValue::Int(1)
        );
        let ty = field_type(&mut vm, &[fields[0]]).unwrap();
        assert!(matches!(
            vm.payload_of(ty),
            Some(Native::ClassObj(ClassOrPrim::Primitive(b'I')))
        ));
        let owner = declaring_class(&mut vm, &[fields[1]]).unwrap();
        assert_eq!(class_id(&mut vm, owner).unwrap(), base);
        let declared = declared_fields(&mut vm, &[value]).unwrap();
        let Some(Native::Array(ArrayData::Obj(fields))) = vm.payload_of(declared) else {
            panic!("Missing declared fields")
        };
        assert_eq!(fields.len(), 1);
    }
}
