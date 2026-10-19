//! Mutable cursors and interpreted Source.read for extension-owned transforms.
use dexvm::dex::insn::InvokeKind;
use dexvm::vm::error::JvmError;
use dexvm::vm::object::{ArrayData, Native};
use dexvm::vm::{MethodRef, NatErr, NativeEntry, Target, Vm};
use dexvm::JValue;

const CURSOR: &str = "Lokio/Buffer$UnsafeCursor;";
const BUFFER: usize = 0;
const DATA: usize = 1;
const START: usize = 2;
const END: usize = 3;
const OFFSET: usize = 4;
const WRITE: usize = 5;
const ORIGIN: usize = 6;
const LIMIT: usize = 16_000_000;

fn error(vm: &mut Vm, message: &str) -> NatErr {
    NatErr::Throw(vm.throwable_of("Ljava/lang/IllegalStateException;", message))
}

fn initialize(vm: &mut Vm, args: &[JValue]) -> Result<JValue, NatErr> {
    let fields = &mut vm.arena.objects[args[0].as_obj() as usize].fields;
    fields.resize(7, JValue::Null);
    fields[BUFFER] = JValue::Null;
    fields[DATA] = JValue::Null;
    fields[START] = JValue::Int(-1);
    fields[END] = JValue::Int(-1);
    fields[OFFSET] = JValue::Long(-1);
    fields[WRITE] = JValue::Int(0);
    fields[ORIGIN] = JValue::Long(0);
    Ok(JValue::Null)
}

fn attach(vm: &mut Vm, args: &[JValue]) -> Result<JValue, NatErr> {
    let cursor = args[1];
    let origin = match &vm.arena.objects[args[0].as_obj() as usize].native {
        Some(Native::OkioBuf { pos, .. }) => *pos,
        _ => return Err(error(vm, "Invalid buffer")),
    };
    let fields = &mut vm.arena.objects[cursor.as_obj() as usize].fields;
    if fields.len() != 7 || !fields[BUFFER].is_null() {
        return Err(error(vm, "Cursor is already attached or invalid"));
    }
    fields[BUFFER] = args[0];
    fields[WRITE] = JValue::Int(1);
    fields[ORIGIN] = JValue::Long(origin as i64);
    Ok(cursor)
}

fn commit(vm: &mut Vm, cursor: JValue) -> Result<(), NatErr> {
    let fields = &vm.arena.objects[cursor.as_obj() as usize].fields;
    let (buffer, data, origin) = (fields[BUFFER], fields[DATA], fields[ORIGIN].as_long());
    if data.is_null() {
        return Ok(());
    }
    let bytes = match vm.payload_of(data) {
        Some(Native::Array(ArrayData::Byte(bytes))) if bytes.len() <= LIMIT => bytes,
        _ => return Err(error(vm, "Invalid cursor data")),
    };
    match &mut vm.arena.objects[buffer.as_obj() as usize].native {
        Some(Native::OkioBuf { bytes: target, pos })
            if origin >= 0
                && origin as usize >= *pos
                && (origin as usize)
                    .checked_add(bytes.len())
                    .is_some_and(|end| end <= target.len()) =>
        {
            let end = origin as usize + bytes.len();
            for (target, value) in target[origin as usize..end].iter_mut().zip(bytes) {
                *target = value as u8;
            }
            Ok(())
        }
        _ => Err(error(vm, "Buffer changed while cursor was attached")),
    }
}

fn seek(vm: &mut Vm, args: &[JValue]) -> Result<JValue, NatErr> {
    let cursor = args[0];
    let offset = args[1].as_long();
    let buffer = vm.arena.objects[cursor.as_obj() as usize].fields[BUFFER];
    if buffer.is_null() {
        return Err(error(vm, "Cursor is not attached"));
    }
    let length = match &vm.arena.objects[buffer.as_obj() as usize].native {
        Some(Native::OkioBuf { bytes, pos }) => bytes.len().saturating_sub(*pos),
        _ => return Err(error(vm, "Invalid cursor buffer")),
    };
    if offset < -1 || offset > length as i64 || length > LIMIT {
        return Err(error(vm, "Cursor offset is out of bounds"));
    }
    commit(vm, cursor)?;
    if offset == -1 || offset as usize == length {
        let fields = &mut vm.arena.objects[cursor.as_obj() as usize].fields;
        fields[DATA] = JValue::Null;
        fields[START] = JValue::Int(-1);
        fields[END] = JValue::Int(-1);
        fields[OFFSET] = JValue::Long(offset);
        return Ok(JValue::Int(-1));
    }
    let segment_size = (length - offset as usize).min(8192);
    let (bytes, origin) = match &vm.arena.objects[buffer.as_obj() as usize].native {
        Some(Native::OkioBuf { bytes, pos }) => {
            let origin = *pos + offset as usize;
            (
                bytes[origin..origin + segment_size]
                    .iter()
                    .map(|b| *b as i8)
                    .collect::<Vec<_>>(),
                origin,
            )
        }
        _ => return Err(error(vm, "Invalid cursor buffer")),
    };
    let data = vm
        .alloc_native("[B", Native::Array(ArrayData::Byte(bytes)))
        .map_err(NatErr::Fatal)?;
    let fields = &mut vm.arena.objects[cursor.as_obj() as usize].fields;
    fields[DATA] = data;
    fields[START] = JValue::Int(0);
    fields[END] = JValue::Int(segment_size as i32);
    fields[OFFSET] = JValue::Long(offset);
    fields[ORIGIN] = JValue::Long(origin as i64);
    Ok(JValue::Int(segment_size as i32))
}

fn next(vm: &mut Vm, args: &[JValue]) -> Result<JValue, NatErr> {
    let fields = &vm.arena.objects[args[0].as_obj() as usize].fields;
    let offset = fields[OFFSET].as_long();
    let end = fields[END].as_int();
    let start = fields[START].as_int();
    let offset = if offset == -1 {
        0
    } else if start >= 0 {
        offset + i64::from(end - start)
    } else {
        return Err(error(vm, "Cursor has no next segment"));
    };
    seek(vm, &[args[0], JValue::Long(offset)])
}

fn close(vm: &mut Vm, args: &[JValue]) -> Result<JValue, NatErr> {
    if vm.arena.objects[args[0].as_obj() as usize].fields[BUFFER].is_null() {
        return Err(error(vm, "Cursor is not attached"));
    }
    commit(vm, args[0])?;
    initialize(vm, args)?;
    let fields = &mut vm.arena.objects[args[0].as_obj() as usize].fields;
    fields[BUFFER] = JValue::Null;
    fields[DATA] = JValue::Null;
    Ok(JValue::Null)
}

fn buffered_source(vm: &mut Vm, args: &[JValue]) -> Result<JValue, NatErr> {
    let source = args[0];
    let class = vm
        .object_class(source)
        .ok_or_else(|| error(vm, "Invalid source"))?;
    let method = MethodRef {
        class_desc: vm.intern("Lokio/Source;"),
        name: vm.intern("read"),
        sig: vm.intern("(Lokio/Buffer;J)J"),
        ret: vm.intern("J"),
        args: vec![vm.intern("Lokio/Buffer;"), vm.intern("J")],
    };
    // Eager native sources already own their bytes. Interpreted overrides must
    // run their read method, including transformations in their own bytecode.
    if matches!(
        vm.resolve_target(InvokeKind::Virtual, &method, Some(source.as_obj()), class)
            .map_err(NatErr::Fatal)?,
        Target::Native(_)
    ) {
        return Ok(source);
    }
    let buffer = vm
        .alloc_native(
            "Lokio/Buffer;",
            Native::OkioBuf {
                bytes: vec![],
                pos: 0,
            },
        )
        .map_err(NatErr::Fatal)?;
    let root = source.as_obj() as usize;
    let base = vm.arena.objects[root].fields.len();
    vm.arena.objects[root].fields.push(buffer);
    let result = (|| loop {
        let before = match &vm.arena.objects[buffer.as_obj() as usize].native {
            Some(Native::OkioBuf { bytes, .. }) => bytes.len(),
            _ => return Err(error(vm, "Invalid destination buffer")),
        };
        let count = vm
            .invoke_virtual_args(
                source,
                "read",
                "(Lokio/Buffer;J)J",
                vec![buffer, JValue::Long(8192)],
            )
            .map_err(NatErr::Fatal)?
            .as_long();
        let after = match &vm.arena.objects[buffer.as_obj() as usize].native {
            Some(Native::OkioBuf { bytes, .. }) => bytes.len(),
            _ => return Err(error(vm, "Invalid destination buffer")),
        };
        if after > LIMIT
            || (count == -1 && after != before)
            || (count != -1
                && (count <= 0
                    || count > 8192
                    || after.checked_sub(before) != Some(count as usize)))
        {
            return Err(error(vm, "Invalid or oversized source read"));
        }
        if count == -1 {
            return Ok(buffer);
        }
    })();
    vm.arena.objects[root].fields.truncate(base);
    result
}

pub(super) fn install(vm: &mut Vm) -> Result<(), JvmError> {
    for class in ["Lokio/Source;", "Lokio/BufferedSource;", "Lokio/Buffer;"] {
        vm.register_native(NativeEntry {
            class,
            name: "read",
            sig: "(Lokio/Buffer;J)J",
            instance: true,
            f: source_read,
        })?;
    }
    for entry in [
        NativeEntry {
            class: CURSOR,
            name: "<init>",
            sig: "()V",
            instance: true,
            f: initialize,
        },
        NativeEntry {
            class: CURSOR,
            name: "seek",
            sig: "(J)I",
            instance: true,
            f: seek,
        },
        NativeEntry {
            class: CURSOR,
            name: "next",
            sig: "()I",
            instance: true,
            f: next,
        },
        NativeEntry {
            class: CURSOR,
            name: "close",
            sig: "()V",
            instance: true,
            f: close,
        },
        NativeEntry {
            class: "Lokio/Buffer;",
            name: "readAndWriteUnsafe",
            sig: "(Lokio/Buffer$UnsafeCursor;)Lokio/Buffer$UnsafeCursor;",
            instance: true,
            f: attach,
        },
    ] {
        vm.register_native(entry)?;
    }
    let class = vm.ensure_class_by_desc(CURSOR)?;
    if !vm.classes[class as usize].instance_fields.is_empty() {
        return Err(JvmError::Resolution(
            "Unexpected buffer cursor layout".into(),
        ));
    }
    for (name, ty) in [
        ("buffer", "Lokio/Buffer;"),
        ("data", "[B"),
        ("start", "I"),
        ("end", "I"),
        ("offset", "J"),
        ("readWrite", "Z"),
        ("animeOrigin", "J"),
    ] {
        let (name, ty) = (vm.intern(name), vm.intern(ty));
        let c = &mut vm.classes[class as usize];
        let slot = c.instance_fields.len() as u32;
        c.instance_fields
            .push((name, ty, dexvm::vm::class::ACC_PUBLIC));
        c.field_offsets.insert((name, ty), slot);
    }
    for class in ["Lokio/Okio;", "Lokio/ByteStreams;", "Lokio/ByteStreamsKt;"] {
        vm.register_native(NativeEntry {
            class,
            name: "buffer",
            sig: "(Lokio/Source;)Lokio/BufferedSource;",
            instance: false,
            f: buffered_source,
        })?;
    }
    Ok(())
}

fn source_read(vm: &mut Vm, args: &[JValue]) -> Result<JValue, NatErr> {
    let count = args[2].as_long();
    if count < 0 {
        return Err(NatErr::Throw(vm.throwable_of(
            "Ljava/lang/IllegalArgumentException;",
            "Negative byte count",
        )));
    }
    if count == 0 {
        return Ok(JValue::Long(0));
    }
    if args[0] == args[1] {
        return Err(error(vm, "Cannot read a buffer into itself"));
    }
    let (JValue::Obj(source), JValue::Obj(target)) = (args[0], args[1]) else {
        return Err(error(vm, "Missing source or destination buffer"));
    };
    let (chunk, next) = match vm.arena.objects[source as usize].native.as_ref() {
        Some(Native::OkioBuf { bytes, pos }) if *pos <= bytes.len() && bytes.len() <= LIMIT => {
            let size = (bytes.len() - *pos).min(count as u64 as usize);
            (bytes[*pos..*pos + size].to_vec(), *pos + size)
        }
        _ => return Err(error(vm, "Invalid source buffer")),
    };
    if chunk.is_empty() {
        return Ok(JValue::Long(-1));
    }
    let size = chunk.len();
    match vm.arena.objects[target as usize].native.as_mut() {
        Some(Native::OkioBuf { bytes, .. }) if bytes.len().saturating_add(size) <= LIMIT => {
            bytes.extend_from_slice(&chunk)
        }
        _ => return Err(error(vm, "Invalid or oversized destination buffer")),
    }
    if let Some(Native::OkioBuf { pos, .. }) = vm.arena.objects[source as usize].native.as_mut() {
        *pos = next;
    }
    Ok(JValue::Long(size as i64))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn context() -> (Vm, JValue, JValue) {
        let mut vm = Vm::new(vec![], Box::new(std::io::sink())).unwrap();
        install(&mut vm).unwrap();
        let cursor = vm.alloc_native(CURSOR, Native::Opaque).unwrap();
        initialize(&mut vm, &[cursor]).unwrap();
        let buffer = vm
            .alloc_native(
                "Lokio/Buffer;",
                Native::OkioBuf {
                    bytes: vec![10, 20, 30, 40],
                    pos: 1,
                },
            )
            .unwrap();
        (vm, cursor, buffer)
    }

    #[test]
    fn cursor_commits_mutations_relative_to_unread_buffer_and_detaches() {
        let (mut vm, cursor, buffer) = context();
        attach(&mut vm, &[buffer, cursor]).unwrap();
        assert!(attach(&mut vm, &[buffer, cursor]).is_err());
        assert!(seek(&mut vm, &[cursor, JValue::Long(1)]).unwrap().as_int() == 2);
        let data = vm.arena.objects[cursor.as_obj() as usize].fields[DATA];
        if let Some(Native::Array(ArrayData::Byte(bytes))) =
            &mut vm.arena.objects[data.as_obj() as usize].native
        {
            bytes[0] = 99;
        } else {
            panic!("Expected byte segment");
        }
        vm.gc(&[cursor.as_obj()]);
        assert_eq!(next(&mut vm, &[cursor]).unwrap().as_int(), -1);
        close(&mut vm, &[cursor]).unwrap();
        assert!(
            matches!(vm.payload_of(buffer), Some(Native::OkioBuf { bytes, pos: 1 }) if bytes == vec![10,20,99,40])
        );
        assert!(seek(&mut vm, &[cursor, JValue::Long(0)]).is_err());
        assert!(close(&mut vm, &[cursor]).is_err());
        assert!(vm.arena.objects[cursor.as_obj() as usize].fields[DATA].is_null());
    }

    #[test]
    fn cursor_rejects_out_of_bounds_seek_without_changing_bytes() {
        let (mut vm, cursor, buffer) = context();
        attach(&mut vm, &[buffer, cursor]).unwrap();
        assert!(seek(&mut vm, &[cursor, JValue::Long(-2)]).is_err());
        assert!(seek(&mut vm, &[cursor, JValue::Long(4)]).is_err());
        assert_eq!(
            seek(&mut vm, &[cursor, JValue::Long(3)]).unwrap().as_int(),
            -1
        );
        close(&mut vm, &[cursor]).unwrap();
        assert!(
            matches!(vm.payload_of(buffer), Some(Native::OkioBuf { bytes, pos: 1 }) if bytes == vec![10,20,30,40])
        );
    }
    #[test]
    fn buffered_source_inherits_bounded_read_with_correct_zero_and_eof_semantics() {
        let (mut vm, _, source) = context();
        let target = vm
            .alloc_native(
                "Lokio/Buffer;",
                Native::OkioBuf {
                    bytes: vec![],
                    pos: 0,
                },
            )
            .unwrap();
        assert!(source_read(&mut vm, &[source, target, JValue::Long(-1)]).is_err());
        assert_eq!(
            source_read(&mut vm, &[source, target, JValue::Long(0)]).unwrap(),
            JValue::Long(0)
        );
        let read = vm
            .invoke_virtual_args(
                source,
                "read",
                "(Lokio/Buffer;J)J",
                vec![target, JValue::Long(2)],
            )
            .unwrap();
        assert_eq!(read, JValue::Long(2));
        assert_eq!(
            source_read(&mut vm, &[source, target, JValue::Long(99)]).unwrap(),
            JValue::Long(1)
        );
        assert_eq!(
            source_read(&mut vm, &[source, target, JValue::Long(99)]).unwrap(),
            JValue::Long(-1)
        );
        assert_eq!(
            source_read(&mut vm, &[source, target, JValue::Long(0)]).unwrap(),
            JValue::Long(0)
        );
        assert!(
            matches!(vm.payload_of(target), Some(Native::OkioBuf { bytes, pos: 0 }) if bytes == vec![20,30,40])
        );
    }
}
