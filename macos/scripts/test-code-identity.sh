#!/bin/bash
set -euo pipefail
mac_root="$(cd "$(dirname "$0")/.." && pwd)"
repo_root="$(cd "$mac_root/.." && pwd)"
app="${BENTO_ARTIFACTS_DIR:-$repo_root/artifacts/macos}/Bento.app"
: "${BENTO_SIGNING_IDENTITY:?A persistent signing identity is required}"
: "${BENTO_SIGNING_KEYCHAIN:?An explicit signing keychain is required}"
fixture="$(mktemp -d "${TMPDIR:-/tmp}/bento-identity-test.XXXXXX")"
trap 'rm -rf "$fixture"' EXIT
"$mac_root/scripts/verify-code-identity.sh" "$app"
requirement="$(/usr/bin/codesign -d -r- "$app" 2>/dev/null | sed -n 's/^designated => //p')"
/usr/bin/ditto "$app" "$fixture/Next.app"
/usr/libexec/PlistBuddy -c 'Set :CFBundleVersion 999999' "$fixture/Next.app/Contents/Info.plist"
printf 'A different release payload\n' > "$fixture/Next.app/Contents/Resources/identity-fixture.txt"
/usr/bin/codesign --force --sign "$BENTO_SIGNING_IDENTITY" --keychain "$BENTO_SIGNING_KEYCHAIN" --timestamp=none --requirements "=designated => $requirement" "$fixture/Next.app"
"$mac_root/scripts/verify-code-identity.sh" "$fixture/Next.app"
first_hash="$(/usr/bin/codesign -dvvv "$app" 2>&1 | sed -n 's/^CDHash=//p')"
next_hash="$(/usr/bin/codesign -dvvv "$fixture/Next.app" 2>&1 | sed -n 's/^CDHash=//p')"
[[ -n "$first_hash" && -n "$next_hash" && "$first_hash" != "$next_hash" ]] || { echo 'Fixture must change the binary code directory hash.' >&2; exit 1; }
/usr/bin/codesign --verify --strict --all-architectures -R "=$requirement" "$fixture/Next.app"
printf 'tampered' >> "$fixture/Next.app/Contents/Resources/identity-fixture.txt"
if /usr/bin/codesign --verify --strict -R "=$requirement" "$fixture/Next.app" >/dev/null 2>&1; then echo 'Tampering was accepted.' >&2; exit 1; fi
/usr/bin/codesign --force --sign - "$fixture/Next.app" >/dev/null 2>&1
if /usr/bin/codesign --verify --strict -R "=$requirement" "$fixture/Next.app" >/dev/null 2>&1; then echo 'A different signer was accepted.' >&2; exit 1; fi
echo 'Different version: same code identity. Tampering and different signer: rejected.'
