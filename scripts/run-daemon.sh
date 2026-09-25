#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

exec /usr/bin/swift run --package-path "$ROOT/MochaKit" mochad run "$@"
