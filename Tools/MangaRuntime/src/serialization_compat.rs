//! Shared kotlinx.serialization and buffered-source compatibility.
use super::{abstract_function, JValue, NatErr, Vm};

pub(super) fn json_decode_sequentially(vm: &mut Vm, args: &[JValue]) -> Result<JValue, NatErr> {
    use dexvm::vm::object::{JsonVal, Native};
    let sequential = match vm.payload_of(args[0]) {
        Some(Native::JsonDecoder { element, .. }) => matches!(
            vm.payload_of(element),
            Some(Native::Json(JsonVal::Array(_)))
        ),
        _ => false,
    };
    Ok(JValue::Int(i32::from(sequential)))
}
pub(super) fn json_element_index(vm: &mut Vm, args: &[JValue]) -> Result<JValue, NatErr> {
    use dexvm::vm::object::{JsonVal, Native};
    let (element, index) = match vm.payload_of(args[0]) {
        Some(Native::JsonDecoder { element, index, .. }) => (element, index),
        _ => return Err(abstract_json_error(vm)),
    };
    let names = match vm.payload_of(args[1]) {
        Some(Native::SerialDescriptor { elements, .. }) => elements,
        _ => return Err(abstract_json_error(vm)),
    };
    let members = match vm.payload_of(element) {
        Some(Native::Json(JsonVal::Object(members))) => members,
        _ => return Err(abstract_json_error(vm)),
    };
    for (offset, (name, _)) in members.iter().enumerate().skip(index.max(0) as usize) {
        if let Some(Native::JsonDecoder { index, .. }) =
            &mut vm.arena.objects[args[0].as_obj() as usize].native
        {
            *index = (offset + 1) as i32;
        }
        if let Some(index) = names.iter().position(|n| n == name) {
            return Ok(JValue::Int(index as i32));
        }
    }
    Ok(JValue::Int(-1))
}
fn abstract_json_error(vm: &mut Vm) -> NatErr {
    NatErr::Throw(vm.throwable_of(
        "Ljava/lang/IllegalArgumentException;",
        "Expected a JSON object and descriptor",
    ))
}

pub(super) static ORIGINAL_LIST_DECODER: std::sync::OnceLock<dexvm::vm::NativeFn> =
    std::sync::OnceLock::new();

pub(super) fn unsupported_serialization(_vm: &mut Vm, _args: &[JValue]) -> Result<JValue, NatErr> {
    Err(NatErr::Fatal(dexvm::vm::error::JvmError::Resolution(
        "Unsupported serialization operation".into(),
    )))
}

// Preserve the generated serializer as a GC-traced object field: protobuf
// asks the descriptor for nested types before it invokes their decoders.
pub(super) fn descriptor_init(vm: &mut Vm, args: &[JValue]) -> Result<JValue, NatErr> {
    let name = vm.str_of_jvalue(args[1]).unwrap_or_default();
    let object = &mut vm.arena.objects[args[0].as_obj() as usize];
    object.native = Some(dexvm::vm::object::Native::SerialDescriptor {
        name,
        elements: Vec::new(),
        element_annotations: Vec::new(),
    });
    object.fields.push(args[2]);
    Ok(JValue::Null)
}
pub(super) fn element_descriptor(vm: &mut Vm, args: &[JValue]) -> Result<JValue, NatErr> {
    use dexvm::vm::object::{ArrayData, Native};
    let JValue::Int(index) = args[1] else {
        return Err(NatErr::Fatal(dexvm::vm::error::JvmError::Resolution(
            "Invalid descriptor index".into(),
        )));
    };
    let list = matches!(vm.payload_of(args[0]), Some(Native::SerialDescriptor { name, .. }) if name == "kotlin.collections.ArrayList");
    let valid = matches!(vm.payload_of(args[0]), Some(Native::SerialDescriptor { elements, .. })
        if index >= 0 && (list || (index as usize) < elements.len()));
    if !valid {
        return Err(NatErr::Throw(vm.throwable_of(
            "Ljava/lang/IndexOutOfBoundsException;",
            "Invalid descriptor child index",
        )));
    }
    let serializer = vm.arena.objects[args[0].as_obj() as usize]
        .fields
        .last()
        .copied()
        .unwrap_or(JValue::Null);
    if list {
        return vm
            .invoke_virtual(
                serializer,
                "getDescriptor",
                "()Lkotlinx/serialization/descriptors/SerialDescriptor;",
            )
            .map_err(NatErr::Fatal);
    }
    let children = vm
        .invoke_virtual(
            serializer,
            "childSerializers",
            "()[Lkotlinx/serialization/KSerializer;",
        )
        .map_err(NatErr::Fatal)?;
    let child = match vm.payload_of(children) {
        Some(Native::Array(ArrayData::Obj(children))) => children.get(index as usize).copied(),
        _ => None,
    }
    .ok_or_else(|| {
        NatErr::Throw(vm.throwable_of(
            "Ljava/lang/IndexOutOfBoundsException;",
            "Invalid descriptor child index",
        ))
    })?;
    vm.invoke_virtual(
        child,
        "getDescriptor",
        "()Lkotlinx/serialization/descriptors/SerialDescriptor;",
    )
    .map_err(NatErr::Fatal)
}
// Generated, primitive and collection descriptors themselves are not nullable;
// kotlinx.serialization represents nullable types with a separate wrapper.
pub(super) fn descriptor_not_nullable(_vm: &mut Vm, _args: &[JValue]) -> Result<JValue, NatErr> {
    Ok(JValue::Int(0))
}
pub(super) fn empty_serializers_module(vm: &mut Vm, _args: &[JValue]) -> Result<JValue, NatErr> {
    vm.alloc_native(
        "Lkotlinx/serialization/modules/SerializersModule;",
        dexvm::vm::object::Native::SerializersModule { polys: Vec::new() },
    )
    .map_err(NatErr::Fatal)
}
pub(super) fn decode_serializable_value(vm: &mut Vm, args: &[JValue]) -> Result<JValue, NatErr> {
    vm.invoke_virtual_args(
        args[1],
        "deserialize",
        "(Lkotlinx/serialization/encoding/Decoder;)Ljava/lang/Object;",
        vec![args[0]],
    )
    .map_err(NatErr::Fatal)
}
pub(super) fn buffered_read_byte(vm: &mut Vm, args: &[JValue]) -> Result<JValue, NatErr> {
    use dexvm::vm::object::Native;
    let object = &mut vm.arena.objects[args[0].as_obj() as usize];
    if let Some(Native::OkioBuf { bytes, pos }) = &mut object.native {
        if let Some(byte) = bytes.get(*pos) {
            let byte = *byte;
            *pos += 1;
            return Ok(JValue::Int(byte as i8 as i32));
        }
    }
    Err(NatErr::Throw(vm.throwable_of(
        "Ljava/io/EOFException;",
        "Buffer is exhausted",
    )))
}
pub(super) fn buffered_read_utf8(vm: &mut Vm, args: &[JValue]) -> Result<JValue, NatErr> {
    use dexvm::vm::object::Native;
    let JValue::Long(count) = args[1] else {
        return abstract_function(vm, args);
    };
    if count < 0 {
        return Err(NatErr::Throw(vm.throwable_of(
            "Ljava/lang/IllegalArgumentException;",
            "Negative byte count",
        )));
    }
    let count = usize::try_from(count).map_err(|_| {
        NatErr::Throw(vm.throwable_of("Ljava/lang/IllegalArgumentException;", "Invalid byte count"))
    })?;
    let text = match &mut vm.arena.objects[args[0].as_obj() as usize].native {
        Some(Native::OkioBuf { bytes, pos }) if count <= bytes.len().saturating_sub(*pos) => {
            let text = String::from_utf8_lossy(&bytes[*pos..*pos + count]).into_owned();
            *pos += count;
            Some(text)
        }
        _ => None,
    }
    .ok_or_else(|| {
        NatErr::Throw(vm.throwable_of("Ljava/io/EOFException;", "Buffer is exhausted"))
    })?;
    Ok(vm.alloc_string(&text))
}
pub(super) fn byte_array_serializer(vm: &mut Vm, _args: &[JValue]) -> Result<JValue, NatErr> {
    // The protobuf implementation compares this singleton by identity when
    // deciding whether a value is a wire byte string or a nested message.
    let class = vm
        .ensure_class_by_desc("Lkotlinx/serialization/internal/ByteArraySerializer;")
        .map_err(NatErr::Fatal)?;
    if let Some(value) = vm.classes[class as usize].statics.first() {
        return Ok(*value);
    }
    let value = vm
        .alloc_native(
            "Lkotlinx/serialization/internal/ByteArraySerializer;",
            dexvm::vm::object::Native::Opaque,
        )
        .map_err(NatErr::Fatal)?;
    vm.classes[class as usize].statics.push(value);
    vm.classes[class as usize].statics_lazy.push(None);
    Ok(value)
}
pub(super) fn primitive_descriptor(vm: &mut Vm, args: &[JValue]) -> Result<JValue, NatErr> {
    use dexvm::vm::object::{Native, PrimitiveSerializerKind};
    let name = match vm.payload_of(args[0]) {
        Some(Native::PrimitiveSerializer(PrimitiveSerializerKind::String)) => "kotlin.String",
        Some(Native::PrimitiveSerializer(PrimitiveSerializerKind::Int)) => "kotlin.Int",
        Some(Native::PrimitiveSerializer(PrimitiveSerializerKind::Long)) => "kotlin.Long",
        Some(Native::PrimitiveSerializer(PrimitiveSerializerKind::Float)) => "kotlin.Float",
        Some(Native::PrimitiveSerializer(PrimitiveSerializerKind::Double)) => "kotlin.Double",
        _ => return abstract_function(vm, args),
    };
    vm.alloc_native(
        "Lkotlinx/serialization/internal/PluginGeneratedSerialDescriptor;",
        Native::SerialDescriptor {
            name: name.into(),
            elements: vec![],
            element_annotations: vec![],
        },
    )
    .map_err(NatErr::Fatal)
}
pub(super) fn primitive_deserialize(vm: &mut Vm, args: &[JValue]) -> Result<JValue, NatErr> {
    use dexvm::vm::object::{Native, PrimitiveSerializerKind};
    let (method, sig) = match vm.payload_of(args[0]) {
        Some(Native::PrimitiveSerializer(PrimitiveSerializerKind::String)) => {
            ("decodeString", "()Ljava/lang/String;")
        }
        Some(Native::PrimitiveSerializer(PrimitiveSerializerKind::Int)) => ("decodeInt", "()I"),
        Some(Native::PrimitiveSerializer(PrimitiveSerializerKind::Long)) => ("decodeLong", "()J"),
        Some(Native::PrimitiveSerializer(PrimitiveSerializerKind::Float)) => ("decodeFloat", "()F"),
        Some(Native::PrimitiveSerializer(PrimitiveSerializerKind::Double)) => {
            ("decodeDouble", "()D")
        }
        _ => return abstract_function(vm, args),
    };
    let value = vm
        .invoke_virtual(args[1], method, sig)
        .map_err(NatErr::Fatal)?;
    match value {
        JValue::Int(value) => vm
            .alloc_native("Ljava/lang/Integer;", Native::IntBox(value))
            .map_err(NatErr::Fatal),
        JValue::Long(value) => vm
            .alloc_native("Ljava/lang/Long;", Native::LongBox(value))
            .map_err(NatErr::Fatal),
        JValue::Float(value) => vm
            .alloc_native("Ljava/lang/Float;", Native::FloatBox(value))
            .map_err(NatErr::Fatal),
        JValue::Double(value) => vm
            .alloc_native("Ljava/lang/Double;", Native::DoubleBox(value))
            .map_err(NatErr::Fatal),
        other => Ok(other),
    }
}
pub(super) fn list_descriptor(vm: &mut Vm, args: &[JValue]) -> Result<JValue, NatErr> {
    use dexvm::vm::object::Native;
    let child = match vm.payload_of(args[0]) {
        Some(Native::ArrayListSerializer { child }) => child,
        _ => return abstract_function(vm, args),
    };
    let descriptor = vm
        .alloc_native(
            "Lkotlinx/serialization/internal/PluginGeneratedSerialDescriptor;",
            Native::SerialDescriptor {
                name: "kotlin.collections.ArrayList".into(),
                elements: vec!["0".into()],
                element_annotations: vec![vec![]],
            },
        )
        .map_err(NatErr::Fatal)?;
    vm.arena.objects[descriptor.as_obj() as usize]
        .fields
        .push(child);
    Ok(descriptor)
}
pub(super) fn list_deserialize(vm: &mut Vm, args: &[JValue]) -> Result<JValue, NatErr> {
    use dexvm::vm::{error::JvmError, object::Native};
    if matches!(
        vm.payload_of(args[1]),
        Some(Native::JsonDecoder { .. } | Native::ProtoDecoder { .. })
    ) {
        return ORIGINAL_LIST_DECODER
            .get()
            .ok_or_else(|| NatErr::Fatal(JvmError::Resolution("Missing list decoder".into())))?(
            vm, args,
        );
    }
    let child = match vm.payload_of(args[0]) {
        Some(Native::ArrayListSerializer { child }) => child,
        _ => return abstract_function(vm, args),
    };
    let root = args[0].as_obj() as usize;
    let base = vm.arena.objects[root].fields.len();
    let result = (|| {
        let descriptor = list_descriptor(vm, args)?;
        vm.arena.objects[root].fields.push(descriptor);
        let decoder = vm.invoke_virtual_args(args[1], "beginStructure", "(Lkotlinx/serialization/descriptors/SerialDescriptor;)Lkotlinx/serialization/encoding/CompositeDecoder;", vec![descriptor]).map_err(NatErr::Fatal)?;
        vm.arena.objects[root].fields.push(decoder);
        let list = vm
            .alloc_native("Ljava/util/ArrayList;", Native::List(Vec::new()))
            .map_err(NatErr::Fatal)?;
        vm.arena.objects[root].fields.push(list);
        let sequential = vm
            .invoke_virtual(decoder, "decodeSequentially", "()Z")
            .map_err(NatErr::Fatal)?
            .as_int()
            != 0;
        let count = if sequential {
            vm.invoke_virtual_args(
                decoder,
                "decodeCollectionSize",
                "(Lkotlinx/serialization/descriptors/SerialDescriptor;)I",
                vec![descriptor],
            )
            .map_err(NatErr::Fatal)?
            .as_int()
        } else {
            -1
        };
        if sequential && !(0..=10_000).contains(&count) {
            return Err(NatErr::Fatal(JvmError::Resolution(
                "Invalid collection size".into(),
            )));
        }
        let mut length = 0;
        loop {
            let index = if sequential {
                if length == count {
                    break;
                }
                length
            } else {
                vm.invoke_virtual_args(
                    decoder,
                    "decodeElementIndex",
                    "(Lkotlinx/serialization/descriptors/SerialDescriptor;)I",
                    vec![descriptor],
                )
                .map_err(NatErr::Fatal)?
                .as_int()
            };
            if index == -1 {
                break;
            }
            if index != length || length >= 10_000 {
                return Err(NatErr::Fatal(JvmError::Resolution(
                    "Invalid or oversized collection".into(),
                )));
            }
            let item = vm.invoke_virtual_args(decoder, "decodeSerializableElement", "(Lkotlinx/serialization/descriptors/SerialDescriptor;ILkotlinx/serialization/DeserializationStrategy;Ljava/lang/Object;)Ljava/lang/Object;", vec![descriptor, JValue::Int(index), child, JValue::Null]).map_err(NatErr::Fatal)?;
            if let Some(Native::List(items)) = &mut vm.arena.objects[list.as_obj() as usize].native
            {
                items.push(item);
            }
            length += 1;
        }
        vm.invoke_virtual_args(
            decoder,
            "endStructure",
            "(Lkotlinx/serialization/descriptors/SerialDescriptor;)V",
            vec![descriptor],
        )
        .map_err(NatErr::Fatal)?;
        Ok(list)
    })();
    vm.arena.objects[root].fields.truncate(base);
    result
}

#[cfg(test)]
mod tests {
    use super::*;
    use dexvm::vm::object::Native;

    #[test]
    fn buffered_reads_consume_exact_bytes_and_preserve_cursor_on_failure() {
        let mut vm = Vm::new(vec![], Box::new(std::io::sink())).unwrap();
        let buffer = vm
            .alloc_native(
                "Lokio/BufferedSource;",
                Native::OkioBuf {
                    bytes: vec![0xe2, 0x82, 0xac, 0xff],
                    pos: 0,
                },
            )
            .unwrap();
        assert!(buffered_read_utf8(&mut vm, &[buffer, JValue::Long(5)]).is_err());
        assert!(buffered_read_utf8(&mut vm, &[buffer, JValue::Long(-1)]).is_err());
        let euro = buffered_read_utf8(&mut vm, &[buffer, JValue::Long(3)]).unwrap();
        assert_eq!(vm.str_of_jvalue(euro).as_deref(), Some("€"));
        assert!(matches!(
            buffered_read_byte(&mut vm, &[buffer]).unwrap(),
            JValue::Int(-1)
        ));
        assert!(buffered_read_byte(&mut vm, &[buffer]).is_err());
        assert!(matches!(
            vm.payload_of(buffer),
            Some(Native::OkioBuf { pos: 4, .. })
        ));
    }

    #[test]
    fn generated_descriptor_keeps_its_serializer_alive_across_gc() {
        let mut vm = Vm::new(vec![], Box::new(std::io::sink())).unwrap();
        let serializer = vm
            .alloc_native("Ljava/lang/Object;", Native::Opaque)
            .unwrap();
        let descriptor = vm
            .alloc_native(
                "Lkotlinx/serialization/internal/PluginGeneratedSerialDescriptor;",
                Native::Opaque,
            )
            .unwrap();
        let name = vm.alloc_string("Owned.model");
        descriptor_init(&mut vm, &[descriptor, name, serializer, JValue::Int(1)]).unwrap();
        vm.gc(&[descriptor.as_obj()]);
        assert!(matches!(vm.payload_of(serializer), Some(Native::Opaque)));
        assert_eq!(
            vm.arena.objects[descriptor.as_obj() as usize].fields[0].as_obj(),
            serializer.as_obj()
        );
        assert!(element_descriptor(&mut vm, &[descriptor, JValue::Int(-1)]).is_err());
        assert!(element_descriptor(&mut vm, &[descriptor, JValue::Int(0)]).is_err());
    }
}
