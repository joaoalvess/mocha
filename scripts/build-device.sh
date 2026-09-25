#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="${DERIVED_DATA_PATH:-$ROOT/build/DerivedData}"

"$ROOT/scripts/bootstrap.sh"

if ! grep -Eq '^DEVELOPMENT_TEAM *= *[A-Z0-9]{10}' "$ROOT/Config/Signing.xcconfig"; then
  echo "Config/Signing.xcconfig sem DEVELOPMENT_TEAM (bloqueio B1)." >&2
  exit 1
fi

/usr/bin/xcodebuild \
  -project "$ROOT/Mocha.xcodeproj" \
  -scheme Mocha \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED_DATA" \
  -allowProvisioningUpdates \
  "$@" \
  build
