//! Java URI relativization operates on package data, without any networking.
use dexvm::vm::object::Native;
use dexvm::vm::{error::JvmError, NatErr, NativeEntry, Vm};
use dexvm::JValue;

struct Parts<'a> {
    scheme: Option<&'a str>,
    authority: Option<&'a str>,
    path: &'a str,
    suffix: &'a str,
    opaque: bool,
}
fn parts(text: &str) -> Parts<'_> {
    let cut = text.find(['?', '#']).unwrap_or(text.len());
    let (head, suffix) = text.split_at(cut);
    let (scheme, mut path) = match head.find(':') {
        Some(i)
            if i > 0
                && head.as_bytes()[0].is_ascii_alphabetic()
                && head[..i]
                    .bytes()
                    .all(|c| c.is_ascii_alphanumeric() || b"+-.".contains(&c)) =>
        {
            (Some(&head[..i]), &head[i + 1..])
        }
        _ => (None, head),
    };
    let opaque = scheme.is_some() && !path.starts_with('/');
    let authority = if let Some(rest) = path.strip_prefix("//") {
        let cut = rest.find('/').unwrap_or(rest.len());
        let authority = &rest[..cut];
        path = &rest[cut..];
        Some(authority)
    } else {
        None
    };
    Parts {
        scheme,
        authority,
        path,
        suffix,
        opaque,
    }
}
fn normalized(path: &str) -> String {
    let mut out = vec![];
    for part in path.split('/') {
        match part {
            "" | "." => {}
            ".." if out.last().is_some_and(|last| *last != "..") => {
                out.pop();
            }
            _ => out.push(part),
        }
    }
    let mut result = out.join("/");
    if path.starts_with('/') {
        result.insert(0, '/');
    }
    if (path.ends_with('/') || path.ends_with("/.") || path.ends_with("/.."))
        && !result.is_empty()
        && !result.ends_with('/')
    {
        result.push('/');
    }
    result
}
fn relative(base: &str, target: &str) -> Option<String> {
    let base = parts(base);
    let target = parts(target);
    if base.opaque
        || target.opaque
        || base.authority != target.authority
        || !match (base.scheme, target.scheme) {
            (Some(a), Some(b)) => a.eq_ignore_ascii_case(b),
            (None, None) => true,
            _ => false,
        }
    {
        return None;
    }
    let mut base_path = normalized(base.path);
    let target_path = normalized(target.path);
    let tail = if base_path == target_path {
        ""
    } else {
        if !base_path.ends_with('/') {
            base_path.push('/');
        }
        target_path.strip_prefix(&base_path)?
    };
    let mut result = String::new();
    if tail
        .split('/')
        .next()
        .is_some_and(|part| part.contains(':'))
    {
        result.push_str("./");
    }
    result.push_str(tail);
    result.push_str(target.suffix);
    Some(result)
}
fn relativize(vm: &mut Vm, args: &[JValue]) -> Result<JValue, NatErr> {
    let (Some(Native::URI(base)), Some(Native::URI(target))) =
        (vm.payload_of(args[0]), vm.payload_of(args[1]))
    else {
        return Err(NatErr::Throw(vm.err_npe()));
    };
    vm.budget -= (base.len() + target.len()) as i64;
    if vm.budget <= 0 || base.len() + target.len() > 32_768 {
        return Err(NatErr::Fatal(JvmError::BudgetExceeded));
    }
    match relative(&base, &target) {
        Some(value) => vm
            .alloc_native("Ljava/net/URI;", Native::URI(value))
            .map_err(NatErr::Fatal),
        None => Ok(args[1]),
    }
}
pub(super) fn install(vm: &mut Vm) -> Result<(), JvmError> {
    vm.register_native(NativeEntry {
        class: "Ljava/net/URI;",
        name: "relativize",
        sig: "(Ljava/net/URI;)Ljava/net/URI;",
        instance: true,
        f: relativize,
    })
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn relativize_preserves_boundaries_queries_fragments_and_unchanged_identity() {
        for (base, target, expected) in [
            (
                "https://owned.example/",
                "https://owned.example/book/42",
                "book/42",
            ),
            (
                "https://owned.example/a",
                "https://owned.example/a/b?x=%2F#p",
                "b?x=%2F#p",
            ),
            (
                "https://owned.example/a/./",
                "https://owned.example/a/b/../c",
                "c",
            ),
            (
                "https://owned.example/a",
                "https://owned.example/a?x=1",
                "?x=1",
            ),
        ] {
            assert_eq!(relative(base, target).as_deref(), Some(expected));
        }
        for target in [
            "https://other.example/a/b",
            "http://owned.example/a/b",
            "https://owned.example/ab/c",
            "mailto:owned@example.com",
        ] {
            assert!(relative("https://owned.example/a", target).is_none());
        }
        let mut vm = Vm::new(vec![], Box::new(std::io::sink())).unwrap();
        install(&mut vm).unwrap();
        let a = vm
            .alloc_native(
                "Ljava/net/URI;",
                Native::URI("https://owned.example/".into()),
            )
            .unwrap();
        let b = vm
            .alloc_native(
                "Ljava/net/URI;",
                Native::URI("https://other.example/book".into()),
            )
            .unwrap();
        assert_eq!(relativize(&mut vm, &[a, b]).unwrap(), b);
    }
}
