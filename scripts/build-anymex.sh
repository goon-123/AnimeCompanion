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
flutter build ios-framework --no-debug --no-profile --output=../../build/AnymeXFrameworks
cd ../..
ditto build/AnymeXBridge/ios/anymex_extension_bridge/Frameworks/OpenJDKRuntime.xcframework \
  build/AnymeXFrameworks/Release/OpenJDKRuntime.xcframework
ditto build/AnymeXBridge/ios/anymex_extension_bridge/Sources/anymex_embedded_jvm/Runtime \
  build/AnymeXFrameworks/Runtime
python3 scripts/anymex-xcode.py
