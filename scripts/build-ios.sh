#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
command -v xcodebuild >/dev/null || { echo 'This build requires macOS with Xcode.'; exit 1; }
command -v xcodegen >/dev/null || { echo 'Install XcodeGen first: brew install xcodegen'; exit 1; }
command -v npm >/dev/null || { echo 'Install Node.js 22 or newer to build the bundled provider runtime.'; exit 1; }
npm --prefix Tools/SeanimeRuntime ci --ignore-scripts --no-audit --no-fund
npm --prefix Tools/SeanimeRuntime run build
npm --prefix Tools/SeanimeRuntime test
npm --prefix Tools/SafariExtension test
python3 scripts/check-safari-bundle.py
swift test -j 2
xcodegen generate
xcodebuild -project AnimeCompanion.xcodeproj -scheme AnimeCompanion -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
python3 scripts/check-safari-bundle.py build/Build/Products/Release-iphoneos/AnimeCompanion.app
mkdir -p Payload
cp -R build/Build/Products/Release-iphoneos/AnimeCompanion.app Payload/
ditto -c -k --sequesterRsrc --keepParent Payload AnimeCompanion-unsigned.ipa
echo 'Created AnimeCompanion-unsigned.ipa. It must be signed before installation.'
