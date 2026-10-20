use dexvm::context::SettingDefinition;
use dexvm::keiyoushi::{Keiyoushi, Source};
use dexvm::vm::error::JvmError;
use dexvm::vm::object::{Native, PreferenceEdit, PreferenceValue};
use dexvm::vm::{NatErr, NativeEntry, NativeFn, Vm};
use dexvm::JValue;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::collections::{HashMap, HashSet};
use std::sync::OnceLock;

const SET_PREFIX: &str = "\0anime-set-v1:";
static ORIGINAL_GET_SET: OnceLock<NativeFn> = OnceLock::new();

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(tag = "type", content = "value", rename_all = "camelCase")]
pub(super) enum SettingValue {
    String(String),
    Boolean(bool),
    Integer(i32),
    Long(i64),
    Decimal(f32),
    StringSet(Vec<String>),
}

pub(super) fn seed(
    ext: &mut Keiyoushi,
    source_id: Option<&str>,
    settings: &HashMap<String, SettingValue>,
) -> Result<(), String> {
    if source_id.is_none() && settings.is_empty() {
        return Ok(());
    }
    let id = source_id
        .ok_or("Missing settings source identity")?
        .parse::<i64>()
        .map_err(|_| "Invalid settings source identity")?;
    if settings.len() > 128
        || serde_json::to_vec(settings)
            .map_err(|_| "Invalid source settings")?
            .len()
            > 65_536
    {
        return Err("Source settings exceed limits".into());
    }
    let mut values = HashMap::new();
    for (key, value) in settings {
        if key.is_empty() || key.len() > 256 {
            return Err("Invalid setting key".into());
        }
        let value = match value {
            SettingValue::String(value) if value.len() <= 16_384 => {
                PreferenceValue::String(value.clone())
            }
            SettingValue::Boolean(value) => PreferenceValue::Bool(*value),
            SettingValue::Integer(value) => PreferenceValue::Int(*value),
            SettingValue::Long(value) => PreferenceValue::Long(*value),
            SettingValue::Decimal(value) if value.is_finite() => PreferenceValue::Float(*value),
            SettingValue::StringSet(items)
                if items.len() <= 128 && items.iter().all(|v| v.len() <= 4096) =>
            {
                PreferenceValue::String(format!(
                    "{SET_PREFIX}{}",
                    serde_json::to_string(items).map_err(|_| "Invalid string set")?
                ))
            }
            _ => return Err("Invalid setting value".into()),
        };
        values.insert(key.clone(), value);
    }
    ext.seed_preferences(&format!("source_{id}"), &values);
    Ok(())
}

pub(super) fn definitions(ext: &mut Keiyoushi, source: &Source) -> Result<Value, String> {
    let source_id = ext
        .source_id(source)
        .map_err(|e| ext.describe_error(&e))?
        .to_string();
    let vm = ext.ctx().vm();
    let class = vm
        .object_class(JValue::Obj(source.inst()))
        .ok_or("Missing source object")?;
    let configurable = vm
        .ensure_class_by_desc("Leu/kanade/tachiyomi/source/ConfigurableSource;")
        .map_err(|e| e.to_string())?;
    if !vm
        .is_assignable(class, configurable)
        .map_err(|e| e.to_string())?
    {
        return Ok(json!({"sourceID":source_id,"settings":[]}));
    }
    let definitions = ext
        .preference_definitions(source)
        .map_err(|e| ext.describe_error(&e))?;
    let mut layout = Layout::default();
    walk(
        ext.ctx().vm(),
        &definitions,
        (None, true),
        "",
        0,
        &mut layout,
    )?;
    Ok(json!({"sourceID":source_id,"settings":layout.settings}))
}

#[derive(Default)]
struct Layout {
    keys: HashSet<String>,
    settings: Vec<Value>,
    bytes: usize,
}

fn walk(
    vm: &Vm,
    definitions: &[SettingDefinition],
    section: (Option<&str>, bool),
    prefix: &str,
    depth: usize,
    layout: &mut Layout,
) -> Result<(), String> {
    if depth > 6 || definitions.len() > 128 {
        return Err("Source settings exceed layout limits".into());
    }
    let (section, inherited_enabled) = section;
    for (index, item) in definitions.iter().enumerate() {
        if !item.visible {
            continue;
        }
        if item.title.as_ref().is_some_and(|v| v.len() > 4096)
            || item.summary.as_ref().is_some_and(|v| v.len() > 16_384)
        {
            return Err("Source settings exceed limits".into());
        }
        let id = format!("{prefix}{index}");
        if !item.children.is_empty() || item.kind.is_none() {
            walk(
                vm,
                &item.children,
                (
                    item.title.as_deref().or(section),
                    inherited_enabled && item.enabled,
                ),
                &format!("{id}."),
                depth + 1,
                layout,
            )?;
            continue;
        }
        let key = item.key.as_deref().unwrap_or("");
        if layout.settings.len() >= 128
            || key.len() > 256
            || item.entries.len() > 128
            || item.entry_values.len() > 128
            || item.default_text.as_ref().is_some_and(|v| v.len() > 16_384)
            || item.default_values.len() > 128
            || item.default_values.iter().any(|v| v.len() > 4096)
        {
            return Err("Source settings exceed limits".into());
        }
        if !key.is_empty() && !layout.keys.insert(key.to_owned()) {
            return Err("Source declares duplicate setting keys".into());
        }
        let kind = item.kind.as_deref().unwrap_or("");
        let (control, default) = if kind.ends_with("SwitchPreferenceCompat")
            || kind.ends_with("SwitchPreference")
            || kind.ends_with("CheckBoxPreference")
        {
            let value = match item.default_value {
                JValue::Int(v) => v != 0,
                other => matches!(vm.payload_of(other), Some(Native::BoolBox(true))),
            };
            ("toggle", Some(SettingValue::Boolean(value)))
        } else if kind.ends_with("MultiSelectListPreference") {
            (
                "multiChoice",
                Some(SettingValue::StringSet(item.default_values.clone())),
            )
        } else if kind.ends_with("ListPreference") {
            (
                "choice",
                item.default_text
                    .as_ref()
                    .map(|s| SettingValue::String(s.clone())),
            )
        } else if kind.ends_with("EditTextPreference") {
            (
                "text",
                item.default_text
                    .as_ref()
                    .map(|s| SettingValue::String(s.clone())),
            )
        } else {
            ("unsupported", None)
        };
        let valid_choices = item.entries.len() == item.entry_values.len()
            && item
                .entries
                .iter()
                .chain(item.entry_values.iter())
                .all(|s| s.len() <= 4096)
            && item.entry_values.iter().collect::<HashSet<_>>().len() == item.entry_values.len();
        let control =
            if key.is_empty() || (!valid_choices && matches!(control, "choice" | "multiChoice")) {
                "unsupported"
            } else {
                control
            };
        let choices = item
            .entries
            .iter()
            .zip(&item.entry_values)
            .map(|(label, value)| json!({"label":label,"value":value}))
            .collect::<Vec<_>>();
        let value = json!({"id":id,"key":key,"title":item.title.as_deref().unwrap_or("Source option"),
            "summary":item.summary.as_deref().unwrap_or(""),"section":section,"control":control,
            "enabled":inherited_enabled && item.enabled,"choices":choices,"defaultValue":default});
        layout.bytes += serde_json::to_vec(&value)
            .map_err(|_| "Invalid source settings")?
            .len();
        if layout.bytes > 524_288 {
            return Err("Source settings exceed layout limits".into());
        }
        layout.settings.push(value);
    }
    Ok(())
}

fn invalid(vm: &mut Vm) -> NatErr {
    NatErr::Throw(vm.throwable_of(
        "Ljava/lang/IllegalArgumentException;",
        "Invalid string-set setting",
    ))
}

fn get_set(vm: &mut Vm, args: &[JValue]) -> Result<JValue, NatErr> {
    let name = match vm.payload_of(args[0]) {
        Some(Native::SharedPreferences(name)) => name,
        _ => return Err(invalid(vm)),
    };
    let key = vm.str_of_jvalue(args[1]).ok_or_else(|| invalid(vm))?;
    let encoded = vm
        .shared_preferences
        .get(&name)
        .and_then(|prefs| prefs.get(&key))
        .and_then(|value| {
            if let PreferenceValue::String(value) = value {
                value.strip_prefix(SET_PREFIX).map(str::to_owned)
            } else {
                None
            }
        });
    if let Some(encoded) = encoded {
        if encoded.len() > 65_536 {
            return Err(invalid(vm));
        }
        let items: Vec<String> = serde_json::from_str(&encoded).map_err(|_| invalid(vm))?;
        if items.len() > 128 || items.iter().any(|v| v.len() > 4096) {
            return Err(invalid(vm));
        }
        let mut unique = HashSet::new();
        let items = items
            .into_iter()
            .filter(|v| unique.insert(v.clone()))
            .map(|v| vm.alloc_string(&v))
            .collect();
        return vm
            .alloc_native("Ljava/util/HashSet;", Native::Set(items))
            .map_err(NatErr::Fatal);
    }
    ORIGINAL_GET_SET
        .get()
        .ok_or_else(|| NatErr::Fatal(JvmError::Resolution("Missing string-set reader".into())))?(
        vm, args,
    )
}

fn put_set(vm: &mut Vm, args: &[JValue]) -> Result<JValue, NatErr> {
    let key = vm.str_of_jvalue(args[1]).ok_or_else(|| invalid(vm))?;
    if key.is_empty() || key.len() > 256 {
        return Err(invalid(vm));
    }
    let value = if args[2].is_null() {
        PreferenceEdit::Remove(key)
    } else {
        let items = match vm.payload_of(args[2]) {
            Some(Native::Set(items)) => items,
            _ => return Err(invalid(vm)),
        };
        let items = items
            .into_iter()
            .map(|v| vm.str_of_jvalue(v).ok_or_else(|| invalid(vm)))
            .collect::<Result<Vec<_>, _>>()?;
        if items.len() > 128 || items.iter().any(|s| s.len() > 4096) {
            return Err(invalid(vm));
        }
        let encoded = serde_json::to_string(&items).map_err(|_| invalid(vm))?;
        if encoded.len() > 65_536 {
            return Err(invalid(vm));
        }
        PreferenceEdit::Put(
            key,
            PreferenceValue::String(format!("{SET_PREFIX}{encoded}")),
        )
    };
    match &mut vm.arena.objects[args[0].as_obj() as usize].native {
        Some(Native::SharedPreferencesEditor { edits, .. }) => edits.push(value),
        _ => return Err(invalid(vm)),
    }
    Ok(args[0])
}

// Android-only presentation/callback setters do not alter the preference's
// default value. The native schema has no Android dialog or listener lifecycle.
fn schema_presentation(vm: &mut Vm, args: &[JValue]) -> Result<JValue, NatErr> {
    match vm.payload_of(args[0]) {
        Some(Native::Preference { .. } | Native::PreferenceScreen { .. }) => Ok(JValue::Null),
        _ => Err(NatErr::Throw(vm.err_npe())),
    }
}

fn preference_enabled(vm: &mut Vm, args: &[JValue]) -> Result<JValue, NatErr> {
    let Some(Native::Preference { enabled, .. }) =
        vm.arena.objects[args[0].as_obj() as usize].native.as_mut()
    else {
        return Err(NatErr::Throw(vm.err_npe()));
    };
    *enabled = !args[1].is_zero();
    Ok(JValue::Null)
}

fn android_ui_callback(vm: &mut Vm, _: &[JValue]) -> Result<JValue, NatErr> {
    Err(NatErr::Throw(vm.throwable_of(
        "Ljava/lang/UnsupportedOperationException;",
        "Android UI callbacks are unavailable in the native settings schema",
    )))
}

pub(super) fn install(vm: &mut Vm) -> Result<(), JvmError> {
    for (class, name, sig) in [
        (
            "Landroidx/preference/EditTextPreference$OnBindEditTextListener;",
            "onBindEditText",
            "(Landroid/widget/EditText;)V",
        ),
        (
            "Landroidx/preference/Preference$OnPreferenceChangeListener;",
            "onPreferenceChange",
            "(Landroidx/preference/Preference;Ljava/lang/Object;)Z",
        ),
        (
            "Landroidx/preference/Preference$OnPreferenceClickListener;",
            "onPreferenceClick",
            "(Landroidx/preference/Preference;)Z",
        ),
    ] {
        vm.register_native(NativeEntry {
            class,
            name,
            sig,
            instance: true,
            f: android_ui_callback,
        })?;
        let listener = vm.ensure_class_by_desc(class)?;
        vm.classes[listener as usize].is_interface = true;
    }
    let presentation: Vec<((u32, u32, u32), bool)> = vm
        .natives
        .keys()
        .filter_map(|key @ (class, name, sig)| {
            let (class, name, sig) = (vm.str_of(*class), vm.str_of(*name), vm.str_of(*sig));
            if !class.starts_with("Landroidx/preference/") {
                return None;
            }
            let presentation = matches!(
                (name, sig),
                ("setOnBindEditTextListener", "(Landroidx/preference/EditTextPreference$OnBindEditTextListener;)V")
                    | ("setOnPreferenceChangeListener", "(Landroidx/preference/Preference$OnPreferenceChangeListener;)V")
                    | ("setOnPreferenceClickListener", "(Landroidx/preference/Preference$OnPreferenceClickListener;)V")
                    | ("setDialogMessage" | "setDialogTitle" | "setSummaryOn" | "setSummaryOff", "(Ljava/lang/CharSequence;)V")
            );
            (presentation || (name == "setEnabled" && sig == "(Z)V"))
                .then_some((*key, name == "setEnabled"))
        })
        .collect();
    for (key, enabled) in presentation {
        vm.natives.insert(
            key,
            if enabled {
                preference_enabled
            } else {
                schema_presentation
            },
        );
    }
    let key = (
        vm.intern("Landroid/content/SharedPreferences;"),
        vm.intern("getStringSet"),
        vm.intern("(Ljava/lang/String;Ljava/util/Set;)Ljava/util/Set;"),
    );
    let original = *vm
        .natives
        .get(&key)
        .ok_or_else(|| JvmError::Resolution("Missing string-set reader".into()))?;
    let _ = ORIGINAL_GET_SET.set(original);
    vm.register_native(NativeEntry {
        class: "Landroid/content/SharedPreferences;",
        name: "getStringSet",
        sig: "(Ljava/lang/String;Ljava/util/Set;)Ljava/util/Set;",
        instance: true,
        f: get_set,
    })?;
    vm.register_native(NativeEntry {
        class: "Landroid/content/SharedPreferences$Editor;",
        name: "putStringSet",
        sig: "(Ljava/lang/String;Ljava/util/Set;)Landroid/content/SharedPreferences$Editor;",
        instance: true,
        f: put_set,
    })?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn android_ui_setters_preserve_defaults_and_enabled_state() {
        let mut vm = Vm::new(vec![], Box::new(std::io::sink())).unwrap();
        install(&mut vm).unwrap();
        let text = vm.alloc_string("Owned default");
        let listener = vm
            .alloc_native(
                "Landroidx/preference/EditTextPreference$OnBindEditTextListener;",
                Native::Opaque,
            )
            .unwrap();
        let value = vm
            .alloc_native(
                "Landroidx/preference/EditTextPreference;",
                Native::Preference {
                    key: None,
                    title: None,
                    summary: None,
                    default_value: text,
                    enabled: true,
                    visible: true,
                    entries: vec![],
                    entry_values: vec![],
                },
            )
            .unwrap();
        vm.invoke_virtual_args(
            value,
            "setOnBindEditTextListener",
            "(Landroidx/preference/EditTextPreference$OnBindEditTextListener;)V",
            vec![listener],
        )
        .unwrap();
        for method in ["setDialogTitle", "setDialogMessage"] {
            vm.invoke_virtual_args(
                value,
                method,
                "(Ljava/lang/CharSequence;)V",
                vec![JValue::Null],
            )
            .unwrap();
        }
        vm.invoke_virtual_args(value, "setEnabled", "(Z)V", vec![JValue::Int(0)])
            .unwrap();
        assert!(matches!(
            vm.payload_of(value),
            Some(Native::Preference { default_value, enabled: false, .. }) if default_value == text
        ));
        let interface = vm.arena.objects[listener.as_obj() as usize].class;
        assert!(vm.classes[interface as usize].is_interface);
        assert!(matches!(
            android_ui_callback(&mut vm, &[listener]),
            Err(NatErr::Throw(_))
        ));
        let choice = vm
            .alloc_native(
                "Landroidx/preference/SwitchPreferenceCompat;",
                Native::Preference {
                    key: None,
                    title: None,
                    summary: None,
                    default_value: JValue::Int(1),
                    enabled: true,
                    visible: true,
                    entries: vec![],
                    entry_values: vec![],
                },
            )
            .unwrap();
        for method in ["setSummaryOn", "setSummaryOff"] {
            vm.invoke_virtual_args(
                choice,
                method,
                "(Ljava/lang/CharSequence;)V",
                vec![text],
            )
            .unwrap();
        }
        vm.invoke_virtual_args(
            choice,
            "setOnPreferenceChangeListener",
            "(Landroidx/preference/Preference$OnPreferenceChangeListener;)V",
            vec![JValue::Null],
        )
        .unwrap();
        assert!(matches!(
            vm.payload_of(choice),
            Some(Native::Preference { default_value: JValue::Int(1), .. })
        ));
    }

    #[test]
    fn string_sets_preserve_newlines_empty_values_and_source_namespaces() {
        let mut vm = Vm::new(vec![], Box::new(std::io::sink())).unwrap();
        install(&mut vm).unwrap();
        let key = vm.alloc_string("genres");
        let items = vec!["", "action\nadventure", "fantasy", "fantasy"];
        let encoded = format!("{SET_PREFIX}{}", serde_json::to_string(&items).unwrap());
        vm.shared_preferences.insert(
            "source_1".into(),
            HashMap::from([("genres".into(), PreferenceValue::String(encoded))]),
        );
        let first = vm
            .alloc_native(
                "Landroid/content/SharedPreferences;",
                Native::SharedPreferences("source_1".into()),
            )
            .unwrap();
        let second = vm
            .alloc_native(
                "Landroid/content/SharedPreferences;",
                Native::SharedPreferences("source_2".into()),
            )
            .unwrap();
        let result = get_set(&mut vm, &[first, key, JValue::Null]).unwrap();
        let Some(Native::Set(values)) = vm.payload_of(result) else {
            panic!("Expected set")
        };
        assert_eq!(
            values
                .into_iter()
                .map(|v| vm.str_of_jvalue(v).unwrap())
                .collect::<HashSet<_>>(),
            HashSet::from(["".into(), "action\nadventure".into(), "fantasy".into()])
        );
        assert!(get_set(&mut vm, &[second, key, JValue::Null])
            .unwrap()
            .is_null());

        let editor = vm
            .alloc_native(
                "Landroid/content/SharedPreferences$Editor;",
                Native::SharedPreferencesEditor {
                    name: "source_1".into(),
                    edits: vec![],
                    clear: false,
                },
            )
            .unwrap();
        put_set(&mut vm, &[editor, key, result]).unwrap();
        put_set(&mut vm, &[editor, key, JValue::Null]).unwrap();
        let Some(Native::SharedPreferencesEditor { edits, .. }) = vm.payload_of(editor) else {
            panic!("Expected editor")
        };
        assert_eq!(edits.len(), 2);
        assert!(
            matches!(&edits[0], PreferenceEdit::Put(k, PreferenceValue::String(v)) if k == "genres" && v.starts_with(SET_PREFIX) && v.contains("action\\nadventure"))
        );
        assert!(matches!(&edits[1], PreferenceEdit::Remove(k) if k == "genres"));
    }

    #[test]
    fn invalid_string_sets_fail_without_queueing_an_edit() {
        let mut vm = Vm::new(vec![], Box::new(std::io::sink())).unwrap();
        install(&mut vm).unwrap();
        let key = vm.alloc_string("genres");
        let text = vm.alloc_string(&"x".repeat(4097));
        let set = vm
            .alloc_native("Ljava/util/HashSet;", Native::Set(vec![text]))
            .unwrap();
        let editor = vm
            .alloc_native(
                "Landroid/content/SharedPreferences$Editor;",
                Native::SharedPreferencesEditor {
                    name: "source_1".into(),
                    edits: vec![],
                    clear: false,
                },
            )
            .unwrap();
        assert!(put_set(&mut vm, &[editor, key, set]).is_err());
        assert!(
            matches!(vm.payload_of(editor), Some(Native::SharedPreferencesEditor { edits, .. }) if edits.is_empty())
        );
        vm.shared_preferences.insert(
            "source_1".into(),
            HashMap::from([(
                "genres".into(),
                PreferenceValue::String(format!("{SET_PREFIX}not json")),
            )]),
        );
        let prefs = vm
            .alloc_native(
                "Landroid/content/SharedPreferences;",
                Native::SharedPreferences("source_1".into()),
            )
            .unwrap();
        assert!(get_set(&mut vm, &[prefs, key, JValue::Null]).is_err());
    }
}
