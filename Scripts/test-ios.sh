#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
DEVICE="${1:-00008030-000A64D41104802E}"
TEST_ARGS=()
if [[ -n "${2:-}" ]]; then TEST_ARGS+=("-only-testing:$2"); fi
mkdir -p .build/logs
LOG="$ROOT/.build/logs/test-ios.log"
RESULT="$ROOT/.build/device-tests-$(date +%Y%m%d-%H%M%S).xcresult"
STEP="generate device checks"
trap 'code=$?; printf "%s failed\n" "$STEP" >&2; tail -n 30 "$LOG" >&2; printf "Full log: %s\n" "$LOG" >&2; exit "$code"' ERR
python3 Scripts/prepare-live-fixtures.py > "$LOG" 2>&1
xcodegen generate --spec DeviceTests/project.yml --project .build >> "$LOG" 2>&1
STEP="AP11 recovery tests"
xcodebuild -project .build/FlipTrackDeviceTests.xcodeproj -scheme FlipTrackDeviceHost -destination "id=$DEVICE" -derivedDataPath .build/device-tests -resultBundlePath "$RESULT" -allowProvisioningUpdates test "${TEST_ARGS[@]}" >> "$LOG" 2>&1
printf '%s\n' "$RESULT" > .build/last-device-test-result
printf 'ok\n'
