#!/bin/bash
set -euo pipefail
mac_root="$(cd "$(dirname "$0")/.." && pwd)"
repo_root="$(cd "$mac_root/.." && pwd)"
configuration="${CONFIGURATION:-release}"
"$mac_root/scripts/swift.sh" build -c "$configuration"
products="$("$mac_root/scripts/swift.sh" build -c "$configuration" --show-bin-path)"
app="$repo_root/artifacts/macos/Bento.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$products/Bento" "$app/Contents/MacOS/Bento"
cp -R "$products/Bento_BentoMac.bundle" "$app/Contents/Resources/"
iconset="$mac_root/.build/Bento.iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
  /usr/bin/sips -z "$size" "$size" "$mac_root/Sources/BentoMac/Resources/bento.png" --out "$iconset/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  /usr/bin/sips -z "$double" "$double" "$mac_root/Sources/BentoMac/Resources/bento.png" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
/usr/bin/iconutil -c icns "$iconset" -o "$app/Contents/Resources/Bento.icns"
cp "$mac_root/Info.plist" "$app/Contents/Info.plist"
/usr/bin/codesign --force --sign "${BENTO_SIGNING_IDENTITY:--}" --options runtime "$app"
/usr/bin/codesign --verify --deep --strict "$app"
/usr/bin/ditto -c -k --keepParent "$app" "$repo_root/artifacts/macos/Bento-macos-$(uname -m).zip"
printf 'Built %s\n' "$app"
