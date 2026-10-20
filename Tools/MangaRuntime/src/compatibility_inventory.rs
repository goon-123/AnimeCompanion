//! Test-only inventory of the actual registered host API, never a support claim.
use super::*;
use std::collections::{BTreeMap, BTreeSet};

pub(super) fn inventory(vm: &mut Vm) -> Value {
    let mut methods: Vec<(String, String, String)> = vm
        .natives
        .keys()
        .map(|(class, name, sig)| {
            (
                vm.str_of(*class).to_owned(),
                vm.str_of(*name).to_owned(),
                vm.str_of(*sig).to_owned(),
            )
        })
        .collect();
    methods.sort();
    let descriptors: BTreeSet<String> = methods.iter().map(|m| m.0.clone()).collect();
    let mut parents = BTreeMap::new();
    let mut unresolved = Vec::new();
    for descriptor in descriptors {
        let Ok(class) = vm.ensure_class_by_desc(&descriptor) else {
            unresolved.push(descriptor);
            continue;
        };
        let owner = &vm.classes[class as usize];
        let mut ancestors: Vec<String> = owner
            .superclass
            .into_iter()
            .chain(owner.interfaces.iter().copied())
            .map(|id| vm.str_of(vm.classes[id as usize].descriptor).to_owned())
            .collect();
        ancestors.sort();
        parents.insert(descriptor, ancestors);
    }
    json!({
        "schemaVersion": 1,
        "meaning": "Registered API presence only; behavior requires execution tests.",
        "methods": methods,
        "parents": parents,
        "unresolvedRegisteredClasses": unresolved,
    })
}

#[test]
fn export_registered_runtime_inventory() {
    let root = std::env::var("MANGA_TEST_APK_DIR").expect("Run test-manga-runtime.sh");
    let apk = std::fs::read(format!("{root}/tachiyomi-en.mangapill-v1.4.9.apk")).unwrap();
    let command = serde_json::from_value(json!({"op":"auditRuntimeInventory"})).unwrap();
    let value = execute(&apk, command, |_| panic!("Inventory must not network")).unwrap();
    let methods = value["methods"].as_array().unwrap();
    assert!(methods.len() > 100);
    assert!(methods.contains(&json!([
        "Lkotlin/collections/ArraysKt;",
        "slice",
        "([BLkotlin/ranges/IntRange;)Ljava/util/List;"
    ])));
    assert!(methods.contains(&json!([
        "Lorg/jsoup/nodes/Element;",
        "data",
        "()Ljava/lang/String;"
    ])));
    if let Ok(path) = std::env::var("MANGA_RUNTIME_INVENTORY") {
        let path = std::path::Path::new(&path);
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent).unwrap();
        }
        std::fs::write(path, serde_json::to_vec_pretty(&value).unwrap()).unwrap();
    }
}
