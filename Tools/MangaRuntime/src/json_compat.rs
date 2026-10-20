//! Nullable kotlinx JSON builders. Website requests remain guest bytecode.
use dexvm::vm::error::JvmError;
use dexvm::vm::object::{JsonVal, Native};
use dexvm::vm::{NatErr, NativeEntry, Vm};
use dexvm::JValue;

type R = Result<JValue, NatErr>;
const ELEMENT: &str = "Lkotlinx/serialization/json/JsonElementKt;";
const BUILDERS: &str = "Lkotlinx/serialization/json/JsonElementBuildersKt;";
const NULL: &str = "Lkotlinx/serialization/json/JsonNull;";

fn thrown(error: JvmError) -> NatErr {
    match error {
        JvmError::Uncaught(object) => NatErr::Throw(object),
        other => NatErr::Fatal(other),
    }
}
fn invalid(vm: &mut Vm, message: &str) -> NatErr {
    NatErr::Throw(vm.throwable_of("Ljava/lang/IllegalArgumentException;", message))
}
pub(super) fn node(vm: &mut Vm, value: JsonVal) -> R {
    if matches!(value, JsonVal::Null) {
        let field = dexvm::vm::FieldRef {
            class_desc: vm.intern(NULL),
            name: vm.intern("INSTANCE"),
            ty: vm.intern(NULL),
        };
        return vm.static_field_get(field).map_err(thrown);
    }
    let class = match value {
        JsonVal::Array(_) => "Lkotlinx/serialization/json/JsonArray;",
        JsonVal::Object(_) => "Lkotlinx/serialization/json/JsonObject;",
        _ => "Lkotlinx/serialization/json/JsonPrimitive;",
    };
    vm.alloc_native(class, Native::Json(value)).map_err(thrown)
}
fn string(vm: &mut Vm, args: &[JValue]) -> R {
    let value = if args[0].is_null_ref() {
        JsonVal::Null
    } else {
        JsonVal::Str(
            vm.str_of_jvalue(args[0])
                .ok_or_else(|| invalid(vm, "Expected a string"))?,
        )
    };
    node(vm, value)
}
fn array_init(vm: &mut Vm, args: &[JValue]) -> R {
    let values = match vm.payload_of(args[1]) {
        Some(Native::Json(JsonVal::Array(values))) => values,
        Some(Native::List(items)) => items
            .into_iter()
            .map(|value| match vm.payload_of(value) {
                Some(Native::Json(value)) => Ok(value),
                _ => Err(invalid(vm, "JsonArray items must be JsonElements")),
            })
            .collect::<Result<Vec<_>, _>>()?,
        _ => return Err(invalid(vm, "JsonArray requires a list")),
    };
    if values.len() > 100_000 {
        return Err(NatErr::Fatal(JvmError::BudgetExceeded));
    }
    vm.budget -= values.len() as i64;
    if vm.budget <= 0 {
        return Err(NatErr::Fatal(JvmError::BudgetExceeded));
    }
    let JValue::Obj(object) = args[0] else {
        return Err(NatErr::Throw(vm.err_npe()));
    };
    vm.arena.objects[object as usize].native = Some(Native::Json(JsonVal::Array(values)));
    Ok(JValue::Null)
}
fn number(vm: &mut Vm, args: &[JValue]) -> R {
    let value = if args[0].is_null_ref() {
        JsonVal::Null
    } else {
        match vm.payload_of(args[0]) {
            Some(Native::IntBox(n)) => JsonVal::Int(i64::from(n)),
            Some(Native::LongBox(n)) => JsonVal::Int(n),
            // Kotlin JsonPrimitive(Number) uses Number.toString(). Widening
            // the binary float directly changes 1.1 into 1.100000023841858,
            // which can select a different chapter in an exact-match API.
            Some(Native::FloatBox(n)) => JsonVal::Double(
                n.to_string()
                    .parse()
                    .map_err(|_| invalid(vm, "Invalid JSON float"))?,
            ),
            Some(Native::DoubleBox(n)) => JsonVal::Double(n),
            _ => return Err(invalid(vm, "Unsupported JSON number")),
        }
    };
    node(vm, value)
}
fn boolean(vm: &mut Vm, args: &[JValue]) -> R {
    let value = if args[0].is_null_ref() {
        JsonVal::Null
    } else if let Some(Native::BoolBox(value)) = vm.payload_of(args[0]) {
        JsonVal::Bool(value)
    } else {
        return Err(invalid(vm, "Expected a boxed boolean"));
    };
    node(vm, value)
}
fn null(vm: &mut Vm, _: &[JValue]) -> R {
    node(vm, JsonVal::Null)
}
fn put(vm: &mut Vm, args: &[JValue], primitive: dexvm::vm::NativeFn) -> R {
    let value = primitive(vm, &args[2..3])?;
    vm.invoke_virtual_args(args[0], "put", "(Ljava/lang/String;Lkotlinx/serialization/json/JsonElement;)Lkotlinx/serialization/json/JsonElement;", vec![args[1], value]).map_err(thrown)
}
fn put_string(vm: &mut Vm, args: &[JValue]) -> R {
    put(vm, args, string)
}
fn put_number(vm: &mut Vm, args: &[JValue]) -> R {
    put(vm, args, number)
}
fn put_boolean(vm: &mut Vm, args: &[JValue]) -> R {
    put(vm, args, boolean)
}
fn put_null(vm: &mut Vm, args: &[JValue]) -> R {
    put(vm, args, null)
}
fn add(vm: &mut Vm, args: &[JValue], primitive: dexvm::vm::NativeFn) -> R {
    let value = primitive(vm, &args[1..2])?;
    vm.invoke_virtual_args(
        args[0],
        "add",
        "(Lkotlinx/serialization/json/JsonElement;)Z",
        vec![value],
    )
    .map_err(thrown)
}
fn add_string(vm: &mut Vm, args: &[JValue]) -> R {
    add(vm, args, string)
}
fn add_number(vm: &mut Vm, args: &[JValue]) -> R {
    add(vm, args, number)
}
fn add_boolean(vm: &mut Vm, args: &[JValue]) -> R {
    add(vm, args, boolean)
}
fn add_null(vm: &mut Vm, args: &[JValue]) -> R {
    add(vm, args, null)
}
fn primitive(vm: &mut Vm, args: &[JValue]) -> R {
    match vm.payload_of(args[0]) {
        Some(Native::Json(JsonVal::Object(_) | JsonVal::Array(_))) | None => {
            Err(invalid(vm, "Expected a JSON primitive"))
        }
        Some(Native::Json(_)) => Ok(args[0]),
        _ => Err(invalid(vm, "Expected a JSON primitive")),
    }
}
fn content(vm: &mut Vm, args: &[JValue]) -> R {
    let text = match vm.payload_of(args[0]) {
        Some(Native::Json(JsonVal::Null)) => "null".into(),
        Some(Native::Json(JsonVal::Str(s))) => s,
        Some(Native::Json(JsonVal::Int(n))) => n.to_string(),
        Some(Native::Json(JsonVal::Double(n))) => n.to_string(),
        Some(Native::Json(JsonVal::Bool(b))) => b.to_string(),
        _ => return Err(invalid(vm, "Expected a JSON primitive")),
    };
    Ok(vm.alloc_string(&text))
}

fn element_deserialize(vm: &mut Vm, args: &[JValue]) -> R {
    if !matches!(vm.payload_of(args[0]), Some(Native::JsonElementSerializer)) {
        return super::abstract_function(vm, args);
    }
    match vm.payload_of(args[1]) {
        Some(Native::JsonDecoder { element, .. }) => Ok(element),
        _ => Err(invalid(vm, "JsonElement requires a JSON decoder")),
    }
}

// Model constructors in the pinned core leave these non-null Kotlin properties
// unset. Initialize on first access, including models reconstructed by the host.
fn model_memo(vm: &mut Vm, args: &[JValue]) -> R {
    let memo = match vm.payload_of(args[0]) {
        Some(Native::SManga { memo, .. } | Native::SChapter { memo, .. }) => memo,
        _ => return Err(invalid(vm, "Expected a source model")),
    };
    if !memo.is_null_ref() {
        return Ok(memo);
    }
    let value = node(vm, JsonVal::Object(Vec::new()))?;
    match &mut vm.arena.objects[args[0].as_obj() as usize].native {
        Some(Native::SManga { memo, .. } | Native::SChapter { memo, .. }) => *memo = value,
        _ => return Err(invalid(vm, "Expected a source model")),
    }
    Ok(value)
}

fn sealed_init(vm: &mut Vm, args: &[JValue]) -> R {
    let object = &mut vm.arena.objects[args[0].as_obj() as usize];
    object.native = Some(Native::Opaque);
    object.fields = args[1..].to_vec();
    Ok(JValue::Null)
}
fn builder_module(vm: &mut Vm, args: &[JValue]) -> R {
    let Some(Native::SerializersModule { polys }) = vm.payload_of(args[0]) else {
        return Err(invalid(vm, "Invalid JSON builder"));
    };
    vm.alloc_native(
        "Lkotlinx/serialization/modules/SerializersModule;",
        Native::SerializersModule { polys },
    )
    .map_err(thrown)
}
fn sealed_deserialize(vm: &mut Vm, args: &[JValue]) -> R {
    use dexvm::vm::object::ArrayData;
    let fields = vm.arena.objects[args[0].as_obj() as usize].fields.clone();
    if fields.len() < 4 {
        return Err(invalid(vm, "Invalid sealed serializer"));
    }
    let (element, module) = match vm.payload_of(args[1]) {
        Some(Native::JsonDecoder {
            element, module, ..
        }) => (element, module),
        _ => return Err(invalid(vm, "Sealed serializer requires JSON")),
    };
    let key = match vm.payload_of(element) {
        Some(Native::Json(JsonVal::Object(members))) => members.into_iter().find_map(|(k, v)| {
            if k == "type" {
                if let JsonVal::Str(s) = v {
                    Some(s)
                } else {
                    None
                }
            } else {
                None
            }
        }),
        _ => None,
    };
    let serializers = match vm.payload_of(fields[3]) {
        Some(Native::Array(ArrayData::Obj(values))) => values,
        _ => return Err(invalid(vm, "Invalid sealed subclasses")),
    };
    for serializer in serializers {
        let descriptor = vm
            .invoke_virtual(
                serializer,
                "getDescriptor",
                "()Lkotlinx/serialization/descriptors/SerialDescriptor;",
            )
            .map_err(thrown)?;
        let name = vm
            .invoke_virtual(descriptor, "getSerialName", "()Ljava/lang/String;")
            .map_err(thrown)?;
        if vm.str_of_jvalue(name) == key && key.is_some() {
            return vm
                .invoke_virtual_args(
                    serializer,
                    "deserialize",
                    "(Lkotlinx/serialization/encoding/Decoder;)Ljava/lang/Object;",
                    vec![args[1]],
                )
                .map_err(thrown);
        }
    }
    if let Some(Native::SerializersModule { polys }) = module.and_then(|m| vm.payload_of(m)) {
        for (base, _, fallback) in polys {
            // KClass instances need not have the same object identity.
            let equal = vm
                .invoke_virtual_args(base, "equals", "(Ljava/lang/Object;)Z", vec![fields[1]])
                .map_err(thrown)?
                .as_int()
                != 0;
            if equal {
                if let Some(fallback) = fallback {
                    let key = key
                        .as_ref()
                        .map(|s| vm.alloc_string(s))
                        .unwrap_or(JValue::Null);
                    let serializer = vm
                        .invoke_virtual_args(
                            fallback,
                            "invoke",
                            "(Ljava/lang/Object;)Ljava/lang/Object;",
                            vec![key],
                        )
                        .map_err(thrown)?;
                    if !serializer.is_null_ref() {
                        return vm
                            .invoke_virtual_args(
                                serializer,
                                "deserialize",
                                "(Lkotlinx/serialization/encoding/Decoder;)Ljava/lang/Object;",
                                vec![args[1]],
                            )
                            .map_err(thrown);
                    }
                }
            }
        }
    }
    Err(invalid(vm, "No serializer for JSON subtype"))
}

pub(super) fn json_value(value: JsonVal, depth: usize) -> Option<serde_json::Value> {
    if depth > 128 {
        return None;
    }
    Some(match value {
        JsonVal::Null => serde_json::Value::Null,
        JsonVal::Str(s) => s.into(),
        JsonVal::Int(n) => n.into(),
        JsonVal::Double(n) => serde_json::Number::from_f64(n)?.into(),
        JsonVal::Bool(b) => b.into(),
        JsonVal::Array(values) => serde_json::Value::Array(
            values
                .into_iter()
                .map(|v| json_value(v, depth + 1))
                .collect::<Option<_>>()?,
        ),
        JsonVal::Object(values) => serde_json::Value::Object(
            values
                .into_iter()
                .map(|(k, v)| Some((k, json_value(v, depth + 1)?)))
                .collect::<Option<_>>()?,
        ),
    })
}
fn stringify(vm: &mut Vm, args: &[JValue]) -> R {
    let Some(Native::Json(value)) = vm.payload_of(args[0]) else {
        return Err(invalid(vm, "Expected a JSON element"));
    };
    let value =
        json_value(value, 0).ok_or_else(|| invalid(vm, "Invalid or excessively nested JSON"))?;
    Ok(vm.alloc_string(&value.to_string()))
}

// Both overloads run the actual configuration lambda. Allocate a distinct
// engine so assigning a serializers module cannot mutate Json.Default.
fn factory(vm: &mut Vm, args: &[JValue]) -> R {
    let inherited = match vm.payload_of(args[0]) {
        Some(Native::JsonWithModule { module }) => match vm.payload_of(module) {
            Some(Native::SerializersModule { polys }) => polys,
            _ => vec![],
        },
        _ => vec![],
    };
    let builder = vm
        .alloc_native(
            "Lkotlinx/serialization/json/JsonBuilder;",
            Native::SerializersModule { polys: inherited },
        )
        .map_err(thrown)?;
    vm.invoke_virtual_args(
        args[1],
        "invoke",
        "(Ljava/lang/Object;)Ljava/lang/Object;",
        vec![builder],
    )
    .map_err(thrown)?;
    let payload = match vm.payload_of(builder) {
        Some(Native::SerializersModule { polys }) => Native::SerializersModule { polys },
        _ => return Err(invalid(vm, "Invalid JSON configuration")),
    };
    let module = vm
        .alloc_native("Lkotlinx/serialization/modules/SerializersModule;", payload)
        .map_err(thrown)?;
    vm.alloc_native(
        "Lkotlinx/serialization/json/Json;",
        Native::JsonWithModule { module },
    )
    .map_err(thrown)
}
fn factory_default(vm: &mut Vm, args: &[JValue]) -> R {
    let from = if args[2].as_int() & 1 != 0 {
        JValue::Null
    } else {
        args[0]
    };
    factory(vm, &[from, args[1]])
}

pub fn install(vm: &mut Vm) -> Result<(), JvmError> {
    for class in [
        "Leu/kanade/tachiyomi/source/model/SManga;",
        "Leu/kanade/tachiyomi/source/model/SChapter;",
    ] {
        vm.register_native(NativeEntry {
            class,
            name: "getMemo",
            sig: "()Lkotlinx/serialization/json/JsonObject;",
            instance: true,
            f: model_memo,
        })?;
    }
    vm.register_native(NativeEntry {
        class: "Lkotlinx/serialization/json/JsonArray;",
        name: "<init>",
        sig: "(Ljava/util/List;)V",
        instance: true,
        f: array_init,
    })?;
    let object = vm.ensure_class_by_desc("Lkotlinx/serialization/json/JsonObject;")?;
    let map = vm.ensure_class_by_desc("Ljava/util/Map;")?;
    if !vm.classes[object as usize].interfaces.contains(&map) {
        vm.classes[object as usize].interfaces.push(map);
    }
    let array = vm.ensure_class_by_desc("Lkotlinx/serialization/json/JsonArray;")?;
    let list = vm.ensure_class_by_desc("Ljava/util/List;")?;
    if !vm.classes[array as usize].interfaces.contains(&list) {
        vm.classes[array as usize].interfaces.push(list);
    }
    // invoke-interface must resolve the declared method before dispatching to
    // the generated serializer supplied by the extension.
    for class in [
        "Lkotlinx/serialization/KSerializer;",
        "Lkotlinx/serialization/DeserializationStrategy;",
    ] {
        vm.register_native(NativeEntry {
            class,
            name: "deserialize",
            sig: "(Lkotlinx/serialization/encoding/Decoder;)Ljava/lang/Object;",
            instance: true,
            f: element_deserialize,
        })?;
    }
    vm.register_native(NativeEntry {
        class: "Lkotlinx/serialization/json/JsonElement;",
        name: "toString",
        sig: "()Ljava/lang/String;",
        instance: true,
        f: stringify,
    })?;
    // A real, GC-rooted singleton (rather than an Opaque materialized field).
    let owner = vm.ensure_class_by_desc(NULL)?;
    let name = vm.intern("INSTANCE");
    let ty = vm.intern(NULL);
    if !vm.classes[owner as usize]
        .static_fields
        .contains_key(&(name, ty))
    {
        let value = vm.alloc_native(NULL, Native::Json(JsonVal::Null))?;
        let class = &mut vm.classes[owner as usize];
        let offset = class.statics.len() as u32;
        class.statics.push(value);
        class.statics_lazy.push(None);
        class.static_fields.insert((name, ty), (owner, offset));
    }
    for (ty, make, put, add) in [
        (
            "Ljava/lang/String;",
            string as dexvm::vm::NativeFn,
            put_string as dexvm::vm::NativeFn,
            add_string as dexvm::vm::NativeFn,
        ),
        ("Ljava/lang/Number;", number, put_number, add_number),
        ("Ljava/lang/Boolean;", boolean, put_boolean, add_boolean),
        ("Ljava/lang/Void;", null, put_null, add_null),
    ] {
        // NativeEntry descriptors have static lifetimes, so register the fixed
        // JVM overloads below; no APK names or obfuscated symbols are inspected.
        let signatures = match ty {
            "Ljava/lang/String;" => ("(Ljava/lang/String;)Lkotlinx/serialization/json/JsonPrimitive;", "(Lkotlinx/serialization/json/JsonObjectBuilder;Ljava/lang/String;Ljava/lang/String;)Lkotlinx/serialization/json/JsonElement;", "(Lkotlinx/serialization/json/JsonArrayBuilder;Ljava/lang/String;)Z"),
            "Ljava/lang/Number;" => ("(Ljava/lang/Number;)Lkotlinx/serialization/json/JsonPrimitive;", "(Lkotlinx/serialization/json/JsonObjectBuilder;Ljava/lang/String;Ljava/lang/Number;)Lkotlinx/serialization/json/JsonElement;", "(Lkotlinx/serialization/json/JsonArrayBuilder;Ljava/lang/Number;)Z"),
            "Ljava/lang/Boolean;" => ("(Ljava/lang/Boolean;)Lkotlinx/serialization/json/JsonPrimitive;", "(Lkotlinx/serialization/json/JsonObjectBuilder;Ljava/lang/String;Ljava/lang/Boolean;)Lkotlinx/serialization/json/JsonElement;", "(Lkotlinx/serialization/json/JsonArrayBuilder;Ljava/lang/Boolean;)Z"),
            _ => ("(Ljava/lang/Void;)Lkotlinx/serialization/json/JsonNull;", "(Lkotlinx/serialization/json/JsonObjectBuilder;Ljava/lang/String;Ljava/lang/Void;)Lkotlinx/serialization/json/JsonElement;", "(Lkotlinx/serialization/json/JsonArrayBuilder;Ljava/lang/Void;)Z"),
        };
        for (class, name, sig, f) in [
            (ELEMENT, "JsonPrimitive", signatures.0, make),
            (BUILDERS, "put", signatures.1, put),
            (BUILDERS, "add", signatures.2, add),
        ] {
            vm.register_native(NativeEntry {
                class,
                name,
                sig,
                instance: false,
                f,
            })?;
        }
    }
    for (class, name, sig, instance, f) in [
        ("Lkotlinx/serialization/SealedClassSerializer;", "<init>", "(Ljava/lang/String;Lkotlin/reflect/KClass;[Lkotlin/reflect/KClass;[Lkotlinx/serialization/KSerializer;[Ljava/lang/annotation/Annotation;)V", true, sealed_init as dexvm::vm::NativeFn),
        ("Lkotlinx/serialization/SealedClassSerializer;", "deserialize", "(Lkotlinx/serialization/encoding/Decoder;)Ljava/lang/Object;", true, sealed_deserialize),
        ("Lkotlinx/serialization/json/JsonBuilder;", "getSerializersModule", "()Lkotlinx/serialization/modules/SerializersModule;", true, builder_module),
        (ELEMENT, "getJsonPrimitive", "(Lkotlinx/serialization/json/JsonElement;)Lkotlinx/serialization/json/JsonPrimitive;", false, primitive as dexvm::vm::NativeFn),
        ("Lkotlinx/serialization/json/JsonPrimitive;", "getContent", "()Ljava/lang/String;", true, content),
        ("Lkotlinx/serialization/json/JsonKt;", "Json", "(Lkotlinx/serialization/json/Json;Lkotlin/jvm/functions/Function1;)Lkotlinx/serialization/json/Json;", false, factory),
        ("Lkotlinx/serialization/json/JsonKt;", "Json$default", "(Lkotlinx/serialization/json/Json;Lkotlin/jvm/functions/Function1;ILjava/lang/Object;)Lkotlinx/serialization/json/Json;", false, factory_default),
    ] {
        vm.register_native(NativeEntry { class, name, sig, instance, f })?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn json_arrays_initialize_fresh_instances_and_keep_collection_interfaces() {
        let mut vm = Vm::new(vec![], Box::new(std::io::sink())).unwrap();
        install(&mut vm).unwrap();
        let value = node(&mut vm, JsonVal::Str("owned".into())).unwrap();
        let list = vm
            .alloc_native("Ljava/util/ArrayList;", Native::List(vec![value]))
            .unwrap();
        let class = vm
            .ensure_class_by_desc("Lkotlinx/serialization/json/JsonArray;")
            .unwrap();
        let fresh = JValue::Obj(vm.alloc_instance(class).unwrap());
        array_init(&mut vm, &[fresh, list]).unwrap();
        assert!(
            matches!(vm.payload_of(fresh),Some(Native::Json(JsonVal::Array(v))) if v==vec![JsonVal::Str("owned".into())])
        );
        let iterable = vm.ensure_class_by_desc("Ljava/lang/Iterable;").unwrap();
        assert!(vm.is_assignable(class, iterable).unwrap());
        let object = vm
            .ensure_class_by_desc("Lkotlinx/serialization/json/JsonObject;")
            .unwrap();
        let map = vm.ensure_class_by_desc("Ljava/util/Map;").unwrap();
        assert!(vm.is_assignable(object, map).unwrap());
    }
    fn vm() -> Vm {
        let mut vm = Vm::new(vec![], Box::new(std::io::sink())).unwrap();
        install(&mut vm).unwrap();
        vm
    }
    #[test]
    fn nullable_primitives_share_the_rooted_json_null_without_coercing_false() {
        let mut vm = vm();
        let nil = null(&mut vm, &[]).unwrap();
        for make in [string as dexvm::vm::NativeFn, number, boolean, null] {
            assert_eq!(make(&mut vm, &[JValue::Null]).unwrap(), nil);
            assert_eq!(make(&mut vm, &[JValue::Int(0)]).unwrap(), nil);
        }
        vm.gc(&[]);
        assert!(matches!(
            vm.payload_of(nil),
            Some(Native::Json(JsonVal::Null))
        ));
        assert_eq!(primitive(&mut vm, &[nil]).unwrap(), nil);
        let text = content(&mut vm, &[nil]).unwrap();
        assert_eq!(vm.str_of_jvalue(text).as_deref(), Some("null"));
        let boxed = vm
            .alloc_native("Ljava/lang/Boolean;", Native::BoolBox(false))
            .unwrap();
        let value = boolean(&mut vm, &[boxed]).unwrap();
        assert!(matches!(
            vm.payload_of(value),
            Some(Native::Json(JsonVal::Bool(false)))
        ));
    }
    #[test]
    fn puts_return_the_previous_element_and_arrays_accept_nullable_overloads() {
        let mut vm = vm();
        let builder = vm
            .alloc_native(
                "Lkotlinx/serialization/json/JsonObjectBuilder;",
                Native::Json(JsonVal::Object(vec![])),
            )
            .unwrap();
        let key = vm.alloc_string("owned");
        let text = vm.alloc_string("value");
        assert!(put_string(&mut vm, &[builder, key, text])
            .unwrap()
            .is_null_ref());
        let old = put_null(&mut vm, &[builder, key, JValue::Null]).unwrap();
        assert!(matches!(vm.payload_of(old),Some(Native::Json(JsonVal::Str(s))) if s == "value"));
        let old = put_string(&mut vm, &[builder, key, text]).unwrap();
        assert!(matches!(
            vm.payload_of(old),
            Some(Native::Json(JsonVal::Null))
        ));
        let array = vm
            .alloc_native(
                "Lkotlinx/serialization/json/JsonArrayBuilder;",
                Native::Json(JsonVal::Array(vec![])),
            )
            .unwrap();
        for add in [
            add_string as dexvm::vm::NativeFn,
            add_number,
            add_boolean,
            add_null,
        ] {
            assert_eq!(
                add(&mut vm, &[array, JValue::Null]).unwrap(),
                JValue::Int(1)
            );
        }
        assert!(
            matches!(vm.payload_of(array),Some(Native::Json(JsonVal::Array(v))) if v.len() == 4 && v.iter().all(|v| matches!(v,JsonVal::Null)))
        );
    }
    #[test]
    fn stringify_produces_json_not_object_identity_and_rejects_nonfinite_values() {
        let mut vm = vm();
        let value = node(
            &mut vm,
            JsonVal::Object(vec![
                ("escaped".into(), JsonVal::Str("\"&\n日本".into())),
                ("id".into(), JsonVal::Int(9_000_000_000_002)),
            ]),
        )
        .unwrap();
        let result = stringify(&mut vm, &[value]).unwrap();
        let parsed: serde_json::Value =
            serde_json::from_str(&vm.str_of_jvalue(result).unwrap()).unwrap();
        assert_eq!(parsed["escaped"], "\"&\n日本");
        assert_eq!(parsed["id"], 9_000_000_000_002_i64);
        let nan = node(&mut vm, JsonVal::Double(f64::NAN)).unwrap();
        assert!(matches!(stringify(&mut vm, &[nan]), Err(NatErr::Throw(_))));
    }
    #[test]
    fn float_json_numbers_keep_their_shortest_round_trip_value() {
        let mut vm = vm();
        let boxed = vm
            .alloc_native("Ljava/lang/Float;", Native::FloatBox(1.1))
            .unwrap();
        let value = number(&mut vm, &[boxed]).unwrap();
        let text = stringify(&mut vm, &[value]).unwrap();
        let parsed: serde_json::Value =
            serde_json::from_str(&vm.str_of_jvalue(text).unwrap()).unwrap();
        assert_eq!(parsed, serde_json::json!(1.1));
    }
    fn configure(vm: &mut Vm, args: &[JValue]) -> R {
        let Some(Native::SerializersModule { mut polys }) = vm.payload_of(args[1]) else {
            return Err(invalid(vm, "Missing builder module"));
        };
        polys.push((args[0], vec![], None));
        vm.arena.objects[args[1].as_obj() as usize].native =
            Some(Native::SerializersModule { polys });
        Ok(JValue::Null)
    }
    #[test]
    fn json_factories_inherit_but_never_mutate_the_original_module() {
        let mut vm = vm();
        vm.register_native(NativeEntry {
            class: "LOwnedConfigure;",
            name: "invoke",
            sig: "(Ljava/lang/Object;)Ljava/lang/Object;",
            instance: true,
            f: configure,
        })
        .unwrap();
        let action = vm.alloc_native("LOwnedConfigure;", Native::Opaque).unwrap();
        let original = factory(&mut vm, &[JValue::Null, action]).unwrap();
        let updated = factory(&mut vm, &[original, action]).unwrap();
        let defaulted =
            factory_default(&mut vm, &[original, action, JValue::Int(1), JValue::Null]).unwrap();
        assert_ne!(original, updated);
        vm.gc(&[original.as_obj(), updated.as_obj(), defaulted.as_obj()]);
        for (value, count) in [(original, 1), (updated, 2), (defaulted, 1)] {
            let Some(Native::JsonWithModule { module }) = vm.payload_of(value) else {
                panic!("Missing module");
            };
            assert!(
                matches!(vm.payload_of(module),Some(Native::SerializersModule { polys }) if polys.len() == count)
            );
        }
    }
}
