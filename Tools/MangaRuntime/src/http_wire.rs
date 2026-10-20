//! Binary-safe request payloads for the existing synchronous C callback.
use super::*;

pub(crate) fn request_json(request: &HttpData) -> Value {
    json!({
        "url": request.url,
        "method": request.method,
        "headers": request.headers,
        "body": request.body,
        "bodyBase64": request.body_bytes.as_ref().map(|bytes| STANDARD.encode(bytes)),
    })
}
