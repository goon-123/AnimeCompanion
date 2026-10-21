//! Bounded virtual stream IO shared by image codecs and gzip streams.
use dexvm::vm::error::JvmError;
use dexvm::vm::object::{ArrayData, Native};
use dexvm::vm::{NatErr, NativeEntry, Vm};
use dexvm::JValue;
use std::io::Read;

pub(super) const BYTE_LIMIT: usize = 16_000_000;
pub(super) fn exception(e: JvmError) -> NatErr {
    match e {
        JvmError::Uncaught(id) => NatErr::Throw(id),
        e => NatErr::Fatal(e),
    }
}
fn invoke(
    vm: &mut Vm,
    stream: JValue,
    name: &str,
    sig: &str,
    args: Vec<JValue>,
) -> Result<JValue, NatErr> {
    if vm.budget <= 0 {
        return Err(NatErr::Fatal(JvmError::BudgetExceeded));
    }
    if vm.recursion_depth >= vm.depth_limit {
        return Err(NatErr::Fatal(JvmError::StackOverflow));
    }
    vm.budget -= 1;
    vm.recursion_depth += 1;
    let result = vm
        .invoke_virtual_args(stream, name, sig, args)
        .map_err(exception);
    vm.recursion_depth -= 1;
    result
}
pub(super) fn read_stream(vm: &mut Vm, stream: JValue) -> Result<Vec<u8>, NatErr> {
    if stream.is_null_ref() {
        return Err(NatErr::Throw(vm.err_npe()));
    }
    let array = vm
        .alloc_native("[B", Native::Array(ArrayData::Byte(vec![0; 8192])))
        .map_err(NatErr::Fatal)?;
    let base = vm.arena.objects[stream.as_obj() as usize].fields.len();
    vm.arena.objects[stream.as_obj() as usize]
        .fields
        .push(array);
    let result = (|| {
        let mut output = Vec::new();
        loop {
            let count = invoke(
                vm,
                stream,
                "read",
                "([BII)I",
                vec![array, JValue::Int(0), JValue::Int(8192)],
            )?
            .as_int();
            if count == -1 {
                return Ok(output);
            }
            if !(1..=8192).contains(&count) {
                return Err(NatErr::Throw(
                    vm.throwable_of("Ljava/io/IOException;", "Invalid stream read"),
                ));
            }
            if output.len().saturating_add(count as usize) > BYTE_LIMIT {
                return Err(NatErr::Fatal(JvmError::BudgetExceeded));
            }
            let Some(Native::Array(ArrayData::Byte(bytes))) = vm.payload_of(array) else {
                return Err(NatErr::Throw(vm.err_npe()));
            };
            output.extend(bytes[..count as usize].iter().map(|b| *b as u8));
        }
    })();
    vm.arena.objects[stream.as_obj() as usize]
        .fields
        .truncate(base);
    result
}

pub(super) fn write_stream(vm: &mut Vm, stream: JValue, bytes: &[u8]) -> Result<(), NatErr> {
    if stream.is_null_ref() {
        return Err(NatErr::Throw(vm.err_npe()));
    }
    if bytes.len() > BYTE_LIMIT {
        return Err(NatErr::Fatal(JvmError::BudgetExceeded));
    }
    let array = vm
        .alloc_native(
            "[B",
            Native::Array(ArrayData::Byte(bytes.iter().map(|b| *b as i8).collect())),
        )
        .map_err(NatErr::Fatal)?;
    invoke(
        vm,
        stream,
        "write",
        "([BII)V",
        vec![array, JValue::Int(0), JValue::Int(bytes.len() as i32)],
    )?;
    Ok(())
}

fn gzip(vm: &mut Vm, args: &[JValue]) -> Result<JValue, NatErr> {
    if args.len() == 3 && args[2].as_int() <= 0 {
        return Err(NatErr::Throw(vm.err_iae("Invalid gzip buffer size")));
    }
    let compressed = read_stream(vm, args[1])?;
    let mut decoder =
        flate2::read::MultiGzDecoder::new(compressed.as_slice()).take(BYTE_LIMIT as u64 + 1);
    let mut bytes = Vec::new();
    decoder.read_to_end(&mut bytes).map_err(|_| {
        NatErr::Throw(vm.throwable_of("Ljava/util/zip/ZipException;", "Invalid gzip stream"))
    })?;
    if bytes.len() > BYTE_LIMIT {
        return Err(NatErr::Fatal(JvmError::BudgetExceeded));
    }
    vm.arena.objects[args[0].as_obj() as usize].native =
        Some(Native::ByteArrayInputStream { bytes, pos: 0 });
    vm.arena.objects[args[0].as_obj() as usize].fields = vec![JValue::Int(0)];
    Ok(JValue::Null)
}
fn open(vm: &mut Vm, stream: JValue) -> Result<(usize, usize), NatErr> {
    if stream.is_null_ref() {
        return Err(NatErr::Throw(vm.err_npe()));
    }
    let object = &vm.arena.objects[stream.as_obj() as usize];
    if object.fields.first().is_some_and(|v| v.as_int() != 0) {
        return Err(NatErr::Throw(
            vm.throwable_of("Ljava/io/IOException;", "Stream closed"),
        ));
    }
    match &object.native {
        Some(Native::ByteArrayInputStream { bytes, pos }) if *pos <= bytes.len() => {
            Ok((bytes.len(), *pos))
        }
        _ => Err(NatErr::Throw(vm.err_npe())),
    }
}
fn gzip_close(vm: &mut Vm, args: &[JValue]) -> Result<JValue, NatErr> {
    let object = &mut vm.arena.objects[args[0].as_obj() as usize];
    object.fields.resize(1, JValue::Int(0));
    object.fields[0] = JValue::Int(1);
    object.native = Some(Native::ByteArrayInputStream {
        bytes: vec![],
        pos: 0,
    });
    Ok(JValue::Null)
}
fn gzip_available(vm: &mut Vm, args: &[JValue]) -> Result<JValue, NatErr> {
    let (length, pos) = open(vm, args[0])?;
    Ok(JValue::Int(i32::from(pos < length)))
}
fn gzip_skip(vm: &mut Vm, args: &[JValue]) -> Result<JValue, NatErr> {
    let (length, pos) = open(vm, args[0])?;
    let n = args[1].as_long();
    if n < 0 {
        return Err(NatErr::Throw(vm.err_iae("Negative skip length")));
    }
    let n = (n as u64).min((length - pos) as u64) as usize;
    if let Some(Native::ByteArrayInputStream { pos, .. }) =
        &mut vm.arena.objects[args[0].as_obj() as usize].native
    {
        *pos += n;
    }
    Ok(JValue::Long(n as i64))
}
fn gzip_read(vm: &mut Vm, args: &[JValue]) -> Result<JValue, NatErr> {
    let (length, pos) = open(vm, args[0])?;
    if args.len() == 1 {
        if pos == length {
            return Ok(JValue::Int(-1));
        }
        let Some(Native::ByteArrayInputStream { bytes, pos }) =
            &mut vm.arena.objects[args[0].as_obj() as usize].native
        else {
            unreachable!()
        };
        let byte = bytes[*pos];
        *pos += 1;
        return Ok(JValue::Int(i32::from(byte)));
    }
    if args[1].is_null_ref() {
        return Err(NatErr::Throw(vm.err_npe()));
    }
    let array_len = match &vm.arena.objects[args[1].as_obj() as usize].native {
        Some(Native::Array(ArrayData::Byte(bytes))) => bytes.len(),
        _ => return Err(NatErr::Throw(vm.err_npe())),
    };
    let (offset, count) = if args.len() == 2 {
        (0, array_len as i64)
    } else {
        (i64::from(args[2].as_int()), i64::from(args[3].as_int()))
    };
    if offset < 0 || count < 0 || offset + count > array_len as i64 {
        return Err(NatErr::Throw(vm.throwable_of(
            "Ljava/lang/IndexOutOfBoundsException;",
            "Invalid stream byte range",
        )));
    }
    if count == 0 {
        return Ok(JValue::Int(0));
    }
    if pos == length {
        return Ok(JValue::Int(-1));
    }
    let count = (count as usize).min(length - pos);
    let Some(Native::ByteArrayInputStream { bytes, pos }) =
        &mut vm.arena.objects[args[0].as_obj() as usize].native
    else {
        unreachable!()
    };
    let chunk = bytes[*pos..*pos + count].to_vec();
    *pos += count;
    let Some(Native::Array(ArrayData::Byte(target))) =
        &mut vm.arena.objects[args[1].as_obj() as usize].native
    else {
        unreachable!()
    };
    for (target, byte) in target[offset as usize..offset as usize + count]
        .iter_mut()
        .zip(chunk)
    {
        *target = byte as i8;
    }
    Ok(JValue::Int(count as i32))
}
pub(super) fn install(vm: &mut Vm) -> Result<(), JvmError> {
    let mut parent = vm.ensure_class_by_desc("Ljava/io/InputStream;")?;
    for class in [
        "Ljava/io/FilterInputStream;",
        "Ljava/util/zip/InflaterInputStream;",
        "Ljava/util/zip/GZIPInputStream;",
    ] {
        let descriptor = vm.intern(class);
        let id = if class == "Ljava/util/zip/GZIPInputStream;" {
            vm.ensure_class_by_desc(class)?
        } else if let Some(id) = vm.class_by_desc.get(&descriptor) {
            *id
        } else {
            let id = vm.classes.len() as u32;
            vm.classes.push(dexvm::vm::class::Class {
                id,
                descriptor,
                access_flags: dexvm::vm::class::ACC_PUBLIC,
                ..Default::default()
            });
            vm.class_by_desc.insert(descriptor, id);
            id
        };
        vm.classes[id as usize].superclass = Some(parent);
        parent = id;
    }
    for sig in ["(Ljava/io/InputStream;)V", "(Ljava/io/InputStream;I)V"] {
        vm.register_native(NativeEntry {
            class: "Ljava/util/zip/GZIPInputStream;",
            name: "<init>",
            sig,
            instance: true,
            f: gzip,
        })?;
    }
    for (name, sig, f) in [
        (
            "read",
            "()I",
            gzip_read as fn(&mut Vm, &[JValue]) -> Result<JValue, NatErr>,
        ),
        ("read", "([B)I", gzip_read),
        ("read", "([BII)I", gzip_read),
        ("close", "()V", gzip_close),
        ("available", "()I", gzip_available),
        ("skip", "(J)J", gzip_skip),
    ] {
        vm.register_native(NativeEntry {
            class: "Ljava/util/zip/GZIPInputStream;",
            name,
            sig,
            instance: true,
            f,
        })?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;
    #[test]
    fn gzip_validates_crc_and_bounds_expansion() {
        let mut vm = Vm::new(vec![], Box::new(std::io::sink())).unwrap();
        install(&mut vm).unwrap();
        let target = vm
            .alloc_native("Ljava/util/zip/GZIPInputStream;", Native::Opaque)
            .unwrap();
        for (size, corrupt) in [(37, false), (37, true), (BYTE_LIMIT + 1, false)] {
            let mut encoder =
                flate2::write::GzEncoder::new(Vec::new(), flate2::Compression::fast());
            encoder.write_all(&vec![42; size]).unwrap();
            let mut bytes = encoder.finish().unwrap();
            if corrupt {
                let n = bytes.len();
                bytes[n - 8] ^= 1;
            }
            let input = vm
                .alloc_native(
                    "Ljava/io/ByteArrayInputStream;",
                    Native::ByteArrayInputStream { bytes, pos: 0 },
                )
                .unwrap();
            let result = gzip(&mut vm, &[target, input]);
            if corrupt {
                assert!(matches!(result, Err(NatErr::Throw(_))));
            } else if size > BYTE_LIMIT {
                assert!(matches!(
                    result,
                    Err(NatErr::Fatal(JvmError::BudgetExceeded))
                ));
            } else {
                result.unwrap();
                assert!(
                    matches!(vm.payload_of(target),Some(Native::ByteArrayInputStream{bytes,..}) if bytes==vec![42;37])
                );
                assert_eq!(read_stream(&mut vm, target).unwrap(), vec![42; 37]);
                let empty = vm
                    .alloc_native("[B", Native::Array(ArrayData::Byte(vec![])))
                    .unwrap();
                assert_eq!(
                    gzip_read(&mut vm, &[target, empty, JValue::Int(0), JValue::Int(0)]).unwrap(),
                    JValue::Int(0)
                );
                assert_eq!(gzip_read(&mut vm, &[target]).unwrap(), JValue::Int(-1));
                gzip_close(&mut vm, &[target]).unwrap();
                assert!(matches!(
                    gzip_read(&mut vm, &[target]),
                    Err(NatErr::Throw(_))
                ));
                gzip_close(&mut vm, &[target]).unwrap();
            }
        }
    }
}
