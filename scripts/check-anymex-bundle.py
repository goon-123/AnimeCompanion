#!/usr/bin/env python3
"""Fail releases when a Dart native asset is missing or has the wrong platform."""
import json
import pathlib
import plistlib
import struct
import sys


def native_frameworks(manifest):
    result = set()
    for assets in manifest.get('native-assets', {}).values():
        for location in assets.values():
            if location[0] == 'absolute':
                parts = pathlib.PurePosixPath(location[1]).parts
                if len(parts) != 2 or not parts[0].endswith('.framework') or parts[1] != parts[0][:-10]:
                    raise ValueError('Unexpected native asset framework path')
                result.add(parts[0][:-10])
    return result


def platforms(data):
    magic = data[:4]
    if magic == b'\xca\xfe\xba\xbe':
        count = struct.unpack_from('>I', data, 4)[0]
        result = set()
        for i in range(count):
            _, _, offset, size, _ = struct.unpack_from('>IIIII', data, 8 + i * 20)
            result.update(platforms(data[offset:offset + size]))
        return result
    if magic != b'\xcf\xfa\xed\xfe':
        raise ValueError('Expected a 64-bit Mach-O dynamic library')
    _, _, _, filetype, count, _, _, _ = struct.unpack_from('<8I', data)
    if filetype != 6:
        raise ValueError('Native asset is not a dynamic library')
    result = set()
    cursor = 32
    for _ in range(count):
        command, size = struct.unpack_from('<II', data, cursor)
        if command == 0x32:
            result.add(struct.unpack_from('<I', data, cursor + 8)[0])
        cursor += size
    if not result:
        raise ValueError('Native asset has no Apple platform metadata')
    return result


def check_bundle(app, simulator=False):
    manifest_path = app / 'Frameworks/App.framework/flutter_assets/NativeAssetsManifest.json'
    names = native_frameworks(json.loads(manifest_path.read_text()))
    if not names:
        raise ValueError('No Dart native assets were declared')
    for name in names:
        framework = app / 'Frameworks' / (name + '.framework')
        binary = framework / name
        if not binary.is_file():
            raise ValueError(f'Missing Dart native asset: {name}.framework')
        expected = 7 if simulator else 2
        if platforms(binary.read_bytes()) != {expected}:
            raise ValueError(f'Wrong platform in native asset: {name}.framework')
    for name in ['Flutter', 'FlutterPluginRegistrant', 'anymex_extension_runtime_bridge', 'OpenJDKRuntime']:
        if not (app / f'Frameworks/{name}.framework/{name}').is_file():
            raise ValueError(f'Missing extension framework: {name}')
    if not (app / 'Runtime/embedded-bridge.jar').is_file():
        raise ValueError('Missing embedded runtime resources')
    print(f'Verified {len(names)} Dart native assets and the extension runtime.')


if __name__ == '__main__':
    check_bundle(pathlib.Path(sys.argv[1]), '--simulator' in sys.argv[2:])
