//! Preserve opaque, bounded extension metadata between fresh VM operations.
//! This is source data, not a cookie/auth store; never interpret its keys.
use super::*;
use dexvm::vm::object::{JsonVal, Native};

const MAX_MEMO: usize = 65_536;

pub(super) fn memo(vm: &Vm, value: JValue) -> Result<Option<String>, String> {
    if value.is_null_ref() {
        return Ok(None);
    }
    let Some(Native::Json(JsonVal::Object(object))) = vm.payload_of(value) else {
        return Err("Invalid source chapter metadata.".into());
    };
    let value = json_compat::json_value(JsonVal::Object(object), 0)
        .ok_or("Invalid source chapter metadata.")?;
    let text = value.to_string();
    if text.len() > MAX_MEMO {
        return Err("Source chapter metadata exceeds limits.".into());
    }
    json_node(value, 0)?;
    Ok(Some(text))
}
fn json_node(value: Value, depth: usize) -> Result<JsonVal, String> {
    if depth > 32 {
        return Err("Source chapter metadata is too deeply nested.".into());
    }
    Ok(match value {
        Value::Null => JsonVal::Null,
        Value::String(s) => JsonVal::Str(s),
        Value::Bool(b) => JsonVal::Bool(b),
        Value::Number(n) => {
            if let Some(n) = n.as_i64() {
                JsonVal::Int(n)
            } else if n.is_u64() {
                return Err("Source chapter integer exceeds runtime limits.".into());
            } else {
                JsonVal::Double(n.as_f64().ok_or("Invalid source chapter number.")?)
            }
        }
        Value::Array(v) => JsonVal::Array(
            v.into_iter()
                .map(|v| json_node(v, depth + 1))
                .collect::<Result<_, _>>()?,
        ),
        Value::Object(v) => JsonVal::Object(
            v.into_iter()
                .map(|(k, v)| Ok((k, json_node(v, depth + 1)?)))
                .collect::<Result<_, String>>()?,
        ),
    })
}
pub(super) fn decode_memo(vm: &mut Vm, text: Option<&str>) -> Result<JValue, String> {
    Ok(match text {
        None => vm
            .alloc_native(
                "Lkotlinx/serialization/json/JsonObject;",
                Native::Json(JsonVal::Object(vec![])),
            )
            .map_err(|e| e.to_string())?,
        Some(text) => {
            if text.len() > MAX_MEMO {
                return Err("Source chapter metadata exceeds limits.".into());
            }
            let value: Value =
                serde_json::from_str(text).map_err(|_| "Invalid source chapter metadata.")?;
            if !value.is_object() {
                return Err("Source chapter metadata must be an object.".into());
            }
            let value = json_node(value, 0)?;
            vm.alloc_native(
                "Lkotlinx/serialization/json/JsonObject;",
                Native::Json(value),
            )
            .map_err(|e| e.to_string())?
        }
    })
}
pub(super) fn pages(
    ext: &mut Keiyoushi,
    src: &Source,
    input: &ChapterInput,
) -> Result<Value, String> {
    let memo = decode_memo(ext.ctx().vm(), input.memo.as_deref())?;
    let number = input.chapter_number.unwrap_or(-1.0);
    if !number.is_finite() {
        return Err("Invalid source chapter number.".into());
    }
    let chapter = ext
        .ctx()
        .vm()
        .alloc_native(
            "Leu/kanade/tachiyomi/source/model/SChapter;",
            Native::SChapter {
                url: input.url.clone(),
                name: input.name.clone(),
                date_upload: input.uploaded_at,
                scanlator: input.scanlator.clone(),
                chapter_number: number,
                memo,
            },
        )
        .map_err(|e| e.to_string())?;
    let class = ext
        .ctx()
        .vm()
        .ensure_class_by_desc("Lkotlin/coroutines/jvm/internal/ContinuationImpl;")
        .map_err(|e| e.to_string())?;
    let continuation = JValue::Obj(
        ext.ctx()
            .vm()
            .alloc_instance(class)
            .map_err(|e| e.to_string())?,
    );
    let out = ext.ctx().invoke_on(src.inst(), "getPageList", "(Leu/kanade/tachiyomi/source/model/SChapter;Lkotlin/coroutines/Continuation;)Ljava/lang/Object;", &[chapter, continuation]).map_err(|e| ext.describe_error(&e))?;
    let Some(Native::List(items)) = ext.ctx().vm().payload_of(out) else {
        return Err("The source returned an invalid page list.".into());
    };
    if items.len() > 5000 {
        return Err("This chapter has too many pages.".into());
    }
    items
        .into_iter()
        .map(|item| match ext.ctx().vm().payload_of(item) {
            Some(Native::SPPage {
                index,
                url,
                image_url,
                ..
            }) => Ok(json!({"index":index,"url":url,"imageURL":image_url})),
            _ => Err("The source returned an invalid page.".into()),
        })
        .collect::<Result<Vec<Value>, String>>()
        .map(Value::Array)
}
