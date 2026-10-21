//! Locale identity and compiled-in calendar text. No host locale files are read.
use dexvm::vm::{error::JvmError, object::Native, NatErr, NativeEntry, Vm};
use dexvm::JValue;
type R = Result<JValue, NatErr>;
const CLASS: &str = "Ljava/util/Locale;";

#[derive(Default, PartialEq, Eq)]
struct Parts {
    language: String,
    country: String,
    variant: String,
    script: String,
    extensions: String,
}
fn language(value: &str) -> String {
    let value = value.to_lowercase();
    match value.as_str() {
        "iw" => "he".into(),
        "ji" => "yi".into(),
        "in" => "id".into(),
        _ => value,
    }
}
fn parts(vm: &mut Vm, value: JValue) -> Result<Parts, NatErr> {
    if value.is_null_ref() {
        return Err(NatErr::Throw(vm.err_npe()));
    }
    let object = &vm.arena.objects[value.as_obj() as usize];
    if vm.str_of(vm.classes[object.class as usize].descriptor) != CLASS {
        return Err(NatErr::Throw(vm.err_iae("Expected Locale")));
    }
    if object.fields.len() == 5 {
        let values: Option<Vec<_>> = object.fields.iter().map(|v| vm.str_of_jvalue(*v)).collect();
        if let Some(values) = values {
            return Ok(Parts {
                language: values[0].clone(),
                country: values[1].clone(),
                variant: values[2].clone(),
                script: values[3].clone(),
                extensions: values[4].clone(),
            });
        }
    }
    let tag = match vm.payload_of(value) {
        Some(Native::Str(tag)) => tag,
        Some(Native::Opaque) => return Ok(Parts::default()),
        _ => return Err(NatErr::Throw(vm.err_npe())),
    };
    if tag.len() > 512 {
        return Err(NatErr::Fatal(JvmError::BudgetExceeded));
    }
    let mut tokens = tag.split(['_', '-']).peekable();
    let mut result = Parts {
        language: language(tokens.next().unwrap_or_default()),
        ..Default::default()
    };
    if tokens
        .peek()
        .is_some_and(|v| v.len() == 4 && v.bytes().all(|b| b.is_ascii_alphabetic()))
    {
        let script = tokens.next().unwrap().to_ascii_lowercase();
        result.script = format!("{}{}", script[..1].to_ascii_uppercase(), &script[1..]);
    }
    if tokens.peek().is_some_and(|v| {
        (v.len() == 2 && v.bytes().all(|b| b.is_ascii_alphabetic()))
            || (v.len() == 3 && v.bytes().all(|b| b.is_ascii_digit()))
    }) {
        result.country = tokens.next().unwrap().to_ascii_uppercase();
    }
    let mut variants = Vec::new();
    while tokens.peek().is_some_and(|v| v.len() > 1) {
        variants.push(tokens.next().unwrap());
    }
    result.variant = variants.join("_");
    result.extensions = tokens.collect::<Vec<_>>().join("-").to_ascii_lowercase();
    Ok(result)
}
fn allocate(vm: &mut Vm, data: Parts) -> R {
    let mut tag = data.language.clone();
    for part in [&data.script, &data.country, &data.variant] {
        if !part.is_empty() {
            tag.push('-');
            tag.push_str(&part.replace('_', "-"));
        }
    }
    let value = vm
        .alloc_native(CLASS, Native::Str(tag))
        .map_err(NatErr::Fatal)?;
    let fields = [
        &data.language,
        &data.country,
        &data.variant,
        &data.script,
        &data.extensions,
    ]
    .into_iter()
    .map(|s| vm.alloc_string(s))
    .collect();
    vm.arena.objects[value.as_obj() as usize].fields = fields;
    Ok(value)
}
fn constructor(vm: &mut Vm, args: &[JValue]) -> R {
    let values = args[1..]
        .iter()
        .map(|v| {
            vm.str_of_jvalue(*v)
                .ok_or_else(|| NatErr::Throw(vm.err_npe()))
        })
        .collect::<Result<Vec<_>, _>>()?;
    if values.iter().any(|v| v.len() > 128) {
        return Err(NatErr::Fatal(JvmError::BudgetExceeded));
    }
    let data = Parts {
        language: language(&values[0]),
        country: values.get(1).unwrap_or(&String::new()).to_uppercase(),
        variant: values.get(2).cloned().unwrap_or_default(),
        script: String::new(),
        extensions: String::new(),
    };
    let created = allocate(vm, data)?;
    let original = vm.arena.objects[created.as_obj() as usize].clone();
    vm.arena.objects[args[0].as_obj() as usize].native = original.native;
    vm.arena.objects[args[0].as_obj() as usize].fields = original.fields;
    Ok(JValue::Null)
}
fn get_language(vm: &mut Vm, args: &[JValue]) -> R {
    let p = parts(vm, args[0])?;
    Ok(vm.alloc_string(&p.language))
}
fn get_country(vm: &mut Vm, args: &[JValue]) -> R {
    let p = parts(vm, args[0])?;
    Ok(vm.alloc_string(&p.country))
}
fn get_variant(vm: &mut Vm, args: &[JValue]) -> R {
    let p = parts(vm, args[0])?;
    Ok(vm.alloc_string(&p.variant))
}
fn get_script(vm: &mut Vm, args: &[JValue]) -> R {
    let p = parts(vm, args[0])?;
    Ok(vm.alloc_string(&p.script))
}
fn legacy_name(p: &Parts) -> String {
    let mut name = p.language.clone();
    if !p.country.is_empty() || (!p.language.is_empty() && !p.variant.is_empty()) {
        name.push('_');
        name.push_str(&p.country);
    }
    if !p.variant.is_empty() && (!p.language.is_empty() || !p.country.is_empty()) {
        name.push('_');
        name.push_str(&p.variant);
    }
    if !p.script.is_empty() || !p.extensions.is_empty() {
        if p.country.is_empty() {
            name.push('_');
        }
        name.push_str("_#");
        name.push_str(&p.script);
        if !p.extensions.is_empty() {
            if !p.script.is_empty() {
                name.push('_');
            }
            name.push_str(&p.extensions);
        }
    }
    name
}
fn to_string(vm: &mut Vm, args: &[JValue]) -> R {
    let p = parts(vm, args[0])?;
    Ok(vm.alloc_string(&legacy_name(&p)))
}
fn equals(vm: &mut Vm, args: &[JValue]) -> R {
    let left = parts(vm, args[0])?;
    let right = if args[1].is_null_ref() {
        None
    } else {
        let class = vm.object_class(args[1]);
        if class.is_some_and(|c| vm.str_of(vm.classes[c as usize].descriptor) == CLASS) {
            Some(parts(vm, args[1])?)
        } else {
            None
        }
    };
    Ok(JValue::Int(i32::from(right.is_some_and(|p| p == left))))
}
fn hash(vm: &mut Vm, args: &[JValue]) -> R {
    let p = parts(vm, args[0])?;
    let value = [p.language, p.country, p.variant, p.script, p.extensions]
        .iter()
        .fold(1_i32, |h, s| {
            h.wrapping_mul(31).wrapping_add(
                s.encode_utf16()
                    .fold(0_i32, |a, c| a.wrapping_mul(31).wrapping_add(i32::from(c))),
            )
        });
    Ok(JValue::Int(value))
}
pub(super) fn calendar_locale(
    vm: &mut Vm,
    value: JValue,
) -> Result<Option<chrono::Locale>, NatErr> {
    if value.is_null_ref() {
        return Ok(Some(chrono::Locale::POSIX));
    }
    let p = parts(vm, value)?;
    if p.language.is_empty() {
        return Ok(Some(chrono::Locale::POSIX));
    }
    if !p.country.is_empty() {
        if let Ok(locale) =
            chrono::Locale::try_from(format!("{}_{}", p.language, p.country).as_str())
        {
            return Ok(Some(locale));
        }
    }
    let id = match p.language.as_str() {
        "en" => "en_US",
        "fr" => "fr_FR",
        "de" => "de_DE",
        "it" => "it_IT",
        "es" => "es_ES",
        "pt" => "pt_PT",
        "ja" => "ja_JP",
        "ko" => "ko_KR",
        "zh" => "zh_CN",
        "tr" => "tr_TR",
        "ru" => "ru_RU",
        "vi" => "vi_VN",
        "id" => "id_ID",
        "ar" => "ar_SA",
        _ => return Ok(None),
    };
    Ok(chrono::Locale::try_from(id).ok())
}
pub(super) fn install(vm: &mut Vm) -> Result<(), JvmError> {
    for (name, sig, f) in [
        (
            "<init>",
            "(Ljava/lang/String;)V",
            constructor as dexvm::vm::NativeFn,
        ),
        (
            "<init>",
            "(Ljava/lang/String;Ljava/lang/String;)V",
            constructor,
        ),
        (
            "<init>",
            "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V",
            constructor,
        ),
        ("getLanguage", "()Ljava/lang/String;", get_language),
        ("getCountry", "()Ljava/lang/String;", get_country),
        ("getVariant", "()Ljava/lang/String;", get_variant),
        ("getScript", "()Ljava/lang/String;", get_script),
        ("toString", "()Ljava/lang/String;", to_string),
        ("equals", "(Ljava/lang/Object;)Z", equals),
        ("hashCode", "()I", hash),
    ] {
        vm.register_native(NativeEntry {
            class: CLASS,
            name,
            sig,
            instance: true,
            f,
        })?;
    }
    let owner = vm.ensure_class_by_desc(CLASS)?;
    for (name, lang, country) in [
        ("ROOT", "", ""),
        ("ENGLISH", "en", ""),
        ("FRENCH", "fr", ""),
        ("GERMAN", "de", ""),
        ("ITALIAN", "it", ""),
        ("JAPANESE", "ja", ""),
        ("KOREAN", "ko", ""),
        ("CHINESE", "zh", ""),
        ("US", "en", "US"),
        ("UK", "en", "GB"),
        ("CANADA", "en", "CA"),
        ("CANADA_FRENCH", "fr", "CA"),
        ("FRANCE", "fr", "FR"),
        ("GERMANY", "de", "DE"),
        ("ITALY", "it", "IT"),
        ("JAPAN", "ja", "JP"),
        ("KOREA", "ko", "KR"),
        ("CHINA", "zh", "CN"),
        ("PRC", "zh", "CN"),
        ("SIMPLIFIED_CHINESE", "zh", "CN"),
        ("TAIWAN", "zh", "TW"),
        ("TRADITIONAL_CHINESE", "zh", "TW"),
    ] {
        let value = allocate(
            vm,
            Parts {
                language: lang.into(),
                country: country.into(),
                ..Default::default()
            },
        )
        .map_err(|e| match e {
            NatErr::Fatal(e) => e,
            NatErr::Throw(o) => JvmError::Uncaught(o),
        })?;
        let key = (vm.intern(name), vm.intern(CLASS));
        let class = &mut vm.classes[owner as usize];
        if let Some((_, offset)) = class.static_fields.get(&key) {
            class.statics[*offset as usize] = value;
            class.statics_lazy[*offset as usize] = None;
        } else {
            let offset = class.statics.len() as u32;
            class.statics.push(value);
            class.statics_lazy.push(None);
            class.static_fields.insert(key, (owner, offset));
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn constructors_preserve_country_variant_constants_and_gc_identity() {
        let mut vm = Vm::new(vec![], Box::new(std::io::sink())).unwrap();
        install(&mut vm).unwrap();
        let class = vm.ensure_class_by_desc(CLASS).unwrap();
        let value = JValue::Obj(vm.alloc_instance(class).unwrap());
        let lang = vm.alloc_string("FR");
        let country = vm.alloc_string("fr");
        let variant = vm.alloc_string("POSIX");
        constructor(&mut vm, &[value, lang, country, variant]).unwrap();
        vm.gc(&[value.as_obj()]);
        assert_eq!(legacy_name(&parts(&mut vm, value).unwrap()), "fr_FR_POSIX");
        let field = dexvm::vm::FieldRef {
            class_desc: vm.intern(CLASS),
            name: vm.intern("ROOT"),
            ty: vm.intern(CLASS),
        };
        let root = vm.static_field_get(field).unwrap();
        assert_ne!(
            parts(&mut vm, value).unwrap().language,
            parts(&mut vm, root).unwrap().language
        );
        assert!(matches!(
            constructor(&mut vm, &[value, JValue::Null]),
            Err(NatErr::Throw(_))
        ));
    }
}
