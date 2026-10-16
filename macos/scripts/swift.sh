#!/bin/bash
set -euo pipefail
mac_root="$(cd "$(dirname "$0")/.." && pwd)"
# Keep caches inside the checkout for restricted workspaces. BENTO_SWIFT and SDKROOT
# can point at an installed toolchain before Xcode's first-launch setup is complete.
export CLANG_MODULE_CACHE_PATH="$mac_root/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$mac_root/.build/module-cache"
swift_bin="${BENTO_SWIFT:-$(/usr/bin/xcrun --find swift)}"
extra=()
if [[ "${BENTO_SWIFT_NO_SANDBOX:-0}" == "1" ]]; then extra+=(--disable-sandbox); fi
exec "$swift_bin" "$@" ${extra[@]+"${extra[@]}"} --package-path "$mac_root" \
  --cache-path "$mac_root/.build/cache" --config-path "$mac_root/.build/config" --security-path "$mac_root/.build/security"
