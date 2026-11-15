#!/usr/bin/env python3
"""Report actual GitHub Actions IPA timings, including queue/cache overhead.

Usage: python3 scripts/benchmark-ipa.py RUN_ID [RUN_ID ...]
Optional GH_TOKEN/GITHUB_TOKEN supports authenticated API rate limits. A local
JSON snapshot with {"run": {...}, "jobs": [...]} can replace any run ID.
"""
import argparse
from datetime import datetime
import json
import os
from pathlib import Path
import urllib.request


def seconds(start, end):
    return max(0, round((datetime.fromisoformat(end.replace("Z", "+00:00")) -
                         datetime.fromisoformat(start.replace("Z", "+00:00"))).total_seconds()))


def duration(value):
    minutes, remainder = divmod(value, 60)
    return f"{minutes}m{remainder:02d}s"


def api(path):
    headers = {"Accept": "application/vnd.github+json", "User-Agent": "AnimeCompanion-IPA-benchmark"}
    token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
    if token:
        headers["Authorization"] = f"Bearer {token}"
    request = urllib.request.Request("https://api.github.com/" + path, headers=headers)
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


def fetch(repo, identifier):
    if not identifier.isdecimal():
        return json.loads(Path(identifier).read_text())
    run = api(f"repos/{repo}/actions/runs/{identifier}")
    jobs = []
    page = 1
    while True:
        batch = api(f"repos/{repo}/actions/runs/{identifier}/jobs?per_page=100&page={page}")["jobs"]
        jobs.extend(batch)
        if len(batch) < 100:
            break
        page += 1
    return {"run": run, "jobs": jobs}


def metrics(snapshot):
    run, jobs = snapshot["run"], snapshot["jobs"]
    if run["status"] != "completed" or run["conclusion"] != "success":
        raise ValueError(f"Run {run['id']} has not completed successfully")
    active = [job for job in jobs if job["conclusion"] != "skipped"]
    for job in active:
        if job["conclusion"] != "success":
            raise ValueError(f"{job['name']} did not succeed")
    build = next(job for job in active if job["name"] == "build")
    initial = [job for job in active if job["name"] in {
        "Core regressions", "Safari video detection and VidHub handoff",
        "Build on-device manga runtime", "Apple encrypted startup cache regressions",
        "MangaBaka public discovery contracts", "On-device extension runtime regressions",
    }]

    def elapsed(job):
        return seconds(job["started_at"], job["completed_at"])

    def step_time(name):
        return sum(seconds(step["started_at"], step["completed_at"])
                   for job in active for step in job.get("steps", [])
                   if step["name"] == name and step["conclusion"] != "skipped")

    upload = next(step for step in build["steps"] if step["name"] == "Upload universal build")
    return {
        "Workflow elapsed (includes queues)": seconds(run["created_at"], run["updated_at"]),
        "IPA artifact ready (includes queues)": seconds(run["created_at"], upload["completed_at"]),
        # Deliberately label this model separately from observed wall time. It
        # removes runner scheduling waits, but includes cache restore/save steps.
        "Queue-free IPA critical path": max(map(elapsed, initial)) + elapsed(build),
        "Native runtime job (includes tests/cache)": elapsed(next(job for job in active if job["name"] == "Build on-device manga runtime")),
        "Apple encrypted-cache test step": step_time("Verify encrypted AniList startup snapshots on Apple platforms"),
        "IPA build job (includes cache upload)": elapsed(build),
        "Release compile step": step_time("Compile universal iPhone and iPad app"),
        "IPA package/validation step": step_time("Package unsigned IPA"),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("runs", nargs="+")
    parser.add_argument("--repo", default="goon-123/AnimeCompanion")
    args = parser.parse_args()
    snapshots = [fetch(args.repo, identifier) for identifier in args.runs]
    values = [metrics(snapshot) for snapshot in snapshots]
    print("| Metric | " + " | ".join(f"[Run {s['run']['id']}]({s['run']['html_url']})" for s in snapshots) + " |")
    print("|---|" + "---|" * len(snapshots))
    for metric in values[0]:
        print("| " + metric + " | " + " | ".join(duration(value[metric]) for value in values) + " |")
    print("\nQueue-free critical path = longest prerequisite job + IPA build job; it is a model, not wall time.")
    print("Compare the same source/toolchain and distinguish first-population, warm and changed-source builds.")


if __name__ == "__main__":
    main()
