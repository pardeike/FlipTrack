#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
mkdir -p .build/logs
LOG="$ROOT/.build/logs/check.log"
STEP="Swift tests"
trap 'code=$?; printf "%s failed\n" "$STEP" >&2; tail -n 25 "$LOG" >&2; printf "Full log: %s\n" "$LOG" >&2; exit "$code"' ERR
: > "$LOG"
if [[ "${1:-}" == "--recording" ]]; then
    STEP="prepare recording fixtures"
    python3 Scripts/prepare-live-fixtures.py >> "$LOG" 2>&1
    export FLIPTRACK_LIVE_FIXTURES="$ROOT/.build/live-fixtures/manifest.json"
    export FLIPTRACK_FINAL_FIXTURES="$ROOT/.build/live-fixtures/finals.json"
    export FLIPTRACK_TURN_SEQUENCE="$ROOT/.build/live-fixtures/switch.json"
fi
STEP="Swift tests"
swift test >> "$LOG" 2>&1
STEP="iOS build"
xcodebuild -project FlipTrack.xcodeproj -scheme FlipTrack -configuration Debug -destination generic/platform=iOS -derivedDataPath .build/live-ios -allowProvisioningUpdates build >> "$LOG" 2>&1
printf 'ok\n'
