//! Non-consuming, independently buffered views of eager host sources.
use dexvm::vm::error::JvmError;
use dexvm::vm::object::{ArrayData, Native};
use dexvm::vm::{NatErr, NativeEntry, Vm};
use dexvm::JValue;

const PEEK: &str = "Lapp/manga/runtime/PeekSource;";
const LIMIT: usize = 16_000_000;
const LIVE_CACHE_LIMIT: usize = 32_000_000;
const PARENT: usize = 0;
const EXPECTED_POS: usize = 1;
const CLOSED: usize = 2;

fn error(vm: &mut Vm, message: &str) -> NatErr {
    NatErr::Throw(vm.throwable_of("Ljava/lang/IllegalStateException;", message))
}

fn is_peek(vm: &Vm, value: JValue) -> bool {
    vm.object_class(value)
        .is_some_and(|c| vm.str_of(vm.classes[c as usize].descriptor) == PEEK)
}

fn state(vm: &mut Vm, value: JValue) -> Result<(usize, usize), NatErr> {
    if let JValue::Obj(id) = value {
        if let Some(Native::OkioBuf { bytes, pos }) = &vm.arena.objects[id as usize].native {
            if bytes.len() > LIMIT {
                return Err(NatErr::Fatal(JvmError::BudgetExceeded));
            }
            if *pos <= bytes.len() {
                return Ok((bytes.len(), *pos));
            }
        }
    }
    Err(error(vm, "Invalid buffered source"))
}

fn peek(vm: &mut Vm, args: &[JValue]) -> Result<JValue, NatErr> {
    let (_, pos) = state(vm, args[0])?;
    if is_peek(vm, args[0]) {
        check_open(vm, args[0])?;
    }
    let result = vm
        .alloc_native(
            PEEK,
            Native::OkioBuf {
                bytes: vec![],
                pos: 0,
            },
        )
        .map_err(NatErr::Fatal)?;
    vm.arena.objects[result.as_obj() as usize].fields =
        vec![args[0], JValue::Long(pos as i64), JValue::Int(0)];
    Ok(result)
}

fn check_open(vm: &mut Vm, source: JValue) -> Result<(), NatErr> {
    if vm.arena.objects[source.as_obj() as usize].fields[CLOSED].as_int() != 0 {
        return Err(error(vm, "closed"));
    }
    Ok(())
}

// Like RealBufferedSource(PeekSource), retain bytes already prefetched even
// after the upstream is consumed. Validate its cursor before each new segment.
fn request_bytes(vm: &mut Vm, source: JValue, count: usize, depth: usize) -> Result<bool, NatErr> {
    if depth >= 64 || count > LIMIT {
        return Err(NatErr::Fatal(JvmError::BudgetExceeded));
    }
    let (mut length, pos) = state(vm, source)?;
    if !is_peek(vm, source) {
        return Ok(length - pos >= count);
    }
    check_open(vm, source)?;
    while length - pos < count {
        let fields = &vm.arena.objects[source.as_obj() as usize].fields;
        let parent = fields[PARENT];
        let expected = fields[EXPECTED_POS].as_long() as usize;
        let (_, parent_pos) = state(vm, parent)?;
        if parent_pos != expected {
            return Err(error(
                vm,
                "Peek source is invalid because upstream source was used",
            ));
        }
        request_bytes(
            vm,
            parent,
            length
                .checked_add(1)
                .ok_or(NatErr::Fatal(JvmError::BudgetExceeded))?,
            depth + 1,
        )?;
        let (parent_length, parent_pos) = state(vm, parent)?;
        let start = parent_pos + length;
        if start >= parent_length {
            return Ok(false);
        }
        let end = (start + 8192).min(parent_length);
        if length + end - start > LIMIT {
            return Err(NatErr::Fatal(JvmError::BudgetExceeded));
        }
        let live: usize = vm
            .arena
            .objects
            .iter()
            .filter_map(|o| {
                if vm.str_of(vm.classes[o.class as usize].descriptor) != PEEK {
                    return None;
                }
                match &o.native {
                    Some(Native::OkioBuf { bytes, .. }) => Some(bytes.len()),
                    _ => None,
                }
            })
            .sum();
        let cost = ((end - start) / 16 + vm.arena.objects.len() / 16 + 1) as i64;
        if live.saturating_add(end - start) > LIVE_CACHE_LIMIT || vm.budget <= cost {
            return Err(NatErr::Fatal(JvmError::BudgetExceeded));
        }
        vm.budget -= cost;
        let chunk = match &vm.arena.objects[parent.as_obj() as usize].native {
            Some(Native::OkioBuf { bytes, .. }) => bytes[start..end].to_vec(),
            _ => unreachable!(),
        };
        if let Some(Native::OkioBuf { bytes, .. }) =
            &mut vm.arena.objects[source.as_obj() as usize].native
        {
            bytes.extend_from_slice(&chunk);
            length = bytes.len();
        }
    }
    Ok(true)
}

fn count(vm: &mut Vm, value: JValue) -> Result<usize, NatErr> {
    let n = value.as_long();
    if n < 0 {
        return Err(NatErr::Throw(vm.err_iae("Negative byte count")));
    }
    usize::try_from(n).map_err(|_| NatErr::Fatal(JvmError::BudgetExceeded))
}

fn read(vm: &mut Vm, args: &[JValue]) -> Result<JValue, NatErr> {
    let count = count(vm, args[2])?;
    check_open(vm, args[0])?;
    if args[1].is_null_ref() {
        return Err(NatErr::Throw(vm.err_npe()));
    }
    if args[0] == args[1] {
        return Err(NatErr::Throw(vm.err_iae("source == sink")));
    }
    if count == 0 {
        return Ok(JValue::Long(0));
    }
    if !request_bytes(vm, args[0], 1, 0)? {
        return Ok(JValue::Long(-1));
    }
    let (len, pos) = state(vm, args[0])?;
    let n = count.min(len - pos);
    let chunk = match &vm.arena.objects[args[0].as_obj() as usize].native {
        Some(Native::OkioBuf { bytes, .. }) => bytes[pos..pos + n].to_vec(),
        _ => unreachable!(),
    };
    match &mut vm.arena.objects[args[1].as_obj() as usize].native {
        Some(Native::OkioBuf { bytes, .. }) if bytes.len().saturating_add(n) <= LIMIT => {
            bytes.extend_from_slice(&chunk)
        }
        Some(Native::OkioBuf { .. }) => return Err(NatErr::Fatal(JvmError::BudgetExceeded)),
        _ => return Err(error(vm, "Invalid destination buffer")),
    }
    advance(vm, args[0], n);
    Ok(JValue::Long(n as i64))
}

fn advance(vm: &mut Vm, source: JValue, n: usize) {
    if let Some(Native::OkioBuf { pos, .. }) =
        &mut vm.arena.objects[source.as_obj() as usize].native
    {
        *pos += n;
    }
}

fn request(vm: &mut Vm, args: &[JValue]) -> Result<JValue, NatErr> {
    let n = count(vm, args[1])?;
    Ok(JValue::Int(i32::from(request_bytes(vm, args[0], n, 0)?)))
}
fn exhausted(vm: &mut Vm, args: &[JValue]) -> Result<JValue, NatErr> {
    Ok(JValue::Int(i32::from(!request_bytes(vm, args[0], 1, 0)?)))
}
fn close(vm: &mut Vm, args: &[JValue]) -> Result<JValue, NatErr> {
    vm.arena.objects[args[0].as_obj() as usize].fields[CLOSED] = JValue::Int(1);
    Ok(JValue::Null)
}
fn read_byte(vm: &mut Vm, args: &[JValue]) -> Result<JValue, NatErr> {
    if !request_bytes(vm, args[0], 1, 0)? {
        return Err(NatErr::Throw(
            vm.throwable_of("Ljava/io/EOFException;", "EOF"),
        ));
    }
    let byte = match &vm.arena.objects[args[0].as_obj() as usize].native {
        Some(Native::OkioBuf { bytes, pos }) => bytes[*pos],
        _ => unreachable!(),
    };
    advance(vm, args[0], 1);
    Ok(JValue::Int(byte as i8 as i32))
}
fn remaining(vm: &mut Vm, source: JValue) -> Result<Vec<u8>, NatErr> {
    loop {
        let (len, pos) = state(vm, source)?;
        if !request_bytes(vm, source, len - pos + 1, 0)? {
            break;
        }
    }
    let (len, pos) = state(vm, source)?;
    let result = match &vm.arena.objects[source.as_obj() as usize].native {
        Some(Native::OkioBuf { bytes, .. }) => bytes[pos..].to_vec(),
        _ => unreachable!(),
    };
    advance(vm, source, len - pos);
    Ok(result)
}
fn read_array(vm: &mut Vm, args: &[JValue]) -> Result<JValue, NatErr> {
    let bytes = remaining(vm, args[0])?;
    vm.alloc_native(
        "[B",
        Native::Array(ArrayData::Byte(
            bytes.into_iter().map(|b| b as i8).collect(),
        )),
    )
    .map_err(NatErr::Fatal)
}
fn read_utf8(vm: &mut Vm, args: &[JValue]) -> Result<JValue, NatErr> {
    let bytes = remaining(vm, args[0])?;
    Ok(vm.alloc_string(&String::from_utf8_lossy(&bytes)))
}

pub(super) fn install(vm: &mut Vm) -> Result<(), JvmError> {
    for class in ["Lokio/Buffer;", "Lokio/BufferedSource;"] {
        vm.register_native(NativeEntry {
            class,
            name: "peek",
            sig: "()Lokio/BufferedSource;",
            instance: true,
            f: peek,
        })?;
    }
    for (name, sig, f) in [
        (
            "peek",
            "()Lokio/BufferedSource;",
            peek as fn(&mut Vm, &[JValue]) -> Result<JValue, NatErr>,
        ),
        ("read", "(Lokio/Buffer;J)J", read),
        ("readByte", "()B", read_byte),
        ("readByteArray", "()[B", read_array),
        ("readUtf8", "()Ljava/lang/String;", read_utf8),
        ("request", "(J)Z", request),
        ("exhausted", "()Z", exhausted),
        ("close", "()V", close),
    ] {
        vm.register_native(NativeEntry {
            class: PEEK,
            name,
            sig,
            instance: true,
            f,
        })?;
    }
    let class = vm.ensure_class_by_desc(PEEK)?;
    let interface = vm.ensure_class_by_desc("Lokio/BufferedSource;")?;
    vm.classes[class as usize].interfaces.push(interface);
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn views_preserve_upstream_gc_and_segment_invalidation() {
        let mut vm = Vm::new(vec![], Box::new(std::io::sink())).unwrap();
        install(&mut vm).unwrap();
        let source = vm
            .alloc_native(
                "Lokio/Buffer;",
                Native::OkioBuf {
                    bytes: (0..9000).map(|i| (i % 251) as u8).collect(),
                    pos: 0,
                },
            )
            .unwrap();
        let view = peek(&mut vm, &[source]).unwrap();
        let other = peek(&mut vm, &[source]).unwrap();
        vm.gc(&[view.as_obj(), other.as_obj()]);
        assert_eq!(read_byte(&mut vm, &[view]).unwrap(), JValue::Int(0));
        assert_eq!(read_byte(&mut vm, &[other]).unwrap(), JValue::Int(0));
        assert_eq!(state(&mut vm, source).unwrap().1, 0);
        advance(&mut vm, source, 1);
        // Prefetched bytes remain usable, then a refill detects consumption.
        assert_eq!(read_byte(&mut vm, &[view]).unwrap(), JValue::Int(1));
        advance(&mut vm, view, 8190);
        assert!(matches!(read_byte(&mut vm, &[view]), Err(NatErr::Throw(_))));
        close(&mut vm, &[other]).unwrap();
        assert!(read_byte(&mut vm, &[other]).is_err());
        assert_eq!(state(&mut vm, source).unwrap().1, 1);
    }
    #[test]
    fn peek_observes_appends_and_nested_views_do_not_consume_their_parent() {
        let mut vm = Vm::new(vec![], Box::new(std::io::sink())).unwrap();
        install(&mut vm).unwrap();
        let source = vm
            .alloc_native(
                "Lokio/Buffer;",
                Native::OkioBuf {
                    bytes: vec![],
                    pos: 0,
                },
            )
            .unwrap();
        let view = peek(&mut vm, &[source]).unwrap();
        assert_eq!(exhausted(&mut vm, &[view]).unwrap(), JValue::Int(1));
        if let Some(Native::OkioBuf { bytes, .. }) =
            &mut vm.arena.objects[source.as_obj() as usize].native
        {
            bytes.extend_from_slice(b"GIF");
        }
        let nested = peek(&mut vm, &[view]).unwrap();
        let text = read_utf8(&mut vm, &[nested]).unwrap();
        assert_eq!(vm.str_of_jvalue(text).as_deref(), Some("GIF"));
        assert_eq!(state(&mut vm, view).unwrap().1, 0);
        assert_eq!(read_byte(&mut vm, &[view]).unwrap(), JValue::Int(71));
        assert!(request(&mut vm, &[view, JValue::Long(-1)]).is_err());
    }
}
