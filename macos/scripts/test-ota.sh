#!/bin/bash
set -euo pipefail
mac_root="$(cd "$(dirname "$0")/.." && pwd)"
repo_root="$(cd "$mac_root/.." && pwd)"
fixture="$(mktemp -d "${TMPDIR:-/tmp}/bento-ota-fixture.XXXXXX")"
trap 'rm -rf "$fixture"' EXIT
swift_bin="${BENTO_SWIFT:-$(/usr/bin/xcrun --find swift)}"
mkdir -p "$fixture/stage"
cat > "$fixture/key.swift" <<'SWIFT'
import Foundation
import CryptoKit
let directory = URL(fileURLWithPath: CommandLine.arguments[1])
let key = Curve25519.Signing.PrivateKey()
let privateFile = directory.appendingPathComponent("fixture.key")
try key.rawRepresentation.base64EncodedData().write(to: privateFile, options: .atomic)
try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: privateFile.path)
try key.publicKey.rawRepresentation.base64EncodedData().write(to: directory.appendingPathComponent("public.txt"))
SWIFT
"$swift_bin" -module-cache-path "$mac_root/.build/release-tools-cache" "$fixture/key.swift" "$fixture"
/usr/bin/ditto "$repo_root/artifacts/macos/Bento.app" "$fixture/Bento.app"
public_key="$(cat "$fixture/public.txt")"
/usr/libexec/PlistBuddy -c 'Delete :SUPublicEDKey' "$fixture/Bento.app/Contents/Info.plist" >/dev/null 2>&1 || true
/usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $public_key" "$fixture/Bento.app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :BentoDevelopmentBuild false' "$fixture/Bento.app/Contents/Info.plist"
/usr/bin/codesign --force --sign - "$fixture/Bento.app" > "$fixture/sign.log" 2>&1
/usr/bin/codesign --verify --deep --strict "$fixture/Bento.app"
/usr/bin/ditto -c -k --keepParent "$fixture/Bento.app" "$fixture/stage/Bento-macos-universal.zip"
tools="$mac_root/.build/artifacts/macos/Sparkle/bin"
release_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$fixture/Bento.app/Contents/Info.plist")"
release_tag="macos-v$release_version"
if ! "$tools/generate_appcast" --ed-key-file "$fixture/fixture.key" --download-url-prefix "https://github.com/AbdullahEgh/Bento-Layout/releases/download/$release_tag/" --maximum-deltas 0 -o "$fixture/stage/appcast.xml" "$fixture/stage" > "$fixture/generate.log" 2>&1; then
  echo 'Fixture appcast generation failed.' >&2; exit 1
fi
"$tools/sign_update" --verify --ed-key-file "$fixture/fixture.key" "$fixture/stage/appcast.xml" > "$fixture/verify.log" 2>&1
"$swift_bin" -module-cache-path "$mac_root/.build/release-tools-cache" "$mac_root/scripts/verify-update.swift" "$fixture/Bento.app/Contents/Info.plist" "$fixture/stage/appcast.xml" "$fixture/stage/Bento-macos-universal.zip" "$release_tag"
printf 'corrupt' >> "$fixture/stage/Bento-macos-universal.zip"
if "$swift_bin" -module-cache-path "$mac_root/.build/release-tools-cache" "$mac_root/scripts/verify-update.swift" "$fixture/Bento.app/Contents/Info.plist" "$fixture/stage/appcast.xml" "$fixture/stage/Bento-macos-universal.zip" "$release_tag" > "$fixture/corrupt.log" 2>&1; then
  echo 'Corruption was not rejected.' >&2; exit 1
fi
printf 'GitHub OTA fixture passed: ad-hoc app, signed feed/archive, corruption rejected. No Developer ID or Keychain key was used.\n'
