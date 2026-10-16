#!/usr/bin/env python3
"""Preserve a fresh target-app crash and stop a stuck XCTest launch promptly."""
import json
import os
from pathlib import Path
import shutil
import signal
import sys
import time

process, device, output = int(sys.argv[1]), sys.argv[2], Path(sys.argv[3])
started = time.time()
roots = [Path.home() / "Library/Logs/DiagnosticReports",
         Path.home() / f"Library/Developer/CoreSimulator/Devices/{device}/data/Library/Logs/CrashReporter"]
while True:
    try:
        os.kill(process, 0)
    except ProcessLookupError:
        break
    for root in roots:
        for report in root.glob("AnimeCompanion-*.ips"):
            try:
                if report.stat().st_mtime < started:
                    continue
                output.mkdir(parents=True, exist_ok=True)
                shutil.copy2(report, output / report.name)
                text = report.read_text()
                decoder = json.JSONDecoder()
                header, end = decoder.raw_decode(text)
                remaining = text[end:].strip()
                crash = decoder.raw_decode(remaining)[0] if remaining else header
                summary = {key: crash.get(key) for key in ("procName", "exception", "termination", "asi")}
                print("Target app crashed during native verification: " + json.dumps(summary), flush=True)
                os.kill(process, signal.SIGTERM)
                raise SystemExit(1)
            except (OSError, ValueError):
                # A report may still be being written. Inspect it on the next pass.
                continue
    time.sleep(2)
