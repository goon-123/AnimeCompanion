//! Jsoup selectors and raw data contracts used by HTML source extensions.
use dexvm::vm::error::JvmError;
use dexvm::vm::object::{JsoupDocRef, Native};
use dexvm::vm::{NatErr, NativeEntry, NativeFn, Vm};
use dexvm::JValue;
use dom_query::{NodeData, NodeId, NodeRef};
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
    for class in [
        "Lorg/jsoup/select/Evaluator$Class;",
        "Lorg/jsoup/select/Evaluator$Id;",
        "Lorg/jsoup/select/Evaluator$Tag;",
    ] {
        vm.register_native(NativeEntry {
            class,
            name: "<init>",
            sig: "(Ljava/lang/String;)V",
            instance: true,
            f: evaluator_init,
        })?;
    }
    vm.register_native(NativeEntry {
        class: "Lorg/jsoup/nodes/Element;",
        name: "toString",
        sig: "()Ljava/lang/String;",
        instance: true,
        f: outer_string,
    })?;
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
    vm.register_native(NativeEntry {
        class: "Lorg/jsoup/nodes/Element;",
        name: "data",
        sig: "()Ljava/lang/String;",
        instance: true,
        f: element_data,
    })?;
    Ok(())
}
fn css_identifier(text: &str) -> String {
    use std::fmt::Write;
    let mut escaped = String::new();
    for (index, c) in text.chars().enumerate() {
        if c == '\0' {
            escaped.push('\u{fffd}');
        } else if c.is_control()
            || (c.is_ascii_digit() && (index == 0 || (index == 1 && text.starts_with('-'))))
        {
            write!(escaped, "\\{:x} ", c as u32).unwrap();
        } else if c.is_ascii_alphanumeric()
            || c == '_'
            || (c == '-' && text != "-")
            || !c.is_ascii()
        {
            escaped.push(c);
        } else {
            escaped.push('\\');
            escaped.push(c);
        }
    }
    escaped
}
fn evaluator_init(vm: &mut Vm, args: &[JValue]) -> Result<JValue, NatErr> {
    let text = vm
        .str_of_jvalue(args[1])
        .ok_or_else(|| NatErr::Throw(vm.err_npe()))?;
    if text.len() > 4096 || vm.budget <= text.len() as i64 {
        return Err(NatErr::Fatal(JvmError::BudgetExceeded));
    }
    vm.budget -= text.len() as i64;
    let class = vm.arena.objects[args[0].as_obj() as usize].class;
    let descriptor = vm.str_of(vm.classes[class as usize].descriptor);
    // The pinned evaluator consumer tests suffixes without the final ';',
    // treating raw class/ID values as tag selectors. Store literal canonical
    // selectors, shared by select, selectFirst and Collector.findFirst.
    let selector = match descriptor {
        "Lorg/jsoup/select/Evaluator$Class;" if text.is_empty() => ":not(*)".into(),
        "Lorg/jsoup/select/Evaluator$Id;" if text.is_empty() => ":not([id]),[id=\"\"]".into(),
        "Lorg/jsoup/select/Evaluator$Class;" => format!(".{}", css_identifier(&text)),
        "Lorg/jsoup/select/Evaluator$Id;" => format!("#{}", css_identifier(&text)),
        _ if text.is_empty() => ":not(*)".into(),
        _ => css_identifier(&text.to_ascii_lowercase()),
    };
    vm.arena.objects[args[0].as_obj() as usize].native = Some(Native::Str(selector));
    Ok(JValue::Null)
}
fn outer_string(vm: &mut Vm, args: &[JValue]) -> Result<JValue, NatErr> {
    vm.invoke_virtual(args[0], "outerHtml", "()Ljava/lang/String;")
        .map_err(|e| match e {
            JvmError::Uncaught(o) => NatErr::Throw(o),
            other => NatErr::Fatal(other),
        })
}

enum Test {
    Attribute { attribute: String, pattern: Regex },
    Data(String),
}
struct Predicate {
    test: Test,
    marker: String,
}

// dom_query represents script/style data as text nodes. Ordinary visible text
// must not participate in Jsoup data(), while comments do. Keep traversal
// iterative and charge both visited nodes and copied bytes against VM limits.
fn raw_data(vm: &mut Vm, node: NodeRef, inspected: &mut usize) -> Result<String, NatErr> {
    let mut result = String::new();
    for child in std::iter::once(node).chain(node.descendants_it()) {
        consume_budget(vm, 1)?;
        let raw_text = child
            .parent()
            .and_then(|parent| parent.node_name())
            .is_some_and(|name| {
                name.eq_ignore_ascii_case("script") || name.eq_ignore_ascii_case("style")
            });
        let data = child
            .query(|item| match &item.data {
                NodeData::Comment { contents } => Some(contents.to_string()),
                NodeData::Text { contents } if raw_text => Some(contents.to_string()),
                _ => None,
            })
            .flatten();
        if let Some(data) = data {
            *inspected += data.len();
            if *inspected > 2_000_000 {
                return Err(invalid(vm, "Jsoup data exceeds text limit"));
            }
            consume_budget(vm, data.len())?;
            result.push_str(&data);
        }
    }
    Ok(result)
}
fn element_data(vm: &mut Vm, args: &[JValue]) -> Result<JValue, NatErr> {
    let (doc, id) = match vm.payload_of(args[0]) {
        Some(Native::JsoupDoc(doc)) => {
            let id = doc.doc.root().id;
            (doc, id)
        }
        Some(Native::JsoupElement { doc, id }) => (doc, id),
        _ => return Err(invalid(vm, "Invalid Jsoup data receiver")),
    };
    let data = raw_data(vm, NodeRef::new(id, &doc.doc.tree), &mut 0)?;
    Ok(vm.alloc_string(&data))
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
    if !selector.contains("~=") && !selector.contains(":containsData(") {
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
            let matched = match &predicate.test {
                Test::Attribute { attribute, pattern } => {
                    let Some(value) = node.attr(attribute) else {
                        continue;
                    };
                    inspected += value.len();
                    if inspected > 2_000_000 {
                        return Err(invalid(vm, "Jsoup selection exceeds text limit"));
                    }
                    consume_budget(vm, value.len())?;
                    pattern.is_match(value.as_ref()).map_err(|_| {
                        invalid(vm, "Jsoup attribute regex exceeded its execution limit")
                    })?
                }
                Test::Data(needle) => raw_data(vm, *node, &mut inspected)?
                    .to_lowercase()
                    .contains(needle),
            };
            if matched {
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
/// Replace non-CSS data/regex tests with temporary per-predicate markers.
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
        if chars[i..].starts_with(&":containsData(".chars().collect::<Vec<_>>()) {
            i += 14;
            let mut depth = 1;
            let mut quoted = None;
            let mut needle = String::new();
            while i < chars.len() {
                let ch = chars[i];
                i += 1;
                if ch == '\\' && i < chars.len() {
                    needle.push(chars[i]);
                    i += 1;
                    continue;
                }
                if let Some(q) = quoted {
                    if ch == q {
                        quoted = None;
                    }
                } else if ch == '\'' || ch == '"' {
                    quoted = Some(ch);
                } else if ch == '(' {
                    depth += 1;
                } else if ch == ')' {
                    depth -= 1;
                    if depth == 0 {
                        break;
                    }
                }
                needle.push(ch);
            }
            if depth != 0 || needle.is_empty() || predicates.len() >= 32 {
                return Err("Invalid Jsoup containsData selector".into());
            }
            let marker = format!("data-animecompanion-regex-{nonce}-{}", predicates.len());
            out.push_str(&format!("[{marker}]"));
            predicates.push(Predicate {
                test: Test::Data(needle.to_lowercase()),
                marker,
            });
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
            test: Test::Attribute { attribute, pattern },
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
    fn evaluator_classes_ids_and_tags_keep_literal_names_and_receiver_scope() {
        let (mut vm, _, _) = fixture();
        let document=JsoupDocRef::new(Document::from("<section id='scope'><p id='owned:1' class='title.with.dot'>Owned</p><p id='other' class='title'>Other</p></section><p id='outside' class='title.with.dot'>Outside</p>"));
        let root = vm
            .alloc_native("Lorg/jsoup/nodes/Document;", Native::JsoupDoc(document))
            .unwrap();
        let scope = query(&mut vm, root, "#scope", true);
        for (kind, name, expected) in [
            ("Class", "title.with.dot", vec!["owned:1"]),
            ("Id", "owned:1", vec!["owned:1"]),
            ("Tag", "P", vec!["owned:1", "other"]),
        ] {
            let evaluator = vm
                .alloc_native(
                    &format!("Lorg/jsoup/select/Evaluator${kind};"),
                    Native::Opaque,
                )
                .unwrap();
            let value = vm.alloc_string(name);
            evaluator_init(&mut vm, &[evaluator, value]).unwrap();
            let result = vm
                .invoke_virtual_args(
                    scope,
                    "select",
                    "(Lorg/jsoup/select/Evaluator;)Lorg/jsoup/select/Elements;",
                    vec![evaluator],
                )
                .unwrap();
            assert_eq!(ids(&vm, result), expected);
            let result = vm
                .invoke_virtual_args(
                    scope,
                    "selectFirst",
                    "(Lorg/jsoup/select/Evaluator;)Lorg/jsoup/nodes/Element;",
                    vec![evaluator],
                )
                .unwrap();
            assert_eq!(ids(&vm, result), [expected[0]]);
        }
        let evaluator = vm
            .alloc_native("Lorg/jsoup/select/Evaluator$Class;", Native::Opaque)
            .unwrap();
        let value = vm.alloc_string("title");
        vm.budget = 0;
        assert!(matches!(
            evaluator_init(&mut vm, &[evaluator, value]),
            Err(NatErr::Fatal(JvmError::BudgetExceeded))
        ));
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
    #[test]
    fn data_selectors_find_raw_scripts_styles_and_comments_without_visible_text() {
        let (mut vm, _, _) = fixture();
        let doc = JsoupDocRef::new(Document::from(
            r#"<html><body><section id="data"><script id="reader">initReader("owned", 0);
  keepWhitespace();</script><style id="style">.owned { color: red; }</style><!--Owned comment--><p>Visible words</p></section><section id="plain"><p>initReader("visible")</p></section></body></html>"#,
        ));
        let root = vm
            .alloc_native("Lorg/jsoup/nodes/Document;", Native::JsoupDoc(doc.clone()))
            .unwrap();
        let before = doc.doc.html();
        for (selector, expected) in [
            ("script:containsData(INITreader)", vec!["reader"]),
            ("section:has(script:containsData(initReader))", vec!["data"]),
            (
                "section:containsData(Owned comment):not(#plain)",
                vec!["data"],
            ),
            ("section:containsData(Visible words)", vec![]),
            ("style:containsData(color: red)", vec!["style"]),
            (
                r#"script:containsData(initReader\("owned", 0\))"#,
                vec!["reader"],
            ),
        ] {
            let selected = query(&mut vm, root, selector, false);
            assert_eq!(ids(&vm, selected), expected, "{selector}");
        }
        let script = query(&mut vm, root, "script:containsData(initReader)", true);
        let data = vm
            .invoke_virtual(script, "data", "()Ljava/lang/String;")
            .unwrap();
        assert_eq!(
            vm.str_of_jvalue(data).unwrap(),
            "initReader(\"owned\", 0);\n  keepWhitespace();"
        );
        let section = query(&mut vm, root, "#data", true);
        let data = vm
            .invoke_virtual(section, "data", "()Ljava/lang/String;")
            .unwrap();
        let data = vm.str_of_jvalue(data).unwrap();
        assert!(data.contains("Owned comment"));
        assert!(data.contains(".owned { color: red; }"));
        assert!(!data.contains("Visible words"));
        let selected = query(&mut vm, section, "script:containsData(initReader)", false);
        assert_eq!(ids(&vm, selected), ["reader"]);
        assert_eq!(doc.doc.html(), before);
    }

    #[test]
    fn data_selectors_reject_malformed_queries_and_leave_no_markers_on_budget_failure() {
        let (mut vm, root, doc) = fixture();
        assert!(rewrite("script:containsData(").is_err());
        assert!(rewrite("script:containsData()").is_err());
        let literal = r#"p[title=":containsData(owned)"]"#;
        let (rewritten, predicates) = rewrite(literal).unwrap();
        assert_eq!(rewritten, literal);
        assert!(predicates.is_empty());
        let before = doc.doc.html();
        let selector = vm.alloc_string("section:containsData(owned)");
        vm.budget = 20;
        assert!(matches!(
            select(&mut vm, &[root, selector], 0),
            Err(NatErr::Fatal(JvmError::BudgetExceeded))
        ));
        assert_eq!(doc.doc.html(), before);
    }
}
