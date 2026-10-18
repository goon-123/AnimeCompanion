#!/usr/bin/env python3
"""Bundle the interpreter's resolved dependency notices with the iOS app."""
import json
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[1]
metadata = json.loads(subprocess.check_output(["cargo", "+1.99.1", "metadata", "--locked", "--manifest-path", str(root / "Tools/MangaRuntime/Cargo.toml"), "--format-version", "1"]))
parts = [(root / "Tools/MangaRuntime/NOTICE.txt").read_text()]
for package in sorted(metadata["packages"], key=lambda item: (item["name"], item["version"])):
    directory = Path(package["manifest_path"]).parent
    files = sorted(set(directory.glob("LICENSE*")) | set(directory.glob("COPYING*")) | set(directory.glob("NOTICE*")))
    if package.get("license_file"):
        files.append(directory / package["license_file"])
    parts.append(f'\n\n{package["name"]} {package["version"]}\nLicense: {package.get("license") or "see notices"}\n{package.get("repository") or ""}\n')
    for file in files:
        if file.is_file(): parts.append(file.read_text(errors="replace"))
(root / "App/MangaRuntimeLicenses.txt").write_text("\n".join(parts))

