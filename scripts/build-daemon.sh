#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE="$ROOT/MochaKit"
XCCONFIG="$ROOT/Config/Signing.xcconfig"
IDENTIFIER="com.joaoalves.mochad"

team_identity() {
    local team="$1" sha subject
    for sha in $(/usr/bin/security find-identity -v -p codesigning | /usr/bin/awk '/^ *[0-9]+\)/ { print $2 }'); do
        subject="$(/usr/bin/security find-certificate -a -c "Apple Development" -Z -p | /usr/bin/awk -v hash="$sha" '
            /^SHA-1 hash:/ { keep = ($3 == hash) }
            keep && /BEGIN CERTIFICATE/ { printing = 1 }
            keep && printing { print }
            /END CERTIFICATE/ { printing = 0 }
        ' | /usr/bin/openssl x509 -noout -subject -nameopt multiline 2>/dev/null || true)"
        if printf '%s\n' "$subject" | /usr/bin/grep -Eq "organizationalUnitName[[:space:]]*=[[:space:]]*${team}\$"; then
            echo "$sha"
            return 0
        fi
    done
    return 1
}

/usr/bin/swift build --package-path "$PACKAGE" -c release --product mochad "$@"
BINARY="$(/usr/bin/swift build --package-path "$PACKAGE" -c release --show-bin-path "$@")/mochad"

TEAM="$(/usr/bin/sed -nE 's/^[[:space:]]*DEVELOPMENT_TEAM[[:space:]]*=[[:space:]]*([A-Z0-9]+).*/\1/p' "$XCCONFIG" 2>/dev/null | /usr/bin/head -n 1 || true)"
if [[ -n "$TEAM" ]] && IDENTITY="$(team_identity "$TEAM")"; then
    /usr/bin/codesign --force --sign "$IDENTITY" --identifier "$IDENTIFIER" --options runtime "$BINARY"
else
    echo "aviso: sem a identidade Apple Development do time ${TEAM:-(DEVELOPMENT_TEAM ausente em Config/Signing.xcconfig)}; o mochad fica sem a assinatura do time e o Keychain vai pedir autorização" >&2
fi

echo "$BINARY"
