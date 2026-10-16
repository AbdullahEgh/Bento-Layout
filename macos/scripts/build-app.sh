#!/bin/bash
set -euo pipefail
mac_root="$(cd "$(dirname "$0")/.." && pwd)"
repo_root="$(cd "$mac_root/.." && pwd)"
configuration="${CONFIGURATION:-release}"
build_options=()
architecture="$(uname -m)"
if [[ "${BENTO_UNIVERSAL:-0}" == "1" ]]; then build_options+=(--arch arm64 --arch x86_64); architecture=universal; fi
"$mac_root/scripts/swift.sh" build -c "$configuration" ${build_options[@]+"${build_options[@]}"}
products="$("$mac_root/scripts/swift.sh" build -c "$configuration" ${build_options[@]+"${build_options[@]}"} --show-bin-path)"
output_dir="${BENTO_ARTIFACTS_DIR:-$repo_root/artifacts/macos}"
app="$output_dir/Bento.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$products/Bento" "$app/Contents/MacOS/Bento"
cp -R "$products/Bento_BentoMac.bundle" "$app/Contents/Resources/"
mkdir -p "$app/Contents/Frameworks"
sparkle="$mac_root/.build/artifacts/macos/Sparkle"
/usr/bin/ditto "$sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework" "$app/Contents/Frameworks/Sparkle.framework"
cp "$sparkle/LICENSE" "$app/Contents/Resources/Sparkle-LICENSE.txt"
iconset="$mac_root/.build/Bento.iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
  /usr/bin/sips -z "$size" "$size" "$mac_root/Sources/BentoMac/Resources/bento.png" --out "$iconset/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  /usr/bin/sips -z "$double" "$double" "$mac_root/Sources/BentoMac/Resources/bento.png" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
/usr/bin/iconutil -c icns "$iconset" -o "$app/Contents/Resources/Bento.icns"
cp "$mac_root/Info.plist" "$app/Contents/Info.plist"
identity="${BENTO_SIGNING_IDENTITY:--}"
sign_options=()
if [[ "$identity" != "-" ]]; then sign_options+=(--options runtime --timestamp); fi
if [[ -n "${BENTO_BUILD_NUMBER:-}" ]]; then
  [[ "$BENTO_BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]] || { echo 'Build number must be a positive integer.' >&2; exit 1; }
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BENTO_BUILD_NUMBER" "$app/Contents/Info.plist"
fi
if [[ -n "${BENTO_MARKETING_VERSION:-}" ]]; then
  [[ "$BENTO_MARKETING_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Version must be X.Y.Z.' >&2; exit 1; }
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $BENTO_MARKETING_VERSION" "$app/Contents/Info.plist"
fi
if [[ "${BENTO_OTA_RELEASE:-0}" == "1" ]]; then
  [[ "$architecture" == "universal" && -n "${BENTO_UPDATE_PUBLIC_KEY:-}" ]] || { echo 'OTA release requires a Bento public update-signing key and a universal build.' >&2; exit 1; }
  [[ "$BENTO_UPDATE_PUBLIC_KEY" =~ ^[A-Za-z0-9+/]{43}=$ ]] || { echo 'Invalid Ed25519 public key.' >&2; exit 1; }
  /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $BENTO_UPDATE_PUBLIC_KEY" "$app/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c 'Set :BentoDevelopmentBuild false' "$app/Contents/Info.plist"
fi
framework="$app/Contents/Frameworks/Sparkle.framework/Versions/B"
for nested in "$framework/XPCServices/Downloader.xpc" "$framework/XPCServices/Installer.xpc" "$framework/Autoupdate" "$framework/Updater.app"; do
  /usr/bin/codesign --force --sign "$identity" ${sign_options[@]+"${sign_options[@]}"} --preserve-metadata=entitlements "$nested"
done
/usr/bin/codesign --force --sign "$identity" ${sign_options[@]+"${sign_options[@]}"} "$app/Contents/Frameworks/Sparkle.framework"
/usr/bin/codesign --force --sign "$identity" ${sign_options[@]+"${sign_options[@]}"} "$app"
/usr/bin/codesign --verify --deep --strict "$app"
/usr/bin/ditto -c -k --keepParent "$app" "$output_dir/Bento-macos-$architecture.zip"
printf 'Built %s\n' "$app"
