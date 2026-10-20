//! Reflection stays inside the interpreted package. Enumerate real fields,
//! respecting public access and inheritance; never synthesize DTO properties.
use dexvm::vm::object::{ArrayData, ClassOrPrim, Native};
use dexvm::vm::{error::JvmError, NatErr, NativeEntry, Vm};
use dexvm::JValue;
use std::collections::HashSet;

type R = Result<JValue, NatErr>;
fn class_id(vm: &mut Vm, value: JValue) -> Result<u32, NatErr> {
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
pub(super) fn install(vm: &mut Vm) -> Result<(), JvmError> {
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
        let owner = declaring_class(&mut vm, &[fields[1]]).unwrap();
        assert_eq!(class_id(&mut vm, owner).unwrap(), base);
        let declared = declared_fields(&mut vm, &[value]).unwrap();
        let Some(Native::Array(ArrayData::Obj(fields))) = vm.payload_of(declared) else {
            panic!("Missing declared fields")
        };
        assert_eq!(fields.len(), 1);
    }
}
