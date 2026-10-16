# GitHub OTA updates

**An Apple Developer ID is not required.** GitHub hosts the Mac ZIP assets and the signed appcast feed. Sparkle verifies them using Bento's own Ed25519 public key, embedded in the installed app. Developer ID signing/notarization can be added later for Apple's installation trust checks; neither is a mandatory OTA gate.

The implementation uses [Sparkle's documented setup](https://sparkle-project.org/documentation/) and a pinned 2.10.0 binary with its official SwiftPM checksum. The archive and feed must both be signed. Checks/downloads are off by default and can be enabled in Updates. System profiling is disabled. Before installation, Bento cancels any active gesture and restores its window positions and temporary desktop preferences. A failed restoration defers installation and offers a retry.

## Repository layout

- Mac assets: GitHub Releases, tags `macos-vX.Y.Z`, asset `Bento-macos-universal.zip`.
- Feed: `https://raw.githubusercontent.com/AbdullahEgh/Bento-Layout/macos-updates/appcast.xml`.
- The separate `macos-updates` branch keeps Mac feed changes independent of Windows releases and the code branch. Mac releases are published with `--latest=false` so the Windows updater's latest-release selection is not changed.
- Both Apple Silicon and Intel receive the universal app. `CFBundleVersion` must increase for every published update.

## One-time free update-key setup

Run after resolving/building the package:

```sh
macos/.build/artifacts/macos/Sparkle/bin/generate_keys --account com.abdullahegh.bento
```

This creates the private signing key in the login Keychain and prints the public key. The public key is checked in as `macos/UpdatePublicKey.txt`; `BENTO_UPDATE_PUBLIC_KEY` can override it in the build environment (it is not secret). Keep a secure backup of the private key; without Developer ID, losing it generally means users must manually install a release with a new key. Never commit the private key or paste it into a release description.

Alternatively set `BENTO_ED_KEY_FILE` to an exported Sparkle key file for signing. `BENTO_ED_KEY_ACCOUNT` selects a different Keychain account; its default is `com.abdullahegh.bento`. Tests use temporary seeds and delete them; they never create a production Keychain key.

## Build, prepare and publish

Commit and push the source before publishing. The build reads the committed public key automatically:

```sh
BENTO_UNIVERSAL=1 BENTO_OTA_RELEASE=1 BENTO_BUILD_NUMBER=2 macos/scripts/build-app.sh
macos/scripts/prepare-update.sh macos-v0.2.0
macos/scripts/publish-update.sh macos-v0.2.0
```

The first command accepts the default ad-hoc identity. Optionally set `BENTO_SIGNING_IDENTITY` to a Developer ID certificate; that path enables Hardened Runtime and signs all embedded helpers with the same identity. If `BENTO_NOTARY_PROFILE` is set, preparation submits to Apple's notarization service, staples and assesses the app. Those steps are skipped when no profile is configured.

Preparation rejects a dirty checkout, mismatched release tag/version, invalid bundle signature, unsigned/incorrect feed, or an archive signature that does not match the app's embedded public key. It records source revision and archive/feed hashes. Signing-tool diagnostics are kept out of console logs to avoid accidental key disclosure on malformed input.

Publishing requires authenticated GitHub CLI and Git access. It uploads the immutable release asset before moving the feed. It does not overwrite an existing differing asset. A failed feed upload can be retried against the same release bytes. The script updates only `macos-updates`, without force pushing or changing Windows assets.

## Bootstrap and current deployment state

The earlier 0.1.0 app did not include an updater. Users must manually install their first OTA-enabled release. Thereafter Sparkle can download and install GitHub updates.

The development ZIP has no production update public key and does not attempt online update checks. The production key is provisioned in the login Keychain under `com.abdullahegh.bento`. With the owner’s explicit approval, the same key is stored only as the encrypted repository secret `BENTO_MACOS_ED25519_PRIVATE_KEY`. It is never committed. GitHub CLI is authenticated as the repository owner. No paid Apple account is required.

The fixture test proves signing and validation of an ad-hoc app/archive/feed without Developer ID. It does not claim a completed online install/relaunch cycle or Gatekeeper acceptance of an unnotarized first download.

## GitHub release workflow

Run **Publish macOS app and OTA** from Actions with a new Mac version, for example `0.2.0`. The workflow tests, builds the universal app, signs the archive and feed using the encrypted secret, and publishes the Mac release and `macos-updates` branch. Private material exists only in a mode-600 temporary runner file and is removed after signing. Build numbers increase with workflow runs. The workflow does not publish Windows assets or mark a Mac release as the latest Windows release.

## Release points in the update popup

Preparation copies `macos/RELEASE_NOTES.md` beside the archive and asks Sparkle to embed it in the signed appcast. The standard update popup displays the points without a separate release-notes download, including in older installed Bento versions. Verification rejects new feeds without embedded notes. Notes must be finalized before signing; never edit the published signed feed.
