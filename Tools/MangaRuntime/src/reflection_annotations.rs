//! Bounded reads of DEX system annotations. The directory and annotation-set
//! offsets are fixed-width u32s, not encoded annotations themselves.
use dexvm::{
    dex::{
        read::{Cursor, DexError},
        DexFile,
    },
    vm::{error::JvmError, NatErr, Vm},
};
#[derive(Clone, Debug)]
enum Value {
    Type(u32),
    Array(Vec<Value>),
    Other,
}
const LIMIT: usize = 10_000;
fn invalid(c: &Cursor<'_>) -> DexError {
    DexError::new(c.pos, "Invalid or excessive reflection annotation")
}
fn value(c: &mut Cursor<'_>, work: &mut usize, depth: usize) -> Result<Value, DexError> {
    if depth > 32 || *work >= LIMIT {
        return Err(invalid(c));
    }
    *work += 1;
    let byte = c.u8()?;
    let tag = byte & 31;
    let width = usize::from(byte >> 5) + 1;
    match tag {
        0x17 | 0x18 if width <= 4 => {
            let mut index = 0u32;
            for i in 0..width {
                index |= u32::from(c.u8()?) << (i * 8);
            }
            Ok(if tag == 0x17 {
                Value::Other
            } else {
                Value::Type(index)
            })
        }
        0x1c if width == 1 => {
            let count = c.uleb128()? as usize;
            if count > LIMIT.saturating_sub(*work) {
                return Err(invalid(c));
            }
            (0..count)
                .map(|_| value(c, work, depth + 1))
                .collect::<Result<Vec<_>, _>>()
                .map(Value::Array)
        }
        0x1d if width == 1 => {
            annotation(c, work, depth + 1)?;
            Ok(Value::Other)
        }
        0x1e if width == 1 => Ok(Value::Other),
        0x1f if width <= 2 => Ok(Value::Other),
        0x00..=0x1b if width <= 8 => {
            for _ in 0..width {
                c.u8()?;
            }
            Ok(Value::Other)
        }
        _ => Err(invalid(c)),
    }
}
fn annotation(
    c: &mut Cursor<'_>,
    work: &mut usize,
    depth: usize,
) -> Result<(u32, Vec<(u32, Value)>), DexError> {
    if depth > 32 || *work >= LIMIT {
        return Err(invalid(c));
    }
    let ty = c.uleb128()?;
    let count = c.uleb128()? as usize;
    if count > LIMIT.saturating_sub(*work) {
        return Err(invalid(c));
    }
    let mut fields = Vec::new();
    for _ in 0..count {
        let name = c.uleb128()?;
        fields.push((name, value(c, work, depth + 1)?));
    }
    Ok((ty, fields))
}
fn read(
    dex: &DexFile,
    class_index: usize,
    method: u32,
    annotation_desc: &str,
    name: &str,
) -> Result<(Option<Value>, usize), DexError> {
    let mut c = Cursor::new(&dex.data);
    let base = c.u32_at(100)? as usize;
    let directory = c.u32_at(base + class_index * 32 + 20)? as usize;
    if directory == 0 {
        return Ok((None, 1));
    }
    let mut set = 0;
    let mut work = 1;
    let fields = c.u32_at(directory + 4)? as usize;
    let methods = c.u32_at(directory + 8)? as usize;
    if fields + methods > LIMIT {
        return Err(invalid(&c));
    }
    let offset = directory + 16 + fields * 8;
    for i in 0..methods {
        work += 1;
        if c.u32_at(offset + i * 8)? == method {
            set = c.u32_at(offset + i * 8 + 4)? as usize;
            break;
        }
    }
    if set == 0 {
        return Ok((None, work));
    }
    let count = c.u32_at(set)? as usize;
    if count > LIMIT.saturating_sub(work) {
        return Err(invalid(&c));
    }
    for i in 0..count {
        let item = c.u32_at(set + 4 + i * 4)? as usize;
        c.seek(item)?;
        c.u8()?; // visibility
        work += 1;
        let (ty, fields) = annotation(&mut c, &mut work, 0)?;
        let desc = dex
            .types
            .get(ty as usize)
            .and_then(|i| dex.strings.get(*i as usize))
            .ok_or_else(|| invalid(&c))?;
        if desc.as_ref() == annotation_desc {
            for (key, value) in fields {
                if dex
                    .strings
                    .get(key as usize)
                    .ok_or_else(|| invalid(&c))?
                    .as_ref()
                    == name
                {
                    return Ok((Some(value), work));
                }
            }
        }
    }
    Ok((None, work))
}
fn member_annotation(
    vm: &mut Vm,
    class: u32,
    member_name: (&str, &str),
    annotation_desc: &str,
) -> Result<Option<(Value, usize)>, NatErr> {
    let descriptor = vm.str_of(vm.classes[class as usize].descriptor).to_owned();
    let scan = vm
        .dexes
        .iter()
        .map(|d| d.classes.len() + d.methods.len())
        .sum::<usize>();
    if vm.budget <= scan as i64 {
        return Err(NatErr::Fatal(JvmError::BudgetExceeded));
    }
    vm.budget -= scan as i64 + 1;
    for (di, dex) in vm.dexes.iter().enumerate() {
        let Some(ci) = dex
            .classes
            .iter()
            .position(|c| dex.type_descriptor(c.class_idx) == descriptor)
        else {
            continue;
        };
        let (name, sig) = member_name;
        let index = dex.methods.iter().position(|m| {
            let proto = &dex.protos[m.proto as usize];
            let parameters = proto
                .params
                .iter()
                .map(|id| dex.type_descriptor(*id))
                .collect::<String>();
            let signature = format!("({parameters}){}", dex.type_descriptor(proto.return_type));
            dex.type_descriptor(m.class) == descriptor
                && dex.strings[m.name as usize].as_ref() == name
                && signature == sig
        });
        let Some(index) = index else {
            return Ok(None);
        };
        let member = index as u32;
        let (result, work) = read(dex, ci, member, annotation_desc, "value")
            .map_err(|e| NatErr::Fatal(JvmError::Fatal(e.to_string())))?;
        if vm.budget <= work as i64 {
            return Err(NatErr::Fatal(JvmError::BudgetExceeded));
        }
        vm.budget -= work as i64 + 1;
        return Ok(result.map(|v| (v, di)));
    }
    Ok(None)
}
pub(super) fn throws(
    vm: &mut Vm,
    method: &dexvm::vm::class::Method,
) -> Result<Vec<String>, NatErr> {
    let name = vm.str_of(method.name).to_owned();
    let sig = vm.str_of(method.sig).to_owned();
    let Some((Value::Array(values), di)) = member_annotation(
        vm,
        method.class,
        (&name, &sig),
        "Ldalvik/annotation/Throws;",
    )?
    else {
        return Ok(vec![]);
    };
    let dex = &vm.dexes[di];
    values
        .into_iter()
        .map(|v| match v {
            Value::Type(index) if (index as usize) < dex.types.len() => {
                Ok(dex.type_descriptor(index).to_owned())
            }
            _ => Err(NatErr::Fatal(JvmError::Fatal(
                "Invalid throws annotation".into(),
            ))),
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn malformed_annotation_offsets_fail_without_panics_or_empty_metadata() {
        let mut dex =
            DexFile::parse(include_bytes!("../test-support/shared-jvm-probe.dex")).unwrap();
        let mut bytes = dex.data.to_vec();
        bytes[100..104].copy_from_slice(&u32::MAX.to_le_bytes());
        dex.data = bytes.into();
        assert!(read(&dex, 0, 0, "Ldalvik/annotation/Throws;", "value").is_err());
    }
}
