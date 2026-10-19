#!/bin/bash
set -euo pipefail
mac_root="$(cd "$(dirname "$0")/.." && pwd)"
repo_root="$(cd "$mac_root/.." && pwd)"
release_tag="${1:?Usage: publish-update.sh macos-vX.Y.Z}"
[[ "$release_tag" =~ ^macos-v[0-9]+\.[0-9]+\.[0-9]+$ ]] || exit 1
stage="${BENTO_ARTIFACTS_DIR:-$repo_root/artifacts/macos}/update"
[[ -s "$stage/appcast.xml" && -s "$stage/Bento-macos-universal.zip" ]] || { echo 'Prepare and verify the signed update first.' >&2; exit 1; }
command -v gh >/dev/null || { echo 'GitHub CLI login is required to publish.' >&2; exit 1; }
[[ "$(cat "$stage/release-tag")" == "$release_tag" ]] || { echo 'Prepared update belongs to a different release tag.' >&2; exit 1; }
[[ "$(cat "$stage/source-commit")" == "$(git -C "$repo_root" rev-parse HEAD)" ]] || { echo 'Source commit changed after release preparation.' >&2; exit 1; }
(cd "$stage" && shasum -a 256 -c update.sha256)
# Release upload completes before the feed moves, so clients never see a missing asset.
if gh release view "$release_tag" --repo AbdullahEgh/Bento-Layout >/dev/null 2>&1; then
  existing="$(mktemp -d "${TMPDIR:-/tmp}/bento-existing-release.XXXXXX")"
  gh release download "$release_tag" --repo AbdullahEgh/Bento-Layout --pattern Bento-macos-universal.zip --dir "$existing"
  /usr/bin/cmp "$existing/Bento-macos-universal.zip" "$stage/Bento-macos-universal.zip" || { echo 'Existing release asset differs; refusing to overwrite it.' >&2; exit 1; }
  rm -rf "$existing"
else
  paired_assets=()
  if [[ -n "${BENTO_PAIRED_WINDOWS_DIR:-}" ]]; then
    [[ -s "$BENTO_PAIRED_WINDOWS_DIR/Bento-win-x64.zip" && -s "$BENTO_PAIRED_WINDOWS_DIR/Bento-windows-release.json" ]]
    paired_assets=("$BENTO_PAIRED_WINDOWS_DIR/Bento-win-x64.zip" "$BENTO_PAIRED_WINDOWS_DIR/Bento-windows-release.json")
  fi
  gh release create "$release_tag" "$stage/Bento-macos-universal.zip" "${paired_assets[@]}" --repo AbdullahEgh/Bento-Layout --target "$(cat "$stage/source-commit")" --title "Bento for macOS ${release_tag#macos-v}" --notes-file "$mac_root/RELEASE_NOTES.md" --latest=false --draft
  gh release edit "$release_tag" --repo AbdullahEgh/Bento-Layout --draft=false --latest=false
fi
feed_checkout="$(mktemp -d "${TMPDIR:-/tmp}/bento-feed.XXXXXX")"
trap 'rm -rf "$feed_checkout"' EXIT
git -C "$feed_checkout" init -q
git -C "$feed_checkout" remote add origin https://github.com/AbdullahEgh/Bento-Layout.git
if git -C "$feed_checkout" ls-remote --exit-code origin refs/heads/macos-updates >/dev/null; then
  git -C "$feed_checkout" fetch --depth=1 origin macos-updates
  git -C "$feed_checkout" checkout -b macos-updates FETCH_HEAD
else
  git -C "$feed_checkout" checkout --orphan macos-updates
fi
cp "$stage/appcast.xml" "$feed_checkout/appcast.xml"
git -C "$feed_checkout" add appcast.xml
if ! git -C "$feed_checkout" diff --cached --quiet; then
  git -C "$feed_checkout" -c user.name='Bento Releases' -c user.email='AbdullahEgh@users.noreply.github.com' commit -m "Publish signed macOS feed for $release_tag"
fi
git -C "$feed_checkout" push origin HEAD:macos-updates
