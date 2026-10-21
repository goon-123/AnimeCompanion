"""Readable, per-source reading evidence; empty-response probes never verify a flow."""
from collections import Counter
import csv
import io
import json
from pathlib import Path

from .dependencies import family_for_class

STAGES = ("popular", "details", "chapters", "pages", "images")
LABELS = {"verified": "Verified offline", "partial": "Partial", "unsupported": "Runtime blocker", "unverified": "Unverified"}
OPERATION = {"popular": "popular", "details": "book", "chapters": "book", "pages": "pages", "images": "image"}
READING_OPS = {"inspect", "popular", "book", "pages", "image"}
BLOCKERS = {"runtimeAPIError", "interpreterDecodeError"}


def operation_gap(operation):
    if operation.get("missingMethod"):
        return " ".join(operation["missingMethod"])
    if operation.get("missingClass"):
        return operation["missingClass"]
    if operation.get("apiClass") and operation.get("status") == "runtimeAPIError":
        return "classAPI " + operation["apiClass"]
    return None


def source_rows(report):
    rows = []
    for package in report["packages"]:
        probe = package.get("probe", {})
        evidence = package.get("evidence", {}).get("sources", {})
        metadata = {item["index"]: item for item in probe.get("sourceMetadata", [])}
        declared = package.get("declaredSources", [])
        declared_by_id = {item["id"]: item for item in declared}
        indices = sorted(set(probe.get("sources", [])) | {int(i) for i in evidence})
        # A failed inspection cannot enumerate indices. Keep a package-level
        # row rather than assigning guessed source indices to catalog entries.
        for index in indices or [None]:
            proof = evidence.get(str(index), {}) if index is not None else {}
            verified = set(proof.get("stages", []))
            operations = [op for op in probe.get("operations", [])
                          if op.get("source") is None or op.get("source") == index]
            observed = [op for op in operations if op["status"] in BLOCKERS]
            identity = metadata.get(index, {})
            public = declared_by_id.get(identity.get("id"), {})
            if not public and len(declared) == 1 and len(indices) == 1:
                public = declared[0]
            display = package.get("displayName") or package["package"].rsplit(".", 1)[-1]
            name = public.get("name") or display
            if index is not None and not public:
                name += f" · source {index}"
            if index is None:
                name += " · not enumerated"
            stages = {}
            for stage in STAGES:
                relevant = [op for op in operations if op["op"] in ("inspect", OPERATION[stage])]
                statuses = {op["status"] for op in relevant}
                if stage in verified:
                    state = "verified"
                elif statuses & BLOCKERS:
                    state = "blocked"
                elif "browserHarnessRequired" in statuses:
                    state = "browser"
                elif "executionLimit" in statuses:
                    state = "limit"
                elif any(op["op"] == OPERATION[stage] and op["status"] == "ownedResponseAccepted" for op in relevant):
                    state = "probeOnly"
                else:
                    state = "unverified"
                stages[stage] = state
            if set(STAGES) <= verified:
                status = "verified"
            elif any(op["op"] in READING_OPS for op in observed):
                status = "unsupported"
            elif verified & (set(STAGES) | {"latest", "search"}):
                status = "partial"
            else:
                status = "unverified"
            gaps = sorted({gap for op in observed if (gap := operation_gap(op))})
            rows.append({
                "package": package["package"], "apk": package["name"], "sha256": package["sha256"],
                "extension": display, "name": name, "sourceIndex": index,
                "sourceID": identity.get("id"), "language": public.get("language") or identity.get("language", ""),
                "version": package.get("version", ""), "status": status, "stages": stages,
                "verifiedStages": sorted(verified), "tests": proof.get("tests", []),
                "runtimeGaps": gaps, "gapFamilies": sorted({family_for_class(gap) for gap in gaps}),
                "dependencies": sorted(package.get("dependencyFamilies", {})),
                "probeOutcomes": dict(sorted(Counter(op["status"] for op in operations).items())),
                "incomplete": probe.get("processStatus") != "completed" or probe.get("unexecutedOperationCells", 0) > 0,
                "historicalEvidence": bool(package.get("evidence", {}).get("historical")),
            })
    return sorted(rows, key=lambda row: (row["name"].casefold(), row["package"], row["sourceIndex"] or 0))


def make_matrix(report):
    rows = source_rows(report)
    return {"schemaVersion": 1, "catalogRef": report["catalogRef"], "runtimeRevision": report["runtimeRevision"],
            "scope": report.get("scope", "unknown"), "summary": report["summary"],
            "sourceStatuses": dict(Counter(row["status"] for row in rows)),
            "packageOnlyRows": sum(row["sourceIndex"] is None for row in rows),
            "dependencyInventoryPackages": sum("dependencyFamilies" in row for row in report["packages"]),
            "dependencySummary": report.get("dependencySummary", []),
            "observedGaps": [{key: gap[key] for key in ("api", "packageCount", "operations")} for gap in report["observedGaps"]],
            "provenance": {key: report.get(key) for key in ("indexSHA256", "assetManifestSHA256", "capabilitiesSHA256", "testLogSHA256")},
            "rows": rows}


def render_html(matrix):
    # Escape script terminators, HTML delimiters and JS line separators. The
    # browser renders all repository metadata with textContent, never HTML.
    data = json.dumps(matrix, ensure_ascii=True, separators=(",", ":")).replace("<", "\\u003c").replace(">", "\\u003e").replace("&", "\\u0026")
    return Path(__file__).with_name("matrix.html").read_text().replace("__MATRIX_DATA__", data)


def render_csv(matrix):
    stream = io.StringIO(newline="")
    writer = csv.writer(stream)
    writer.writerow(["Source", "Extension", "Language", "Source index", "Status", "Catalog", "Details", "Chapters", "Pages", "Images", "APK", "SHA-256", "Runtime gaps", "Evidence tests", "Incomplete probes"])
    def safe(value):
        text = str(value)
        return "'" + text if text.lstrip().startswith(("=", "+", "-", "@")) or text.startswith(("\t", "\r", "\n")) else text
    for row in matrix["rows"]:
        writer.writerow([safe(value) for value in [row["name"], row["extension"], row["language"], row["sourceIndex"] if row["sourceIndex"] is not None else "not enumerated",
            LABELS[row["status"]], *[row["stages"][stage] for stage in STAGES], row["apk"], row["sha256"], "; ".join(row["runtimeGaps"]), "; ".join(row["tests"]), row["incomplete"]]])
    return stream.getvalue()


def write_matrix(output, report):
    output = Path(output)
    output.mkdir(parents=True, exist_ok=True)
    matrix = make_matrix(report)
    (output / "compatibility.html").write_text(render_html(matrix))
    (output / "compatibility.csv").write_text(render_csv(matrix))
    (output / "compatibility-matrix.json").write_text(json.dumps(matrix, ensure_ascii=False, indent=2) + "\n")
    return matrix
