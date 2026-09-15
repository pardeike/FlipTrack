#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG="$ROOT_DIR/.build/logs/recognition-tests.log"
mkdir -p "$(dirname "$LOG")"
if ! swift test --package-path "$ROOT_DIR/Recognition" \
    --scratch-path "$ROOT_DIR/.build/recognition-tests" --sanitize=thread \
    -Xswiftc -warnings-as-errors -Xswiftc -strict-memory-safety > "$LOG" 2>&1; then
    printf 'recognition tests failed\n' >&2
    tail -n 25 "$LOG" >&2
    printf 'Full log: %s\n' "$LOG" >&2
    exit 1
fi
printf 'ok\n'
