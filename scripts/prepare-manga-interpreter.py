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
PATCHED_SOURCE_SHA256 = "a9acb463bc1af9b0c65b86fccb075ac545fb9c4be5f39975c231340662afbb95"
PATCHED_COLLECTIONS_SHA256 = "377a6ac4a1af671c067ebbcbfa25b7d7536d3e59a76792904544c9a7a33797e4"
PATCHED_JOIN_SHA256 = "dce8e171a42e6aa57fdda334f5eeec78f164515a3ed453d3bc8c5e6b0ade345f"
PATCHED_DECODER_SHA256 = "657fb30464c446dd6f1ed218772abda7df484f76045ea5d00787d1f73f118a69"
DESTINATION = ROOT / "Tools/MangaRuntime/target/patched-dexvm"


def git(directory, *args):
    return subprocess.check_output(["git", "-C", str(directory), *args])


def verify(directory):
    if git(directory, "rev-parse", "HEAD").decode().strip() != REVISION:
        raise RuntimeError("Unexpected interpreter revision; leave existing files untouched")
    # Verify the entire tracked checkout, not only the patched function.
    changed = git(directory, "diff", "HEAD", "--name-only").decode().splitlines()
    if changed != ["src/dex/insn.rs", "src/vm/interpret.rs", "src/vm/native/java/util/mod.rs", "src/vm/native/kotlin/collections.rs"]:
        raise RuntimeError("Unexpected interpreter changes; leave existing files untouched")
    git(directory, "apply", "--reverse", "--check", str(PATCH))
    digest = hashlib.sha256((directory / "src/vm/interpret.rs").read_bytes()).hexdigest()
    if digest != PATCHED_SOURCE_SHA256:
        raise RuntimeError("Unexpected interpreter patch contents")
    digest = hashlib.sha256((directory / "src/vm/native/java/util/mod.rs").read_bytes()).hexdigest()
    if digest != PATCHED_COLLECTIONS_SHA256:
        raise RuntimeError("Unexpected collection patch contents")
    digest = hashlib.sha256((directory / "src/vm/native/kotlin/collections.rs").read_bytes()).hexdigest()
    if digest != PATCHED_JOIN_SHA256:
        raise RuntimeError("Unexpected Kotlin collection patch contents")
    digest = hashlib.sha256((directory / "src/dex/insn.rs").read_bytes()).hexdigest()
    if digest != PATCHED_DECODER_SHA256:
        raise RuntimeError("Unexpected bytecode decoder patch contents")
    if git(directory, "ls-files", "--others", "--exclude-standard").strip():
        raise RuntimeError("Unexpected files in interpreter checkout")


DESTINATION.parent.mkdir(parents=True, exist_ok=True)
if DESTINATION.exists():
    # CI may restore build 41's generated checkout via a cache prefix. Only
    # migrate that exact known state, and preserve it instead of resetting a
    # dirty directory. Unknown changes still stop verification unchanged.
    legacy = (
        git(DESTINATION, "rev-parse", "HEAD").decode().strip() == REVISION
        and git(DESTINATION, "diff", "HEAD", "--name-only").decode().splitlines() == ["src/vm/interpret.rs"]
        and hashlib.sha256((DESTINATION / "src/vm/interpret.rs").read_bytes()).hexdigest()
            == "8227ecc575a7cfb085b5b908245389611d6937da33d7e371a5764bff3898482b"
        and not git(DESTINATION, "ls-files", "--others", "--exclude-standard").strip()
    )
    legacy_44 = (
        git(DESTINATION, "rev-parse", "HEAD").decode().strip() == REVISION
        and git(DESTINATION, "diff", "HEAD", "--name-only").decode().splitlines()
            == ["src/dex/insn.rs", "src/vm/interpret.rs", "src/vm/native/java/util/mod.rs", "src/vm/native/kotlin/collections.rs"]
        and all(hashlib.sha256((DESTINATION / path).read_bytes()).hexdigest() == digest
                for path, digest in {
                    "src/vm/interpret.rs": "5e867280ff79c12f4c79bce01ff1a677c50f2a842ebf4c6a04256c562321e05b",
                    "src/dex/insn.rs": PATCHED_DECODER_SHA256,
                    "src/vm/native/java/util/mod.rs": PATCHED_COLLECTIONS_SHA256,
                    "src/vm/native/kotlin/collections.rs": PATCHED_JOIN_SHA256,
                }.items())
        and not git(DESTINATION, "ls-files", "--others", "--exclude-standard").strip()
    )
    if legacy or legacy_44:
        backup = Path(tempfile.mkdtemp(prefix="manga-legacy-interpreter-", dir=DESTINATION.parent)) / "source"
        DESTINATION.rename(backup)
        print(f"Preserved the known previous generated interpreter at {backup}")
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
