//! Kotlin extension-receiver default bits differ from regular parameters.
use dexvm::vm::{
    error::JvmError,
    object::{ArrayData, Native},
    NatErr, NativeEntry, Vm,
};
use dexvm::JValue;
fn create_bytes(vm: &mut Vm, args: &[JValue]) -> Result<JValue, NatErr> {
    let Some(Native::Array(ArrayData::Byte(bytes))) = vm.payload_of(args[1]) else {
        return Err(NatErr::Throw(vm.err_npe()));
    };
    let mask = args[5].as_int();
    let offset = if mask & 2 != 0 { 0 } else { args[3].as_int() };
    let count = if mask & 4 != 0 {
        bytes.len() as i64
    } else {
        i64::from(args[4].as_int())
    };
    if offset < 0 || count < 0 || i64::from(offset) + count > bytes.len() as i64 {
        return Err(NatErr::Throw(vm.throwable_of(
            "Ljava/lang/ArrayIndexOutOfBoundsException;",
            "Invalid request body slice",
        )));
    }
    if count > 16_000_000 || vm.budget <= count + 1 {
        return Err(NatErr::Fatal(JvmError::BudgetExceeded));
    }
    vm.budget -= count + 1;
    let content_type = if mask & 1 != 0 {
        None
    } else {
        match vm.payload_of(args[2]) {
            Some(Native::Str(t)) => Some(t),
            _ => None,
        }
    };
    let data = bytes[offset as usize..offset as usize + count as usize]
        .iter()
        .map(|v| *v as u8)
        .collect();
    vm.alloc_native(
        "Lokhttp3/RequestBody;",
        Native::RequestBody { data, content_type },
    )
    .map_err(NatErr::Fatal)
}

pub(super) fn install(vm: &mut Vm) -> Result<(), JvmError> {
    for (name, sig) in [
        ("onResponse", "(Lokhttp3/Call;Lokhttp3/Response;)V"),
        ("onFailure", "(Lokhttp3/Call;Ljava/io/IOException;)V"),
    ] {
        vm.register_native(NativeEntry {
            class: "Lokhttp3/Callback;",
            name,
            sig,
            instance: true,
            f: super::abstract_function,
        })?;
    }
    let callback = vm.ensure_class_by_desc("Lokhttp3/Callback;")?;
    vm.classes[callback as usize].is_interface = true;
    vm.classes[callback as usize].is_abstract = true;
    vm.classes[callback as usize].access_flags = 0x601;
    vm.register_native(NativeEntry{class:"Lokhttp3/RequestBody$Companion;",name:"create$default",
        sig:"(Lokhttp3/RequestBody$Companion;[BLokhttp3/MediaType;IIILjava/lang/Object;)Lokhttp3/RequestBody;",
        instance:false,f:create_bytes})
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn kotlin_byte_body_defaults_keep_binary_data_type_and_checked_ranges() {
        let mut vm = Vm::new(vec![], Box::new(std::io::sink())).unwrap();
        install(&mut vm).unwrap();
        let bytes = vm
            .alloc_native("[B", Native::Array(ArrayData::Byte(vec![0, -1, 23, -128])))
            .unwrap();
        let mime = vm
            .alloc_native(
                "Lokhttp3/MediaType;",
                Native::Str("application/json".into()),
            )
            .unwrap();
        for (offset, count, mask, expected, typed) in [
            (99, 99, 6, vec![0, 255, 23, 128], true),
            (1, 2, 0, vec![255, 23], true),
            (0, 0, 0, vec![], true),
            (99, 99, 7, vec![0, 255, 23, 128], false),
        ] {
            let body=vm.invoke_static("Lokhttp3/RequestBody$Companion;","create$default",
                "(Lokhttp3/RequestBody$Companion;[BLokhttp3/MediaType;IIILjava/lang/Object;)Lokhttp3/RequestBody;",
                vec![JValue::Null,bytes,mime,JValue::Int(offset),JValue::Int(count),JValue::Int(mask),JValue::Null]).unwrap();
            assert!(
                matches!(vm.payload_of(body),Some(Native::RequestBody{data,content_type}) if data==expected && content_type==typed.then(||"application/json".into()))
            );
        }
        for (offset, count, mask) in [(-1, 1, 0), (4, 1, 0), (1, 0, 4), (0, -1, 0)] {
            assert!(matches!(
                create_bytes(
                    &mut vm,
                    &[
                        JValue::Null,
                        bytes,
                        mime,
                        JValue::Int(offset),
                        JValue::Int(count),
                        JValue::Int(mask),
                        JValue::Null
                    ]
                ),
                Err(NatErr::Throw(_))
            ));
        }
    }
}
