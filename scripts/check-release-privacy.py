#!/usr/bin/env python3
"""Fail closed on credential literals and private device files; never echo values."""
import argparse
import json
import pathlib
import plistlib
import re
import subprocess
import sys

PATTERNS = {
    "MangaBaka personal key": rb"\bmb-[A-Za-z0-9_-]{24,}\b",
    "GitHub access token": rb"\b(?:gh[pousr]_[A-Za-z0-9_]{30,}|github_pat_[A-Za-z0-9_]{40,})\b",
    "AWS access key": rb"\b(?:AKIA|ASIA)[A-Z0-9]{16}\b",
    "JWT credential": rb"\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{20,}\b",
    "private PEM key": rb"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----\s+[A-Za-z0-9+/=\r\n]{100,}-----END",
    "credential assignment": rb'''(?i)["']?(?:api[_-]?key|access[_-]?token|refresh[_-]?token|client[_-]?secret|authorization)["']?\s*[:=]\s*["'](?:Bearer )?([A-Za-z0-9_./+=-]{24,})["']''',
    "Swift credential default": rb'''(?i)(?:let|var)\s+\w*(?:token|secret|api_?key)\w*\s*(?::\s*String\??)?\s*=\s*["']([A-Za-z0-9_./+=-]{24,})["']''',
    "credential in URL": rb"(?i)[?&](?:api[_-]?key|token|access_token|password)=([A-Za-z0-9_%./+=-]{24,})",
}
PREVIEW_MARKERS = [b"owned-preview-not-a-real-credential", b"owned-preview-second-account",
                   b"--ui-customization-preview", b"--ui-onboarding-preview"]
PRIVATE_SUFFIXES = {".sqlite", ".sqlite3", ".db", ".log", ".har", ".xcresult", ".mobileprovision"}
PRIVATE_PARTS = {".git", "keychain", "preferences", "caches", "ownedfixtures", "fixtures", "__pycache__"}


def placeholder(value):
    lower = value.lower()
    return any(word in lower for word in [b"your_", b"your-", b"example", b"placeholder", b"owned-", b"replace_me"])


def scan_bytes(data, name, release=False):
    findings = []
    for kind, pattern in PATTERNS.items():
        for match in re.finditer(pattern, data):
            if kind in {"credential assignment", "credential in URL", "Swift credential default"} and placeholder(match.group(1)):
                continue
            findings.append({"file": name, "line": data[:match.start()].count(b"\n") + 1, "kind": kind})
            break
    if release and any(marker in data for marker in PREVIEW_MARKERS):
        findings.append({"file": name, "kind": "debug account/setup fixture in Release"})
    return findings


def scan_bundle(root):
    findings = []
    info = plistlib.loads((root / "Info.plist").read_bytes())
    if info.get("MangaBakaClientID"):
        findings.append({"file": "Info.plist", "kind": "bundled MangaBaka OAuth app configuration"})
    for path in root.rglob("*"):
        relative = path.relative_to(root)
        if set(part.lower() for part in relative.parts) & PRIVATE_PARTS or path.suffix.lower() in PRIVATE_SUFFIXES:
            findings.append({"file": str(relative), "kind": "private/device or test-only resource"})
        if path.is_file():
            findings += scan_bytes(path.read_bytes(), str(relative), release=True)
    return findings


def scan_source(root):
    names = subprocess.check_output(["git", "ls-files", "-z"], cwd=root).decode().split("\0")
    findings = []
    for name in names:
        if name and (name.startswith(("App/", "Sources/", "SafariExtension/")) or name == "project.yml"):
            path = root / name
            if path.is_file():
                findings += scan_bytes(path.read_bytes(), name)
    return findings


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("path", type=pathlib.Path)
    parser.add_argument("--source", action="store_true")
    args = parser.parse_args()
    findings = scan_source(args.path) if args.source else scan_bundle(args.path)
    print(json.dumps({"passed": not findings, "findings": findings}, sort_keys=True))
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
