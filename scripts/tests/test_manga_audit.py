"""Meaningful checks for untrusted metadata, inheritance and evidence boundaries."""
import importlib.util
import json
import os
from pathlib import Path
import struct
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
from manga_audit.dex import Dex, DexError, apk_inventory, unmatched_references
from manga_audit.report import cell, fixture_evidence, passing_tests, group_gaps
from manga_audit.runtime import classify
from manga_audit.matrix import make_matrix, render_html, render_csv, write_matrix
from manga_audit.dependencies import dependency_families, dependency_summary

spec = importlib.util.spec_from_file_location("audit_cli", ROOT / "scripts/audit-manga-compatibility.py")
cli = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cli)


def owned_dex():
    strings = ["Lowned/Guest;", "Ljava/lang/Object;", "V", "call", "<init>"]
    header = bytearray(112)
    strings_off = 112
    types_off = strings_off + len(strings) * 4
    protos_off = types_off + 12
    methods_off = protos_off + 12
    classes_off = methods_off + 16
    class_data_off = classes_off + 32
    class_data = bytes([0, 0, 0, 1, 1, 0x81, 0x08, 0])
    data = bytearray(class_data)
    offsets = []
    for value in strings:
        offsets.append(class_data_off + len(data))
        data += bytes([len(value)]) + value.encode() + b"\0"
    header[:8] = b"dex\n035\0"
    struct.pack_into("<III", header, 32, class_data_off + len(data), 112, 0x12345678)
    for location, count, offset in [
        (56, len(strings), strings_off), (64, 3, types_off), (72, 1, protos_off),
        (80, 0, 0), (88, 2, methods_off), (96, 1, classes_off),
    ]:
        struct.pack_into("<II", header, location, count, offset)
    return bytes(header) + b"".join(struct.pack("<I", x) for x in offsets) + struct.pack(
        "<III", 0, 1, 2) + struct.pack("<III", 2, 2, 0) + struct.pack(
        "<HHIHHI", 1, 0, 4, 0, 0, 3) + struct.pack(
        "<8I", 0, 0x401, 1, 0, 0xFFFFFFFF, 0, class_data_off, 0) + data


class DexInventoryTests(unittest.TestCase):
    def test_declarations_descriptors_and_external_constructor_are_distinct(self):
        value = Dex(owned_dex()).inventory()
        self.assertIn(("Lowned/Guest;", "call", "()V"), value["declared"])
        self.assertNotIn(("Ljava/lang/Object;", "<init>", "()V"), value["declared"])
        self.assertEqual(value["parents"]["Lowned/Guest;"], ["Ljava/lang/Object;"])
        missing = unmatched_references(value, {"methods": [], "parents": {}})
        self.assertEqual(missing, [("Ljava/lang/Object;", "<init>", "()V")])

    def test_truncated_tables_bad_indices_and_uleb_overflow_are_rejected(self):
        data = bytearray(owned_dex())
        struct.pack_into("<I", data, 60, len(data) - 1)
        with self.assertRaises(DexError):
            Dex(data)
        data = bytearray(owned_dex())
        strings_offset = struct.unpack_from("<I", data, 68)[0]
        struct.pack_into("<I", data, strings_offset, 9999)
        with self.assertRaises(DexError):
            Dex(data).inventory()
        with self.assertRaises(DexError):
            Dex(owned_dex()).uleb(len(owned_dex()))
        dex = Dex(owned_dex())
        dex.data = b"\xff" * 5
        with self.assertRaises(DexError):
            dex.uleb(0)

    def test_inherited_methods_resolve_but_constructors_are_not_inherited(self):
        inventory = {"references": {("Lowned/Child;", "get", "()I"),
                                    ("Lowned/Child;", "<init>", "(I)V")},
                     "declared": set(), "native": set(),
                     "parents": {"Lowned/Child;": ["Ljava/util/Parent;"]}}
        capabilities = {"methods": [["Ljava/util/Parent;", "get", "()I"],
                                     ["Ljava/util/Parent;", "<init>", "(I)V"]],
                        "parents": {}}
        self.assertEqual(unmatched_references(inventory, capabilities),
                         [("Lowned/Child;", "<init>", "(I)V")])

    @unittest.skipUnless(os.environ.get("MANGA_TEST_APK_DIR"), "Pinned APK directory required")
    def test_actual_pinned_hentainexus_references_the_slice_api(self):
        root = Path(os.environ["MANGA_TEST_APK_DIR"])
        value = apk_inventory((root / "tachiyomi-en.hentainexus-v1.6.20.apk").read_bytes())
        self.assertIn(("Lkotlin/collections/ArraysKt;", "slice",
                       "([BLkotlin/ranges/IntRange;)Ljava/util/List;"), value["references"])


class EvidenceTests(unittest.TestCase):
    def test_report_cells_escape_identifiers_and_table_delimiters(self):
        self.assertEqual(cell('<init>|owned\n'), '&lt;init&gt;\\|owned ')

    def test_only_passing_tests_at_exact_checksum_and_source_index_count(self):
        entry = {"package": "owned", "sha256": "a" * 64}
        fixture = {**entry, "name": "owned.apk", "cases": [
            {"test": "suite::catalog", "sources": [17], "stages": ["popular"]},
            {"test": "suite::reader", "sources": [17], "stages": ["pages", "images"]},
        ]}
        passed = passing_tests("test suite::catalog ... ok\ntest suite::reader ... FAILED\n")
        result = fixture_evidence(entry, [fixture], passed)
        self.assertEqual(result["sources"]["17"]["stages"], ["popular"])
        self.assertFalse(result["sources"]["17"]["completeOwnedFlow"])
        self.assertFalse(result["liveVerified"])
        changed = fixture_evidence({**entry, "sha256": "b" * 64}, [fixture], passed)
        self.assertEqual(changed["sources"], {})
        self.assertEqual(changed["historical"][0]["name"], "owned.apk")

    def test_method_gap_ranking_counts_packages_once_across_source_languages(self):
        ref = ["Ljava/util/Owned;", "read", "()V"]
        row = {"package": "owned", "_unmatched": [ref], "probe": {"operations": [
            {"missingMethod": ref, "op": "popular", "source": 0},
            {"missingMethod": ref, "op": "popular", "source": 1},
        ]}}
        observed, potential = group_gaps([row])
        self.assertEqual(observed[0]["packageCount"], 1)
        self.assertEqual(observed[0]["sourceInstances"], 2)
        self.assertEqual(potential[0]["packageCount"], 1)

    def test_error_classification_keeps_secrets_and_fixture_failures_out_of_api_data(self):
        result = classify({"ok": False, "error": "uncaught exception: https://private.example/?token=secret"}, 1, 0)
        self.assertEqual(result["status"], "unclassifiedFailure")
        self.assertNotIn("secret", json.dumps(result))
        result = classify({"ok": False, "error": "resolution error: no method read ()V found (on Ljava/util/Owned; starting from Ljava/lang/Object;)"},
                          0, 0)
        self.assertEqual(result["missingMethod"], ["Ljava/util/Owned;", "read", "()V"])
        self.assertEqual(result["status"], "runtimeAPIError")
        self.assertEqual(classify({"ok": False, "error": "empty result"}, 1, 1)["status"],
                         "browserHarnessRequired")

    def test_catalog_parser_rejects_truncation_and_download_origins(self):
        with self.assertRaises(ValueError):
            cli.protobuf(b"\x0a\x05x")
        for url in ["http://github.com/owned", "https://github.com@private.example/x",
                    "https://private.example/x", "https://github.com:444/x"]:
            with self.assertRaises(ValueError):
                cli.validate_url(url)

    def test_fixture_inventory_checksums_match_the_actual_test_downloader(self):
        import re
        fixtures = json.loads((ROOT / "Tools/MangaRuntime/support/compatibility-fixtures.json").read_text())
        script = (ROOT / "scripts/test-manga-runtime.sh").read_text()
        expected = dict(re.findall(r"'([^']+\.apk)': '([0-9a-f]{64})'", script))
        self.assertEqual({f["name"]: f["sha256"] for f in fixtures["fixtures"]}, expected)


class MatrixTests(unittest.TestCase):
    def entry(self, **changes):
        value = {"package": "eu.kanade.tachiyomi.extension.en.owned", "name": "owned-v1.apk", "sha256": "a" * 64,
                 "displayName": "Owned extension", "evidence": {"sources": {}, "historical": []},
                 "declaredSources": [{"id": "42", "name": "Owned source", "language": "en"}],
                 "probe": {"sources": [0], "operations": [], "processStatus": "completed"}}
        value.update(changes)
        return value

    def matrix(self, *entries):
        return make_matrix({"packages": list(entries), "catalogRef": "b" * 40, "runtimeRevision": "c" * 40,
                            "summary": {"catalogPackages": len(entries)}, "observedGaps": []})

    def test_only_complete_exact_source_fixtures_verify_reading(self):
        value = self.entry()
        value["probe"]["operations"] = [{"op": op, "source": 0, "status": "ownedResponseAccepted"} for op in ("popular", "book", "pages", "image")]
        self.assertEqual(self.matrix(value)["rows"][0]["status"], "unverified")
        self.assertEqual(self.matrix(value)["rows"][0]["stages"]["pages"], "probeOnly")
        value["evidence"]["sources"]["0"] = {"stages": ["popular", "details", "chapters", "pages"], "tests": ["owned::partial"]}
        self.assertEqual(self.matrix(value)["rows"][0]["status"], "partial")
        value["evidence"]["sources"]["0"]["stages"].append("images")
        self.assertEqual(self.matrix(value)["rows"][0]["status"], "verified")
        value["probe"]["sources"].append(1)
        self.assertEqual([r["status"] for r in self.matrix(value)["rows"]], ["verified", "unverified"])
        value["evidence"] = {"sources": {}, "historical": [{"name": "old.apk"}]}
        self.assertTrue(all(r["status"] == "unverified" for r in self.matrix(value)["rows"]))

    def test_reading_blockers_are_distinct_from_settings_errors_and_unknown_failures(self):
        value = self.entry()
        value["probe"]["operations"] = [{"source": 0, "op": "settings", "status": "runtimeAPIError", "missingClass": "Landroid/Owned;"},
                                          {"source": 0, "op": "pages", "status": "unclassifiedFailure"}]
        self.assertEqual(self.matrix(value)["rows"][0]["status"], "unverified")
        value["probe"]["operations"].append({"source": 0, "op": "pages", "status": "runtimeAPIError", "missingClass": "Lokhttp3/Owned;"})
        self.assertEqual(self.matrix(value)["rows"][0]["status"], "unsupported")
        value["probe"] = {"sources": [], "operations": [{"source": None, "op": "inspect", "status": "runtimeAPIError", "missingClass": "LOwned;"}], "processStatus": "completed"}
        row = self.matrix(value)["rows"][0]
        self.assertIsNone(row["sourceIndex"])
        self.assertEqual(set(row["stages"].values()), {"blocked"})

    def test_identity_joins_catalog_by_id_without_assuming_language_order(self):
        value = self.entry()
        value["declaredSources"].append({"id": "17", "name": "Owned French", "language": "fr"})
        value["probe"].update(sources=[0, 1], sourceMetadata=[{"index": 0, "id": "17", "language": "fr"}, {"index": 1, "id": "42", "language": "en"}])
        rows = {r["sourceIndex"]: r for r in self.matrix(value)["rows"]}
        self.assertEqual((rows[0]["name"], rows[0]["language"]), ("Owned French", "fr"))
        self.assertEqual(rows[1]["name"], "Owned source")
        value["probe"].pop("sourceMetadata")
        self.assertTrue(all(r["language"] == "" for r in self.matrix(value)["rows"]))

    def test_library_ranking_counts_packages_once_and_excludes_guest_declarations(self):
        supplied = ("Lkotlin/Owned;", "call", "()V")
        families = dependency_families({"references": {supplied, ("Lokhttp3/Request;", "build", "()V"), ("Lokhttp3/Headers;", "get", "()V")}, "declared": {supplied}})
        self.assertEqual(families, {"OkHttp": {"classes": 2, "methods": 2}})
        value = self.entry(dependencyFamilies=families)
        gaps = [{"api": "Lokhttp3/Headers; get ()V", "packages": [value["package"]]}]
        summary = dependency_summary([value], gaps)
        self.assertEqual((summary[0]["referencingPackages"], summary[0]["blockedPackages"]), (1, 1))

    def test_html_metadata_and_spreadsheet_formulas_remain_inert(self):
        value = self.entry(displayName='</script><img src=x onerror=alert(1)>')
        value["declaredSources"][0]["name"] = '=HYPERLINK("https://example.invalid")'
        matrix = self.matrix(value)
        html = render_html(matrix)
        self.assertNotIn('</script><img', html)
        self.assertIn('\\u003c/script\\u003e', html)
        import csv, io
        rows = list(csv.reader(io.StringIO(render_csv(matrix))))
        self.assertTrue(rows[1][0].startswith("'="))
        self.assertIn("textContent", html)
        self.assertNotIn("innerHTML", html)

    def test_probe_metadata_keeps_only_bounded_ids_and_languages(self):
        from manga_audit.runtime import probe
        secret = "private-token-must-not-escape"
        class FakeRuntime:
            def __init__(self, _path): pass
            def execute(self, _apk, _command):
                return {"ok": True, "data": {"sources": [
                    {"index": 0, "id": "42", "language": "en", "name": secret, "homeURL": "https://private.example/" + secret},
                    {"index": 1, "id": secret, "language": "fr"}]}}, 0, 0
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); (root / "owned.apk").write_bytes(b"owned")
            with patch("manga_audit.runtime.OfflineRuntime", FakeRuntime):
                probe("unused", root / "owned.apk", root / "probe.jsonl", True, seconds=0)
            text = (root / "probe.jsonl").read_text()
            self.assertNotIn(secret, text)
            self.assertEqual(cli.read_probe(root / "probe.jsonl")["sourceMetadata"], [{"index": 0, "id": "42", "language": "en"}])


if __name__ == "__main__":
    unittest.main()
