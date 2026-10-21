//! Reflection is restricted to VM methods. Arguments follow Java unboxing and
//! widening rules; only a guest exception is wrapped in InvocationTargetException.
use dexvm::dex::insn::InvokeKind;
use dexvm::vm::{
    error::JvmError,
    object::{ArrayData, ClassOrPrim, Native},
    MethodRef, NatErr, NativeEntry, Vm,
};
use dexvm::JValue;
use std::collections::HashSet;
type R = Result<JValue, NatErr>;
const METHOD: &str = "Ljava/lang/reflect/Method;";
fn charge(vm: &mut Vm, n: usize) -> Result<(), NatErr> {
    if n > 10_000 || vm.budget <= n as i64 {
        return Err(NatErr::Fatal(JvmError::BudgetExceeded));
    }
    vm.budget -= n as i64;
    Ok(())
}
fn class_id(vm: &mut Vm, value: JValue) -> Result<u32, NatErr> {
    if value.is_null_ref() {
        return Err(NatErr::Throw(vm.err_npe()));
    }
    match vm.payload_of(value) {
        Some(Native::ClassObj(ClassOrPrim::Class(id))) => Ok(id),
        _ => Err(NatErr::Throw(vm.err_iae("Expected reference class"))),
    }
}
fn descriptor(vm: &mut Vm, value: JValue) -> Result<String, NatErr> {
    if value.is_null_ref() {
        return Err(NatErr::Throw(vm.err_npe()));
    }
    match vm.payload_of(value) {
        Some(Native::ClassObj(ClassOrPrim::Class(id))) => {
            Ok(vm.str_of(vm.classes[id as usize].descriptor).into())
        }
        Some(Native::ClassObj(ClassOrPrim::Primitive(c))) => Ok((c as char).to_string()),
        _ => Err(NatErr::Throw(vm.err_iae("Expected class"))),
    }
}
fn array(vm: &mut Vm, value: JValue) -> Result<Vec<JValue>, NatErr> {
    if value.is_null_ref() {
        return Ok(vec![]);
    }
    let Some(Native::Array(ArrayData::Obj(values))) =
        &vm.arena.objects[value.as_obj() as usize].native
    else {
        return Err(NatErr::Throw(vm.err_iae("Expected object array")));
    };
    let n = values.len();
    charge(vm, n)?;
    let Some(Native::Array(ArrayData::Obj(values))) = vm.payload_of(value) else {
        unreachable!()
    };
    Ok(values)
}
fn find(vm: &mut Vm, args: &[JValue], inherited: bool) -> R {
    let owner = class_id(vm, args[0])?;
    let name = vm
        .str_of_jvalue(args[1])
        .ok_or_else(|| NatErr::Throw(vm.err_npe()))?;
    let parameters = array(vm, args[2])?
        .into_iter()
        .map(|value| descriptor(vm, value))
        .collect::<Result<Vec<_>, _>>()?;
    let prefix = format!("({})", parameters.join(""));
    let mut pending = vec![owner];
    let mut seen = HashSet::new();
    while let Some(class) = pending.pop() {
        if !seen.insert(class) {
            continue;
        }
        if seen.len() > 512 {
            return Err(NatErr::Fatal(JvmError::BudgetExceeded));
        }
        charge(vm, vm.classes[class as usize].methods.len() + 1)?;
        // The dispatch table selects the latest app override, avoiding duplicate
        // native registrations masquerading as separate Java overloads.
        let found = vm.classes[class as usize]
            .dispatch
            .values()
            .copied()
            .filter(|slot| {
                let method = &vm.classes[class as usize].methods[*slot as usize];
                vm.str_of(method.name) == name
                    && !name.starts_with('<')
                    && vm.str_of(method.sig).starts_with(&prefix)
                    && (!inherited || method.access_flags & 1 != 0)
            })
            .min();
        if let Some(slot) = found {
            let value = vm
                .alloc_native(METHOD, Native::Opaque)
                .map_err(NatErr::Fatal)?;
            vm.arena.objects[value.as_obj() as usize].fields = vec![
                JValue::Int(class as i32),
                JValue::Int(slot as i32),
                JValue::Int(0),
            ];
            return Ok(value);
        }
        if inherited {
            pending.extend(vm.classes[class as usize].interfaces.iter().rev().copied());
            pending.extend(vm.classes[class as usize].superclass);
        }
    }
    Err(NatErr::Throw(
        vm.throwable_of("Ljava/lang/NoSuchMethodException;", name),
    ))
}
fn declared(vm: &mut Vm, args: &[JValue]) -> R {
    find(vm, args, false)
}
fn public(vm: &mut Vm, args: &[JValue]) -> R {
    find(vm, args, true)
}
fn method(vm: &mut Vm, value: JValue) -> Result<(dexvm::vm::class::Method, bool), NatErr> {
    if value.is_null_ref() {
        return Err(NatErr::Throw(vm.err_npe()));
    }
    let fields = &vm.arena.objects[value.as_obj() as usize].fields;
    if let [class, slot, access] = fields.as_slice() {
        if let Some(method) = vm
            .classes
            .get(class.as_int() as usize)
            .and_then(|c| c.methods.get(slot.as_int() as usize))
        {
            return Ok((method.clone(), !access.is_zero()));
        }
    }
    Err(NatErr::Throw(vm.err_iae("Expected a method")))
}
pub(super) fn unbox(vm: &mut Vm, value: JValue, ty: &str) -> R {
    if ty.starts_with(['L', '[']) {
        if value.is_null_ref() {
            return Ok(value);
        }
        let actual = vm
            .object_class(value)
            .ok_or_else(|| NatErr::Throw(vm.err_iae("Expected reference argument")))?;
        let expected = vm.ensure_class_by_desc(ty).map_err(NatErr::Fatal)?;
        return if vm.is_assignable(actual, expected).map_err(NatErr::Fatal)? {
            Ok(value)
        } else {
            Err(NatErr::Throw(vm.err_iae("Wrong argument class")))
        };
    }
    if value.is_null_ref() {
        return Err(NatErr::Throw(vm.err_iae("Null primitive argument")));
    }
    let payload = vm.payload_of(value);
    let (rank, integer, float) = match payload {
        Some(Native::BoolBox(v)) if ty == "Z" => return Ok(JValue::Int(i32::from(v))),
        Some(Native::ByteBox(v)) => (0, i64::from(v), f64::from(v)),
        Some(Native::ShortBox(v)) => (1, i64::from(v), f64::from(v)),
        Some(Native::CharBox(v)) if matches!(ty, "C" | "I" | "J" | "F" | "D") => {
            (2, i64::from(v), f64::from(v))
        }
        Some(Native::IntBox(v)) => (2, i64::from(v), f64::from(v)),
        Some(Native::LongBox(v)) => (3, v, v as f64),
        Some(Native::FloatBox(v)) => (4, 0, f64::from(v)),
        Some(Native::DoubleBox(v)) => (5, 0, v),
        _ => return Err(NatErr::Throw(vm.err_iae("Invalid primitive argument"))),
    };
    let wanted = match ty {
        "B" => 0,
        "S" => 1,
        "C" if matches!(payload, Some(Native::CharBox(_))) => 2,
        "I" => 2,
        "J" => 3,
        "F" => 4,
        "D" => 5,
        _ => return Err(NatErr::Throw(vm.err_iae("Invalid primitive conversion"))),
    };
    if rank > wanted {
        return Err(NatErr::Throw(vm.err_iae("Narrowing primitive conversion")));
    }
    Ok(match ty {
        "B" | "S" | "C" | "I" => JValue::Int(integer as i32),
        "J" => JValue::Long(integer),
        "F" => JValue::Float(if rank <= 3 {
            integer as f32
        } else {
            float as f32
        }),
        _ => JValue::Double(float),
    })
}
pub(super) fn boxed(vm: &mut Vm, value: JValue, ty: &str) -> R {
    let (class, payload) = match ty {
        "V" => return Ok(JValue::Null),
        "Z" => ("Ljava/lang/Boolean;", Native::BoolBox(!value.is_zero())),
        "B" => ("Ljava/lang/Byte;", Native::ByteBox(value.as_int() as i8)),
        "S" => ("Ljava/lang/Short;", Native::ShortBox(value.as_int() as i16)),
        "C" => (
            "Ljava/lang/Character;",
            Native::CharBox(value.as_int() as u16),
        ),
        "I" => ("Ljava/lang/Integer;", Native::IntBox(value.as_int())),
        "J" => ("Ljava/lang/Long;", Native::LongBox(value.as_long())),
        "F" => (
            "Ljava/lang/Float;",
            Native::FloatBox(match value {
                JValue::Float(v) => v,
                _ => f32::from_bits(value.as_int() as u32),
            }),
        ),
        "D" => (
            "Ljava/lang/Double;",
            Native::DoubleBox(match value {
                JValue::Double(v) => v,
                _ => f64::from_bits(value.as_long() as u64),
            }),
        ),
        _ => return Ok(value),
    };
    vm.alloc_native(class, payload).map_err(NatErr::Fatal)
}
pub(super) fn call(
    vm: &mut Vm,
    method: &dexvm::vm::class::Method,
    receiver: JValue,
    args: Vec<JValue>,
) -> Result<JValue, JvmError> {
    let class = method.class;
    let static_method = method.static_method;
    let private = method.access_flags & 2 != 0;
    if vm.budget <= 0 {
        return Err(JvmError::BudgetExceeded);
    }
    if vm.recursion_depth >= vm.depth_limit {
        return Err(JvmError::StackOverflow);
    }
    vm.budget -= 1;
    vm.recursion_depth += 1;
    let mref = MethodRef {
        class_desc: vm.classes[class as usize].descriptor,
        name: method.name,
        sig: method.sig,
        ret: 0,
        args: vec![],
    };
    let kind = if static_method {
        InvokeKind::Static
    } else if private {
        InvokeKind::Direct
    } else {
        InvokeKind::Virtual
    };
    let result = vm
        .resolve_target(
            kind,
            &mref,
            if static_method {
                None
            } else {
                Some(receiver.as_obj())
            },
            class,
        )
        .and_then(|target| {
            let mut all = vec![];
            if !static_method {
                all.push(receiver);
            }
            all.extend(args);
            vm.call_target(target, all)
        });
    vm.recursion_depth -= 1;
    result
}
fn invoke(vm: &mut Vm, args: &[JValue]) -> R {
    let (m, accessible) = method(vm, args[0])?;
    if !accessible && m.access_flags & 1 == 0 {
        return Err(NatErr::Throw(vm.throwable_of(
            "Ljava/lang/IllegalAccessException;",
            "Method is not public",
        )));
    }
    if !m.static_method {
        let actual = vm
            .object_class(args[1])
            .ok_or_else(|| NatErr::Throw(vm.err_npe()))?;
        if !vm.is_assignable(actual, m.class).map_err(NatErr::Fatal)? {
            return Err(NatErr::Throw(vm.err_iae("Wrong method receiver")));
        }
    }
    let supplied = array(vm, args[2])?;
    if supplied.len() != m.args.len() {
        return Err(NatErr::Throw(vm.err_iae("Wrong method argument count")));
    }
    let values = supplied
        .into_iter()
        .zip(&m.args)
        .map(|(v, ty)| {
            let ty = vm.str_of(*ty).to_owned();
            unbox(vm, v, &ty)
        })
        .collect::<Result<Vec<_>, _>>()?;
    let result = call(vm, &m, args[1], values);
    let value = match result {
        Ok(value) => value,
        Err(JvmError::Uncaught(cause)) => {
            let wrapper = vm
                .alloc_native(
                    "Ljava/lang/reflect/InvocationTargetException;",
                    Native::Throwable {
                        message: None,
                        cause: JValue::Obj(cause),
                    },
                )
                .map_err(NatErr::Fatal)?;
            return Err(NatErr::Throw(wrapper.as_obj()));
        }
        Err(error) => return Err(NatErr::Fatal(error)),
    };
    let ret = vm.str_of(m.ret).to_owned();
    boxed(vm, value, &ret)
}
fn set_accessible(vm: &mut Vm, args: &[JValue]) -> R {
    method(vm, args[0])?;
    vm.arena.objects[args[0].as_obj() as usize].fields[2] = args[1];
    Ok(JValue::Null)
}
fn get_name(vm: &mut Vm, args: &[JValue]) -> R {
    let (m, _) = method(vm, args[0])?;
    let name = vm.str_of(m.name).to_owned();
    Ok(vm.alloc_string(&name))
}
fn get_owner(vm: &mut Vm, args: &[JValue]) -> R {
    let (m, _) = method(vm, args[0])?;
    vm.class_obj(m.class).map_err(NatErr::Fatal)
}
fn get_modifiers(vm: &mut Vm, args: &[JValue]) -> R {
    let (m, _) = method(vm, args[0])?;
    Ok(JValue::Int(m.access_flags as i32))
}
fn class_object(vm: &mut Vm, desc: &str) -> R {
    if desc.len() == 1 {
        vm.alloc_native(
            "Ljava/lang/Class;",
            Native::ClassObj(ClassOrPrim::Primitive(desc.as_bytes()[0])),
        )
        .map_err(NatErr::Fatal)
    } else {
        let class = vm.ensure_class_by_desc(desc).map_err(NatErr::Fatal)?;
        vm.class_obj(class).map_err(NatErr::Fatal)
    }
}
fn get_return(vm: &mut Vm, args: &[JValue]) -> R {
    let (m, _) = method(vm, args[0])?;
    let desc = vm.str_of(m.ret).to_owned();
    class_object(vm, &desc)
}
fn get_parameters(vm: &mut Vm, args: &[JValue]) -> R {
    let (m, _) = method(vm, args[0])?;
    charge(vm, m.args.len())?;
    let values = m
        .args
        .iter()
        .map(|ty| {
            let desc = vm.str_of(*ty).to_owned();
            class_object(vm, &desc)
        })
        .collect::<Result<Vec<_>, _>>()?;
    vm.alloc_native("[Ljava/lang/Class;", Native::Array(ArrayData::Obj(values)))
        .map_err(NatErr::Fatal)
}
fn cause(vm: &mut Vm, args: &[JValue]) -> R {
    match vm.payload_of(args[0]) {
        Some(Native::Throwable { cause, .. }) => Ok(cause),
        _ => Err(NatErr::Throw(vm.err_npe())),
    }
}
pub(super) fn install(vm: &mut Vm) -> Result<(), JvmError> {
    for (class, name, sig, f) in [
        (
            "Ljava/lang/Class;",
            "getDeclaredMethod",
            "(Ljava/lang/String;[Ljava/lang/Class;)Ljava/lang/reflect/Method;",
            declared as dexvm::vm::NativeFn,
        ),
        (
            "Ljava/lang/Class;",
            "getMethod",
            "(Ljava/lang/String;[Ljava/lang/Class;)Ljava/lang/reflect/Method;",
            public,
        ),
        (
            METHOD,
            "invoke",
            "(Ljava/lang/Object;[Ljava/lang/Object;)Ljava/lang/Object;",
            invoke,
        ),
        (METHOD, "setAccessible", "(Z)V", set_accessible),
        (METHOD, "getName", "()Ljava/lang/String;", get_name),
        (
            METHOD,
            "getDeclaringClass",
            "()Ljava/lang/Class;",
            get_owner,
        ),
        (METHOD, "getModifiers", "()I", get_modifiers),
        (METHOD, "getReturnType", "()Ljava/lang/Class;", get_return),
        (
            METHOD,
            "getParameterTypes",
            "()[Ljava/lang/Class;",
            get_parameters,
        ),
        (
            "Ljava/lang/reflect/InvocationTargetException;",
            "getTargetException",
            "()Ljava/lang/Throwable;",
            cause,
        ),
        (
            "Ljava/lang/reflect/InvocationTargetException;",
            "getCause",
            "()Ljava/lang/Throwable;",
            cause,
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
    let exception = vm.ensure_class_by_desc("Ljava/lang/reflect/InvocationTargetException;")?;
    vm.classes[exception as usize].superclass =
        Some(vm.ensure_class_by_desc("Ljava/lang/Exception;")?);
    Ok(())
}
#[cfg(test)]
mod tests {
    use super::*;
    fn exhausted(_vm: &mut Vm, _args: &[JValue]) -> R {
        Err(NatErr::Fatal(JvmError::BudgetExceeded))
    }
    #[test]
    fn reflection_rejects_bad_arguments_and_keeps_execution_limits_fatal() {
        let mut vm = Vm::new(vec![], Box::new(std::io::sink())).unwrap();
        install(&mut vm).unwrap();
        vm.register_native(NativeEntry {
            class: "Lapp/ReflectionLimit;",
            name: "exhausted",
            sig: "()Ljava/lang/Object;",
            instance: false,
            f: exhausted,
        })
        .unwrap();
        let class = vm.ensure_class_by_desc("Lapp/ReflectionLimit;").unwrap();
        let owner = vm.class_obj(class).unwrap();
        let name = vm.alloc_string("exhausted");
        let method = declared(&mut vm, &[owner, name, JValue::Null]).unwrap();
        assert!(matches!(
            invoke(&mut vm, &[method, JValue::Null, JValue::Null]),
            Err(NatErr::Fatal(JvmError::BudgetExceeded))
        ));
        let one = vm
            .alloc_native(
                "[Ljava/lang/Object;",
                Native::Array(ArrayData::Obj(vec![name])),
            )
            .unwrap();
        assert!(matches!(
            invoke(&mut vm, &[method, JValue::Null, one]),
            Err(NatErr::Throw(_))
        ));
        let double = vm
            .alloc_native("Ljava/lang/Double;", Native::DoubleBox(2.0))
            .unwrap();
        assert!(matches!(unbox(&mut vm, double, "I"), Err(NatErr::Throw(_))));
        assert!(matches!(
            unbox(&mut vm, JValue::Null, "I"),
            Err(NatErr::Throw(_))
        ));
        vm.gc(&[method.as_obj(), name.as_obj()]);
        assert_eq!(get_modifiers(&mut vm, &[method]).unwrap(), JValue::Int(9));
        vm.budget = 0;
        assert!(matches!(
            declared(&mut vm, &[owner, name, JValue::Null]),
            Err(NatErr::Fatal(JvmError::BudgetExceeded))
        ));
    }
}
