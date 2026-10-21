//! Shared framework types do not exempt sources from host limits.
use dexvm::vm::{error::JvmError, object::Native, Vm};
pub(super) fn install(vm: &mut Vm) -> Result<(), JvmError> {
    let marker =
        super::kotlin_type_compat::marker(vm, "Leu/kanade/tachiyomi/source/UnmeteredSource;");
    let source = vm.ensure_class_by_desc("Leu/kanade/tachiyomi/source/Source;")?;
    vm.classes[marker as usize].interfaces = vec![source];
    let class = "Leu/kanade/tachiyomi/source/model/UpdateStrategy;";
    for (ordinal, name) in ["ALWAYS_UPDATE", "ONLY_FETCH_ONCE"].into_iter().enumerate() {
        let value = vm.alloc_native(
            class,
            Native::Enum {
                name: name.into(),
                ordinal: ordinal as i32,
            },
        )?;
        super::multipart_compat::static_value(vm, class, name, class, value)?;
    }
    Ok(())
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn source_marker_and_update_constants_preserve_inheritance_identity_and_order() {
        let mut vm = Vm::new(vec![], Box::new(std::io::sink())).unwrap();
        install(&mut vm).unwrap();
        let marker = vm
            .ensure_class_by_desc("Leu/kanade/tachiyomi/source/UnmeteredSource;")
            .unwrap();
        let source = vm
            .ensure_class_by_desc("Leu/kanade/tachiyomi/source/Source;")
            .unwrap();
        assert!(vm.classes[marker as usize].is_interface);
        assert!(vm.is_assignable(marker, source).unwrap());
        for (ordinal, name) in ["ALWAYS_UPDATE", "ONLY_FETCH_ONCE"].into_iter().enumerate() {
            let class = "Leu/kanade/tachiyomi/source/model/UpdateStrategy;";
            let field = dexvm::vm::FieldRef {
                class_desc: vm.intern(class),
                name: vm.intern(name),
                ty: vm.intern(class),
            };
            let value = vm.static_field_get(field).unwrap();
            vm.gc(&[]);
            assert_eq!(vm.static_field_get(field).unwrap(), value);
            assert!(
                matches!(vm.payload_of(value),Some(Native::Enum{ordinal:value,..}) if value==ordinal as i32)
            );
        }
    }
}
