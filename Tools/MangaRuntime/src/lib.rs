//! On-device Keiyoushi APK execution. The Swift host owns networking and storage.
use base64::{engine::general_purpose::STANDARD, Engine};
use dexvm::keiyoushi::{Chapter, HttpData, HttpResp, Keiyoushi, Manga, Source};
use dexvm::permission::{FilesystemPermission, NetworkPermission, Permission, ProcessPermission};
use dexvm::vm::{NatErr, NativeEntry, Vm};
use dexvm::JValue;
use serde::Deserialize;
use serde_json::{json, Value};
use std::ffi::{c_char, c_void, CStr, CString};
use std::io::Cursor;
use std::panic::{catch_unwind, AssertUnwindSafe};

const MAX_APK: usize = 32 * 1024 * 1024;
const MAX_EXPANDED: u64 = 96 * 1024 * 1024;

mod jsoup_compat;
mod okio_compat;
mod serialization_compat;
mod source_settings;
use serialization_compat::*;

#[cfg(test)]
mod compatibility_tests;

// The extension supplies these functional-interface implementations itself.
// Register the host type so DEX lambdas can resolve their Java 8 interfaces;
// invoking an unimplemented abstract method must fail, never return fake data.
fn abstract_function(_vm: &mut Vm, _args: &[JValue]) -> Result<JValue, NatErr> {
    Err(NatErr::Fatal(dexvm::vm::error::JvmError::Resolution(
        "Unimplemented Java functional interface".into(),
    )))
}

// Network natives complete inline, but async must still retain thrown results
// until await. The pinned host silently converted every failed task to null.
fn coroutine_async(vm: &mut Vm, args: &[JValue]) -> Result<JValue, NatErr> {
    use dexvm::vm::{error::JvmError, object::Native};
    let (value, error) = match vm.invoke_virtual_args(
        args[3],
        "invoke",
        "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;",
        vec![args[0], JValue::Null],
    ) {
        Ok(value) => (value, JValue::Null),
        Err(JvmError::Uncaught(error)) => (JValue::Null, JValue::Obj(error)),
        Err(error) => return Err(NatErr::Fatal(error)),
    };
    vm.alloc_native(
        "Lkotlinx/coroutines/Deferred;",
        Native::Deferred { value, error },
    )
    .map_err(NatErr::Fatal)
}

fn coroutine_await(vm: &mut Vm, args: &[JValue]) -> Result<JValue, NatErr> {
    match vm.payload_of(args[0]) {
        Some(dexvm::vm::object::Native::Deferred { value, error }) => {
            if error.is_null() {
                Ok(value)
            } else {
                Err(NatErr::Throw(error.as_obj()))
            }
        }
        _ => Err(NatErr::Throw(vm.throwable_of(
            "Ljava/lang/NullPointerException;",
            "Invalid deferred result",
        ))),
    }
}

fn install_host_fields(vm: &mut Vm) -> Result<(), dexvm::vm::error::JvmError> {
    let owner = vm.ensure_class_by_desc("Lkotlin/time/Instant;")?;
    let name = vm.intern("Companion");
    let ty = vm.intern("Lkotlin/time/Instant$Companion;");
    if !vm.classes[owner as usize]
        .static_fields
        .contains_key(&(name, ty))
    {
        let value = vm.alloc_native(
            "Lkotlin/time/Instant$Companion;",
            dexvm::vm::object::Native::Opaque,
        )?;
        let class = &mut vm.classes[owner as usize];
        let offset = class.statics.len() as u32;
        class.statics.push(value);
        class.statics_lazy.push(None);
        class.static_fields.insert((name, ty), (owner, offset));
    }
    Ok(())
}
fn compute_if_absent(vm: &mut Vm, args: &[JValue]) -> Result<JValue, NatErr> {
    let existing = vm
        .invoke_virtual_args(
            args[0],
            "get",
            "(Ljava/lang/Object;)Ljava/lang/Object;",
            vec![args[1]],
        )
        .map_err(NatErr::Fatal)?;
    if !existing.is_null() {
        return Ok(existing);
    }
    let value = vm
        .invoke_virtual_args(
            args[2],
            "apply",
            "(Ljava/lang/Object;)Ljava/lang/Object;",
            vec![args[1]],
        )
        .map_err(NatErr::Fatal)?;
    if !value.is_null() {
        vm.invoke_virtual_args(
            args[0],
            "put",
            "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;",
            vec![args[1], value],
        )
        .map_err(NatErr::Fatal)?;
    }
    Ok(value)
}
fn descriptor_kind(vm: &mut Vm, args: &[JValue]) -> Result<JValue, NatErr> {
    let name = vm
        .invoke_virtual(args[0], "getSerialName", "()Ljava/lang/String;")
        .map_err(NatErr::Fatal)?;
    let name = vm.str_of_jvalue(name).unwrap_or_default();
    let class = match name.as_str() {
        "kotlin.String" => "Lkotlinx/serialization/descriptors/PrimitiveKind$STRING;",
        "kotlin.Int" => "Lkotlinx/serialization/descriptors/PrimitiveKind$INT;",
        "kotlin.Long" => "Lkotlinx/serialization/descriptors/PrimitiveKind$LONG;",
        "kotlin.Boolean" => "Lkotlinx/serialization/descriptors/PrimitiveKind$BOOLEAN;",
        "kotlin.Float" => "Lkotlinx/serialization/descriptors/PrimitiveKind$FLOAT;",
        "kotlin.Double" => "Lkotlinx/serialization/descriptors/PrimitiveKind$DOUBLE;",
        "kotlin.collections.ArrayList" | "kotlin.collections.LinkedHashSet" => {
            "Lkotlinx/serialization/descriptors/StructureKind$LIST;"
        }
        "kotlin.collections.LinkedHashMap" => {
            "Lkotlinx/serialization/descriptors/StructureKind$MAP;"
        }
        _ => "Lkotlinx/serialization/descriptors/StructureKind$CLASS;",
    };
    let field = dexvm::vm::FieldRef {
        class_desc: vm.intern(class),
        name: vm.intern("INSTANCE"),
        ty: vm.intern(class),
    };
    vm.static_field_get(field).map_err(NatErr::Fatal)
}
fn element_annotations(vm: &mut Vm, args: &[JValue]) -> Result<JValue, NatErr> {
    let JValue::Int(index) = args[1] else {
        return Err(NatErr::Fatal(dexvm::vm::error::JvmError::Resolution(
            "Invalid descriptor index".into(),
        )));
    };
    let annotations = match vm.payload_of(args[0]) {
        Some(dexvm::vm::object::Native::SerialDescriptor {
            element_annotations,
            ..
        }) => element_annotations.get(index as usize).cloned(),
        _ => None,
    }
    .ok_or_else(|| {
        NatErr::Fatal(dexvm::vm::error::JvmError::Resolution(
            "Descriptor index out of range".into(),
        ))
    })?;
    vm.alloc_native(
        "Ljava/util/ArrayList;",
        dexvm::vm::object::Native::List(annotations),
    )
    .map_err(NatErr::Fatal)
}
fn progression_iterator(vm: &mut Vm, args: &[JValue]) -> Result<JValue, NatErr> {
    use dexvm::vm::object::Native;
    let (first, last, step) = match vm.payload_of(args[0]) {
        Some(Native::IntProgression(a, b, c)) => (a, b, c),
        Some(Native::IntRange(a, b)) => (a, b, 1),
        _ => {
            return Err(NatErr::Fatal(dexvm::vm::error::JvmError::Resolution(
                "Invalid integer progression".into(),
            )))
        }
    };
    if step == 0 {
        return Err(NatErr::Fatal(dexvm::vm::error::JvmError::Resolution(
            "Zero progression step".into(),
        )));
    }
    let iterator = vm
        .alloc_native(
            "Lkotlin/collections/IntIterator;",
            Native::IntProgression(first, last, step),
        )
        .map_err(NatErr::Fatal)?;
    vm.arena.objects[iterator.as_obj() as usize]
        .fields
        .push(JValue::Int(i32::from(if step > 0 {
            first <= last
        } else {
            first >= last
        })));
    Ok(iterator)
}
fn integer_iterator_has_next(vm: &mut Vm, args: &[JValue]) -> Result<JValue, NatErr> {
    let object = &vm.arena.objects[args[0].as_obj() as usize];
    if let Some(value) = object.fields.first() {
        return Ok(*value);
    }
    match object.native {
        Some(dexvm::vm::object::Native::IntRange(first, last)) => {
            Ok(JValue::Int(i32::from(first <= last)))
        }
        _ => Err(NatErr::Fatal(dexvm::vm::error::JvmError::Resolution(
            "Invalid integer iterator".into(),
        ))),
    }
}
fn integer_iterator_next(vm: &mut Vm, args: &[JValue]) -> Result<JValue, NatErr> {
    if integer_iterator_has_next(vm, args)?.is_zero() {
        return Err(NatErr::Throw(vm.throwable_of(
            "Ljava/util/NoSuchElementException;",
            "Integer iterator is exhausted",
        )));
    }
    let object = &mut vm.arena.objects[args[0].as_obj() as usize];
    let (first, last, step) = match object.native {
        Some(dexvm::vm::object::Native::IntProgression(a, b, c)) => (a, b, c),
        Some(dexvm::vm::object::Native::IntRange(a, b)) => (a, b, 1),
        _ => {
            return Err(NatErr::Fatal(dexvm::vm::error::JvmError::Resolution(
                "Invalid integer iterator".into(),
            )))
        }
    };
    let next = i64::from(first) + i64::from(step);
    let more = if step > 0 {
        next <= i64::from(last)
    } else {
        next >= i64::from(last)
    };
    object.native = Some(dexvm::vm::object::Native::IntProgression(
        if more { next as i32 } else { first },
        last,
        step,
    ));
    object.fields = vec![JValue::Int(i32::from(more))];
    Ok(JValue::Int(first))
}
fn integer_iterator_boxed(vm: &mut Vm, args: &[JValue]) -> Result<JValue, NatErr> {
    let value = integer_iterator_next(vm, args)?.as_int();
    vm.alloc_native(
        "Ljava/lang/Integer;",
        dexvm::vm::object::Native::IntBox(value),
    )
    .map_err(NatErr::Fatal)
}
// The pinned host maps Regex.findAll$default to a single MatchResult. Sequence
// operations need every match. Materialize the host's collection representation
// with an aggregate bound instead of returning a malformed sequence.
fn regex_find_all(vm: &mut Vm, args: &[JValue]) -> Result<JValue, NatErr> {
    use dexvm::vm::object::{MatcherState, Native};
    let invalid = || {
        NatErr::Fatal(dexvm::vm::error::JvmError::Resolution(
            "Invalid regex sequence".into(),
        ))
    };
    let Some(Native::Pattern { re, .. }) = vm.payload_of(args[0]) else {
        return Err(invalid());
    };
    let text = vm.str_of_jvalue(args[1]).ok_or_else(invalid)?;
    let start = args[2].as_int();
    if start < 0 || start as usize > text.encode_utf16().count() {
        return Err(invalid());
    }
    let mut utf16 = 0;
    let byte_start = text
        .char_indices()
        .find_map(|(byte, ch)| {
            let hit = utf16 >= start as usize;
            utf16 += ch.len_utf16();
            hit.then_some(byte)
        })
        .unwrap_or(text.len());
    let mut items = Vec::new();
    for matched in re.captures_iter(&text) {
        let matched = matched.map_err(|_| invalid())?;
        let range = matched.get(0).ok_or_else(invalid)?;
        if range.start() < byte_start {
            continue;
        }
        if items.len() >= 10000 || (items.len() + 1) * text.len() > 32_000_000 {
            return Err(invalid());
        }
        let state = MatcherState {
            pattern: re.clone(),
            text: text.clone(),
            pos: range.end(),
            last: Some((range.start(), range.end())),
            groups: (0..matched.len())
                .map(|i| matched.get(i).map(|m| (m.start(), m.end())))
                .collect(),
        };
        items.push(
            vm.alloc_native("Lkotlin/text/MatcherMatchResult;", Native::Matcher(state))
                .map_err(NatErr::Fatal)?,
        );
    }
    vm.alloc_native("Ljava/util/ArrayList;", Native::List(items))
        .map_err(NatErr::Fatal)
}
fn regex_find_all_default(vm: &mut Vm, args: &[JValue]) -> Result<JValue, NatErr> {
    regex_find_all(
        vm,
        &[
            args[0],
            args[1],
            if args[3].as_int() & 2 != 0 {
                JValue::Int(0)
            } else {
                args[2]
            },
        ],
    )
}
fn image_url_request(vm: &mut Vm, args: &[JValue]) -> Result<JValue, NatErr> {
    use dexvm::vm::object::Native;
    let Some(Native::SPPage { url, .. }) = vm.payload_of(args[1]) else {
        return Err(NatErr::Fatal(dexvm::vm::error::JvmError::Resolution(
            "Invalid source page".into(),
        )));
    };
    let headers = vm
        .invoke_virtual(args[0], "getHeaders", "()Lokhttp3/Headers;")
        .map_err(NatErr::Fatal)?;
    let Some(Native::Headers(headers)) = vm.payload_of(headers) else {
        return Err(NatErr::Fatal(dexvm::vm::error::JvmError::Resolution(
            "Invalid source headers".into(),
        )));
    };
    vm.alloc_native(
        "Lokhttp3/Request;",
        Native::Request {
            url,
            method: "GET".into(),
            headers,
            body: None,
        },
    )
    .map_err(NatErr::Fatal)
}
static FUNCTION_INTERFACES: &[NativeEntry] = &[
    NativeEntry { class: "Lokio/BufferedSource;", name: "readUtf8", sig: "(J)Ljava/lang/String;", instance: true, f: buffered_read_utf8 },
    NativeEntry { class: "Lkotlinx/serialization/internal/PluginGeneratedSerialDescriptor;", name: "isInline", sig: "()Z", instance: true, f: descriptor_not_nullable },
    NativeEntry { class: "Lkotlinx/serialization/internal/ArrayListSerializer;", name: "getDescriptor", sig: "()Lkotlinx/serialization/descriptors/SerialDescriptor;", instance: true, f: list_descriptor },
    NativeEntry { class: "Lkotlinx/serialization/internal/ArrayListSerializer;", name: "deserialize", sig: "(Lkotlinx/serialization/encoding/Decoder;)Ljava/lang/Object;", instance: true, f: list_deserialize },
    NativeEntry {
        class: "Lkotlinx/serialization/internal/AbstractCollectionSerializer;",
        name: "merge",
        sig: "(Lkotlinx/serialization/encoding/Decoder;Ljava/lang/Object;)Ljava/lang/Object;",
        instance: true,
        f: unsupported_serialization,
    },
    NativeEntry {
        class: "Lkotlinx/serialization/builtins/BuiltinSerializersKt;",
        name: "ByteArraySerializer",
        sig: "()Lkotlinx/serialization/KSerializer;",
        instance: false,
        f: byte_array_serializer,
    },
    NativeEntry {
        class: "Lkotlinx/serialization/internal/ByteArraySerializer;",
        name: "deserialize",
        sig: "(Lkotlinx/serialization/encoding/Decoder;)Ljava/lang/Object;",
        instance: true,
        f: unsupported_serialization,
    },
    NativeEntry {
        class: "Lokio/BufferedSource;",
        name: "readByte",
        sig: "()B",
        instance: true,
        f: buffered_read_byte,
    },
    NativeEntry {
        class: "Lkotlinx/serialization/encoding/AbstractDecoder;",
        name: "decodeSequentially",
        sig: "()Z",
        instance: true,
        f: descriptor_not_nullable,
    },
    NativeEntry {
        class: "Lkotlinx/serialization/encoding/AbstractDecoder;",
        name: "decodeSerializableValue",
        sig: "(Lkotlinx/serialization/DeserializationStrategy;)Ljava/lang/Object;",
        instance: true,
        f: decode_serializable_value,
    },
    NativeEntry {
        class: "Lkotlinx/serialization/modules/SerializersModuleBuildersKt;",
        name: "EmptySerializersModule",
        sig: "()Lkotlinx/serialization/modules/SerializersModule;",
        instance: false,
        f: empty_serializers_module,
    },
    NativeEntry {
        class: "Lkotlinx/serialization/internal/PluginGeneratedSerialDescriptor;",
        name: "isNullable",
        sig: "()Z",
        instance: true,
        f: descriptor_not_nullable,
    },
    NativeEntry {
        class: "Lkotlinx/serialization/internal/PluginGeneratedSerialDescriptor;",
        name: "<init>",
        sig: "(Ljava/lang/String;Lkotlinx/serialization/internal/GeneratedSerializer;I)V",
        instance: true,
        f: descriptor_init,
    },
    NativeEntry {
        class: "Lkotlinx/serialization/internal/PluginGeneratedSerialDescriptor;",
        name: "getElementDescriptor",
        sig: "(I)Lkotlinx/serialization/descriptors/SerialDescriptor;",
        instance: true,
        f: element_descriptor,
    },
    NativeEntry {
        class: "Lkotlinx/coroutines/BuildersKt;",
        name: "async$default",
        sig: "(Lkotlinx/coroutines/CoroutineScope;Lkotlin/coroutines/CoroutineContext;Lkotlinx/coroutines/CoroutineStart;Lkotlin/jvm/functions/Function2;ILjava/lang/Object;)Lkotlinx/coroutines/Deferred;",
        instance: false,
        f: coroutine_async,
    },
    NativeEntry {
        class: "Lkotlinx/coroutines/Deferred;",
        name: "await",
        sig: "(Lkotlin/coroutines/Continuation;)Ljava/lang/Object;",
        instance: true,
        f: coroutine_await,
    },
    NativeEntry {
        class: "Leu/kanade/tachiyomi/source/online/HttpSource;",
        name: "imageUrlRequest",
        sig: "(Leu/kanade/tachiyomi/source/model/Page;)Lokhttp3/Request;",
        instance: true,
        f: image_url_request,
    },
    NativeEntry {
        class: "Lkotlin/text/Regex;",
        name: "findAll$default",
        sig: "(Lkotlin/text/Regex;Ljava/lang/CharSequence;IILjava/lang/Object;)Lkotlin/sequences/Sequence;",
        instance: false,
        f: regex_find_all_default,
    },
    NativeEntry {
        class: "Lkotlin/text/Regex;",
        name: "findAll",
        sig: "(Ljava/lang/CharSequence;I)Lkotlin/sequences/Sequence;",
        instance: true,
        f: regex_find_all,
    },
    NativeEntry {
        class: "Lkotlin/collections/IntIterator;",
        name: "hasNext",
        sig: "()Z",
        instance: true,
        f: integer_iterator_has_next,
    },
    NativeEntry {
        class: "Lkotlin/collections/IntIterator;",
        name: "nextInt",
        sig: "()I",
        instance: true,
        f: integer_iterator_next,
    },
    NativeEntry {
        class: "Lkotlin/collections/IntIterator;",
        name: "next",
        sig: "()Ljava/lang/Integer;",
        instance: true,
        f: integer_iterator_boxed,
    },
    NativeEntry {
        class: "Lkotlin/collections/IntIterator;",
        name: "next",
        sig: "()Ljava/lang/Object;",
        instance: true,
        f: integer_iterator_boxed,
    },
    NativeEntry {
        class: "Lkotlin/ranges/IntProgression;",
        name: "iterator",
        sig: "()Ljava/util/Iterator;",
        instance: true,
        f: progression_iterator,
    },
    NativeEntry {
        class: "Ljava/lang/annotation/Annotation;",
        name: "annotationType",
        sig: "()Ljava/lang/Class;",
        instance: true,
        f: abstract_function,
    },
    NativeEntry {
        class: "Lkotlinx/serialization/internal/PluginGeneratedSerialDescriptor;",
        name: "getElementAnnotations",
        sig: "(I)Ljava/util/List;",
        instance: true,
        f: element_annotations,
    },
    NativeEntry {
        class: "Lkotlinx/serialization/internal/PluginGeneratedSerialDescriptor;",
        name: "getKind",
        sig: "()Lkotlinx/serialization/descriptors/SerialKind;",
        instance: true,
        f: descriptor_kind,
    },
    NativeEntry {
        class: "Ljava/util/concurrent/ConcurrentHashMap;",
        name: "computeIfAbsent",
        sig: "(Ljava/lang/Object;Ljava/util/function/Function;)Ljava/lang/Object;",
        instance: true,
        f: compute_if_absent,
    },
    NativeEntry {
        class: "Ljava/util/HashMap;",
        name: "computeIfAbsent",
        sig: "(Ljava/lang/Object;Ljava/util/function/Function;)Ljava/lang/Object;",
        instance: true,
        f: compute_if_absent,
    },
    NativeEntry {
        class: "Ljava/util/function/Function;",
        name: "apply",
        sig: "(Ljava/lang/Object;)Ljava/lang/Object;",
        instance: true,
        f: abstract_function,
    },
    NativeEntry {
        class: "Ljava/util/function/BiFunction;",
        name: "apply",
        sig: "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;",
        instance: true,
        f: abstract_function,
    },
    NativeEntry {
        class: "Ljava/util/function/Consumer;",
        name: "accept",
        sig: "(Ljava/lang/Object;)V",
        instance: true,
        f: abstract_function,
    },
    NativeEntry {
        class: "Ljava/util/function/Predicate;",
        name: "test",
        sig: "(Ljava/lang/Object;)Z",
        instance: true,
        f: abstract_function,
    },
    NativeEntry {
        class: "Ljava/util/function/Supplier;",
        name: "get",
        sig: "()Ljava/lang/Object;",
        instance: true,
        f: abstract_function,
    },
];
type HttpCallback = unsafe extern "C" fn(*mut c_void, *const c_char) -> *mut c_char;
type ReleaseCallback = unsafe extern "C" fn(*mut c_char);

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Command {
    op: String,
    #[serde(default)]
    source: usize,
    #[serde(default = "first_page")]
    page: i32,
    #[serde(default)]
    query: String,
    #[serde(default)]
    modern: bool,
    #[serde(default)]
    manga: MangaInput,
    #[serde(default)]
    chapter: ChapterInput,
    #[serde(default)]
    image: ImageInput,
    #[serde(default, rename = "settingsSourceID")]
    settings_source_id: Option<String>,
    #[serde(default)]
    settings: std::collections::HashMap<String, source_settings::SettingValue>,
}
fn first_page() -> i32 {
    1
}

#[derive(Default, Deserialize)]
#[serde(default, rename_all = "camelCase")]
struct MangaInput {
    url: String,
    title: String,
}
#[derive(Default, Deserialize)]
#[serde(default)]
struct ChapterInput {
    url: String,
    name: String,
}

#[derive(Default, Deserialize)]
#[serde(default, rename_all = "camelCase")]
struct ImageInput {
    index: i32,
    url: String,
    #[serde(rename = "imageURL")]
    image_url: String,
}

fn chapter_numbers(ext: &mut Keiyoushi) -> std::collections::HashMap<String, f32> {
    ext.ctx()
        .vm()
        .arena
        .objects
        .iter()
        .filter_map(|object| {
            if let Some(dexvm::vm::object::Native::SChapter {
                url,
                chapter_number,
                ..
            }) = &object.native
            {
                if chapter_number.is_finite() && *chapter_number >= 0.0 {
                    return Some((url.clone(), *chapter_number));
                }
            }
            None
        })
        .collect()
}

fn chapters_json(ext: &mut Keiyoushi, list: Vec<Chapter>) -> Value {
    let numbers = chapter_numbers(ext);
    json!(list
        .into_iter()
        .map(
            |c| json!({"url":c.url,"name":c.name,"uploadedAt":c.date_upload,
        "scanlator":c.scanlator,"chapterNumber":numbers.get(&c.url)})
        )
        .collect::<Vec<_>>())
}

fn modern_book(ext: &mut Keiyoushi, src: &Source, manga: &Manga) -> Result<Value, String> {
    use dexvm::vm::object::Native;
    let update = ext.manga_update_coro(src, manga, true, true).map_err(|e| {
        #[cfg(test)]
        eprintln!("Manga update trace: {:?}", ext.ctx().vm().trace_ring);
        ext.describe_error(&e)
    })?;
    let m = ext
        .ctx()
        .invoke_on(
            update.as_obj(),
            "getManga",
            "()Leu/kanade/tachiyomi/source/model/SManga;",
            &[],
        )
        .map_err(|e| ext.describe_error(&e))?;
    let data = match ext.ctx().vm().payload_of(m) {
        Some(Native::SManga {
            title,
            author,
            artist,
            description,
            genre,
            status,
            thumbnail_url,
            url,
            ..
        }) => manga_json(Manga {
            title,
            author: author.unwrap_or_default(),
            artist: artist.unwrap_or_default(),
            description: description.unwrap_or_default(),
            genre: genre.unwrap_or_default(),
            status,
            thumbnail_url,
            url,
        }),
        _ => return Err("The source returned invalid title details.".into()),
    };
    let list = ext
        .ctx()
        .invoke_on(update.as_obj(), "getChapters", "()Ljava/util/List;", &[])
        .map_err(|e| ext.describe_error(&e))?;
    let Some(Native::List(items)) = ext.ctx().vm().payload_of(list) else {
        return Err("The source returned an invalid chapter list.".into());
    };
    if items.len() > 10000 {
        return Err("This title has too many chapters.".into());
    }
    let chapters: Vec<Value> = items.into_iter().filter_map(|item| {
        match ext.ctx().vm().payload_of(item) {
            Some(Native::SChapter { name, url, date_upload, scanlator, chapter_number, .. }) =>
                Some(json!({"name":name,"url":url,"uploadedAt":date_upload,"scanlator":scanlator,
                    "chapterNumber":if chapter_number.is_finite() && chapter_number >= 0.0 {Some(chapter_number)}else{None}})),
            _ => None,
        }
    }).collect();
    Ok(json!({"manga":data,"chapters":chapters}))
}

/// Keep the source Page, imageRequest, headers and OkHttp interceptors together.
/// URL resolution is lazy; source image bytes can be decrypted by its own client.
fn source_image(
    ext: &mut Keiyoushi,
    src: &Source,
    input: ImageInput,
    modern: bool,
) -> Result<Vec<u8>, String> {
    use dexvm::vm::object::Native;
    let page = ext
        .ctx()
        .vm()
        .alloc_native(
            "Leu/kanade/tachiyomi/source/model/Page;",
            Native::SPPage {
                index: input.index,
                name: String::new(),
                url: input.url,
                image_url: input.image_url.clone(),
            },
        )
        .map_err(|e| ext.describe_error(&e))?;
    if input.image_url.is_empty() {
        let resolved = if modern {
            let cid = ext
                .ctx()
                .vm()
                .ensure_class_by_desc("Lkotlin/coroutines/jvm/internal/ContinuationImpl;")
                .map_err(|e| ext.describe_error(&e))?;
            let continuation = JValue::Obj(
                ext.ctx()
                    .vm()
                    .alloc_instance(cid)
                    .map_err(|e| ext.describe_error(&e))?,
            );
            ext.ctx().invoke_on(src.inst(), "getImageUrl",
                "(Leu/kanade/tachiyomi/source/model/Page;Lkotlin/coroutines/Continuation;)Ljava/lang/Object;", &[page, continuation])
                .map_err(|e| ext.describe_error(&e))?
        } else {
            let observable = ext
                .ctx()
                .invoke_on(
                    src.inst(),
                    "fetchImageUrl",
                    "(Leu/kanade/tachiyomi/source/model/Page;)Lrx/Observable;",
                    &[page],
                )
                .map_err(|e| ext.describe_error(&e))?;
            let blocking = ext
                .ctx()
                .invoke_on(
                    observable.as_obj(),
                    "toBlocking",
                    "()Lrx/observables/BlockingObservable;",
                    &[],
                )
                .map_err(|e| ext.describe_error(&e))?;
            ext.ctx()
                .invoke_on(blocking.as_obj(), "first", "()Ljava/lang/Object;", &[])
                .map_err(|e| ext.describe_error(&e))?
        };
        let url = ext
            .ctx()
            .string_of(resolved.as_obj())
            .filter(|s| !s.is_empty())
            .ok_or("The source did not resolve an image.")?;
        if let Some(Native::SPPage { image_url, .. }) = ext.ctx().vm().arena.objects
            [page.as_obj() as usize]
            .native
            .as_mut()
        {
            *image_url = url;
        }
    }
    let source_headers = ext
        .ctx()
        .invoke_on(src.inst(), "getHeaders", "()Lokhttp3/Headers;", &[])
        .map_err(|e| ext.describe_error(&e))?;
    let mut additions = match ext.ctx().vm().payload_of(source_headers) {
        Some(Native::Headers(headers)) => headers,
        _ => return Err("The source returned invalid image headers.".into()),
    };
    if !additions
        .iter()
        .any(|(name, _)| name.eq_ignore_ascii_case("referer"))
    {
        let base = ext
            .source_base_url(src)
            .map_err(|e| ext.describe_error(&e))?;
        additions.push(("Referer".into(), format!("{}/", base.trim_end_matches('/'))));
    }
    let request = ext
        .ctx()
        .invoke_on(
            src.inst(),
            "imageRequest",
            "(Leu/kanade/tachiyomi/source/model/Page;)Lokhttp3/Request;",
            &[page],
        )
        .map_err(|e| ext.describe_error(&e))?;
    let Some(Native::Request { headers, .. }) = ext.ctx().vm().arena.objects
        [request.as_obj() as usize]
        .native
        .as_mut()
    else {
        return Err("The source returned an invalid image request.".into());
    };
    for (name, value) in additions {
        if !headers
            .iter()
            .any(|(existing, _)| existing.eq_ignore_ascii_case(&name))
        {
            headers.push((name, value));
        }
    }
    let client = ext
        .ctx()
        .invoke_on(src.inst(), "getClient", "()Lokhttp3/OkHttpClient;", &[])
        .map_err(|e| ext.describe_error(&e))?;
    let call = ext
        .ctx()
        .invoke_on(
            client.as_obj(),
            "newCall",
            "(Lokhttp3/Request;)Lokhttp3/Call;",
            &[request],
        )
        .map_err(|e| ext.describe_error(&e))?;
    let response = ext
        .ctx()
        .invoke_on(call.as_obj(), "execute", "()Lokhttp3/Response;", &[])
        .map_err(|e| ext.describe_error(&e))?;
    match ext.ctx().vm().payload_of(response) {
        Some(Native::Response {
            code: 200..=299,
            body: Some(data),
            ..
        }) if !data.is_empty() && data.len() <= 16_000_000 => Ok(data),
        _ => Err("The source image could not be loaded.".into()),
    }
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct HostResponse {
    code: i32,
    #[serde(default)]
    headers: Vec<(String, String)>,
    #[serde(default)]
    body_base64: String,
}

fn validate_apk(apk: &[u8]) -> Result<(), String> {
    if apk.is_empty() || apk.len() > MAX_APK {
        return Err("Extension exceeds the package size limit.".into());
    }
    let mut archive =
        zip::ZipArchive::new(Cursor::new(apk)).map_err(|_| "Invalid extension archive.")?;
    if archive.len() > 2048 {
        return Err("Extension contains too many resources.".into());
    }
    let mut total = 0_u64;
    let mut has_dex = false;
    for i in 0..archive.len() {
        let file = archive
            .by_index(i)
            .map_err(|_| "Invalid extension archive entry.")?;
        total = total
            .checked_add(file.size())
            .ok_or("Invalid extension resource size.")?;
        if total > MAX_EXPANDED || file.size() > MAX_APK as u64 {
            return Err("Extension expands beyond the resource limit.".into());
        }
        has_dex |= file.name() == "classes.dex";
    }
    if !has_dex {
        return Err("This package contains no Android extension bytecode.".into());
    }
    Ok(())
}

fn manga_json(m: Manga) -> Value {
    json!({"url":m.url,"title":m.title,"author":m.author,"artist":m.artist,
        "description":m.description,"genre":m.genre,"status":m.status,"thumbnailURL":m.thumbnail_url})
}

fn source_json(ext: &mut Keiyoushi, source: &Source, index: usize) -> Result<Value, String> {
    // Source IDs remain strings throughout the C/Swift bridge (they exceed JS's integer range).
    let name = ext
        .source_name(source)
        .map_err(|e| ext.describe_error(&e))?;
    let language = ext
        .source_lang(source)
        .map_err(|e| ext.describe_error(&e))?;
    let id = ext
        .source_id(source)
        .map_err(|e| ext.describe_error(&e))?
        .to_string();
    let home_url = ext
        .source_base_url(source)
        .map_err(|e| ext.describe_error(&e))?;
    let supports_latest = ext.supports_latest(source).unwrap_or(false);
    Ok(
        json!({"index":index,"id":id,"name":name,"language":language,
        "homeURL":home_url,"supportsLatest":supports_latest}),
    )
}

fn execute<F>(apk: &[u8], command: Command, http: F) -> Result<Value, String>
where
    F: Fn(&HttpData) -> HttpResp + 'static,
{
    validate_apk(apk)?;
    if command.page < 1 || command.page > 10000 || command.query.len() > 4096 {
        return Err("Invalid source request.".into());
    }
    let mut ext = Keiyoushi::new_with_libraries(
        apk,
        &[include_bytes!("../support/serialization-decoder.dex")],
    )
    .map_err(|e| e.to_string())?;
    // The convenience constructor grants all capabilities. Remove them before
    // executing any extension constructor or method; only host-mediated HTTP remains.
    for permission in [
        Permission::Filesystem(FilesystemPermission::Any),
        Permission::Process(ProcessPermission::Any),
        Permission::Env,
        Permission::Network(NetworkPermission::Any),
    ] {
        ext.ctx().revoke(&permission);
    }
    ext.ctx().grant(Permission::Network(NetworkPermission::Any));
    ext.ctx().vm().budget = 30_000_000;
    ext.ctx().vm().depth_limit = 256;
    // Load the bundled boot class first so registration replaces its default
    // method. The pinned VM cannot resolve its interface invoke-super path.
    ext.ctx()
        .vm()
        .ensure_class_by_desc("Lkotlinx/serialization/encoding/AbstractDecoder;")
        .map_err(|e| e.to_string())?;
    let vm = ext.ctx().vm();
    let list_key = (
        vm.intern("Lkotlinx/serialization/internal/ArrayListSerializer;"),
        vm.intern("deserialize"),
        vm.intern("(Lkotlinx/serialization/encoding/Decoder;)Ljava/lang/Object;"),
    );
    let original = *vm
        .natives
        .get(&list_key)
        .ok_or("Missing built-in list decoder")?;
    let _ = ORIGINAL_LIST_DECODER.set(original);
    ext.ctx()
        .register_natives(&[FUNCTION_INTERFACES])
        .map_err(|e| e.to_string())?;
    for class in [
        "Lkotlinx/serialization/internal/StringSerializer;",
        "Lkotlinx/serialization/internal/IntSerializer;",
        "Lkotlinx/serialization/internal/LongSerializer;",
        "Lkotlinx/serialization/internal/FloatSerializer;",
        "Lkotlinx/serialization/internal/DoubleSerializer;",
    ] {
        ext.ctx()
            .vm()
            .register_native(NativeEntry {
                class,
                name: "getDescriptor",
                sig: "()Lkotlinx/serialization/descriptors/SerialDescriptor;",
                instance: true,
                f: primitive_descriptor,
            })
            .map_err(|e| e.to_string())?;
        ext.ctx()
            .vm()
            .register_native(NativeEntry {
                class,
                name: "deserialize",
                sig: "(Lkotlinx/serialization/encoding/Decoder;)Ljava/lang/Object;",
                instance: true,
                f: primitive_deserialize,
            })
            .map_err(|e| e.to_string())?;
    }
    install_host_fields(ext.ctx().vm()).map_err(|e| e.to_string())?;
    jsoup_compat::install(ext.ctx().vm()).map_err(|e| e.to_string())?;
    okio_compat::install(ext.ctx().vm()).map_err(|e| e.to_string())?;
    source_settings::install(ext.ctx().vm()).map_err(|e| e.to_string())?;
    source_settings::seed(
        &mut ext,
        command.settings_source_id.as_deref(),
        &command.settings,
    )?;
    ext.set_http(move |request| {
        // A source may retain an image-decryption key in the URL fragment.
        // HTTP never transmits fragments; keep it in the VM for interceptors,
        // while the Swift transport receives only the network URL.
        if let Some((url, _)) = request.url.split_once('#') {
            let mut transport = request.clone();
            transport.url = url.to_owned();
            http(&transport)
        } else {
            http(request)
        }
    });
    let manifest = ext.manifest().map_err(|e| e.to_string())?;
    if !manifest
        .package_id
        .starts_with("eu.kanade.tachiyomi.extension.")
    {
        return Err("This APK is not a Mihon source extension.".into());
    }
    let sources = ext.sources().map_err(|e| ext.describe_error(&e))?;
    if sources.is_empty() || sources.len() > 512 {
        return Err("Extension declared an invalid source list.".into());
    }
    if command.op == "inspect" {
        let mut list = Vec::with_capacity(sources.len());
        for (index, source) in sources.iter().enumerate() {
            list.push(source_json(&mut ext, source, index)?);
        }
        return Ok(
            json!({"packageName":manifest.package_id,"versionName":manifest.version_name,"sources":list}),
        );
    }
    let src = sources
        .get(command.source)
        .ok_or("This extension no longer contains the selected source.")?;
    if let Some(expected) = &command.settings_source_id {
        let actual = ext
            .source_id(src)
            .map_err(|e| ext.describe_error(&e))?
            .to_string();
        if &actual != expected {
            return Err("Source settings identity does not match".into());
        }
    }
    if command.op == "settings" {
        return source_settings::definitions(&mut ext, src);
    }
    let manga = Manga {
        url: command.manga.url,
        title: command.manga.title,
        ..Default::default()
    };
    let chapter = Chapter {
        url: command.chapter.url,
        name: command.chapter.name,
        ..Default::default()
    };
    match command.op.as_str() {
        "image" => {
            let data = source_image(&mut ext, src, command.image, command.modern)?;
            Ok(json!({"bodyBase64":STANDARD.encode(data)}))
        }
        "book" => {
            if command.modern {
                modern_book(&mut ext, src, &manga)
            } else {
                let details = ext
                    .manga_details(src, &manga)
                    .map_err(|e| ext.describe_error(&e))?;
                let chapters = ext
                    .chapters(src, &manga)
                    .map_err(|e| ext.describe_error(&e))?;
                if chapters.len() > 10000 {
                    return Err("This title has too many chapters.".into());
                }
                let chapters = chapters_json(&mut ext, chapters);
                Ok(json!({"manga":manga_json(details),"chapters":chapters}))
            }
        }
        "popular" | "latest" | "search" => {
            let result = match (command.op.as_str(), command.modern) {
                ("popular", true) => ext.popular_coro(src, command.page),
                ("popular", false) => ext.popular(src, command.page),
                ("latest", true) => ext.latest_coro(src, command.page),
                ("latest", false) => ext.latest(src, command.page),
                (_, true) => ext.search_coro(src, command.page, &command.query, &[]),
                (_, false) => ext.search(src, command.page, &command.query, &[]),
            }
            .map_err(|e| ext.describe_error(&e))?;
            Ok(
                json!({"mangas":result.mangas.into_iter().map(manga_json).collect::<Vec<_>>(),"hasNext":result.has_next}),
            )
        }
        "details" => {
            let m = if command.modern {
                ext.manga_update_details(src, &manga)
            } else {
                ext.manga_details(src, &manga)
            }
            .map_err(|e| ext.describe_error(&e))?;
            Ok(manga_json(m))
        }
        "chapters" => {
            let list = if command.modern {
                ext.manga_update_chapters(src, &manga)
            } else {
                ext.chapters(src, &manga)
            }
            .map_err(|e| ext.describe_error(&e))?;
            Ok(chapters_json(&mut ext, list))
        }
        "pages" => {
            let list = if command.modern {
                ext.pages_coro(src, &chapter)
            } else {
                ext.pages(src, &chapter)
            }
            .map_err(|e| ext.describe_error(&e))?;
            if list.len() > 5000 {
                return Err("This chapter has too many pages.".into());
            }
            Ok(json!(list
                .into_iter()
                .map(|p| json!({"index":p.index,"url":p.url,"imageURL":p.image_url}))
                .collect::<Vec<_>>()))
        }
        _ => Err("Unknown manga runtime operation.".into()),
    }
}

/// # Safety
/// apk points to apk_length readable bytes; command_json is NUL-terminated.
/// Host callbacks and context remain valid until this synchronous call returns.
#[no_mangle]
pub unsafe extern "C" fn ac_manga_execute(
    apk: *const u8,
    apk_length: usize,
    command_json: *const c_char,
    http: Option<HttpCallback>,
    release_http: Option<ReleaseCallback>,
    context: *mut c_void,
) -> *mut c_char {
    let outcome = catch_unwind(AssertUnwindSafe(|| -> Result<Value, String> {
        if apk.is_null() || command_json.is_null() || apk_length == 0 || apk_length > MAX_APK {
            return Err("Invalid extension input.".into());
        }
        let command: Command = serde_json::from_slice(CStr::from_ptr(command_json).to_bytes())
            .map_err(|_| "Invalid extension command.")?;
        let bytes = std::slice::from_raw_parts(apk, apk_length);
        execute(bytes, command, move |request| {
            let fallback = || HttpResp {
                code: 599,
                message: "Source request failed".into(),
                headers: vec![],
                body: None,
            };
            let (Some(callback), Some(release)) = (http, release_http) else {
                return fallback();
            };
            let Ok(input) = CString::new(
                json!({"url":request.url,"method":request.method,
                "headers":request.headers,"body":request.body})
                .to_string(),
            ) else {
                return fallback();
            };
            let result = callback(context, input.as_ptr());
            if result.is_null() {
                return fallback();
            }
            let decoded = serde_json::from_slice::<HostResponse>(CStr::from_ptr(result).to_bytes());
            release(result);
            let Ok(response) = decoded else {
                return fallback();
            };
            let Ok(body) = STANDARD.decode(response.body_base64) else {
                return fallback();
            };
            HttpResp {
                code: response.code,
                message: "HTTP response".into(),
                headers: response.headers,
                body: Some(body),
            }
        })
    }));
    let response = match outcome {
        Ok(Ok(value)) => json!({"ok":true,"data":value}),
        Ok(Err(error)) => json!({"ok":false,"error":error}),
        Err(_) => {
            json!({"ok":false,"error":"This extension could not be executed by the on-device runtime."})
        }
    };
    CString::new(response.to_string())
        .unwrap_or_default()
        .into_raw()
}

/// # Safety
/// string was returned by ac_manga_execute and has not already been freed.
#[no_mangle]
pub unsafe extern "C" fn ac_manga_free_string(string: *mut c_char) {
    if !string.is_null() {
        drop(CString::from_raw(string));
    }
}

#[cfg(test)]
mod weebcentral_tests;

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn image_bytes_follow_the_real_source_client_and_headers_for_both_apis() {
        let dir = std::env::var("MANGA_TEST_APK_DIR").expect("Run test-manga-runtime.sh");
        for (file, modern) in [
            ("tachiyomi-all.akuma-v1.4.10.apk", false),
            ("tachiyomi-all.commitstrip-v1.6.0.apk", true),
        ] {
            let apk = std::fs::read(format!("{dir}/{file}")).unwrap();
            let command = serde_json::from_value(json!({"op":"image","modern":modern,
                "image":{"index":7,"url":"https://source.example/chapter#page-data","imageURL":"https://images.example/page.jpg"}})).unwrap();
            let result = execute(&apk, command, |request| {
                assert_eq!(request.method, "GET");
                assert_eq!(request.url, "https://images.example/page.jpg");
                assert!(request
                    .headers
                    .iter()
                    .any(|(key, value)| key.eq_ignore_ascii_case("referer") && !value.is_empty()));
                HttpResp {
                    code: 200,
                    message: "OK".into(),
                    headers: vec![("Content-Type".into(), "image/jpeg".into())],
                    body: Some(vec![0, 255, 10, 128, 65]),
                }
            })
            .unwrap();
            assert_eq!(
                STANDARD
                    .decode(result["bodyBase64"].as_str().unwrap())
                    .unwrap(),
                vec![0, 255, 10, 128, 65]
            );
        }
    }
    #[test]
    fn failed_image_responses_are_not_returned_as_readable_page_data() {
        use std::sync::{
            atomic::{AtomicUsize, Ordering},
            Arc,
        };
        let dir = std::env::var("MANGA_TEST_APK_DIR").expect("Run test-manga-runtime.sh");
        let apk = std::fs::read(format!("{dir}/tachiyomi-all.commitstrip-v1.6.0.apk")).unwrap();
        let command = serde_json::from_value(json!({"op":"image","modern":true,
            "image":{"imageURL":"https://images.example/unavailable.jpg"}}))
        .unwrap();
        let calls = Arc::new(AtomicUsize::new(0));
        let observed = calls.clone();
        let result = execute(&apk, command, move |_| {
            observed.fetch_add(1, Ordering::SeqCst);
            HttpResp {
                code: 403,
                message: "Forbidden".into(),
                headers: vec![],
                body: Some(b"<html>denied</html>".to_vec()),
            }
        });
        assert_eq!(calls.load(Ordering::SeqCst), 1);
        assert!(result.is_err());
    }
    #[test]
    fn modern_book_and_pages_execute_real_extension_parsers() {
        let dir = std::env::var("MANGA_TEST_APK_DIR").expect("Run test-manga-runtime.sh");
        let apk = std::fs::read(format!("{dir}/tachiyomi-all.commitstrip-v1.6.0.apk")).unwrap();
        let command = serde_json::from_value(json!({"op":"book","modern":true,
            "manga":{"url":"https://www.commitstrip.com/en/2026","title":"Owned parser fixture"}}))
        .unwrap();
        let book = execute(&apk, command, |request| {
            assert!(request.url.starts_with("https://www.commitstrip.com/"));
            HttpResp::ok(r#"<html><body><div class="excerpt"><a href="https://www.commitstrip.com/2026/09/04/second"><span>Owned second chapter</span></a><a href="https://www.commitstrip.com/2026/09/03/first"><span>Owned first chapter</span></a></div></body></html>"#)
        }).unwrap();
        assert_eq!(book["manga"]["title"], "Owned parser fixture");
        let chapters = book["chapters"].as_array().unwrap();
        assert_eq!(chapters.len(), 2);
        assert_eq!(chapters[0]["chapterNumber"], 2.0);
        assert_eq!(chapters[1]["chapterNumber"], 1.0);
        let command = serde_json::from_value(json!({"op":"pages","modern":true,
            "chapter":{"url":chapters[0]["url"],"name":chapters[0]["name"]}}))
        .unwrap();
        let pages = execute(&apk, command, |_| HttpResp::ok(r#"<html><body><div class="entry-content"><p><img src="https://images.example/owned-strip.png"></p></div></body></html>"#)).unwrap();
        assert_eq!(pages[0]["index"], 0);
        assert_eq!(
            pages[0]["imageURL"],
            "https://images.example/owned-strip.png"
        );
    }
    #[test]
    fn classic_book_pages_and_lazy_images_execute_real_extension_parsers() {
        let dir = std::env::var("MANGA_TEST_APK_DIR").expect("Run test-manga-runtime.sh");
        let apk = std::fs::read(format!("{dir}/tachiyomi-all.akuma-v1.4.10.apk")).unwrap();
        let html = r#"<html><body><h1 class="entry-title">Owned parser story</h1><span>Owned synopsis</span><img class="img-thumbnail" src="https://images.example/cover.jpg"><select class="nav-select"><option value="1">1</option><option value="2">2</option></select><div class="entry-content"><img src="https://images.example/owned-page.jpg"></div></body></html>"#;
        let command = serde_json::from_value(json!({"op":"book","modern":false,
            "manga":{"url":"/g/fixture","title":"Owned parser story"}}))
        .unwrap();
        let book = execute(&apk, command, move |_| HttpResp::ok(html)).unwrap();
        assert_eq!(book["manga"]["title"], "Owned parser story");
        let chapter = &book["chapters"][0];
        let command = serde_json::from_value(json!({"op":"pages","modern":false,
            "chapter":{"url":chapter["url"],"name":chapter["name"]}}))
        .unwrap();
        let pages = execute(&apk, command, move |_| HttpResp::ok(html)).unwrap();
        assert_eq!(pages.as_array().unwrap().len(), 2);
        assert_eq!(
            pages[0]["imageURL"],
            "https://images.example/owned-page.jpg"
        );
        assert_eq!(pages[1]["imageURL"], "");
        let command =
            serde_json::from_value(json!({"op":"image","modern":false,"image":pages[1]})).unwrap();
        let image = execute(&apk, command, move |request| {
            if request.url == "https://images.example/owned-page.jpg" {
                HttpResp {
                    code: 200,
                    message: "OK".into(),
                    headers: vec![],
                    body: Some(vec![1, 2, 255, 0]),
                }
            } else {
                HttpResp::ok(html)
            }
        })
        .unwrap();
        assert_eq!(
            STANDARD
                .decode(image["bodyBase64"].as_str().unwrap())
                .unwrap(),
            vec![1, 2, 255, 0]
        );
    }
    #[test]
    fn modern_extension_executes_its_real_catalog_and_detail_code() {
        let dir = std::env::var("MANGA_TEST_APK_DIR").expect("Run test-manga-runtime.sh");
        let apk = std::fs::read(format!("{dir}/tachiyomi-all.commitstrip-v1.6.0.apk")).unwrap();
        let command = serde_json::from_value(json!({"op":"popular","modern":true})).unwrap();
        let page = execute(&apk, command, |_| {
            panic!("This extension builds its year catalog without HTTP")
        })
        .unwrap();
        assert!(page["mangas"].as_array().unwrap().len() >= 5);
        let first = &page["mangas"][0];
        let command = serde_json::from_value(json!({"op":"details","modern":true,"manga":{"url":first["url"],"title":first["title"]}})).unwrap();
        let detail = execute(&apk, command, |_| {
            panic!("Title details are computed by the extension")
        })
        .unwrap();
        assert_eq!(detail["url"], first["url"]);
        assert!(!detail["title"].as_str().unwrap().is_empty());
    }
    #[test]
    fn classic_extension_builds_requests_and_parses_host_responses() {
        let dir = std::env::var("MANGA_TEST_APK_DIR").expect("Run test-manga-runtime.sh");
        let apk = std::fs::read(format!("{dir}/tachiyomi-all.akuma-v1.4.10.apk")).unwrap();
        let command = serde_json::from_value(json!({"op":"popular","modern":false})).unwrap();
        let result = execute(&apk, command, |request| {
            assert!(request.url.starts_with("https://"));
            assert!(["GET", "POST"].contains(&request.method.as_str()));
            HttpResp::ok(r#"<html><body><div class="post-loop"><ul><li><a href="/manga/fixture"><div class="cover"><img src="/img/fixture.jpg"></div></a><div class="overlay-title">Fixture title</div></li></ul></div></body></html>"#)
        }).unwrap();
        assert_eq!(result["mangas"][0]["title"], "Fixture title");
        assert_eq!(result["mangas"][0]["url"], "/manga/fixture");
    }
    #[test]
    fn rejects_non_extensions() {
        assert!(validate_apk(b"not an apk").is_err());
        assert!(validate_apk(&[]).is_err());
    }
    #[test]
    fn ffi_errors_are_owned_and_recoverable() {
        unsafe {
            let result = ac_manga_execute(
                std::ptr::null(),
                0,
                std::ptr::null(),
                None,
                None,
                std::ptr::null_mut(),
            );
            let value: Value = serde_json::from_slice(CStr::from_ptr(result).to_bytes()).unwrap();
            assert_eq!(value["ok"], false);
            ac_manga_free_string(result);
        }
    }
    #[test]
    fn loads_both_extension_generations_without_network() {
        let dir = std::env::var("MANGA_TEST_APK_DIR")
            .expect("Run scripts/test-manga-runtime.sh to prepare pinned fixtures");
        for (file, modern) in [
            ("tachiyomi-en.mangapill-v1.4.9.apk", false),
            ("tachiyomi-vi.cuutruyenmoe-v1.6.3.apk", true),
        ] {
            let apk = std::fs::read(format!("{dir}/{file}")).unwrap();
            let command: Command =
                serde_json::from_value(json!({"op":"inspect","modern":modern})).unwrap();
            let result = execute(&apk, command, |_| {
                panic!("Inspection must not make network requests")
            })
            .unwrap();
            assert!(result["packageName"]
                .as_str()
                .unwrap()
                .starts_with("eu.kanade.tachiyomi.extension."));
            assert!(!result["sources"].as_array().unwrap().is_empty());
            assert!(!result["sources"][0]["name"].as_str().unwrap().is_empty());
        }
    }
}
