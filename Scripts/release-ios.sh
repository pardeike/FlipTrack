#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVICE="${1:-AP11}"
LOG_DIR="$ROOT_DIR/.build/logs"
LOG="$LOG_DIR/release-ios.log"
SETTINGS="$ROOT_DIR/.build/release-settings.txt"
CATALOG="$ROOT_DIR/.build/release-catalog.json"
STEP="prepare release"

mkdir -p "$LOG_DIR"
: > "$LOG"

on_error() {
    local exit_code=$?
    trap - ERR
    printf '%s failed\n' "$STEP" >&2
    tail -n 20 "$LOG" >&2
    printf 'Full log: %s\n' "$LOG" >&2
    exit "$exit_code"
}
trap on_error ERR

STEP="read build settings"
xcodebuild -project "$ROOT_DIR/FlipTrack.xcodeproj" -scheme FlipTrack \
    -configuration Release -destination 'generic/platform=iOS' \
    -showBuildSettings > "$SETTINGS" 2>> "$LOG"
cat "$SETTINGS" >> "$LOG"

marketing_version="$(awk -F ' = ' '/ MARKETING_VERSION = / { print $2; exit }' "$SETTINGS")"
project_build="$(awk -F ' = ' '/ CURRENT_PROJECT_VERSION = / { print $2; exit }' "$SETTINGS")"
if [[ -z "$marketing_version" || ! "$project_build" =~ ^[0-9]+$ ]]; then
    printf 'Could not read a numeric build and marketing version.\n' >> "$LOG"
    false
fi

STEP="read current web version"
curl --fail --silent --show-error --location --output "$CATALOG" \
    https://www.brrai.nz/apps/apps.json 2>> "$LOG"
catalog_values="$(python3 -c '
import json, sys
entries = [entry for entry in json.load(open(sys.argv[1])) if entry["bundle_id"] == "net.pardeike.FlipTrack"]
if len(entries) != 1 or not str(entries[0]["build"]).isdigit():
    raise SystemExit("FlipTrack is missing or ambiguous in the web catalog")
print(entries[0]["version"], entries[0]["build"], sep="\t")
' "$CATALOG" 2>> "$LOG")"
IFS=$'\t' read -r live_version live_build <<< "$catalog_values"

release_build="$project_build"
if [[ "$marketing_version" == "$live_version" && "$release_build" -le "$live_build" ]]; then
    release_build="$((live_build + 1))"
fi
archive="$ROOT_DIR/.build/FlipTrack-$marketing_version-$release_build.xcarchive"

STEP="run Swift tests"
swift test >> "$LOG" 2>&1

STEP="archive signed iOS build"
xcodebuild -project "$ROOT_DIR/FlipTrack.xcodeproj" -scheme FlipTrack \
    -configuration Release -destination 'generic/platform=iOS' \
    -archivePath "$archive" CURRENT_PROJECT_VERSION="$release_build" \
    -allowProvisioningUpdates archive >> "$LOG" 2>&1

STEP="install and publish iOS build"
ios-release "$archive" --device "$DEVICE" --icon "$ROOT_DIR/Icon.png" >> "$LOG" 2>&1

printf 'ok\n'
