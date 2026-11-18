#!/usr/bin/env python3
"""Generate an XcodeGen include from the actual Flutter framework output."""
import pathlib
import plistlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
directory = ROOT / 'build/AnymeXFrameworks/Release'
frameworks = sorted(directory.glob('*.xcframework'))
required = {'App', 'Flutter', 'FlutterPluginRegistrant', 'anymex_extension_runtime_bridge', 'OpenJDKRuntime'}
missing = required - {p.stem for p in frameworks}
if missing:
    raise SystemExit('Missing AnymeX frameworks: ' + ', '.join(sorted(missing)))
lines = ['targets:', '  AnimeCompanion:', '    sources:',
         '      - path: build/AnymeXFrameworks/Runtime', '        type: folder',
         '        buildPhase: resources', '    dependencies:']
for framework in frameworks:
    info = plistlib.loads((framework / 'Info.plist').read_bytes())
    library = info['AvailableLibraries'][0]
    binary = framework / library['LibraryIdentifier'] / library['LibraryPath'] / framework.stem
    with binary.open('rb') as stream:
        magic = stream.read(8)
    static = magic.startswith(b'!<arch>')
    lines += [f'      - framework: {framework.relative_to(ROOT)}', f'        embed: {str(not static).lower()}']
(ROOT / 'build/AnymeXDependencies.yml').write_text('\n'.join(lines) + '\n')
print(f'Linked {len(frameworks)} extension frameworks.')
