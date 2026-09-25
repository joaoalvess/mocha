#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ ! -f Config/Signing.xcconfig ]]; then
  cp Config/Signing.example.xcconfig Config/Signing.xcconfig
fi

/opt/homebrew/bin/xcodegen generate --spec project.yml --quiet
