#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/prepare-anymex.py
command -v flutter >/dev/null || { echo 'Install Flutter 3.38.5 to build the extension module.' >&2; exit 1; }
cd Tools/ExtensionBridge
if [[ ! -d .ios ]]; then
  flutter create --template=module --project-name=companion_extensions --org=com.animecompanion --no-pub .
fi
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
if [[ "${1:-}" == '--check' ]]; then exit 0; fi
[[ "$(uname -s)" == 'Darwin' ]] || { echo 'iOS frameworks require macOS and Xcode.' >&2; exit 1; }
python3 - <<'PY'
import pathlib
import plistlib
import re

ios = pathlib.Path('.ios')
# Flutter's generated module defaults to iOS 13. Match the native host's
# minimum instead, including the CocoaPods host used to build plugins.
podfile = ios / 'Podfile'
value, count = re.subn(r"(?m)^#?\s*platform :ios, '[\d.]+'", "platform :ios, '17.0'", podfile.read_text())
if count != 1:
    raise SystemExit('Could not configure the generated iOS platform.')
podfile.write_text(value)
project = ios / 'Runner.xcodeproj/project.pbxproj'
value, count = re.subn(r'IPHONEOS_DEPLOYMENT_TARGET = [\d.]+;', 'IPHONEOS_DEPLOYMENT_TARGET = 17.0;', project.read_text())
if count == 0:
    raise SystemExit('Could not configure the generated iOS deployment target.')
project.write_text(value)
info = ios / 'Flutter/AppFrameworkInfo.plist'
properties = plistlib.loads(info.read_bytes())
properties['MinimumOSVersion'] = '17.0'
info.write_bytes(plistlib.dumps(properties))
PY
# Resolve native dependencies before the more expensive Dart AOT compilation.
(cd .ios && pod install)
flutter build ios-framework --no-debug --no-profile --output=../../build/AnymeXFrameworks
cd ../..
ditto build/AnymeXBridge/ios/anymex_extension_bridge/Frameworks/OpenJDKRuntime.xcframework \
  build/AnymeXFrameworks/Release/OpenJDKRuntime.xcframework
ditto build/AnymeXBridge/ios/anymex_extension_bridge/Sources/anymex_embedded_jvm/Runtime \
  build/AnymeXFrameworks/Runtime
python3 scripts/anymex-xcode.py
