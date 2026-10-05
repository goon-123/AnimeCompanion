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

# Bound the workaround to this disposable test runner and resume paused services.
background_watcher_pid=""
# Preserve reviewable screenshots even when an assertion fails.
export_attachments() {
  if [ -n "$background_watcher_pid" ]; then
    kill -TERM "$background_watcher_pid" 2>/dev/null || true
    wait "$background_watcher_pid" || true
  fi
  if [ -d "$result_path" ]; then
    xcrun xcresulttool export attachments --path "$result_path" \
      --output-path "$screenshot_path" || true
  fi
}
trap export_attachments EXIT

# iOS 26 wallpaper/APNS background loops can monopolize hosted VM CPUs.
# The watcher checks executable runtime paths and never targets the app or XCTest.
python3 scripts/simulator-background.py &
background_watcher_pid="$!"

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
python3 - "$simulator_id" <<'PY'
import subprocess,sys
try:
    print('Starting simulator and waiting for readiness...',flush=True)
    # An already booted device returns a nonzero code here; bootstatus below
    # remains the authoritative readiness check.
    subprocess.run(['xcrun','simctl','boot',sys.argv[1]],timeout=120)
    completed=subprocess.run(['xcrun','simctl','bootstatus',sys.argv[1],'-b'],timeout=240)
    raise SystemExit(completed.returncode)
except subprocess.TimeoutExpired:
    raise SystemExit('Simulator startup timed out; rerun on a fresh runner.')
PY

# Permit one retry for a cold hosted simulator's first-launch timeout.
# Both attempts stay in xcresult; repeated failures still fail the job.
xcodebuild test -project AnimeCompanion.xcodeproj -scheme AnimeCompanion \
  -configuration Debug -destination "platform=iOS Simulator,id=$simulator_id" \
  -derivedDataPath build/Simulator -resultBundlePath "$result_path" \
  -only-testing:"AnimeCompanionUITests/$test_class" \
  -only-testing:AnimeCompanionUITests/DiscoveryNavigationTests \
  -only-testing:AnimeCompanionUITests/ExploreUpgradeTests \
  -retry-tests-on-failure -test-iterations 2 \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-
