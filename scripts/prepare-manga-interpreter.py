#!/usr/bin/env python3
"""Prepare the pinned interpreter plus our reviewable Dalvik semantics patch.

The generated checkout is build input, not an alternate extension engine or a
server. Never modify Cargo's shared dependency cache.
"""
import hashlib
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
REVISION = "38d3438d7e36b5c2c17414029fd36b2d717eefcb"
PATCH = ROOT / "Tools/MangaRuntime/support/dexvm-core.patch"
PATCHED_SOURCE_SHA256 = "8227ecc575a7cfb085b5b908245389611d6937da33d7e371a5764bff3898482b"
DESTINATION = ROOT / "Tools/MangaRuntime/target/patched-dexvm"


def git(directory, *args):
    return subprocess.check_output(["git", "-C", str(directory), *args])


def verify(directory):
    if git(directory, "rev-parse", "HEAD").decode().strip() != REVISION:
        raise RuntimeError("Unexpected interpreter revision; leave existing files untouched")
    # Verify the entire tracked checkout, not only the patched function.
    changed = git(directory, "diff", "HEAD", "--name-only").decode().splitlines()
    if changed != ["src/vm/interpret.rs"]:
        raise RuntimeError("Unexpected interpreter changes; leave existing files untouched")
    git(directory, "apply", "--reverse", "--check", str(PATCH))
    digest = hashlib.sha256((directory / "src/vm/interpret.rs").read_bytes()).hexdigest()
    if digest != PATCHED_SOURCE_SHA256:
        raise RuntimeError("Unexpected interpreter patch contents")
    if git(directory, "ls-files", "--others", "--exclude-standard").strip():
        raise RuntimeError("Unexpected files in interpreter checkout")


DESTINATION.parent.mkdir(parents=True, exist_ok=True)
if not DESTINATION.exists():
    with tempfile.TemporaryDirectory(prefix="manga-interpreter-", dir=DESTINATION.parent) as temporary:
        directory = Path(temporary) / "source"
        directory.mkdir()
        git(directory, "init", "--quiet")
        git(directory, "fetch", "--quiet", "--depth=1", "https://github.com/tachibana-shin/dexvm", REVISION)
        git(directory, "checkout", "--quiet", "--detach", "FETCH_HEAD")
        git(directory, "apply", "--check", str(PATCH))
        git(directory, "apply", str(PATCH))
        verify(directory)
        directory.rename(DESTINATION)
verify(DESTINATION)
print(f"Interpreter {REVISION[:12]}, patch SHA-256 {hashlib.sha256(PATCH.read_bytes()).hexdigest()}")
