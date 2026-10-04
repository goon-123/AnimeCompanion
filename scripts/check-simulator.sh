#!/usr/bin/env bash
set -euo pipefail

simulator_id="$(xcrun simctl list devices available --json | python3 -c '
import json,sys
devices=json.load(sys.stdin)["devices"]
phones=[d for runtime,items in devices.items() if "iOS" in runtime
        for d in items if d.get("isAvailable") and d["name"].startswith("iPhone")]
if not phones:
    raise SystemExit("No available iPhone simulator on this runner")
print(phones[0]["udid"])
')"

xcodebuild test -project AnimeCompanion.xcodeproj -scheme AnimeCompanion \
  -configuration Debug -destination "platform=iOS Simulator,id=$simulator_id" \
  -derivedDataPath build/Simulator -resultBundlePath build/SimulatorTests.xcresult \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO

xcrun xcresulttool export attachments --path build/SimulatorTests.xcresult \
  --output-path build/screenshots
