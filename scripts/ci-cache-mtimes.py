#!/usr/bin/env python3
"""Preserve input mtimes only when the input's content is unchanged.

Xcode records nanosecond timestamps in DerivedData. A fresh checkout otherwise
invalidates that cache. This manifest contains no source contents or credentials.
Changed/new/deleted files retain their current timestamps and rebuild normally.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path


def fingerprint(path):
    if path.is_dir():
        return hashlib.sha256("\0".join(sorted(p.name for p in path.iterdir())).encode()).hexdigest()
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def inputs(root, roots):
    for name in roots:
        path = root / name
        if path.is_symlink() or not path.exists():
            continue
        yield path
        if path.is_dir():
            for directory, directories, files in os.walk(path, followlinks=False):
                directories[:] = sorted(d for d in directories if d != ".git" and not (Path(directory) / d).is_symlink())
                for child in directories + sorted(files):
                    entry = Path(directory) / child
                    if not entry.is_symlink():
                        yield entry


def snapshot(root, roots):
    return {
        str(path.relative_to(root)): {"sha256": fingerprint(path), "mtime_ns": path.stat().st_mtime_ns}
        for path in inputs(root, roots)
    }


def restore(root, roots, saved):
    count = 0
    # Enumerate current allowed inputs instead of trusting paths in cached JSON.
    for path in inputs(root, roots):
        previous = saved.get(str(path.relative_to(root)), {})
        if previous.get("sha256") == fingerprint(path):
            timestamp = previous.get("mtime_ns")
            if isinstance(timestamp, int) and timestamp >= 0:
                os.utime(path, ns=(path.stat().st_atime_ns, timestamp))
                count += 1
    return count


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=["save", "restore"])
    parser.add_argument("manifest", type=Path)
    parser.add_argument("roots", nargs="+")
    args = parser.parse_args()
    root = Path.cwd().resolve()
    for name in args.roots:
        path = Path(name)
        if path.is_absolute() or ".." in path.parts or not (root / path).resolve().is_relative_to(root):
            parser.error("Input roots must stay inside the checkout")
    if args.operation == "save":
        data = snapshot(root, args.roots)
        args.manifest.parent.mkdir(parents=True, exist_ok=True)
        args.manifest.write_text(json.dumps(data, sort_keys=True) + "\n")
        print(f"Recorded {len(data)} build input timestamps")
    elif args.manifest.exists():
        try:
            data = json.loads(args.manifest.read_text())
            if not isinstance(data, dict):
                raise ValueError("Expected an object")
            count = restore(root, args.roots, data)
            print(f"Restored {count} content-matching input timestamps")
        except (ValueError, TypeError, AttributeError) as error:
            print(f"Ignoring invalid timestamp cache; inputs will rebuild: {error}")
    else:
        print("No input timestamp cache; performing a normal build")


if __name__ == "__main__":
    main()
