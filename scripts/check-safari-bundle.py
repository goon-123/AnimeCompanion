#!/usr/bin/env python3
"""Verify Safari resources and, after a build, the actual embedded .appex."""
import json
import pathlib
import plistlib
import re
import sys

repo = pathlib.Path(__file__).resolve().parent.parent
root = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else repo / "SafariExtension" / "Resources"
app = root if root.suffix == ".app" else None
if app:
    extensions = list((app / "PlugIns").glob("*.appex"))
    assert len(extensions) == 1, "The IPA must contain the Safari extension"
    root = extensions[0]
    app_info = plistlib.loads((app / "Info.plist").read_bytes())
    info = plistlib.loads((root / "Info.plist").read_bytes())
    assert info["CFBundleIdentifier"].startswith(app_info["CFBundleIdentifier"] + ".")
    assert info["CFBundleVersion"] == app_info["CFBundleVersion"]
    assert info["CFBundleShortVersionString"] == app_info["CFBundleShortVersionString"]
    assert info["NSExtension"]["NSExtensionPointIdentifier"] == "com.apple.Safari.web-extension"
    assert (root / info["CFBundleExecutable"]).is_file(), "Extension executable is missing"
manifest = json.loads((root / "manifest.json").read_text())
assert manifest["manifest_version"] == 3
assert manifest["background"]["persistent"] is False
assert "webRequest" not in manifest["permissions"], "webRequest is unavailable in iOS Safari"
assert "cookies" not in manifest["permissions"]
assert set(manifest["host_permissions"]) == {"http://*/*", "https://*/*"}
files = set(manifest["background"]["scripts"])
files.add(manifest["action"]["default_popup"])
files.update(manifest["icons"].values())
files.update(manifest["action"]["default_icon"].values())
for content in manifest["content_scripts"]:
    assert content["all_frames"] is True
    files.update(content["js"])
files.update(["popup.js", "popup.css"])
for name in files:
    assert (root / name).is_file(), f"Missing bundled Safari resource: {name}"
if app:
    assert manifest["version"] == app_info["CFBundleShortVersionString"]
else:
    version = re.search(r"^\s+MARKETING_VERSION:\s*['\"]?([0-9]+(?:\.[0-9]+){1,3})['\"]?\s*$",
                        (repo / "project.yml").read_text(), re.MULTILINE)
    assert version is not None, "App marketing version is missing"
    assert manifest["version"] == version.group(1), "Safari and app versions must match"
print(f"Safari extension verified: {len(files)} resources" + (" inside the app" if app else ""))
