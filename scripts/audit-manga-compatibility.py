#!/usr/bin/env python3
"""Inventory a frozen extension catalog and run bounded offline C-ABI preflights.

No guest HTTP/browser request reaches a website. Exact-version owned-fixture
evidence is recorded separately from static candidates and generic preflights.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import gzip
import hashlib
import io
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time
import urllib.parse
import urllib.request

from manga_audit.dex import Dex, apk_inventory, unmatched_references, MAX_APK
from manga_audit.report import fixture_evidence, passing_tests, write_report
from manga_audit.runtime import probe, safe_reference

ROOT = Path(__file__).resolve().parents[1]
CONFIG = ROOT / "Tools/MangaRuntime/support/compatibility-fixtures.json"
ALLOWED_HOSTS = {"github.com", "raw.githubusercontent.com", "release-assets.githubusercontent.com",
                 "objects.githubusercontent.com"}


class HTTPSRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, message, headers, newurl):
        validate_url(newurl)
        return super().redirect_request(request, fp, code, message, headers, newurl)


def validate_url(url):
    parts = urllib.parse.urlsplit(url)
    if (parts.scheme != "https" or parts.hostname not in ALLOWED_HOSTS
            or parts.username or parts.password or parts.port not in (None, 443)):
        raise ValueError("Audit download must use an approved HTTPS host")


def fetch(url, limit):
    validate_url(url)
    opener = urllib.request.build_opener(HTTPSRedirect())
    with opener.open(url, timeout=30) as response:
        data = response.read(limit + 1)
    if len(data) > limit:
        raise ValueError("Audit download exceeds limit")
    return data


def protobuf(data):
    pos = 0

    def varint():
        nonlocal pos
        result = 0
        for shift in range(0, 70, 7):
            if pos >= len(data):
                raise ValueError("Truncated protobuf")
            value = data[pos]
            pos += 1
            result |= (value & 127) << shift
            if not value & 128:
                return result
        raise ValueError("Invalid protobuf integer")

    fields = {}
    while pos < len(data):
        key = varint()
        if key >> 3 == 0:
            raise ValueError("Invalid protobuf field")
        if key & 7 == 0:
            value = varint()
        elif key & 7 == 2:
            size = varint()
            if size > len(data) - pos:
                raise ValueError("Truncated protobuf field")
            value = data[pos:pos + size]
            pos += size
        else:
            raise ValueError("Unsupported protobuf wire type")
        fields.setdefault(key >> 3, []).append(value)
    return fields


def catalog(ref):
    if not re.fullmatch(r"[0-9a-f]{40}", ref):
        raise ValueError("Catalog revision must be a full commit SHA")
    base = f"https://raw.githubusercontent.com/keiyoushi/extensions/{ref}"
    raw = fetch(base + "/index.pb", 4 * 1024 * 1024)
    checksums = fetch(base + "/release-assets.json", 8 * 1024 * 1024)
    if raw[:2] == b"\x1f\x8b":
        with gzip.GzipFile(fileobj=io.BytesIO(raw)) as stream:
            expanded = stream.read(8 * 1024 * 1024 + 1)
    else:
        expanded = raw
    if len(expanded) > 8 * 1024 * 1024:
        raise ValueError("Expanded catalog exceeds limit")
    index = protobuf(protobuf(expanded)[101][0])[1]
    assets = json.loads(checksums)
    entries = []
    for encoded in index:
        entry = protobuf(encoded)
        package = entry[2][0].decode()
        resources = protobuf(entry[3][0])
        apk = assets.get(package, {}).get("apk")
        if not apk:
            raise ValueError("Catalog package lacks published APK checksum")
        name, digest, url = apk["name"], apk["sha256"], resources[1][0].decode()
        if (not re.fullmatch(r"eu\.kanade\.tachiyomi\.extension\.[A-Za-z0-9_.]+", package)
                or not re.fullmatch(r"tachiyomi-[A-Za-z0-9_.-]+\.apk", name)
                or not re.fullmatch(r"[0-9a-f]{64}", digest)):
            raise ValueError("Invalid catalog identifiers")
        validate_url(url)
        if not url.startswith("https://github.com/keiyoushi/extensions/releases/download/"):
            raise ValueError("Unexpected catalog APK origin")
        entries.append({"package": package, "name": name, "sha256": digest,
                        "url": url, "api": entry[4][0].decode()})
    if len({entry["package"] for entry in entries}) != len(entries):
        raise ValueError("Duplicate catalog package")
    return entries, {"indexSHA256": hashlib.sha256(raw).hexdigest(),
                     "assetManifestSHA256": hashlib.sha256(checksums).hexdigest()}


def verified_apk(entry, cache):
    path = cache / (entry["sha256"] + ".apk")
    if path.exists():
        data = path.read_bytes()
    else:
        data = fetch(entry["url"], MAX_APK)
    if hashlib.sha256(data).hexdigest() != entry["sha256"]:
        raise ValueError("APK checksum mismatch")
    if not path.exists():
        # Cache names are validated content digests, never repository paths.
        with tempfile.NamedTemporaryFile(dir=cache, delete=False) as stream:
            stream.write(data)
            temporary = Path(stream.name)
        temporary.replace(path)
    return path, data


def read_probe(path):
    operations, sources = [], []
    if path.exists():
        for line in path.read_text().splitlines():
            try:
                row = json.loads(line)
            except (ValueError, TypeError):
                continue
            if row.get("record") == "operation":
                row.pop("record")
                operations.append(row)
            elif row.get("record") == "sources":
                sources = row["indices"]
    return {"operations": operations, "sources": sources}


def run_probe(library, apk, modern, seconds, directory):
    with tempfile.TemporaryDirectory(prefix="probe-", dir=directory) as temporary:
        output = Path(temporary) / "result.jsonl"
        command = [sys.executable, str(Path(__file__).resolve()), "--probe-apk", str(apk),
                   "--probe-output", str(output), "--library", str(library),
                   "--probe-seconds", str(seconds), "--api", "1.6" if modern else "1.4"]
        status = "completed"
        try:
            result = subprocess.run(command, stdout=subprocess.DEVNULL,
                                    stderr=subprocess.DEVNULL, timeout=seconds + 8, check=False)
            if result.returncode:
                status = "processFailure"
        except subprocess.TimeoutExpired:
            status = "timedOut"
        result = read_probe(output)
        result["processStatus"] = status
        result["expectedOperationCells"] = len(result["sources"]) * 7
        result["unexecutedOperationCells"] = max(
            0, result["expectedOperationCells"]
            - sum(op.get("source") is not None for op in result["operations"]))
        return result


def audit_entry(entry, args, capabilities, bundled, fixtures, passed):
    row = {key: value for key, value in entry.items() if key != "url"}
    row["evidence"] = fixture_evidence(entry, fixtures, passed)
    try:
        path, data = verified_apk(entry, args.cache)
    except Exception as error:
        row.update(inventoryStatus="downloadFailure", failureType=type(error).__name__)
        return row
    try:
        inventory = apk_inventory(data)
        missing = unmatched_references(inventory, capabilities, bundled)
        # Only bounded API identifiers enter reports; never guest content strings.
        missing = [list(ref) for ref in missing if safe_reference(ref)]
        row.update(inventoryStatus="complete", methodReferences=len(inventory["references"]),
                   unmatchedReferenceCount=len(missing), unmatchedReferences=missing[:256],
                   unmatchedReferencesTruncated=len(missing) > 256, _unmatched=missing)
    except Exception as error:
        row.update(inventoryStatus="parseFailure", failureType=type(error).__name__)
    row["probe"] = run_probe(args.library, path, entry["api"] == "1.6",
                             args.probe_seconds, args.output)
    return row


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--library", type=Path, default=ROOT / "Tools/MangaRuntime/target/debug/deps/libanime_manga_runtime.so")
    parser.add_argument("--capabilities", type=Path, default=ROOT / "build/manga-audit/runtime-inventory.json")
    parser.add_argument("--test-log", type=Path, default=ROOT / "build/manga-audit/tests.log")
    parser.add_argument("--cache", type=Path, default=ROOT / "Tools/MangaRuntime/target/audit-apks")
    parser.add_argument("--output", type=Path, default=ROOT / "build/manga-audit")
    parser.add_argument("--catalog-ref")
    parser.add_argument("--packages", nargs="+")
    parser.add_argument("--workers", type=int, default=4)
    parser.add_argument("--probe-seconds", type=int, default=15)
    parser.add_argument("--deadline-seconds", type=int, default=1200)
    parser.add_argument("--probe-apk", type=Path, help=argparse.SUPPRESS)
    parser.add_argument("--probe-output", type=Path, help=argparse.SUPPRESS)
    parser.add_argument("--api", default="1.6", help=argparse.SUPPRESS)
    args = parser.parse_args()
    if args.probe_apk:
        probe(args.library, args.probe_apk, args.probe_output, args.api == "1.6", args.probe_seconds)
        return 0
    if not 1 <= args.workers <= 8 or not 1 <= args.probe_seconds <= 60:
        parser.error("Workers or per-package probe duration outside bounds")
    config = json.loads(CONFIG.read_text())
    ref = args.catalog_ref or config["catalogRef"]
    entries, snapshot = catalog(ref)
    if args.packages:
        entries = [entry for entry in entries if any(
            entry["package"].endswith(".extension." + suffix) or entry["package"] == suffix
            for suffix in args.packages)]
        if not entries:
            parser.error("No requested packages in pinned catalog")
    args.cache.mkdir(parents=True, exist_ok=True)
    args.output.mkdir(parents=True, exist_ok=True)
    args.library = args.library.resolve()
    capabilities = json.loads(args.capabilities.read_text())
    passed = passing_tests(args.test_log.read_text())
    if "compatibility_inventory::export_registered_runtime_inventory" not in passed:
        parser.error("Runtime inventory test must pass in the supplied test log")
    fixture_root = Path(os.environ.get("MANGA_TEST_APK_DIR", ROOT / "Tools/MangaRuntime/target/fixtures"))
    smoke_apk = fixture_root / "tachiyomi-en.mangapill-v1.4.9.apk"
    smoke = run_probe(args.library, smoke_apk, False, 2, args.output)
    if not any(op["op"] == "inspect" and op["status"] == "ownedResponseAccepted"
               for op in smoke["operations"]):
        parser.error("Production C-ABI smoke inspection failed; audit results would be invalid")
    bundled = Dex((ROOT / "Tools/MangaRuntime/support/serialization-decoder.dex").read_bytes()).inventory()
    deadline = time.monotonic() + args.deadline_seconds

    def bounded(entry):
        if time.monotonic() >= deadline:
            return {**{k: v for k, v in entry.items() if k != "url"},
                    "inventoryStatus": "deadlineNotRun",
                    "evidence": fixture_evidence(entry, config["fixtures"], passed)}
        return audit_entry(entry, args, capabilities, bundled, config["fixtures"], passed)

    rows = []
    print(json.dumps({"catalogPackages": len(entries), "catalogRef": ref}), flush=True)
    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        futures = [pool.submit(bounded, entry) for entry in entries]
        for future in as_completed(futures):
            rows.append(future.result())
            if len(rows) % 50 == 0:
                print(json.dumps({"packagesFinished": len(rows), "of": len(entries)}), flush=True)
    report = write_report(args.output, rows, {
        "catalogRef": ref, "runtimeRevision": os.environ.get("GITHUB_SHA", "local"),
        "scope": "selectedPackages" if args.packages else "entireCatalog",
        "capabilitiesSHA256": hashlib.sha256(args.capabilities.read_bytes()).hexdigest(),
        "testLogSHA256": hashlib.sha256(args.test_log.read_bytes()).hexdigest(), **snapshot,
    })
    def compact_gap(gap):
        return {**{k: v for k, v in gap.items() if k != "packages"},
                "samplePackages": gap["packages"][:8]}
    print("MANGA_AUDIT_SUMMARY " + json.dumps({
        "summary": report["summary"],
        "topObservedGaps": [compact_gap(g) for g in report["observedGaps"][:40]],
        "topPotentialGaps": [compact_gap(g) for g in report["potentialGaps"][:40]],
    }, sort_keys=True), flush=True)
    snapshot = {
        **{k: v for k, v in report.items() if k not in ("packages", "potentialGaps")},
        "potentialGaps": [compact_gap(g) for g in report["potentialGaps"][:100]],
        "packages": [{k: v for k, v in row.items()
                      if k not in ("unmatchedReferences", "probe")}
                     | {"probeCounts": dict(__import__("collections").Counter(
                         op["status"] for op in row.get("probe", {}).get("operations", []))),
                        "probeProcessStatus": row.get("probe", {}).get("processStatus", "notRun"),
                        "unexecutedOperationCells": row.get("probe", {}).get("unexecutedOperationCells", 0)}
                     for row in report["packages"]],
    }
    print("MANGA_AUDIT_SNAPSHOT " + json.dumps(snapshot, sort_keys=True), flush=True)
    return 0 if all(row.get("inventoryStatus") == "complete" for row in rows) else 2


if __name__ == "__main__":
    raise SystemExit(main())
