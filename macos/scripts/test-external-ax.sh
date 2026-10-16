#!/bin/bash
set -euo pipefail
mac_root="$(cd "$(dirname "$0")/.." && pwd)"
repo_root="$(cd "$mac_root/.." && pwd)"
fixture="$repo_root/artifacts/macos/BentoFixture.app"
mkdir -p "$fixture/Contents/MacOS"
/usr/bin/xcrun swiftc -module-cache-path "$mac_root/.build/release-tools-cache" "$mac_root/tools/FixtureApp.swift" -o "$fixture/Contents/MacOS/BentoFixture"
/usr/bin/plutil -create xml1 "$fixture/Contents/Info.plist"
for pair in CFBundleIdentifier=com.abdullahegh.bento.fixture CFBundleExecutable=BentoFixture CFBundleName=BentoFixture CFBundlePackageType=APPL NSPrincipalClass=NSApplication; do
  /usr/bin/plutil -insert "${pair%%=*}" -string "${pair#*=}" "$fixture/Contents/Info.plist"
done
/usr/bin/codesign --force --sign - "$fixture"
"$fixture/Contents/MacOS/BentoFixture" &
fixture_pid=$!
trap 'kill "$fixture_pid" 2>/dev/null || true' EXIT
sleep 1
"$repo_root/artifacts/macos/Bento.app/Contents/MacOS/Bento" --external-ax-smoke "$fixture_pid" "$repo_root/artifacts/macos/external-ax"
