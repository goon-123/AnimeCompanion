"""Evidence-aware matrix and shared-gap ranking."""
from collections import Counter, defaultdict
import html
import json
from pathlib import Path
import re
from .dependencies import dependency_summary
from .matrix import write_matrix

READING_FLOW = {"popular", "details", "chapters", "pages", "images"}


def passing_tests(text):
    return set(re.findall(r"^test ([A-Za-z0-9_:]+) \.\.\. ok\s*$", text, re.MULTILINE))


def fixture_evidence(entry, fixtures, passed):
    matched, historical = {}, []
    for fixture in fixtures:
        if fixture["package"] != entry["package"]:
            continue
        verified = [case for case in fixture["cases"] if case["test"] in passed]
        if fixture["sha256"] != entry["sha256"]:
            if verified:
                historical.append({"name": fixture["name"], "sha256": fixture["sha256"],
                                   "tests": sorted(case["test"] for case in verified)})
            continue
        for case in verified:
            for index in case["sources"]:
                row = matched.setdefault(str(index), {"stages": set(), "tests": set()})
                row["stages"].update(case["stages"])
                row["tests"].add(case["test"])
    return {
        "sources": {index: {"stages": sorted(row["stages"]), "tests": sorted(row["tests"]),
                           "completeOwnedFlow": READING_FLOW <= row["stages"]}
                    for index, row in sorted(matched.items())},
        "historical": historical,
        "liveVerified": False,
    }


def group_gaps(rows):
    observed = defaultdict(lambda: {"packages": set(), "sources": set(), "operations": set()})
    potential = defaultdict(set)
    for row in rows:
        pkg = row["package"]
        for operation in row.get("probe", {}).get("operations", []):
            key = None
            if operation.get("missingMethod"):
                key = " ".join(operation["missingMethod"])
            elif operation.get("missingClass"):
                key = operation["missingClass"]
            elif operation.get("status") == "runtimeAPIError" and operation.get("apiClass"):
                key = "classAPI " + operation["apiClass"]
            if key:
                observed[key]["packages"].add(pkg)
                observed[key]["sources"].add((pkg, operation.get("source")))
                observed[key]["operations"].add(operation["op"])
        for reference in row.pop("_unmatched", []):
            potential[" ".join(reference)].add(pkg)

    def priority(item):
        key, value = item
        return -len(value["packages"]), -len(value["sources"]), key

    observed_rows = [{"api": key, "packageCount": len(data["packages"]),
                      "sourceInstances": len(data["sources"]),
                      "operations": sorted(data["operations"]),
                      "packages": sorted(data["packages"])}
                     for key, data in sorted(observed.items(), key=priority)]
    potential_rows = [{"api": key, "packageCount": len(packages),
                       "packages": sorted(packages)}
                      for key, packages in sorted(potential.items(), key=lambda item: (-len(item[1]), item[0]))]
    return observed_rows, potential_rows


def cell(text):
    return html.escape(str(text), quote=False).replace("\\", "\\\\").replace("|", "\\|").replace("\n", " ").replace("\r", " ").replace("`", "'")


def render(report):
    rows = report["packages"]
    counts = report["summary"]
    lines = [
        "# Manga extension compatibility audit",
        "",
        "Development evidence from a frozen catalog and the actual bundled runtime.",
        "No website catalog, chapter or image content is fetched by the probes.",
        "Static references and empty owned-response probes do not certify live sources.",
        "",
        f"- Catalog revision: `{report['catalogRef']}`",
        f"- Runtime code revision: `{report['runtimeRevision']}`",
        f"- Catalog packages: {counts['catalogPackages']}; inventoried: {counts['inventoriedPackages']}.",
        f"- Sources enumerated by runtime: {counts['enumeratedSources']}; operation probes: {counts['operationProbes']}.",
        f"- Exact-version sources with complete owned-flow evidence: {counts['completeOwnedSources']}.",
        f"- Observed API-gap groups: {len(report['observedGaps'])}; unmatched static reference groups: {len(report['potentialGaps'])}.",
        "",
        "## Meaning of results",
        "",
        "- Owned-flow evidence requires named passing tests and an exact APK checksum/source index.",
        "- A registered API may still have incorrect behavior; presence is not conformance.",
        "- An unmatched reference can be optional, inherited through an unknown type, or dynamically dispatched.",
        "- Probes use empty owned HTML and synthetic title/chapter URLs. Unclassified errors can be fixture limitations or runtime bugs.",
        "- Browser probes are marked as needing the WebKit harness, not as website/runtime failures.",
        "- Source constructors and operations are isolated and bounded; timeouts and unexecuted cells remain explicit.",
        "- No source is marked live verified by this report.",
        "- Open compatibility.html for the searchable per-source matrix, or compatibility.csv for a spreadsheet.",
        "",
        "## Shared library families",
        "",
        "References show dependency use, not implementation conformance. Counts overlap across families.",
        "",
        "| Family | Referencing packages | Packages with observed gaps |",
        "| --- | ---: | ---: |",
    ]
    for family in report.get("dependencySummary", []):
        lines.append(f"| {cell(family['family'])} | {family['referencingPackages']} | {family['blockedPackages']} |")
    lines += [
        "",
        "## Observed shared runtime gaps",
        "",
        "| API | Packages | Source instances | Operations |",
        "| --- | ---: | ---: | --- |",
    ]
    for gap in report["observedGaps"][:100]:
        lines.append(f"| {cell(gap['api'])} | {gap['packageCount']} | {gap['sourceInstances']} | {cell(', '.join(gap['operations']))} |")
    if not report["observedGaps"]:
        lines.append("| No API error observed in exercised paths | 0 | 0 | Other paths remain unverified |")
    lines += ["", "## Potential shared API gaps from declarations", "",
              "These are investigation candidates, not confirmed failures.", "",
              "| Reference | Packages |", "| --- | ---: |"]
    for gap in report["potentialGaps"][:100]:
        lines.append(f"| {cell(gap['api'])} | {gap['packageCount']} |")
    lines += ["", "## Exact-version source evidence", "",
              "| Package / APK | Source | Owned fixture stages verified | Complete owned flow |",
              "| --- | ---: | --- | --- |"]
    for row in rows:
        for index, evidence in row["evidence"]["sources"].items():
            lines.append(f"| {cell(row['name'])} | {index} | {cell(', '.join(evidence['stages']))} | {'Yes' if evidence['completeOwnedFlow'] else 'Partial'} |")
    lines += ["", "## Catalog inventory and offline preflights", "",
              "| Package | APK | Static inventory | Probe outcome counts |",
              "| --- | --- | --- | --- |"]
    for row in rows:
        statuses = Counter(op["status"] for op in row.get("probe", {}).get("operations", []))
        result = ", ".join(f"{key}: {value}" for key, value in sorted(statuses.items()))
        if row.get("probe", {}).get("processStatus") != "completed":
            result += " / " + row.get("probe", {}).get("processStatus", "notRun")
        static = row.get("inventoryStatus", "notRun")
        lines.append(f"| {cell(row['package'])} | {cell(row['name'])} | {cell(static)} | {cell(result)} |")
    return "\n".join(lines) + "\n"


def write_report(output, rows, metadata):
    output = Path(output)
    output.mkdir(parents=True, exist_ok=True)
    rows.sort(key=lambda row: row["package"])
    observed, potential = group_gaps(rows)
    report = {
        "schemaVersion": 1, **metadata,
        "summary": {
            "catalogPackages": len(rows),
            "inventoriedPackages": sum(row.get("inventoryStatus") == "complete" for row in rows),
            "enumeratedSources": sum(len(row.get("probe", {}).get("sources", [])) for row in rows),
            "operationProbes": sum(op["status"] != "notAdvertised" for row in rows
                for op in row.get("probe", {}).get("operations", [])),
            "completeOwnedSources": sum(data["completeOwnedFlow"]
                for row in rows for data in row["evidence"]["sources"].values()),
        },
        "observedGaps": observed, "potentialGaps": potential, "packages": rows,
        "dependencySummary": dependency_summary(rows, observed),
    }
    (output / "compatibility.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    (output / "compatibility.md").write_text(render(report))
    write_matrix(output, report)
    return report
