//! Only bounded host identifiers cross into user-visible errors. Guest exception
//! messages may contain request URLs, cookies or tokens and stay out of this data.
use serde_json::{json, Value};

pub(super) fn diagnostic(error: &str) -> Option<Value> {
    let kind = if error.starts_with("resolution error: class not found:")
        || error.starts_with("resolution error: no method ")
        || error.starts_with("resolution error: no static field ")
    {
        "unsupportedAPI"
    } else if matches!(error, "instruction budget exceeded" | "stack overflow") {
        "executionLimit"
    } else if error.starts_with("resolution error: json:") {
        "sourceResponse"
    } else {
        return None;
    };
    let api = error.split_whitespace().find_map(|word| {
        let class = word.strip_prefix('L')?.strip_suffix(';')?;
        if class.len() > 180
            || ![
                "java/",
                "kotlin/",
                "kotlinx/",
                "android/",
                "androidx/",
                "okhttp3/",
                "okio/",
                "org/jsoup/",
            ]
            .iter()
            .any(|prefix| class.starts_with(prefix))
            || !class
                .bytes()
                .all(|c| c.is_ascii_alphanumeric() || b"/_$".contains(&c))
            || class.split('/').any(str::is_empty)
        {
            return None;
        }
        Some(class.replace('/', "."))
    });
    Some(json!({"kind":kind,"api":api}))
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn only_host_api_names_are_disclosed() {
        let value = diagnostic("resolution error: no method parseCaseInsensitive () in Ljava/time/format/DateTimeFormatterBuilder;").unwrap();
        assert_eq!(value["kind"], "unsupportedAPI");
        assert_eq!(value["api"], "java.time.format.DateTimeFormatterBuilder");
        for error in [
            "uncaught Ljava/lang/Exception;: https://private.example/?token=secret",
            "resolution error: class not found: Lextension/private/token;",
            "resolution error: class not found: Ljava/private?token=secret;",
            "resolution error: class not found: Ljava//secret;",
        ] {
            assert!(diagnostic(error).is_none_or(|v| v["api"].is_null()));
        }
        assert_eq!(
            diagnostic("instruction budget exceeded").unwrap()["kind"],
            "executionLimit"
        );
        assert!(diagnostic("Invalid extension input.").is_none());
        let bad_json =
            diagnostic("resolution error: json: https://private.example/?token=secret").unwrap();
        assert_eq!(bad_json["kind"], "sourceResponse");
        assert!(!bad_json.to_string().contains("secret"));
    }
}
