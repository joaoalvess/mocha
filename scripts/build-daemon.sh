#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE="$ROOT/MochaKit"

/usr/bin/swift build --package-path "$PACKAGE" -c release --product mochad "$@"
echo "$(/usr/bin/swift build --package-path "$PACKAGE" -c release --show-bin-path "$@")/mochad"
