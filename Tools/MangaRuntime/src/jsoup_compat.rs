//! Jsoup's [attribute~=regex] is not CSS's whitespace-token ~= operator.
use dexvm::vm::error::JvmError;
use dexvm::vm::object::{JsoupDocRef, Native};
use dexvm::vm::{NatErr, NativeEntry, NativeFn, Vm};
use dexvm::JValue;
use dom_query::{NodeId, NodeRef};
use fancy_regex::{Regex, RegexBuilder};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::OnceLock;

static ORIGINALS: OnceLock<[NativeFn; 5]> = OnceLock::new();
static NEXT_MARKER: AtomicU64 = AtomicU64::new(0);

fn document_select(vm: &mut Vm, args: &[JValue]) -> Result<JValue, NatErr> {
    select(vm, args, 0)
}
fn element_select(vm: &mut Vm, args: &[JValue]) -> Result<JValue, NatErr> {
    select(vm, args, 1)
}
fn elements_select(vm: &mut Vm, args: &[JValue]) -> Result<JValue, NatErr> {
    select(vm, args, 2)
}
fn element_first(vm: &mut Vm, args: &[JValue]) -> Result<JValue, NatErr> {
    select(vm, args, 3)
}
fn elements_first(vm: &mut Vm, args: &[JValue]) -> Result<JValue, NatErr> {
    select(vm, args, 4)
}

static ENTRIES: &[NativeEntry] = &[
    NativeEntry {
        class: "Lorg/jsoup/nodes/Document;",
        name: "select",
        sig: "(Ljava/lang/String;)Lorg/jsoup/select/Elements;",
        instance: true,
        f: document_select,
    },
    NativeEntry {
        class: "Lorg/jsoup/nodes/Element;",
        name: "select",
        sig: "(Ljava/lang/String;)Lorg/jsoup/select/Elements;",
        instance: true,
        f: element_select,
    },
    NativeEntry {
        class: "Lorg/jsoup/select/Elements;",
        name: "select",
        sig: "(Ljava/lang/String;)Lorg/jsoup/select/Elements;",
        instance: true,
        f: elements_select,
    },
    NativeEntry {
        class: "Lorg/jsoup/nodes/Element;",
        name: "selectFirst",
        sig: "(Ljava/lang/String;)Lorg/jsoup/nodes/Element;",
        instance: true,
        f: element_first,
    },
    NativeEntry {
        class: "Lorg/jsoup/select/Elements;",
        name: "selectFirst",
        sig: "(Ljava/lang/String;)Lorg/jsoup/nodes/Element;",
        instance: true,
        f: elements_first,
    },
];

pub(super) fn install(vm: &mut Vm) -> Result<(), JvmError> {
    if ORIGINALS.get().is_none() {
        let mut originals: Vec<NativeFn> = Vec::new();
        for entry in ENTRIES {
            let key = (
                vm.intern(entry.class),
                vm.intern(entry.name),
                vm.intern(entry.sig),
            );
            originals.push(
                *vm.natives
                    .get(&key)
                    .ok_or_else(|| JvmError::Resolution("Missing Jsoup host selector".into()))?,
            );
        }
        let _ = ORIGINALS.set(
            originals
                .try_into()
                .map_err(|_| JvmError::Resolution("Invalid Jsoup host table".into()))?,
        );
    }
    for entry in ENTRIES {
        vm.register_native(*entry)?;
    }
    Ok(())
}

struct Predicate {
    attribute: String,
    pattern: Regex,
    marker: String,
}

fn invalid(vm: &mut Vm, reason: &str) -> NatErr {
    NatErr::Throw(vm.throwable_of("Ljava/lang/IllegalArgumentException;", reason))
}

fn consume_budget(vm: &mut Vm, amount: usize) -> Result<(), NatErr> {
    vm.budget -= amount as i64;
    if vm.budget < 0 {
        Err(NatErr::Fatal(JvmError::BudgetExceeded))
    } else {
        Ok(())
    }
}

// Only trusted native selector code runs while the markers exist. Drop removes
// them even on an error/panic, before the original DOM/element IDs reach DEX.
struct Markers {
    doc: JsoupDocRef,
    changed: Vec<(NodeId, String)>,
}
impl Drop for Markers {
    fn drop(&mut self) {
        for (id, name) in &self.changed {
            NodeRef::new(*id, &self.doc.doc.tree).remove_attr(name);
        }
    }
}

fn select(vm: &mut Vm, args: &[JValue], entry: usize) -> Result<JValue, NatErr> {
    let original = ORIGINALS.get().ok_or_else(|| {
        NatErr::Fatal(JvmError::Resolution(
            "Missing Jsoup compatibility table".into(),
        ))
    })?[entry];
    let selector = vm
        .str_of_jvalue(args[1])
        .ok_or_else(|| invalid(vm, "Invalid Jsoup selector"))?;
    if !selector.contains("~=") {
        return original(vm, args);
    }
    if selector.len() > 16_384 {
        return Err(invalid(vm, "Jsoup selector exceeds size limit"));
    }
    let (rewritten, predicates) = rewrite(&selector).map_err(|e| invalid(vm, &e))?;
    if predicates.is_empty() {
        return original(vm, args);
    }
    let doc = match vm.payload_of(args[0]) {
        Some(Native::JsoupDoc(doc))
        | Some(Native::JsoupElement { doc, .. })
        | Some(Native::JsoupElements { doc, .. }) => doc,
        _ => return Err(invalid(vm, "Invalid Jsoup selector receiver")),
    };
    let mut markers = Markers {
        doc,
        changed: Vec::new(),
    };
    let elements = markers.doc.doc.select("*");
    if elements.length() > 50_000 {
        return Err(invalid(vm, "Jsoup regex selection exceeds node limit"));
    }
    let mut inspected = 0usize;
    for predicate in &predicates {
        for node in elements.nodes() {
            consume_budget(vm, 1)?;
            if node.has_attr(&predicate.marker) {
                return Err(invalid(vm, "Jsoup selector marker collision"));
            }
            let Some(value) = node.attr(&predicate.attribute) else {
                continue;
            };
            inspected += value.len();
            if inspected > 2_000_000 {
                return Err(invalid(vm, "Jsoup regex selection exceeds text limit"));
            }
            consume_budget(vm, value.len())?;
            if predicate
                .pattern
                .is_match(value.as_ref())
                .map_err(|_| invalid(vm, "Jsoup attribute regex exceeded its execution limit"))?
            {
                if markers.changed.len() >= 50_000 {
                    return Err(invalid(vm, "Jsoup regex selection exceeds match limit"));
                }
                node.set_attr(&predicate.marker, "");
                markers.changed.push((node.id, predicate.marker.clone()));
            }
        }
    }
    let rewritten = vm.alloc_string(&rewritten);
    let result = original(vm, &[args[0], rewritten]);
    drop(markers);
    result
}

/// Keep the original selector's combinators, lists, :has/:not and root scope.
/// Replace only regex attribute tests with temporary per-predicate markers.
fn rewrite(selector: &str) -> Result<(String, Vec<Predicate>), String> {
    let chars: Vec<char> = selector.chars().collect();
    let mut out = String::new();
    let mut predicates = Vec::new();
    let mut i = 0;
    let mut quote = None;
    let nonce = NEXT_MARKER.fetch_add(1, Ordering::Relaxed);
    while i < chars.len() {
        let c = chars[i];
        if c == '\\' && i + 1 < chars.len() {
            out.extend([c, chars[i + 1]]);
            i += 2;
            continue;
        }
        if let Some(q) = quote {
            out.push(c);
            if c == q {
                quote = None;
            }
            i += 1;
            continue;
        }
        if c == '\'' || c == '"' {
            quote = Some(c);
            out.push(c);
            i += 1;
            continue;
        }
        if c != '[' {
            out.push(c);
            i += 1;
            continue;
        }
        let start = i;
        i += 1;
        let mut depth = 1;
        let mut inner_quote = None;
        while i < chars.len() {
            let c = chars[i];
            if c == '\\' && i + 1 < chars.len() {
                i += 2;
                continue;
            }
            if let Some(q) = inner_quote {
                if c == q {
                    inner_quote = None;
                }
            } else if c == '\'' || c == '"' {
                inner_quote = Some(c);
            } else if c == '[' {
                depth += 1;
            } else if c == ']' {
                depth -= 1;
                if depth == 0 {
                    break;
                }
            }
            i += 1;
        }
        if depth != 0 {
            return Err("Unclosed Jsoup attribute selector".into());
        }
        let fragment: String = chars[start + 1..i].iter().collect();
        i += 1;
        let mut q = None;
        let mut op = None;
        let bytes = fragment.as_bytes();
        let mut j = 0;
        while j + 1 < bytes.len() {
            if bytes[j] == b'\\' {
                j += 2;
                continue;
            }
            if let Some(current) = q {
                if bytes[j] == current {
                    q = None;
                }
            } else if matches!(bytes[j], b'\'' | b'"') {
                q = Some(bytes[j]);
            } else if bytes[j] == b'~' && bytes[j + 1] == b'=' {
                op = Some(j);
                break;
            }
            j += 1;
        }
        let Some(op) = op else {
            out.extend(chars[start..i].iter());
            continue;
        };
        let attribute = fragment[..op].trim().to_ascii_lowercase();
        let mut pattern = fragment[op + 2..].trim();
        if pattern.len() >= 2
            && ((pattern.starts_with('"') && pattern.ends_with('"'))
                || (pattern.starts_with('\'') && pattern.ends_with('\'')))
        {
            pattern = &pattern[1..pattern.len() - 1];
        }
        if attribute.is_empty()
            || attribute.len() > 256
            || pattern.len() > 4096
            || predicates.len() >= 32
        {
            return Err("Jsoup regex selector exceeds limits".into());
        }
        let pattern = RegexBuilder::new(pattern)
            .backtrack_limit(10_000)
            .build()
            .map_err(|_| "Invalid Jsoup attribute regex")?;
        let marker = format!("data-animecompanion-regex-{nonce}-{}", predicates.len());
        out.push_str(&format!("[{marker}]"));
        predicates.push(Predicate {
            attribute,
            pattern,
            marker,
        });
    }
    Ok((out, predicates))
}

#[cfg(test)]
mod tests {
    use super::*;
    use dom_query::Document;

    const HTML: &str = r#"<html><body>
<section id="first" x-data="{ scroll: true }"><img id="one" src="/one.webp" data-code="AA12"><img id="two" src="/two.png" data-code="BB34"><span><img id="nested" src="/nested.webp"></span></section>
<section id="other" x-data="{ menu: true }"><img id="ad" src="/ad.png"></section>
<section id="second" x-data="scrollImages()"><img id="three" src="/three.webp" data-title="海岸线"></section>
<p id="literal" title="literal~=text">[fake~=value]</p></body></html>"#;

    fn fixture() -> (Vm, JValue, JsoupDocRef) {
        let mut vm = Vm::new(vec![], Box::new(std::io::sink())).unwrap();
        install(&mut vm).unwrap();
        let doc = JsoupDocRef::new(Document::from(HTML));
        let root = vm
            .alloc_native("Lorg/jsoup/nodes/Document;", Native::JsoupDoc(doc.clone()))
            .unwrap();
        (vm, root, doc)
    }
    fn query(vm: &mut Vm, receiver: JValue, selector: &str, first: bool) -> JValue {
        let selector = vm.alloc_string(selector);
        vm.invoke_virtual_args(
            receiver,
            if first { "selectFirst" } else { "select" },
            if first {
                "(Ljava/lang/String;)Lorg/jsoup/nodes/Element;"
            } else {
                "(Ljava/lang/String;)Lorg/jsoup/select/Elements;"
            },
            vec![selector],
        )
        .unwrap()
    }
    fn ids(vm: &Vm, value: JValue) -> Vec<String> {
        let (doc, ids) = match vm.payload_of(value).unwrap() {
            Native::JsoupElements { doc, ids } => (doc, ids),
            Native::JsoupElement { doc, id } => (doc, vec![id]),
            _ => panic!("Not a Jsoup selection"),
        };
        ids.iter()
            .map(|id| {
                NodeRef::new(*id, &doc.doc.tree)
                    .attr("id")
                    .unwrap()
                    .to_string()
            })
            .collect()
    }

    #[test]
    fn regex_matches_substrings_without_changing_the_dom_or_child_order() {
        let (mut vm, root, doc) = fixture();
        let before = doc.doc.html();
        let result = query(&mut vm, root, "section[x-data~=scroll] > img", false);
        assert_eq!(ids(&vm, result), ["one", "two", "three"]);
        assert_eq!(doc.doc.html(), before);
        let result = query(&mut vm, root, "section[x-data~=^missing$] > img", false);
        assert!(ids(&vm, result).is_empty());
    }

    #[test]
    fn element_elements_and_select_first_keep_their_receiver_scope() {
        let (mut vm, root, doc) = fixture();
        let first_id = doc.doc.select("#first").nodes()[0].id;
        let first = vm
            .alloc_native(
                "Lorg/jsoup/nodes/Element;",
                Native::JsoupElement {
                    doc: doc.clone(),
                    id: first_id,
                },
            )
            .unwrap();
        let result = query(&mut vm, first, "section[x-data~=scroll] > img", false);
        assert_eq!(ids(&vm, result), ["one", "two"]);
        let second_id = doc.doc.select("#second").nodes()[0].id;
        let roots = vm
            .alloc_native(
                "Lorg/jsoup/select/Elements;",
                Native::JsoupElements {
                    doc,
                    ids: vec![second_id, first_id],
                },
            )
            .unwrap();
        let result = query(&mut vm, roots, "section[x-data~=scroll] > img", false);
        assert_eq!(ids(&vm, result), ["three", "one", "two"]);
        let result = query(&mut vm, root, "section[x-data~=scroll] > img", true);
        assert_eq!(ids(&vm, result), ["one"]);
        let result = query(&mut vm, roots, "section[x-data~=scroll] > img", true);
        assert_eq!(ids(&vm, result), ["three"]);
    }

    #[test]
    fn regex_groups_character_classes_negation_and_has_are_not_css_word_tests() {
        let (mut vm, root, _) = fixture();
        for (selector, expected) in [
            (
                r"section[x-data~=scroll]:not([id~=second]) > img[src~=(?i)\.(png|webp)$]",
                vec!["one", "two"],
            ),
            (r"img[data-code~=[A-Z]{2}\d+]", vec!["one", "two"]),
            (
                r"section:has(> img[src~=(?i)\.PNG$])",
                vec!["first", "other"],
            ),
            (r"img[data-title~=海岸]", vec!["three"]),
        ] {
            let result = query(&mut vm, root, selector, false);
            assert_eq!(ids(&vm, result), expected, "{selector}");
        }
    }

    #[test]
    fn quoted_literal_operators_are_not_rewritten_as_attributes() {
        let (mut vm, root, doc) = fixture();
        let before = doc.doc.html();
        let literal = r#"p:contains("[fake~=value]")"#;
        let (rewritten, predicates) = rewrite(literal).unwrap();
        assert_eq!(rewritten, literal);
        assert!(predicates.is_empty());
        let result = query(&mut vm, root, r#"p[title="literal~=text"]"#, false);
        assert_eq!(ids(&vm, result), ["literal"]);
        let (_, predicates) = rewrite(r#"p[title="literal~=text"]"#).unwrap();
        assert!(predicates.is_empty());
        assert_eq!(doc.doc.html(), before);
    }

    #[test]
    fn invalid_patterns_and_budget_exhaustion_fail_without_leaking_markers() {
        let (mut vm, root, doc) = fixture();
        let before = doc.doc.html();
        let selector = vm.alloc_string("section[x-data~=(] > img");
        assert!(select(&mut vm, &[root, selector], 0).is_err());
        let selector = vm.alloc_string("section[x-data~=scroll] > img");
        vm.budget = 30;
        assert!(matches!(
            select(&mut vm, &[root, selector], 0),
            Err(NatErr::Fatal(JvmError::BudgetExceeded))
        ));
        assert_eq!(doc.doc.html(), before);
        assert!(rewrite("img[src~=[a-z]").is_err());
        assert!(rewrite(&format!("img[src~={}]", "a".repeat(4097))).is_err());
    }
}
