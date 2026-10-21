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
pub(super) fn install(vm: &mut Vm) -> Result<(), JvmError> {
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
