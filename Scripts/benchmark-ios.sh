#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
MODE="${1:-build}"
DEVICE="${2:-AP11}"
LOG="$ROOT_DIR/.build/logs/benchmark-$MODE.log"
mkdir -p "$(dirname "$LOG")"
STEP="$MODE"
trap 'printf "%s failed\n" "$STEP" >&2; tail -n 20 "$LOG" >&2; printf "Full log: %s\n" "$LOG" >&2' ERR
case "$MODE" in
  build|install)
    STEP=verify-inputs
    python3 Scripts/verify-recognition-inputs.py > "$LOG" 2>&1
    STEP=generate
    xcodegen generate --spec Benchmark/project.yml >> "$LOG" 2>&1
    STEP=build
    xcodebuild -project Benchmark/FlipTrackBenchmark.xcodeproj -scheme FlipTrackBenchmark \
      -configuration Release -destination generic/platform=iOS \
      -derivedDataPath .build/benchmark -allowProvisioningUpdates build >> "$LOG" 2>&1
    STEP=verify-signature
    codesign --verify --deep --strict .build/benchmark/Build/Products/Release-iphoneos/FlipTrackBenchmark.app >> "$LOG" 2>&1
    if [[ "$MODE" == install ]]; then
      STEP=install
      xcrun devicectl device install app --device "$DEVICE" --timeout 1200 \
        .build/benchmark/Build/Products/Release-iphoneos/FlipTrackBenchmark.app >> "$LOG" 2>&1
    fi
    ;;
  smoke|full)
    xcrun devicectl device process launch --device "$DEVICE" --terminate-existing \
      net.pardeike.FlipTrackBenchmark "--$MODE" > "$LOG" 2>&1
    ;;
  results|verify)
    mkdir -p .build/benchmark-results
    xcrun devicectl device copy from --device "$DEVICE" --domain-type appDataContainer \
      --domain-identifier net.pardeike.FlipTrackBenchmark --source Documents \
      --destination .build/benchmark-results > "$LOG" 2>&1
    if [[ "$MODE" == verify ]]; then
      STEP=verify-results
      python3 Scripts/verify-benchmark.py >> "$LOG" 2>&1
    fi
    ;;
  *) printf 'Usage: %s build|install|smoke|full|results|verify [device]\n' "$0" >&2; exit 2 ;;
esac
printf 'ok\n'
