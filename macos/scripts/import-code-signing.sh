#!/bin/bash
set -euo pipefail
set +x
umask 077
: "${BENTO_CODESIGN_P12_B64:?Missing encrypted signing identity}"
: "${BENTO_CODESIGN_PASSWORD:?Missing signing identity password}"
: "${RUNNER_TEMP:?This import is for an ephemeral CI runner}"
: "${GITHUB_ENV:?Missing GitHub environment file}"
mac_root="$(cd "$(dirname "$0")/.." && pwd)"
keychain="$RUNNER_TEMP/bento-signing.keychain-db"
p12="$(mktemp "$RUNNER_TEMP/bento-identity.XXXXXX")"
trap 'rm -f "$p12"' EXIT
printf '%s' "$BENTO_CODESIGN_P12_B64" | /usr/bin/base64 --decode > "$p12"
unset BENTO_CODESIGN_P12_B64
/usr/bin/security create-keychain -p "$BENTO_CODESIGN_PASSWORD" "$keychain"
/usr/bin/security set-keychain-settings -lut 21600 "$keychain"
/usr/bin/security unlock-keychain -p "$BENTO_CODESIGN_PASSWORD" "$keychain"
# Keep both halves of the signing identity discoverable in the runner's
# user search list as well as codesign's explicit keychain. This runner is disposable.
/usr/bin/security list-keychains -d user -s "$keychain"
/usr/bin/security import "$p12" -f pkcs12 -k "$keychain" -P "$BENTO_CODESIGN_PASSWORD" -T /usr/bin/codesign >/dev/null
/usr/bin/security set-key-partition-list -S apple-tool:,apple: -s -k "$BENTO_CODESIGN_PASSWORD" "$keychain" >/dev/null
identity="$(/usr/bin/openssl x509 -in "$mac_root/CodeSigningCertificate.pem" -noout -fingerprint -sha1 | cut -d= -f2 | tr -d ':')"
[[ "$identity" =~ ^[0-9A-F]{40}$ ]] || exit 1
/usr/bin/security find-identity -p codesigning "$keychain" | /usr/bin/grep -F "$identity" >/dev/null || { echo 'Imported certificate has no matching signing key.' >&2; exit 1; }
printf 'BENTO_SIGNING_IDENTITY=%s\nBENTO_SIGNING_KEYCHAIN=%s\nBENTO_SIGNING_MODE=stable\n' "$identity" "$keychain" >> "$GITHUB_ENV"
