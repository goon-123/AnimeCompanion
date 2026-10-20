//! Primitive-array collection adapters used by extension-owned decoders.
use dexvm::vm::error::JvmError;
use dexvm::vm::object::{ArrayData, Native};
use dexvm::vm::{NatErr, NativeEntry, Vm};
use dexvm::JValue;

fn slice_bytes(vm: &mut Vm, args: &[JValue]) -> Result<JValue, NatErr> {
    let JValue::Obj(array) = args[0] else {
        return Err(NatErr::Throw(vm.err_npe()));
    };
    let Some(Native::IntRange(first, last)) = vm.payload_of(args[1]) else {
        return Err(NatErr::Throw(vm.err_npe()));
    };
    let Some(Native::Array(ArrayData::Byte(values))) = &vm.arena.objects[array as usize].native
    else {
        return Err(NatErr::Throw(vm.err_npe()));
    };
    // Kotlin accepts empty ranges before checking their endpoints. Nonempty
    // slices must reject bad indices rather than clipping/padding their data.
    if first > last {
        return vm
            .alloc_native("Ljava/util/ArrayList;", Native::List(vec![]))
            .map_err(NatErr::Fatal);
    }
    if first < 0 || last as usize >= values.len() {
        return Err(NatErr::Throw(vm.throwable_of(
            "Ljava/lang/IndexOutOfBoundsException;",
            "Byte slice indices outside array",
        )));
    }
    let length = (i64::from(last) - i64::from(first) + 1) as usize;
    if length > 1_000_000 {
        return Err(NatErr::Throw(vm.throwable_of(
            "Ljava/lang/IllegalArgumentException;",
            "Byte slice exceeds resource limit",
        )));
    }
    vm.budget -= (length * 2) as i64;
    if vm.budget < 0 {
        return Err(NatErr::Fatal(JvmError::BudgetExceeded));
    }
    let values = values[first as usize..=last as usize].to_vec();
    let mut boxed = Vec::with_capacity(length);
    for value in values {
        boxed.push(
            vm.alloc_native("Ljava/lang/Byte;", Native::ByteBox(value))
                .map_err(NatErr::Fatal)?,
        );
    }
    vm.alloc_native("Ljava/util/ArrayList;", Native::List(boxed))
        .map_err(NatErr::Fatal)
}

pub(super) fn install(vm: &mut Vm) -> Result<(), JvmError> {
    vm.register_native(NativeEntry {
        class: "Lkotlin/collections/ArraysKt;",
        name: "slice",
        sig: "([BLkotlin/ranges/IntRange;)Ljava/util/List;",
        instance: false,
        f: slice_bytes,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fixture() -> (Vm, JValue) {
        let mut vm = Vm::new(vec![], Box::new(std::io::sink())).unwrap();
        install(&mut vm).unwrap();
        let array = vm
            .alloc_native("[B", Native::Array(ArrayData::Byte(vec![-1, -128, 0, 127])))
            .unwrap();
        (vm, array)
    }
    fn range(vm: &mut Vm, first: i32, last: i32) -> JValue {
        vm.alloc_native("Lkotlin/ranges/IntRange;", Native::IntRange(first, last))
            .unwrap()
    }

    #[test]
    fn byte_slices_box_signed_values_without_changing_the_original() {
        let (mut vm, array) = fixture();
        let indices = range(&mut vm, 1, 3);
        let result = vm
            .invoke_static(
                "Lkotlin/collections/ArraysKt;",
                "slice",
                "([BLkotlin/ranges/IntRange;)Ljava/util/List;",
                vec![array, indices],
            )
            .unwrap();
        let Some(Native::List(values)) = vm.payload_of(result) else {
            panic!("Expected boxed byte list");
        };
        let mut bytes = Vec::new();
        for value in values {
            assert_eq!(
                vm.class_desc_str(vm.arena.objects[value.as_obj() as usize].class),
                "java.lang.Byte"
            );
            bytes.push(
                vm.invoke_virtual(value, "byteValue", "()B")
                    .unwrap()
                    .as_int(),
            );
        }
        assert_eq!(bytes, [-128, 0, 127]);
        assert!(
            matches!(vm.payload_of(array), Some(Native::Array(ArrayData::Byte(values))) if values == [-1, -128, 0, 127])
        );
    }

    #[test]
    fn byte_slices_keep_empty_ranges_and_throw_for_invalid_nonempty_ranges() {
        let (mut vm, array) = fixture();
        for (first, last) in [(0, -1), (4, 3), (100, 99)] {
            let indices = range(&mut vm, first, last);
            let result = slice_bytes(&mut vm, &[array, indices]).unwrap();
            assert!(
                matches!(vm.payload_of(result), Some(Native::List(values)) if values.is_empty())
            );
        }
        for (first, last) in [(-1, 1), (0, 4), (i32::MAX, i32::MAX)] {
            let indices = range(&mut vm, first, last);
            assert!(matches!(
                slice_bytes(&mut vm, &[array, indices]),
                Err(NatErr::Throw(_))
            ));
        }
        assert!(
            matches!(vm.payload_of(array), Some(Native::Array(ArrayData::Byte(values))) if values == [-1, -128, 0, 127])
        );
    }

    #[test]
    fn byte_slice_expansion_respects_the_vm_instruction_budget() {
        let (mut vm, array) = fixture();
        let indices = range(&mut vm, 0, 3);
        vm.budget = 1;
        assert!(matches!(
            slice_bytes(&mut vm, &[array, indices]),
            Err(NatErr::Fatal(JvmError::BudgetExceeded))
        ));
    }
}
