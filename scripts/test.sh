#!/usr/bin/env bash
#
# Runs the unit tests (Tests/TBDTests) without launching the app.
#
# Usage: ./scripts/test.sh
#
# Built with `build-for-testing`, then run with `xctest` directly: the test
# bundle has no host app, and `xcodebuild test` on Xcode 27.1 refuses to load
# such a bundle from a path that contains spaces ("executable not found"),
# which this repository's usual folder name does.
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED="$ROOT/build/TestDerivedData"
LOG="$ROOT/build/test-build.log"
cd "$ROOT"
mkdir -p "$ROOT/build"

xcodegen generate >/dev/null

if ! xcodebuild build-for-testing -project TBD.xcodeproj -scheme TBD \
    -destination 'platform=macOS' -derivedDataPath "$DERIVED" \
    CODE_SIGN_IDENTITY=- >"$LOG" 2>&1; then
  /usr/bin/grep -E "error:" "$LOG" | /usr/bin/sort -u | /usr/bin/head -30
  echo "❌ Build failed — full log: $LOG"
  exit 1
fi

xcrun xctest "$DERIVED/Build/Products/Debug/TBDTests.xctest" 2>&1 \
  | /usr/bin/grep -E "error|failed|Executed" | /usr/bin/tail -30
