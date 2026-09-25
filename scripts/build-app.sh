#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="${DERIVED_DATA_PATH:-$ROOT/build/DerivedData}"

"$ROOT/scripts/bootstrap.sh"

/usr/bin/xcodebuild \
  -project "$ROOT/Mocha.xcodeproj" \
  -scheme Mocha \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  "$@" \
  build
