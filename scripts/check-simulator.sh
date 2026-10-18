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
test_scope="${2:-full}"
if [[ "$test_scope" != full && "$test_scope" != focused && "$test_scope" != weekly && "$test_scope" != fixes && "$test_scope" != streams && "$test_scope" != layout ]]; then
  echo "Expected full, focused, weekly, fixes, streams or layout test scope"
  exit 2
fi
if [[ "$device_family" == ipad ]]; then
  result_path="build/IPadTests.xcresult"
  screenshot_path="build/ipad-screenshots"
  test_class="IPadLayoutTests"
fi
if [[ "$test_scope" == focused ]]; then
  result_path="build/Focused-${device_family}.xcresult"
  screenshot_path="build/focused-${device_family}-screenshots"
fi
if [[ "$test_scope" == weekly ]]; then
  result_path="build/Weekly-${device_family}.xcresult"
  screenshot_path="build/weekly-${device_family}-screenshots"
fi
if [[ "$test_scope" == fixes || "$test_scope" == streams || "$test_scope" == layout ]]; then
  result_path="build/Fixes-${device_family}.xcresult"
  screenshot_path="build/fixes-${device_family}-screenshots"
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

simulator_id="$(xcrun simctl list devices available --json | python3 -c '
import json,sys
devices=json.load(sys.stdin)["devices"]
family=sys.argv[1]
candidates=[(runtime,d) for runtime,items in devices.items() if "iOS-18" in runtime or "iOS-26" in runtime
        for d in items if d.get("isAvailable") and
        (d["name"].startswith("iPhone") if family == "iphone" else
         d["name"].startswith("iPad Pro") and ("11-inch" in d["name"] or "11 inch" in d["name"]))]
if not candidates:
    raise SystemExit("No available " + family + " simulator (iPad must be an 11-inch Pro)")
# The hosted iOS 26 runtime has repeatedly stalled before app launch. Exercise
# the supported iOS 18 runtime when present; builds still use the iOS 26 SDK.
candidates.sort(key=lambda item: (0 if "iOS-18" in item[0] else 1, item[0], item[1]["name"]))
runtime,device=candidates[0]
print("Testing " + device["name"] + " with " + runtime, file=sys.stderr)
print(device["udid"])
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

# iOS 18.5 can omit WebKit's Swift overlay from dyld's default search path
# (WebKit bug 293831). Resolve the library from this exact simulator runtime,
# and expose it only in the disposable simulator build-products directory.
simulator_runtime_root="$(python3 - "$simulator_id" <<'PY'
import json, pathlib, subprocess, sys
devices=json.loads(subprocess.check_output(['xcrun','simctl','list','devices','available','--json']))['devices']
runtime_id=next(key for key,items in devices.items() if any(d['udid']==sys.argv[1] for d in items))
runtimes=json.loads(subprocess.check_output(['xcrun','simctl','list','runtimes','--json']))['runtimes']
runtime=next(r for r in runtimes if r['identifier']==runtime_id)
print(pathlib.Path(runtime['bundlePath'])/'Contents/Resources/RuntimeRoot')
PY
)"
simulator_products="build/Simulator/Build/Products/Debug-iphonesimulator"
for simulator_swift_library in \
  "$simulator_runtime_root/System/Cryptexes/OS/usr/lib/swift/libswiftWebKit.dylib" \
  "$simulator_runtime_root/usr/lib/swift/libswiftWebKit.dylib"; do
  if [[ -f "$simulator_swift_library" ]]; then
    mkdir -p "$simulator_products"
    ln -sf "$simulator_swift_library" "$simulator_products/libswiftWebKit.dylib"
    echo "Using the selected simulator runtime's WebKit Swift library."
    break
  fi
done

# Leave simulator services running normally. Suspending system services can
# interfere with browser navigation, account UI, and XCTest app launch.

# Permit one retry for a cold hosted simulator's first-launch timeout.
# Both attempts stay in xcresult; repeated failures still fail the job.
test_arguments=(-only-testing:AnimeCompanionUITests/WeeklyScheduleUITests)
if [[ "$test_scope" != weekly ]]; then
test_arguments=(-only-testing:AnimeCompanionUITests/ImmersivePlaybackTests
  -only-testing:AnimeCompanionUITests/MetadataTrackingUITests
  -only-testing:AnimeCompanionUITests/AiringProgressUITests
  -only-testing:AnimeCompanionUITests/PolishedDesignUITests
  -only-testing:AnimeCompanionUITests/WeeklyScheduleUITests
  -only-testing:AnimeCompanionUITests/ExplorePresentationUITests)
test_arguments+=(-only-testing:AnimeCompanionUITests/PhaseOneReliabilityUITests)
test_arguments+=(-only-testing:AnimeCompanionUITests/SourceAudioUITests)
test_arguments+=(-only-testing:AnimeCompanionUITests/PhaseTwoNavigationUITests)
test_arguments+=(-only-testing:AnimeCompanionUITests/PhaseThreePerformanceUITests)
test_arguments+=(-only-testing:AnimeCompanionUITests/ExploreAndAddonUITests)
test_arguments+=(-only-testing:AnimeCompanionUITests/AddonDirectoryUITests)
test_arguments+=(-only-testing:AnimeCompanionUITests/SeanimeTorBoxUITests)
test_arguments+=(-only-testing:AnimeCompanionUITests/StreamPickerUITests)
test_arguments+=(-only-testing:AnimeCompanionUITests/TabletPresentationUITests)
fi
if [[ "$test_scope" == full ]]; then
  test_arguments+=("-only-testing:AnimeCompanionUITests/$test_class"
    -only-testing:AnimeCompanionUITests/DiscoveryNavigationTests
    -only-testing:AnimeCompanionUITests/ExploreUpgradeTests
    -only-testing:AnimeCompanionUITests/PlaybackUITests)
fi
if [[ "$test_scope" == fixes ]]; then
  test_arguments=(
    -only-testing:AnimeCompanionUITests/ExploreAndAddonUITests/testLargeTwoColumnPostersAutomaticallyLoadMoreAfterScrollingStops
    -only-testing:AnimeCompanionUITests/ExploreAndAddonUITests/testListAutomaticallyLoadsMoreAfterScrollingStops
    -only-testing:AnimeCompanionUITests/PhaseOneReliabilityUITests/testPartialFilteredScanExplainsCoverageAndCanContinueToCatalogEnd
    -only-testing:AnimeCompanionUITests/SeanimeTorBoxUITests/testHTTP400CacheMissExplainsTheCauseAndCanBeRetriedWithUserApproval
    -only-testing:AnimeCompanionUITests/SeanimeTorBoxUITests/testOnDeviceTypeScriptSearchAndExactTorBoxFileHandoff
    -only-testing:AnimeCompanionUITests/SeanimeTorBoxUITests/testWatchCombinesStreamingTorrentSearchAndInlineFileHandoff
    -only-testing:AnimeCompanionUITests/SeanimeTorBoxUITests/testQueuedReceiptCanRefreshToFilesWithoutAnotherAdd
    -only-testing:AnimeCompanionUITests/SeanimeTorBoxUITests/testAcceptedTorrentSurvivesUnreadableFileResponseAndRefreshesWithoutResubmitting
    -only-testing:AnimeCompanionUITests/SeanimeTorBoxUITests/testAlreadyAddedReleaseOpensFilesWithoutAnAccountAdd
  )
fi
if [[ "$test_scope" == streams ]]; then
  # Focus on the clean picker, shared audio filters, and the actual inline
  # uncached download/status/file handoff. Settings/WebDAV cases remain in the
  # broader fixes/focused/full scopes retain all previous regression cases.
  test_arguments=(
    -only-testing:AnimeCompanionUITests/StreamPickerUITests
  )
fi
if [[ "$test_scope" == layout ]]; then
  test_arguments=(
    -only-testing:AnimeCompanionUITests/TabletPresentationUITests
    -only-testing:AnimeCompanionUITests/PhaseTwoNavigationUITests/testBrowseDetailRotationRetainsQueryResultsAndGenreNavigation
  )
fi
run_tests() {
xcodebuild test -project AnimeCompanion.xcodeproj -scheme AnimeCompanion \
  -configuration Debug -destination "platform=iOS Simulator,id=$simulator_id" \
  -derivedDataPath build/Simulator -resultBundlePath "$result_path" \
  "${test_arguments[@]}" \
  -retry-tests-on-failure -test-iterations 2 \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-
}
if [[ "$test_scope" == fixes || "$test_scope" == streams || "$test_scope" == layout ]]; then
  # XCTest can otherwise spend the whole job waiting for a process that aborted
  # before its first screen. Keep the actual crash, rather than masking a timeout.
  run_tests &
  native_test_pid=$!
  python3 scripts/watch-simulator-crash.py "$native_test_pid" "$simulator_id" "build/fixes-${device_family}-diagnostics" &
  background_watcher_pid=$!
  wait "$native_test_pid"
else
  run_tests
fi
