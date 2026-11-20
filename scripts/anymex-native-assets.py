#!/usr/bin/env python3
"""Package Dart native assets as device + simulator XCFrameworks."""
import pathlib
import shutil
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[1]
MODULE = ROOT / 'Tools/ExtensionBridge'
RELEASE = ROOT / 'build/AnymeXFrameworks/Release'
STAGING = ROOT / 'build/AnymeXNativeAssets'


def main():
    # ios-framework leaves the final (simulator) native-assets pass as loose
    # frameworks. Preserve it before assembling the physical-device pass.
    native = sorted(RELEASE.glob('*.framework'))
    if not native:
        raise SystemExit('Flutter produced no native asset frameworks.')
    for framework in native:
        destination = STAGING / 'simulator' / framework.name
        shutil.copytree(framework, destination, dirs_exist_ok=True)
    sdk = subprocess.check_output(['xcrun', '--sdk', 'iphoneos', '--show-sdk-path'], text=True).strip()
    subprocess.run([
        'flutter', 'assemble', '--no-pub',
        '-dTargetPlatform=ios', '-dTargetFile=lib/main.dart',
        '-dBuildMode=release', '-dIosArchs=arm64', f'-dSdkRoot={sdk}',
        '-dTreeShakeIcons=true', '-dDartObfuscation=false', '-dTrackWidgetCreation=true',
        f'--output={STAGING / "device-app"}',
        'release_ios_bundle_flutter_assets',
    ], cwd=MODULE, check=True)
    device = MODULE / 'build/native_assets/ios'
    for framework in native:
        physical = device / framework.name
        simulator = STAGING / 'simulator' / framework.name
        if not physical.is_dir():
            raise SystemExit(f'Missing device native asset: {framework.name}')
        output = RELEASE / (framework.stem + '.xcframework')
        if output.exists():
            shutil.rmtree(output)
        subprocess.run(['xcrun', 'xcodebuild', '-create-xcframework',
                        '-framework', str(physical), '-framework', str(simulator),
                        '-output', str(output)], check=True)
    print(f'Packaged {len(native)} native asset frameworks for device and simulator.')


if __name__ == '__main__':
    main()
