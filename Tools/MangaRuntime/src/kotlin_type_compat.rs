//! Kotlin's lightweight JVM type tokens, not arbitrary runtime reflection.
//! Keep classifier, generic projections and nullability as GC-traced fields.
use dexvm::vm::class::{Class, ACC_ABSTRACT, ACC_INTERFACE, ACC_PUBLIC};
use dexvm::vm::error::JvmError;
use dexvm::vm::object::{ArrayData, ClassOrPrim, Native};
use dexvm::vm::{NatErr, NativeEntry, Vm};
use dexvm::JValue;

type R = Result<JValue, NatErr>;
const CLASS: &str = "Lkotlin/jvm/internal/ClassReference;";
const TYPE: &str = "Lkotlin/jvm/internal/TypeReference;";
const PROJECTION: &str = "Lkotlin/reflect/KTypeProjection;";
const VARIANCE: &str = "Lkotlin/reflect/KVariance;";

fn invalid(vm: &mut Vm, message: &str) -> NatErr {
    NatErr::Throw(vm.err_iae(message))
}
fn fields(vm: &mut Vm, value: JValue, class: &str) -> Result<Vec<JValue>, NatErr> {
    let JValue::Obj(object) = value else {
        return Err(NatErr::Throw(vm.err_npe()));
    };
    let object = &vm.arena.objects[object as usize];
    if vm.str_of(vm.classes[object.class as usize].descriptor) != class {
        return Err(invalid(vm, "Unexpected Kotlin type token"));
    }
    Ok(object.fields.clone())
}
fn object(vm: &mut Vm, class: &str, fields: Vec<JValue>) -> R {
    let value = vm
        .alloc_native(class, Native::Opaque)
        .map_err(NatErr::Fatal)?;
    vm.arena.objects[value.as_obj() as usize].fields = fields;
    Ok(value)
}
fn kotlin_class(vm: &mut Vm, args: &[JValue]) -> R {
    let Some(Native::ClassObj(class)) = vm.payload_of(args[0]) else {
        return Err(invalid(vm, "Expected a Java Class"));
    };
    // The core module registry compares class tokens by identity. Cache on the
    // VM's rooted Java Class object, never in an untraced process-global map.
    for value in &vm.arena.objects[args[0].as_obj() as usize].fields {
        if let JValue::Obj(id) = value {
            if vm.str_of(vm.classes[vm.arena.objects[*id as usize].class as usize].descriptor)
                == CLASS
            {
                return Ok(*value);
            }
        }
    }
    // Retain the raw Class as a field for JVM mapping; equality is by class,
    // never by the identity of newly allocated Kotlin wrappers.
    let value = vm
        .alloc_native(CLASS, Native::ClassObj(class))
        .map_err(NatErr::Fatal)?;
    vm.arena.objects[value.as_obj() as usize].fields = vec![args[0]];
    vm.arena.objects[args[0].as_obj() as usize]
        .fields
        .push(value);
    Ok(value)
}
fn normalized_class(vm: &Vm, value: JValue) -> Option<ClassOrPrim> {
    let Native::ClassObj(class) = vm.payload_of(value)? else {
        return None;
    };
    Some(match class {
        ClassOrPrim::Class(id) => match vm.str_of(vm.classes[id as usize].descriptor) {
            "Ljava/lang/Boolean;" => ClassOrPrim::Primitive(b'Z'),
            "Ljava/lang/Byte;" => ClassOrPrim::Primitive(b'B'),
            "Ljava/lang/Character;" => ClassOrPrim::Primitive(b'C'),
            "Ljava/lang/Short;" => ClassOrPrim::Primitive(b'S'),
            "Ljava/lang/Integer;" => ClassOrPrim::Primitive(b'I'),
            "Ljava/lang/Long;" => ClassOrPrim::Primitive(b'J'),
            "Ljava/lang/Float;" => ClassOrPrim::Primitive(b'F'),
            "Ljava/lang/Double;" => ClassOrPrim::Primitive(b'D'),
            "Ljava/lang/Void;" => ClassOrPrim::Primitive(b'V'),
            _ => class,
        },
        _ => class,
    })
}
fn class_equals(vm: &mut Vm, args: &[JValue]) -> R {
    let is_class = |value: JValue| matches!(value, JValue::Obj(id) if vm.str_of(vm.classes[vm.arena.objects[id as usize].class as usize].descriptor) == CLASS);
    Ok(JValue::Int(i32::from(
        is_class(args[1]) && normalized_class(vm, args[0]) == normalized_class(vm, args[1]),
    )))
}
fn class_hash(vm: &mut Vm, args: &[JValue]) -> R {
    let value = match normalized_class(vm, args[0]) {
        Some(ClassOrPrim::Class(id)) => id as i32,
        Some(ClassOrPrim::Primitive(code)) => -(i32::from(code)),
        None => return Err(invalid(vm, "Invalid KClass")),
    };
    Ok(JValue::Int(value))
}
fn java_class(vm: &mut Vm, args: &[JValue]) -> R {
    let fields = fields(vm, args[0], CLASS)?;
    fields
        .first()
        .copied()
        .ok_or_else(|| invalid(vm, "Missing Java Class"))
}
fn java_object_type(vm: &mut Vm, args: &[JValue]) -> R {
    let raw = java_class(vm, args)?;
    let desc = match vm.payload_of(raw) {
        Some(Native::ClassObj(ClassOrPrim::Primitive(code))) => match code {
            b'Z' => "Ljava/lang/Boolean;",
            b'B' => "Ljava/lang/Byte;",
            b'C' => "Ljava/lang/Character;",
            b'S' => "Ljava/lang/Short;",
            b'I' => "Ljava/lang/Integer;",
            b'J' => "Ljava/lang/Long;",
            b'F' => "Ljava/lang/Float;",
            b'D' => "Ljava/lang/Double;",
            b'V' => "Ljava/lang/Void;",
            _ => return Err(invalid(vm, "Invalid primitive Class")),
        },
        _ => return Ok(raw),
    };
    let class = vm.ensure_class_by_desc(desc).map_err(NatErr::Fatal)?;
    vm.class_obj(class).map_err(NatErr::Fatal)
}
fn make_type(vm: &mut Vm, args: &[JValue], nullable: bool) -> R {
    let classifier = kotlin_class(vm, &args[..1])?;
    let arguments = if args.len() == 2 {
        match vm.payload_of(args[1]) {
            Some(Native::Array(ArrayData::Obj(values))) => values,
            _ => vec![args[1]],
        }
    } else {
        args[1..].to_vec()
    };
    if arguments.len() > 256 {
        return Err(NatErr::Fatal(JvmError::BudgetExceeded));
    }
    for argument in &arguments {
        if fields(vm, *argument, PROJECTION)?.len() != 2 {
            return Err(invalid(vm, "Invalid type projection"));
        }
    }
    let arguments = vm
        .alloc_native("Ljava/util/ArrayList;", Native::List(arguments))
        .map_err(NatErr::Fatal)?;
    object(
        vm,
        TYPE,
        vec![classifier, arguments, JValue::Int(i32::from(nullable))],
    )
}
fn type_of(vm: &mut Vm, args: &[JValue]) -> R {
    make_type(vm, args, false)
}
fn nullable_type_of(vm: &mut Vm, args: &[JValue]) -> R {
    make_type(vm, args, true)
}
fn classifier(vm: &mut Vm, args: &[JValue]) -> R {
    Ok(fields(vm, args[0], TYPE)?[0])
}
fn arguments(vm: &mut Vm, args: &[JValue]) -> R {
    Ok(fields(vm, args[0], TYPE)?[1])
}
fn nullable(vm: &mut Vm, args: &[JValue]) -> R {
    Ok(fields(vm, args[0], TYPE)?[2])
}
fn projection(vm: &mut Vm, args: &[JValue], variance: &str) -> R {
    fields(vm, args[1], TYPE)?;
    let field = dexvm::vm::FieldRef {
        class_desc: vm.intern(VARIANCE),
        name: vm.intern(variance),
        ty: vm.intern(VARIANCE),
    };
    let variance = vm.static_field_get(field).map_err(NatErr::Fatal)?;
    object(vm, PROJECTION, vec![variance, args[1]])
}
fn invariant(vm: &mut Vm, args: &[JValue]) -> R {
    projection(vm, args, "INVARIANT")
}
fn contravariant(vm: &mut Vm, args: &[JValue]) -> R {
    projection(vm, args, "IN")
}
fn covariant(vm: &mut Vm, args: &[JValue]) -> R {
    projection(vm, args, "OUT")
}
fn projection_type(vm: &mut Vm, args: &[JValue]) -> R {
    Ok(fields(vm, args[0], PROJECTION)?[1])
}
fn projection_variance(vm: &mut Vm, args: &[JValue]) -> R {
    Ok(fields(vm, args[0], PROJECTION)?[0])
}

fn token_equal(vm: &mut Vm, a: JValue, b: JValue, depth: usize) -> Result<bool, NatErr> {
    if depth > 64 || vm.budget <= 0 {
        return Err(NatErr::Fatal(JvmError::BudgetExceeded));
    }
    vm.budget -= 1;
    if a == b {
        return Ok(true);
    }
    let (JValue::Obj(a_id), JValue::Obj(b_id)) = (a, b) else {
        return Ok(false);
    };
    let a_class = vm.arena.objects[a_id as usize].class;
    if a_class != vm.arena.objects[b_id as usize].class {
        return Ok(false);
    }
    let desc = vm
        .str_of(vm.classes[a_class as usize].descriptor)
        .to_owned();
    if desc == CLASS {
        return Ok(normalized_class(vm, a) == normalized_class(vm, b));
    }
    if desc != TYPE && desc != PROJECTION {
        return Ok(false);
    }
    let af = fields(vm, a, &desc)?;
    let bf = fields(vm, b, &desc)?;
    if af.len() != bf.len() {
        return Ok(false);
    }
    for (a, b) in af.into_iter().zip(bf) {
        let payload = |v| {
            if matches!(v, JValue::Obj(_)) {
                vm.payload_of(v)
            } else {
                None
            }
        };
        match (payload(a), payload(b)) {
            (Some(Native::List(a)), Some(Native::List(b))) => {
                if a.len() != b.len() {
                    return Ok(false);
                }
                for (a, b) in a.into_iter().zip(b) {
                    if !token_equal(vm, a, b, depth + 1)? {
                        return Ok(false);
                    }
                }
            }
            _ => {
                if !token_equal(vm, a, b, depth + 1)? {
                    return Ok(false);
                }
            }
        }
    }
    Ok(true)
}
fn token_equals(vm: &mut Vm, args: &[JValue]) -> R {
    Ok(JValue::Int(i32::from(token_equal(
        vm, args[0], args[1], 0,
    )?)))
}
fn token_hash_inner(vm: &mut Vm, value: JValue, depth: usize) -> Result<i32, NatErr> {
    if depth > 64 || vm.budget <= 0 {
        return Err(NatErr::Fatal(JvmError::BudgetExceeded));
    }
    vm.budget -= 1;
    match value {
        JValue::Null => return Ok(0),
        JValue::Int(v) => return Ok(v),
        _ => {}
    }
    let JValue::Obj(id) = value else {
        return Err(invalid(vm, "Invalid Kotlin token"));
    };
    let desc = vm
        .str_of(vm.classes[vm.arena.objects[id as usize].class as usize].descriptor)
        .to_owned();
    if desc == CLASS {
        return Ok(class_hash(vm, &[value])?.as_int());
    }
    let parts = match vm.payload_of(value) {
        Some(Native::List(v)) => v,
        _ if desc == TYPE || desc == PROJECTION => fields(vm, value, &desc)?,
        _ => return Ok(id as i32),
    };
    let mut hash = 1_i32;
    for part in parts {
        hash = hash
            .wrapping_mul(31)
            .wrapping_add(token_hash_inner(vm, part, depth + 1)?);
    }
    Ok(hash)
}
fn token_hash(vm: &mut Vm, args: &[JValue]) -> R {
    Ok(JValue::Int(token_hash_inner(vm, args[0], 0)?))
}

// A marker has no callable methods. Register the actual interface, not a
// fabricated method which could accidentally make unsupported reflection work.
pub(super) fn marker(vm: &mut Vm, desc: &str) -> u32 {
    let descriptor = vm.intern(desc);
    if let Some(id) = vm.class_by_desc.get(&descriptor) {
        return *id;
    }
    let id = vm.classes.len() as u32;
    vm.classes.push(Class {
        id,
        descriptor,
        access_flags: ACC_PUBLIC | ACC_INTERFACE | ACC_ABSTRACT,
        is_interface: true,
        is_abstract: true,
        ..Default::default()
    });
    vm.class_by_desc.insert(descriptor, id);
    id
}
fn singleton(
    vm: &mut Vm,
    owner: &str,
    name: &str,
    ty: &str,
    value: JValue,
) -> Result<(), JvmError> {
    let id = vm.ensure_class_by_desc(owner)?;
    let key = (vm.intern(name), vm.intern(ty));
    let class = &mut vm.classes[id as usize];
    if !class.static_fields.contains_key(&key) {
        let offset = class.statics.len() as u32;
        class.statics.push(value);
        class.statics_lazy.push(None);
        class.static_fields.insert(key, (id, offset));
    }
    Ok(())
}
fn variance_name(vm: &mut Vm, args: &[JValue]) -> R {
    match vm.payload_of(args[0]) {
        Some(Native::Enum { name, .. }) => Ok(vm.alloc_string(&name)),
        _ => Err(invalid(vm, "Invalid variance")),
    }
}
pub(super) fn install(vm: &mut Vm) -> Result<(), JvmError> {
    for (class, name, sig, instance, f) in [
        (
            "Lkotlin/jvm/internal/Reflection;",
            "getOrCreateKotlinClass",
            "(Ljava/lang/Class;)Lkotlin/reflect/KClass;",
            false,
            kotlin_class as dexvm::vm::NativeFn,
        ),
        (CLASS, "equals", "(Ljava/lang/Object;)Z", true, class_equals),
        (CLASS, "hashCode", "()I", true, class_hash),
        (CLASS, "getJClass", "()Ljava/lang/Class;", true, java_class),
        (
            "Lkotlin/jvm/JvmClassMappingKt;",
            "getJavaClass",
            "(Lkotlin/reflect/KClass;)Ljava/lang/Class;",
            false,
            java_class,
        ),
        (
            "Lkotlin/jvm/JvmClassMappingKt;",
            "getJavaObjectType",
            "(Lkotlin/reflect/KClass;)Ljava/lang/Class;",
            false,
            java_object_type,
        ),
        (
            "Lkotlin/reflect/KType;",
            "getClassifier",
            "()Lkotlin/reflect/KClassifier;",
            true,
            classifier,
        ),
        (
            "Lkotlin/reflect/KType;",
            "getArguments",
            "()Ljava/util/List;",
            true,
            arguments,
        ),
        (
            "Lkotlin/reflect/KType;",
            "isMarkedNullable",
            "()Z",
            true,
            nullable,
        ),
        (
            TYPE,
            "getClassifier",
            "()Lkotlin/reflect/KClassifier;",
            true,
            classifier,
        ),
        (TYPE, "getArguments", "()Ljava/util/List;", true, arguments),
        (TYPE, "isMarkedNullable", "()Z", true, nullable),
        (TYPE, "equals", "(Ljava/lang/Object;)Z", true, token_equals),
        (TYPE, "hashCode", "()I", true, token_hash),
        (
            PROJECTION,
            "equals",
            "(Ljava/lang/Object;)Z",
            true,
            token_equals,
        ),
        (PROJECTION, "hashCode", "()I", true, token_hash),
        (
            PROJECTION,
            "getType",
            "()Lkotlin/reflect/KType;",
            true,
            projection_type,
        ),
        (
            PROJECTION,
            "getVariance",
            "()Lkotlin/reflect/KVariance;",
            true,
            projection_variance,
        ),
        (
            PROJECTION,
            "component1",
            "()Lkotlin/reflect/KVariance;",
            true,
            projection_variance,
        ),
        (
            PROJECTION,
            "component2",
            "()Lkotlin/reflect/KType;",
            true,
            projection_type,
        ),
        (
            "Lkotlin/reflect/KTypeProjection$Companion;",
            "invariant",
            "(Lkotlin/reflect/KType;)Lkotlin/reflect/KTypeProjection;",
            true,
            invariant,
        ),
        (
            "Lkotlin/reflect/KTypeProjection$Companion;",
            "contravariant",
            "(Lkotlin/reflect/KType;)Lkotlin/reflect/KTypeProjection;",
            true,
            contravariant,
        ),
        (
            "Lkotlin/reflect/KTypeProjection$Companion;",
            "covariant",
            "(Lkotlin/reflect/KType;)Lkotlin/reflect/KTypeProjection;",
            true,
            covariant,
        ),
        (
            VARIANCE,
            "name",
            "()Ljava/lang/String;",
            true,
            variance_name,
        ),
    ] {
        vm.register_native(NativeEntry {
            class,
            name,
            sig,
            instance,
            f,
        })?;
    }
    for (name, f) in [
        ("typeOf", type_of as dexvm::vm::NativeFn),
        ("nullableTypeOf", nullable_type_of),
    ] {
        for sig in ["(Ljava/lang/Class;)Lkotlin/reflect/KType;", "(Ljava/lang/Class;Lkotlin/reflect/KTypeProjection;)Lkotlin/reflect/KType;", "(Ljava/lang/Class;Lkotlin/reflect/KTypeProjection;Lkotlin/reflect/KTypeProjection;)Lkotlin/reflect/KType;", "(Ljava/lang/Class;[Lkotlin/reflect/KTypeProjection;)Lkotlin/reflect/KType;"] {
            vm.register_native(NativeEntry { class:"Lkotlin/jvm/internal/Reflection;",name,sig,instance:false,f })?;
        }
    }
    let classifier = marker(vm, "Lkotlin/reflect/KClassifier;");
    let kclass = vm.ensure_class_by_desc("Lkotlin/reflect/KClass;")?;
    if !vm.classes[kclass as usize].interfaces.contains(&classifier) {
        vm.classes[kclass as usize].interfaces.push(classifier);
    }
    for (class, interface) in [
        (CLASS, kclass),
        (TYPE, vm.ensure_class_by_desc("Lkotlin/reflect/KType;")?),
    ] {
        let id = vm.ensure_class_by_desc(class)?;
        if !vm.classes[id as usize].interfaces.contains(&interface) {
            vm.classes[id as usize].interfaces.push(interface);
        }
    }
    let variance_class = vm.ensure_class_by_desc(VARIANCE)?;
    vm.classes[variance_class as usize].superclass =
        Some(vm.ensure_class_by_desc("Ljava/lang/Enum;")?);
    for (ordinal, name) in ["INVARIANT", "IN", "OUT"].into_iter().enumerate() {
        let value = vm.alloc_native(
            VARIANCE,
            Native::Enum {
                name: name.into(),
                ordinal: ordinal as i32,
            },
        )?;
        singleton(vm, VARIANCE, name, VARIANCE, value)?;
    }
    let companion_class = "Lkotlin/reflect/KTypeProjection$Companion;";
    let companion = vm.alloc_native(companion_class, Native::Opaque)?;
    singleton(vm, PROJECTION, "Companion", companion_class, companion)?;
    let star = object(vm, PROJECTION, vec![JValue::Null, JValue::Null]).map_err(|e| match e {
        NatErr::Fatal(e) => e,
        NatErr::Throw(o) => JvmError::Uncaught(o),
    })?;
    singleton(vm, PROJECTION, "STAR", PROJECTION, star)?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn types_preserve_classifiers_projections_nullability_and_gc_roots() {
        let mut vm = Vm::new(vec![], Box::new(std::io::sink())).unwrap();
        install(&mut vm).unwrap();
        let string = vm.ensure_class_by_desc("Ljava/lang/String;").unwrap();
        let string = vm.class_obj(string).unwrap();
        let child = nullable_type_of(&mut vm, &[string]).unwrap();
        let projection = invariant(&mut vm, &[JValue::Null, child]).unwrap();
        let list = vm.ensure_class_by_desc("Ljava/util/List;").unwrap();
        let list = vm.class_obj(list).unwrap();
        let parent = type_of(&mut vm, &[list, projection]).unwrap();
        let same_child = nullable_type_of(&mut vm, &[string]).unwrap();
        let same_projection = invariant(&mut vm, &[JValue::Null, same_child]).unwrap();
        let same_parent = type_of(&mut vm, &[list, same_projection]).unwrap();
        assert_eq!(
            token_equals(&mut vm, &[parent, same_parent]).unwrap(),
            JValue::Int(1)
        );
        assert_eq!(
            token_hash(&mut vm, &[parent]).unwrap(),
            token_hash(&mut vm, &[same_parent]).unwrap()
        );
        assert_ne!(parent, list);
        assert_ne!(projection, child);
        let a = classifier(&mut vm, &[parent]).unwrap();
        let b = kotlin_class(&mut vm, &[list]).unwrap();
        assert_eq!(class_equals(&mut vm, &[a, b]).unwrap(), JValue::Int(1));
        assert_eq!(class_equals(&mut vm, &[a, list]).unwrap(), JValue::Int(0));
        assert_eq!(
            class_hash(&mut vm, &[a]).unwrap(),
            class_hash(&mut vm, &[b]).unwrap()
        );
        vm.gc(&[parent.as_obj()]);
        let args = arguments(&mut vm, &[parent]).unwrap();
        assert!(matches!(vm.payload_of(args), Some(Native::List(v)) if v == vec![projection]));
        let nested = projection_type(&mut vm, &[projection]).unwrap();
        assert_eq!(nullable(&mut vm, &[nested]).unwrap(), JValue::Int(1));
        assert_eq!(nullable(&mut vm, &[parent]).unwrap(), JValue::Int(0));
        let a = classifier(&mut vm, &[nested]).unwrap();
        assert_eq!(java_class(&mut vm, &[a]).unwrap(), string);
    }
}
