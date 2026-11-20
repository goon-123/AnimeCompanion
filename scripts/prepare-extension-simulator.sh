#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/prepare-anymex.py
cd Tools/ExtensionBridge
if [[ ! -d .ios ]]; then
  flutter create --template=module --project-name=companion_extensions --org=com.animecompanion --no-pub .
fi
flutter pub get
flutter precache --ios
simulator_sdk="$(xcrun --sdk iphonesimulator --show-sdk-path)"
simulator_arch="$(uname -m)"
# The Release ios-framework command's simulator slice has no JIT snapshots.
# Assemble the same Dart sources in Debug for the actual simulator smoke test.
flutter assemble -dTargetPlatform=ios -dTargetFile=lib/main.dart \
  -dBuildMode=debug -dIosArchs="$simulator_arch" -dSdkRoot="$simulator_sdk" \
  -dDartObfuscation=false -dTrackWidgetCreation=true \
  --output=../../build/ExtensionSimulatorBundle debug_ios_bundle_flutter_assets
cd ../..
python3 - <<'PY'
import importlib.util,json,pathlib,plistlib,shutil,subprocess
root=pathlib.Path.cwd()
release=root/'build/AnymeXFrameworks/Release'
simulator_app=root/'build/ExtensionSimulatorBundle/App.framework'
if not (simulator_app/'flutter_assets/kernel_blob.bin').is_file():
    raise SystemExit('The simulator Dart snapshot was not produced.')
spec=importlib.util.spec_from_file_location('checks',root/'scripts/check-anymex-bundle.py')
checks=importlib.util.module_from_spec(spec);spec.loader.exec_module(checks)
names=checks.native_frameworks(json.loads((simulator_app/'flutter_assets/NativeAssetsManifest.json').read_text()))
for name in sorted(names|{'App'}):
    xcframework=release/(name+'.xcframework')
    info=plistlib.loads((xcframework/'Info.plist').read_bytes())
    device=next(e for e in info['AvailableLibraries'] if e['SupportedPlatform']=='ios' and e.get('SupportedPlatformVariant') is None)
    original=xcframework/device['LibraryIdentifier']/device['LibraryPath']
    preserved=root/'build/ExtensionSimulatorDevice'/original.name
    shutil.copytree(original,preserved,dirs_exist_ok=True)
    simulator=simulator_app if name=='App' else root/'Tools/ExtensionBridge/build/native_assets/ios'/(name+'.framework')
    if not simulator.is_dir():raise SystemExit('Missing simulator framework: '+name)
    shutil.rmtree(xcframework)
    subprocess.run(['xcrun','xcodebuild','-create-xcframework','-framework',str(preserved),'-framework',str(simulator),'-output',str(xcframework)],check=True)
PY
python3 scripts/anymex-xcode.py
