#!/usr/bin/env python3
"""Generate an XcodeGen include from the actual Flutter framework output."""
import pathlib
import plistlib
import json
import importlib.util

spec = importlib.util.spec_from_file_location('anymex_bundle_checks', pathlib.Path(__file__).with_name('check-anymex-bundle.py'))
checks = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checks)

ROOT = pathlib.Path(__file__).resolve().parents[1]
directory = ROOT / 'build/AnymeXFrameworks/Release'
frameworks = sorted(directory.glob('*.xcframework'))
native_assets = set()
required = {'App', 'Flutter', 'FlutterPluginRegistrant', 'anymex_extension_runtime_bridge', 'OpenJDKRuntime'}
for manifest in (directory / 'App.xcframework').glob('*/App.framework/flutter_assets/NativeAssetsManifest.json'):
    native_assets.update(checks.native_frameworks(json.loads(manifest.read_text())))
if 'objective_c' not in native_assets:
    raise SystemExit('The extension native asset manifest is missing objective_c.')
required.update(native_assets)
missing = required - {p.stem for p in frameworks}
if missing:
    raise SystemExit('Missing AnymeX frameworks: ' + ', '.join(sorted(missing)))
dependencies = []
for framework in frameworks:
    info = plistlib.loads((framework / 'Info.plist').read_bytes())
    for entry in info['AvailableLibraries']:
        if framework.stem in native_assets:
            expected = 7 if entry.get('SupportedPlatformVariant') == 'simulator' else 2
            executable = framework / entry['LibraryIdentifier'] / entry['LibraryPath'] / framework.stem
            if checks.platforms(executable.read_bytes()) != {expected}:
                raise SystemExit(f'Wrong native asset platform: {framework.name}')
    library = info['AvailableLibraries'][0]
    binary = framework / library['LibraryIdentifier'] / library['LibraryPath'] / framework.stem
    with binary.open('rb') as stream:
        magic = stream.read(8)
    static = magic.startswith(b'!<arch>')
    dependencies.append({'framework': str(framework.relative_to(ROOT)), 'embed': not static})
(ROOT / 'build/AnymeXDependencies.yml').write_text(json.dumps({'targets': {'AnimeCompanion': {'sources': [{'path': 'build/AnymeXFrameworks/Runtime', 'type': 'folder', 'buildPhase': 'resources'}], 'dependencies': dependencies}}}, indent=2) + '\n')
print(f'Linked {len(frameworks)} extension frameworks.')
