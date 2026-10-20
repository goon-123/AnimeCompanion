//! Shared JSON tree serializers and Map encoding. Guest DTO serializers still
//! execute normally; no source IDs, DTO names or website rules are substituted.
use dexvm::vm::error::JvmError;
use dexvm::vm::object::{JsonVal, Native};
use dexvm::vm::{NatErr, NativeEntry, Vm};
use dexvm::JValue;

type R = Result<JValue, NatErr>;
const SERIALIZERS: &[(&str, &str, &str)] = &[
    (
        "Lkotlinx/serialization/json/JsonElementSerializer;",
        "JsonElement",
        "Lkotlinx/serialization/json/JsonElement$Companion;",
    ),
    (
        "Lkotlinx/serialization/json/JsonPrimitiveSerializer;",
        "JsonPrimitive",
        "Lkotlinx/serialization/json/JsonPrimitive$Companion;",
    ),
    (
        "Lkotlinx/serialization/json/JsonNullSerializer;",
        "JsonNull",
        "Lkotlinx/serialization/json/JsonNull;",
    ),
    (
        "Lkotlinx/serialization/json/JsonLiteralSerializer;",
        "JsonLiteral",
        "Lkotlinx/serialization/json/JsonLiteral;",
    ),
    (
        "Lkotlinx/serialization/json/JsonObjectSerializer;",
        "JsonObject",
        "Lkotlinx/serialization/json/JsonObject$Companion;",
    ),
    (
        "Lkotlinx/serialization/json/JsonArraySerializer;",
        "JsonArray",
        "Lkotlinx/serialization/json/JsonArray$Companion;",
    ),
];
fn thrown(error: JvmError) -> NatErr {
    match error {
        JvmError::Uncaught(o) => NatErr::Throw(o),
        other => NatErr::Fatal(other),
    }
}
fn invalid(vm: &mut Vm, message: &str) -> NatErr {
    NatErr::Throw(vm.err_iae(message))
}
fn kind(vm: &mut Vm, serializer: JValue) -> Result<&'static str, NatErr> {
    let JValue::Obj(id) = serializer else {
        return Err(NatErr::Throw(vm.err_npe()));
    };
    let desc = vm.str_of(vm.classes[vm.arena.objects[id as usize].class as usize].descriptor);
    SERIALIZERS
        .iter()
        .find(|(class, _, _)| *class == desc)
        .map(|(_, name, _)| *name)
        .ok_or_else(|| invalid(vm, "Invalid JSON serializer"))
}
fn check(vm: &mut Vm, serializer: JValue, value: JValue) -> Result<JsonVal, NatErr> {
    let kind = kind(vm, serializer)?;
    let Some(Native::Json(value)) = vm.payload_of(value) else {
        return Err(invalid(vm, "Expected a JsonElement"));
    };
    let valid = match kind {
        "JsonElement" => true,
        "JsonNull" => matches!(value, JsonVal::Null),
        "JsonObject" => matches!(value, JsonVal::Object(_)),
        "JsonArray" => matches!(value, JsonVal::Array(_)),
        "JsonLiteral" => matches!(
            value,
            JsonVal::Str(_) | JsonVal::Int(_) | JsonVal::Double(_) | JsonVal::Bool(_)
        ),
        _ => !matches!(value, JsonVal::Object(_) | JsonVal::Array(_)),
    };
    if !valid {
        return Err(invalid(vm, "JSON element does not match its serializer"));
    }
    validate(vm, &value, 0)?;
    Ok(value)
}
fn validate(vm: &mut Vm, value: &JsonVal, depth: usize) -> Result<(), NatErr> {
    if depth > 128 || vm.budget <= 0 {
        return Err(NatErr::Fatal(JvmError::BudgetExceeded));
    }
    vm.budget -= 1;
    match value {
        JsonVal::Double(value) if !value.is_finite() => {
            return Err(invalid(vm, "Non-finite JSON number"))
        }
        JsonVal::Array(values) => {
            if values.len() > 100_000 {
                return Err(NatErr::Fatal(JvmError::BudgetExceeded));
            }
            for value in values {
                validate(vm, value, depth + 1)?;
            }
        }
        JsonVal::Object(values) => {
            if values.len() > 100_000 {
                return Err(NatErr::Fatal(JvmError::BudgetExceeded));
            }
            for (_, value) in values {
                validate(vm, value, depth + 1)?;
            }
        }
        _ => {}
    }
    Ok(())
}
fn deserialize(vm: &mut Vm, args: &[JValue]) -> R {
    let Some(Native::JsonDecoder { element, .. }) = vm.payload_of(args[1]) else {
        return Err(invalid(vm, "JsonElement requires a JSON decoder"));
    };
    let value = check(vm, args[0], element)?;
    if kind(vm, args[0])? == "JsonLiteral" {
        return vm
            .alloc_native(
                "Lkotlinx/serialization/json/JsonLiteral;",
                Native::Json(value),
            )
            .map_err(thrown);
    }
    Ok(element)
}
fn write(vm: &mut Vm, encoder: JValue, value: JsonVal) -> R {
    validate(vm, &value, 0)?;
    let JValue::Obj(id) = encoder else {
        return Err(NatErr::Throw(vm.err_npe()));
    };
    let Some(Native::JsonEncoder { value: target, .. }) = &mut vm.arena.objects[id as usize].native
    else {
        return Err(invalid(vm, "Expected a JSON encoder"));
    };
    *target = Some(value);
    Ok(JValue::Null)
}
fn serialize(vm: &mut Vm, args: &[JValue]) -> R {
    let value = check(vm, args[0], args[2])?;
    write(vm, args[1], value)
}
fn singleton(vm: &mut Vm, class: &'static str) -> R {
    let field = dexvm::vm::FieldRef {
        class_desc: vm.intern(class),
        name: vm.intern("INSTANCE"),
        ty: vm.intern(class),
    };
    vm.static_field_get(field).map_err(thrown)
}
fn companion_serializer(vm: &mut Vm, args: &[JValue]) -> R {
    let JValue::Obj(id) = args[0] else {
        return Err(NatErr::Throw(vm.err_npe()));
    };
    let desc = vm.str_of(vm.classes[vm.arena.objects[id as usize].class as usize].descriptor);
    let class = SERIALIZERS
        .iter()
        .find(|(_, _, companion)| *companion == desc)
        .map(|(class, _, _)| *class)
        .ok_or_else(|| invalid(vm, "Invalid JSON companion"))?;
    singleton(vm, class)
}
fn descriptor(vm: &mut Vm, args: &[JValue]) -> R {
    let kind = kind(vm, args[0])?;
    let elements = match kind {
        "JsonElement" => vec![
            "JsonPrimitive",
            "JsonNull",
            "JsonLiteral",
            "JsonObject",
            "JsonArray",
        ],
        "JsonObject" => vec!["0", "1"],
        "JsonArray" => vec!["0"],
        _ => vec![],
    };
    let mut children = Vec::new();
    match kind {
        "JsonElement" => {
            for &(class, _, _) in &SERIALIZERS[1..] {
                children.push(singleton(vm, class)?);
            }
        }
        "JsonObject" => {
            children.push(singleton(
                vm,
                "Lkotlinx/serialization/internal/StringSerializer;",
            )?);
            children.push(singleton(vm, SERIALIZERS[0].0)?);
        }
        "JsonArray" => children.push(singleton(vm, SERIALIZERS[0].0)?),
        _ => {}
    }
    descriptor_with_children(
        vm,
        &format!("kotlinx.serialization.json.{kind}"),
        elements,
        children,
    )
}
fn descriptor_with_children(
    vm: &mut Vm,
    name: &str,
    elements: Vec<&str>,
    children: Vec<JValue>,
) -> R {
    let children = vm
        .alloc_native(
            "[Lkotlinx/serialization/KSerializer;",
            Native::Array(dexvm::vm::object::ArrayData::Obj(children)),
        )
        .map_err(thrown)?;
    let descriptor = vm
        .alloc_native(
            "Lkotlinx/serialization/internal/PluginGeneratedSerialDescriptor;",
            Native::SerialDescriptor {
                name: name.into(),
                element_annotations: vec![vec![]; elements.len()],
                elements: elements.into_iter().map(str::to_owned).collect(),
            },
        )
        .map_err(thrown)?;
    vm.arena.objects[descriptor.as_obj() as usize]
        .fields
        .push(children);
    Ok(descriptor)
}
fn map_serializer(vm: &mut Vm, args: &[JValue]) -> R {
    if args.iter().any(|a| a.is_null_ref()) {
        return Err(NatErr::Throw(vm.err_npe()));
    }
    vm.alloc_native(
        "Lkotlinx/serialization/internal/LinkedHashMapSerializer;",
        Native::LinkedHashMapSerializer {
            key: args[0],
            value: args[1],
        },
    )
    .map_err(thrown)
}
fn encode(vm: &mut Vm, serializer: JValue, value: JValue) -> Result<JsonVal, NatErr> {
    if vm.budget <= 0 {
        return Err(NatErr::Fatal(JvmError::BudgetExceeded));
    }
    vm.budget -= 1;
    let json = vm
        .alloc_native("Lkotlinx/serialization/json/Json;", Native::Opaque)
        .map_err(thrown)?;
    let element = vm.invoke_virtual_args(json, "encodeToJsonElement", "(Lkotlinx/serialization/SerializationStrategy;Ljava/lang/Object;)Lkotlinx/serialization/json/JsonElement;", vec![serializer,value]).map_err(thrown)?;
    match vm.payload_of(element) {
        Some(Native::Json(v)) => Ok(v),
        _ => Err(invalid(vm, "Serializer did not produce JSON")),
    }
}
fn map_serialize(vm: &mut Vm, args: &[JValue]) -> R {
    // Native-to-native calls do not enter an interpreter frame. Count this
    // reentry too, so cyclic serializers/maps cannot exhaust the Rust stack.
    if vm.recursion_depth >= vm.depth_limit.min(64) {
        return Err(NatErr::Fatal(JvmError::StackOverflow));
    }
    vm.recursion_depth += 1;
    let result = map_serialize_inner(vm, args);
    vm.recursion_depth -= 1;
    result
}
fn map_serialize_inner(vm: &mut Vm, args: &[JValue]) -> R {
    let Some(Native::LinkedHashMapSerializer { key, value }) = vm.payload_of(args[0]) else {
        return Err(invalid(vm, "Invalid map serializer"));
    };
    let Some(Native::Map(entries)) = vm.payload_of(args[2]) else {
        return Err(invalid(vm, "Expected a Map"));
    };
    if entries.len() > 100_000 {
        return Err(NatErr::Fatal(JvmError::BudgetExceeded));
    }
    let mut members = Vec::with_capacity(entries.len());
    for (k, v) in entries {
        let key = match encode(vm, key, k)? {
            JsonVal::Str(s) => s,
            JsonVal::Int(n) => n.to_string(),
            JsonVal::Double(n) if n.is_finite() => n.to_string(),
            JsonVal::Bool(b) => b.to_string(),
            JsonVal::Null => "null".into(),
            _ => return Err(invalid(vm, "JSON object keys must be primitive values")),
        };
        members.push((key, encode(vm, value, v)?));
    }
    write(vm, args[1], JsonVal::Object(members))
}
fn map_descriptor(vm: &mut Vm, args: &[JValue]) -> R {
    let Some(Native::LinkedHashMapSerializer { key, value }) = vm.payload_of(args[0]) else {
        return Err(invalid(vm, "Invalid map serializer"));
    };
    descriptor_with_children(
        vm,
        "kotlin.collections.LinkedHashMap",
        vec!["0", "1"],
        vec![key, value],
    )
}
fn boolean_serialize(vm: &mut Vm, args: &[JValue]) -> R {
    let Some(Native::BoolBox(value)) = vm.payload_of(args[2]) else {
        return Err(invalid(vm, "Expected a Boolean"));
    };
    vm.invoke_virtual_args(
        args[1],
        "encodeBoolean",
        "(Z)V",
        vec![JValue::Int(i32::from(value))],
    )
    .map_err(thrown)
}
fn boolean_deserialize(vm: &mut Vm, args: &[JValue]) -> R {
    let value = vm
        .invoke_virtual(args[1], "decodeBoolean", "()Z")
        .map_err(thrown)?;
    vm.alloc_native("Ljava/lang/Boolean;", Native::BoolBox(value.as_int() != 0))
        .map_err(thrown)
}
fn boolean_descriptor(vm: &mut Vm, _: &[JValue]) -> R {
    vm.alloc_native(
        "Lkotlinx/serialization/internal/PluginGeneratedSerialDescriptor;",
        Native::SerialDescriptor {
            name: "kotlin.Boolean".into(),
            elements: vec![],
            element_annotations: vec![],
        },
    )
    .map_err(thrown)
}
fn install_singleton(vm: &mut Vm, class: &'static str) -> Result<(), JvmError> {
    let id = vm.ensure_class_by_desc(class)?;
    let key = (vm.intern("INSTANCE"), vm.intern(class));
    let value = vm.alloc_native(class, Native::Opaque)?;
    let owner = &mut vm.classes[id as usize];
    if !owner.static_fields.contains_key(&key) {
        let offset = owner.statics.len() as u32;
        owner.statics.push(value);
        owner.statics_lazy.push(None);
        owner.static_fields.insert(key, (id, offset));
    }
    let serializer = vm.ensure_class_by_desc("Lkotlinx/serialization/KSerializer;")?;
    if !vm.classes[id as usize].interfaces.contains(&serializer) {
        vm.classes[id as usize].interfaces.push(serializer);
    }
    Ok(())
}
fn kind_string(vm: &mut Vm, args: &[JValue]) -> R {
    let Some(Native::Str(name)) = vm.payload_of(args[0]) else {
        return Err(invalid(vm, "Invalid serial kind"));
    };
    Ok(vm.alloc_string(&name))
}
fn kind_init(_vm: &mut Vm, _args: &[JValue]) -> R {
    Ok(JValue::Null)
}
fn install_kinds(vm: &mut Vm) -> Result<(), JvmError> {
    use dexvm::vm::class::{Class, ACC_ABSTRACT, ACC_PUBLIC};
    for (desc, parent) in [
        (
            "Lkotlinx/serialization/descriptors/SerialKind;",
            "Ljava/lang/Object;",
        ),
        (
            "Lkotlinx/serialization/descriptors/PrimitiveKind;",
            "Lkotlinx/serialization/descriptors/SerialKind;",
        ),
        (
            "Lkotlinx/serialization/descriptors/StructureKind;",
            "Lkotlinx/serialization/descriptors/SerialKind;",
        ),
        (
            "Lkotlinx/serialization/descriptors/PolymorphicKind;",
            "Lkotlinx/serialization/descriptors/SerialKind;",
        ),
    ] {
        let descriptor = vm.intern(desc);
        // Some APKs supply concrete descriptor-kind subclasses. Preserve a
        // bundled base implementation when it exists instead of shadowing it.
        let missing = match vm.ensure_class_by_desc(desc) {
            Ok(_) => false,
            Err(JvmError::Resolution(message)) if message == format!("class not found: {desc}") => {
                true
            }
            Err(error) => return Err(error),
        };
        if missing {
            let superclass = vm.ensure_class_by_desc(parent)?;
            let id = vm.classes.len() as u32;
            vm.classes.push(Class {
                id,
                descriptor,
                superclass: Some(superclass),
                access_flags: ACC_PUBLIC | ACC_ABSTRACT,
                is_abstract: true,
                ..Default::default()
            });
            vm.class_by_desc.insert(descriptor, id);
            for sig in ["()V", "(Lkotlin/jvm/internal/DefaultConstructorMarker;)V"] {
                vm.register_native(NativeEntry {
                    class: desc,
                    name: "<init>",
                    sig,
                    instance: true,
                    f: kind_init,
                })?;
            }
        }
    }
    for (class, parent, name) in [
        (
            "Lkotlinx/serialization/descriptors/PrimitiveKind$STRING;",
            "Lkotlinx/serialization/descriptors/PrimitiveKind;",
            "STRING",
        ),
        (
            "Lkotlinx/serialization/descriptors/PrimitiveKind$INT;",
            "Lkotlinx/serialization/descriptors/PrimitiveKind;",
            "INT",
        ),
        (
            "Lkotlinx/serialization/descriptors/PrimitiveKind$LONG;",
            "Lkotlinx/serialization/descriptors/PrimitiveKind;",
            "LONG",
        ),
        (
            "Lkotlinx/serialization/descriptors/PrimitiveKind$BOOLEAN;",
            "Lkotlinx/serialization/descriptors/PrimitiveKind;",
            "BOOLEAN",
        ),
        (
            "Lkotlinx/serialization/descriptors/PrimitiveKind$FLOAT;",
            "Lkotlinx/serialization/descriptors/PrimitiveKind;",
            "FLOAT",
        ),
        (
            "Lkotlinx/serialization/descriptors/PrimitiveKind$DOUBLE;",
            "Lkotlinx/serialization/descriptors/PrimitiveKind;",
            "DOUBLE",
        ),
        (
            "Lkotlinx/serialization/descriptors/StructureKind$LIST;",
            "Lkotlinx/serialization/descriptors/StructureKind;",
            "LIST",
        ),
        (
            "Lkotlinx/serialization/descriptors/StructureKind$MAP;",
            "Lkotlinx/serialization/descriptors/StructureKind;",
            "MAP",
        ),
        (
            "Lkotlinx/serialization/descriptors/StructureKind$CLASS;",
            "Lkotlinx/serialization/descriptors/StructureKind;",
            "CLASS",
        ),
        (
            "Lkotlinx/serialization/descriptors/PolymorphicKind$SEALED;",
            "Lkotlinx/serialization/descriptors/PolymorphicKind;",
            "SEALED",
        ),
        (
            "Lkotlinx/serialization/descriptors/SerialKind$ENUM;",
            "Lkotlinx/serialization/descriptors/SerialKind;",
            "ENUM",
        ),
    ] {
        vm.register_native(NativeEntry {
            class,
            name: "toString",
            sig: "()Ljava/lang/String;",
            instance: true,
            f: kind_string,
        })?;
        let id = vm.ensure_class_by_desc(class)?;
        vm.classes[id as usize].superclass = Some(vm.ensure_class_by_desc(parent)?);
        let key = (vm.intern("INSTANCE"), vm.intern(class));
        let value = vm.alloc_native(class, Native::Str(name.into()))?;
        let owner = &mut vm.classes[id as usize];
        if !owner.static_fields.contains_key(&key) {
            let offset = owner.statics.len() as u32;
            owner.statics.push(value);
            owner.statics_lazy.push(None);
            owner.static_fields.insert(key, (id, offset));
        }
    }
    Ok(())
}
pub(super) fn install(vm: &mut Vm) -> Result<(), JvmError> {
    install_kinds(vm)?;
    for &(class, _, companion) in SERIALIZERS {
        for (name, sig, f) in [
            (
                "deserialize",
                "(Lkotlinx/serialization/encoding/Decoder;)Ljava/lang/Object;",
                deserialize as dexvm::vm::NativeFn,
            ),
            (
                "serialize",
                "(Lkotlinx/serialization/encoding/Encoder;Ljava/lang/Object;)V",
                serialize,
            ),
            (
                "getDescriptor",
                "()Lkotlinx/serialization/descriptors/SerialDescriptor;",
                descriptor,
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
        // JsonLiteral has no public companion serializer API.
        if class != "Lkotlinx/serialization/json/JsonLiteralSerializer;" {
            vm.register_native(NativeEntry {
                class: companion,
                name: "serializer",
                sig: "()Lkotlinx/serialization/KSerializer;",
                instance: true,
                f: companion_serializer,
            })?;
        }
        let (decode_sig,encode_sig) = match class {
            "Lkotlinx/serialization/json/JsonElementSerializer;" => ("(Lkotlinx/serialization/encoding/Decoder;)Lkotlinx/serialization/json/JsonElement;","(Lkotlinx/serialization/encoding/Encoder;Lkotlinx/serialization/json/JsonElement;)V"),
            "Lkotlinx/serialization/json/JsonPrimitiveSerializer;" => ("(Lkotlinx/serialization/encoding/Decoder;)Lkotlinx/serialization/json/JsonPrimitive;","(Lkotlinx/serialization/encoding/Encoder;Lkotlinx/serialization/json/JsonPrimitive;)V"),
            "Lkotlinx/serialization/json/JsonNullSerializer;" => ("(Lkotlinx/serialization/encoding/Decoder;)Lkotlinx/serialization/json/JsonNull;","(Lkotlinx/serialization/encoding/Encoder;Lkotlinx/serialization/json/JsonNull;)V"),
            "Lkotlinx/serialization/json/JsonLiteralSerializer;" => ("(Lkotlinx/serialization/encoding/Decoder;)Lkotlinx/serialization/json/JsonLiteral;","(Lkotlinx/serialization/encoding/Encoder;Lkotlinx/serialization/json/JsonLiteral;)V"),
            "Lkotlinx/serialization/json/JsonObjectSerializer;" => ("(Lkotlinx/serialization/encoding/Decoder;)Lkotlinx/serialization/json/JsonObject;","(Lkotlinx/serialization/encoding/Encoder;Lkotlinx/serialization/json/JsonObject;)V"),
            _ => ("(Lkotlinx/serialization/encoding/Decoder;)Lkotlinx/serialization/json/JsonArray;","(Lkotlinx/serialization/encoding/Encoder;Lkotlinx/serialization/json/JsonArray;)V"),
        };
        vm.register_native(NativeEntry {
            class,
            name: "deserialize",
            sig: decode_sig,
            instance: true,
            f: deserialize,
        })?;
        vm.register_native(NativeEntry {
            class,
            name: "serialize",
            sig: encode_sig,
            instance: true,
            f: serialize,
        })?;
        install_singleton(vm, class)?;
        if companion.ends_with("$Companion;") {
            let owner = companion.replace("$Companion;", ";");
            let owner = vm.ensure_class_by_desc(&owner)?;
            let key = (vm.intern("Companion"), vm.intern(companion));
            if !vm.classes[owner as usize].static_fields.contains_key(&key) {
                let value = vm.alloc_native(companion, Native::Opaque)?;
                let class = &mut vm.classes[owner as usize];
                let offset = class.statics.len() as u32;
                class.statics.push(value);
                class.statics_lazy.push(None);
                class.static_fields.insert(key, (owner, offset));
            }
        }
    }
    for (class,name,sig,instance,f) in [
        ("Lkotlinx/serialization/internal/LinkedHashMapSerializer;","serialize","(Lkotlinx/serialization/encoding/Encoder;Ljava/lang/Object;)V",true,map_serialize as dexvm::vm::NativeFn),
        ("Lkotlinx/serialization/internal/LinkedHashMapSerializer;","getDescriptor","()Lkotlinx/serialization/descriptors/SerialDescriptor;",true,map_descriptor),
        ("Lkotlinx/serialization/builtins/BuiltinSerializersKt;","MapSerializer","(Lkotlinx/serialization/KSerializer;Lkotlinx/serialization/KSerializer;)Lkotlinx/serialization/KSerializer;",false,map_serializer),
        ("Lkotlinx/serialization/internal/BooleanSerializer;","serialize","(Lkotlinx/serialization/encoding/Encoder;Ljava/lang/Object;)V",true,boolean_serialize),
        ("Lkotlinx/serialization/internal/BooleanSerializer;","deserialize","(Lkotlinx/serialization/encoding/Decoder;)Ljava/lang/Object;",true,boolean_deserialize),
        ("Lkotlinx/serialization/internal/BooleanSerializer;","getDescriptor","()Lkotlinx/serialization/descriptors/SerialDescriptor;",true,boolean_descriptor),
    ] { vm.register_native(NativeEntry {class,name,sig,instance,f})?; }
    install_singleton(vm, "Lkotlinx/serialization/internal/BooleanSerializer;")?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    fn vm() -> Vm {
        let mut vm = Vm::new(vec![], Box::new(std::io::sink())).unwrap();
        for &entry in crate::FUNCTION_INTERFACES {
            vm.register_native(entry).unwrap();
        }
        for class in [
            "Lkotlinx/serialization/internal/StringSerializer;",
            "Lkotlinx/serialization/internal/IntSerializer;",
        ] {
            vm.register_native(NativeEntry {
                class,
                name: "getDescriptor",
                sig: "()Lkotlinx/serialization/descriptors/SerialDescriptor;",
                instance: true,
                f: crate::primitive_descriptor,
            })
            .unwrap();
        }
        crate::json_compat::install(&mut vm).unwrap();
        install(&mut vm).unwrap();
        vm
    }
    fn encoder(vm: &mut Vm) -> JValue {
        vm.alloc_native(
            "Lkotlinx/serialization/json/internal/StreamingJsonEncoder;",
            Native::JsonEncoder {
                value: None,
                elements: Vec::new(),
            },
        )
        .unwrap()
    }
    #[test]
    fn json_serializers_are_rooted_singletons_and_reject_wrong_element_shapes() {
        let mut vm = vm();
        let values = [
            JsonVal::Null,
            JsonVal::Str("null".into()),
            JsonVal::Int(9_007_199_254_740_993),
            JsonVal::Bool(false),
            JsonVal::Array(vec![]),
            JsonVal::Object(vec![]),
        ];
        for (class, kind, _) in SERIALIZERS {
            let serializer = singleton(&mut vm, class).unwrap();
            vm.gc(&[]);
            assert_eq!(singleton(&mut vm, class).unwrap(), serializer);
            for value in &values {
                let valid = match *kind {
                    "JsonElement" => true,
                    "JsonNull" => matches!(value, JsonVal::Null),
                    "JsonArray" => matches!(value, JsonVal::Array(_)),
                    "JsonObject" => matches!(value, JsonVal::Object(_)),
                    "JsonLiteral" => !matches!(
                        value,
                        JsonVal::Null | JsonVal::Array(_) | JsonVal::Object(_)
                    ),
                    _ => !matches!(value, JsonVal::Array(_) | JsonVal::Object(_)),
                };
                let node = crate::json_compat::node(&mut vm, value.clone()).unwrap();
                let decoder = vm
                    .alloc_native(
                        "Lkotlinx/serialization/json/internal/StreamingJsonDecoder;",
                        Native::JsonDecoder {
                            element: node,
                            members: None,
                            index: 0,
                            module: None,
                        },
                    )
                    .unwrap();
                let encoder = encoder(&mut vm);
                if valid {
                    let decoded = deserialize(&mut vm, &[serializer, decoder]).unwrap();
                    assert!(matches!(vm.payload_of(decoded),Some(Native::Json(v)) if &v == value));
                    serialize(&mut vm, &[serializer, encoder, node]).unwrap();
                    assert!(
                        matches!(vm.payload_of(encoder),Some(Native::JsonEncoder {value:Some(v),..}) if &v == value)
                    );
                } else {
                    assert!(matches!(
                        deserialize(&mut vm, &[serializer, decoder]),
                        Err(NatErr::Throw(_))
                    ));
                    assert!(matches!(
                        serialize(&mut vm, &[serializer, encoder, node]),
                        Err(NatErr::Throw(_))
                    ));
                }
            }
        }
        let serializer = singleton(&mut vm, SERIALIZERS[0].0).unwrap();
        let nan = crate::json_compat::node(&mut vm, JsonVal::Double(f64::NAN)).unwrap();
        let encoder = encoder(&mut vm);
        assert!(matches!(
            serialize(&mut vm, &[serializer, encoder, nan]),
            Err(NatErr::Throw(_))
        ));
    }
    #[test]
    fn map_factory_keeps_both_serializers_and_nested_map_order_and_values() {
        let mut vm = vm();
        let key = singleton(&mut vm, "Lkotlinx/serialization/internal/StringSerializer;").unwrap();
        let element = singleton(&mut vm, SERIALIZERS[0].0).unwrap();
        let serializer = map_serializer(&mut vm, &[key, element]).unwrap();
        let first = vm.alloc_string("z\"日本");
        let second = vm.alloc_string("a");
        let number =
            crate::json_compat::node(&mut vm, JsonVal::Int(9_007_199_254_740_993)).unwrap();
        let null = crate::json_compat::node(&mut vm, JsonVal::Null).unwrap();
        let map = vm
            .alloc_native(
                "Ljava/util/LinkedHashMap;",
                Native::Map(vec![(first, number), (second, null)]),
            )
            .unwrap();
        let list_serializer = vm
            .alloc_native(
                "Lkotlinx/serialization/internal/ArrayListSerializer;",
                Native::ArrayListSerializer { child: serializer },
            )
            .unwrap();
        let list = vm
            .alloc_native("Ljava/util/ArrayList;", Native::List(vec![map]))
            .unwrap();
        vm.gc(&[list_serializer.as_obj(), list.as_obj()]);
        assert_eq!(
            encode(&mut vm, list_serializer, list).unwrap(),
            JsonVal::Array(vec![JsonVal::Object(vec![
                ("z\"日本".into(), JsonVal::Int(9_007_199_254_740_993)),
                ("a".into(), JsonVal::Null)
            ])])
        );
        assert_eq!(vm.recursion_depth, 0);
    }
    #[test]
    fn maps_reject_structured_keys_and_unwind_native_depth_on_failure() {
        let mut vm = vm();
        let element = singleton(&mut vm, SERIALIZERS[0].0).unwrap();
        let serializer = map_serializer(&mut vm, &[element, element]).unwrap();
        let key = crate::json_compat::node(&mut vm, JsonVal::Object(vec![])).unwrap();
        let value = crate::json_compat::node(&mut vm, JsonVal::Bool(false)).unwrap();
        let map = vm
            .alloc_native("Ljava/util/LinkedHashMap;", Native::Map(vec![(key, value)]))
            .unwrap();
        assert!(matches!(
            encode(&mut vm, serializer, map),
            Err(NatErr::Throw(_))
        ));
        assert_eq!(vm.recursion_depth, 0);
        let string =
            singleton(&mut vm, "Lkotlinx/serialization/internal/StringSerializer;").unwrap();
        let recursive = map_serializer(&mut vm, &[string, element]).unwrap();
        vm.arena.objects[recursive.as_obj() as usize].native =
            Some(Native::LinkedHashMapSerializer {
                key: string,
                value: recursive,
            });
        let key = vm.alloc_string("cycle");
        vm.arena.objects[map.as_obj() as usize].native = Some(Native::Map(vec![(key, map)]));
        vm.depth_limit = 4;
        assert!(matches!(
            encode(&mut vm, recursive, map),
            Err(NatErr::Fatal(JvmError::StackOverflow))
        ));
        assert_eq!(vm.recursion_depth, 0);
        vm.budget = 0;
        assert!(matches!(
            encode(&mut vm, serializer, map),
            Err(NatErr::Fatal(JvmError::BudgetExceeded))
        ));
    }
    #[test]
    fn json_and_map_descriptors_expose_real_kinds_and_child_serializers() {
        let mut vm = vm();
        for (class, name, _) in SERIALIZERS {
            let serializer = singleton(&mut vm, class).unwrap();
            let descriptor = descriptor(&mut vm, &[serializer]).unwrap();
            let kind = crate::descriptor_kind(&mut vm, &[descriptor]).unwrap();
            let name = match *name {
                "JsonElement" => "SEALED",
                "JsonNull" => "ENUM",
                "JsonObject" => "MAP",
                "JsonArray" => "LIST",
                _ => "STRING",
            };
            let actual = vm
                .invoke_virtual(kind, "toString", "()Ljava/lang/String;")
                .unwrap();
            assert_eq!(vm.str_of_jvalue(actual).as_deref(), Some(name));
            if name == "LIST" || name == "MAP" || name == "SEALED" {
                let child =
                    crate::element_descriptor(&mut vm, &[descriptor, JValue::Int(0)]).unwrap();
                assert!(matches!(
                    vm.payload_of(child),
                    Some(Native::SerialDescriptor { .. })
                ));
                assert_eq!(
                    crate::descriptor_element_optional(&mut vm, &[descriptor, JValue::Int(0)])
                        .unwrap(),
                    JValue::Int(0)
                );
            }
            assert!(matches!(
                crate::element_descriptor(&mut vm, &[descriptor, JValue::Int(-1)]),
                Err(NatErr::Throw(_))
            ));
        }
    }
}
