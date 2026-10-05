#!/usr/bin/env bash
set -euo pipefail

device_family="${1:-iphone}"
if [[ "$device_family" != iphone && "$device_family" != ipad ]]; then
  echo "Expected iphone or ipad"
  exit 2
fi
result_path="build/SimulatorTests.xcresult"
screenshot_path="build/screenshots"
test_class="AppSmokeTests"
if [[ "$device_family" == ipad ]]; then
  result_path="build/IPadTests.xcresult"
  screenshot_path="build/ipad-screenshots"
  test_class="IPadLayoutTests"
fi

# Preserve reviewable screenshots even when an assertion fails.
export_attachments() {
  if [ -d "$result_path" ]; then
    xcrun xcresulttool export attachments --path "$result_path" \
      --output-path "$screenshot_path" || true
  fi
}
trap export_attachments EXIT

simulator_id="$(xcrun simctl list devices available --json | python3 -c '
import json,sys
devices=json.load(sys.stdin)["devices"]
family=sys.argv[1]
candidates=[d for runtime,items in devices.items() if "iOS-26" in runtime
        for d in items if d.get("isAvailable") and
        (d["name"].startswith("iPhone") if family == "iphone" else
         d["name"].startswith("iPad Pro") and ("11-inch" in d["name"] or "11 inch" in d["name"]))]
if not candidates:
    raise SystemExit("No available " + family + " simulator (iPad must be an 11-inch Pro)")
print("Testing " + candidates[0]["name"], file=sys.stderr)
print(candidates[0]["udid"])
' "$device_family")"

# Bring the iOS 26 device to a ready state before XCTest starts its runner.
# Bound this separately so a stalled simulator reports a clear startup failure.
xcrun simctl boot "$simulator_id" 2>/dev/null || true
python3 - "$simulator_id" <<'PY'
import subprocess,sys
try:
    completed=subprocess.run(['xcrun','simctl','bootstatus',sys.argv[1],'-b'],timeout=180)
    raise SystemExit(completed.returncode)
except subprocess.TimeoutExpired:
    raise SystemExit('Simulator startup exceeded 180 seconds; rerun on a fresh runner.')
PY

xcodebuild test -project AnimeCompanion.xcodeproj -scheme AnimeCompanion \
  -configuration Debug -destination "platform=iOS Simulator,id=$simulator_id" \
  -derivedDataPath build/Simulator -resultBundlePath "$result_path" \
  -only-testing:"AnimeCompanionUITests/$test_class" \
  -only-testing:AnimeCompanionUITests/DiscoveryNavigationTests \
  -only-testing:AnimeCompanionUITests/ExploreUpgradeTests \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-
