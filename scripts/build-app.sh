#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="${DERIVED_DATA_PATH:-$ROOT/build/DerivedData}"

source "$ROOT/scripts/lib/xcode-lock.sh"

"$ROOT/scripts/bootstrap.sh"

xcode_lock_acquire

/usr/bin/xcodebuild \
  -project "$ROOT/Mocha.xcodeproj" \
  -scheme Mocha \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$DERIVED_DATA" \
  -clonedSourcePackagesDirPath "$HOME/Library/Caches/com.joaoalves.mocha/SourcePackages" \
  CODE_SIGNING_ALLOWED=NO \
  "$@" \
  build
