#!/bin/bash
set -euo pipefail
mac_root="$(cd "$(dirname "$0")/.." && pwd)"
app="${1:?Usage: verify-code-identity.sh Bento.app}"
identity="$(/usr/bin/openssl x509 -in "$mac_root/CodeSigningCertificate.pem" -noout -fingerprint -sha1 | cut -d= -f2 | tr -d ':' | tr 'A-F' 'a-f')"
[[ "$identity" =~ ^[0-9a-f]{40}$ ]] || exit 1
requirement="identifier \"com.abdullahegh.bento\" and certificate leaf = H\"$identity\""
/usr/bin/codesign --verify --deep --strict --all-architectures -R "=$requirement" "$app"
actual="$(/usr/bin/codesign -d -r- "$app" 2>/dev/null | sed -n 's/^designated => //p')"
[[ "$actual" == "$requirement" ]] || { echo 'App identity is not the pinned stable requirement.' >&2; exit 1; }
echo 'Verified stable Bento code identity and all architecture signatures.'
