#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
command -v xcodebuild >/dev/null || { echo 'This build requires macOS with Xcode.'; exit 1; }
command -v xcodegen >/dev/null || { echo 'Install XcodeGen first: brew install xcodegen'; exit 1; }
swift test -j 2
xcodegen generate
xcodebuild -project AnimeCompanion.xcodeproj -scheme AnimeCompanion -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
mkdir -p Payload
cp -R build/Build/Products/Release-iphoneos/AnimeCompanion.app Payload/
ditto -c -k --sequesterRsrc --keepParent Payload AnimeCompanion-unsigned.ipa
echo 'Created AnimeCompanion-unsigned.ipa. It must be signed before installation.'
