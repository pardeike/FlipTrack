#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
mkdir -p .build/logs
LOG="$ROOT/.build/logs/check.log"
STEP="Swift tests"
trap 'code=$?; printf "%s failed\n" "$STEP" >&2; tail -n 25 "$LOG" >&2; printf "Full log: %s\n" "$LOG" >&2; exit "$code"' ERR
swift test > "$LOG" 2>&1
STEP="iOS build"
xcodebuild -project FlipTrack.xcodeproj -scheme FlipTrack -configuration Debug -destination generic/platform=iOS -derivedDataPath .build/live-ios -allowProvisioningUpdates build >> "$LOG" 2>&1
printf 'ok\n'
