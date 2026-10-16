# Bento for macOS — development preview

A native Swift, SwiftUI and AppKit app alongside the existing Windows version. Targets macOS 15+. No Electron, third-party packages, screen capture, display-resolution changes or application zoom changes.

## Run

With Xcode installed and its first-launch setup completed:

```sh
macos/scripts/swift.sh test
macos/scripts/build-app.sh
open artifacts/macos/Bento.app
```

Open `macos/Package.swift` in Xcode to edit and debug. The build script makes a standalone `.app`, reuses the original Windows PNG as its Mac icon, copies SwiftPM resources, signs the local build ad hoc, verifies its signature, and creates an architecture-named ZIP. An ad-hoc signature is for local development, not a notarized public release. Set `BENTO_SIGNING_IDENTITY` to a Developer ID identity for a later distribution build; notarization is a separate release step.

Keep the app at a stable path when granting Accessibility permission. Rebuilding or moving a development app can require renewing permission. Launch the app bundle, not `swift run`, for normal use.

If an installed toolchain is usable before Xcode setup finishes, set `BENTO_SWIFT` to its full `swift` path and `SDKROOT` to its Mac SDK path. In an already restricted execution environment that cannot nest SwiftPM's manifest sandbox, `BENTO_SWIFT_NO_SANDBOX=1` disables only that build-time sandbox. Normal local and CI builds leave it enabled. All caches stay under the ignored `.build` directory.

## Onboarding

Four native screens use the Windows palette, original Bento icon, and original line-icon paths:

1. **Welcome:** an illustrated desktop explains the app.
2. **Accessibility:** live permission state, System Settings link, and manual recheck. A preview route is available without permission.
3. **Find your flow:** add a fourth illustrated window or swap two in the in-app preview. Actual windows never move in this step. Respects Reduce Motion.
4. **Ready:** eligible-window count, gap selection and the explicit first-arrangement action. Arrangement is disabled without permission; finishing setup without arranging is supported.

Light and dark appearance follow the system or the selected setting. Onboarding can be reopened from the menu bar or About page. It is marked complete only on the final step. Settings are stored locally under `~/Library/Application Support/Bento/`.

![Welcome in light mode](docs/onboarding-1-light.png)
![Accessibility in dark mode](docs/onboarding-2-dark.png)

## Implemented in this milestone

- Menu-bar app, native settings and fixed Control–Option–B toggle; shortcut registration failure leaves the menu-bar controls available.
- Accessibility permission checks and public AX window discovery. The app excludes its own windows, hidden apps, minimized/fullscreen/fixed-size windows, and windows without matching public on-screen metadata.
- Automatic constraint-aware recursive arrangement on each window's current display; display work areas exclude the Dock and menu bar.
- Swift port of Windows automatic layout, insertion/removal, four-direction placement, center swapping, ratio resizing, bounded undo/redo and hold-to-split intent policy. The native gesture UI is **not connected yet**.
- Native geometry validation before writes, pre-activation snapshots, post-write bounds verification, best-effort rollback, original-position restoration on toggle-off and normal quit.
- One-second membership and display checks while active. Membership changes preserve existing ratios where feasible. Display changes rebuild against current visible areas. Permission revocation pauses management.
- Mac-specific saved layouts, matching bundle identifier and title, with missing windows left floating. Disconnected display layouts are not silently reassigned.
- Separate GitHub Actions checks for Mac builds/tests and Windows shared geometry contracts.

## Architecture and parity decisions

`Sources/BentoCore/` is a pure Foundation geometry package. It mirrors the existing C# algorithms instead of embedding a .NET runtime. Integer logical points are used on Mac, while the Windows adapter keeps physical pixels. Shared fixture coordinates are abstract units; ties-to-even rounding is explicit on both sides. AppKit/AX coordinate conversion happens only in `WindowSystem.swift`.

`Sources/BentoMac/` contains the OS adapter, transaction controller, SwiftUI onboarding/settings, menu bar and shortcut. `Resources/bento.png` and `bento.svg` are exact copies of the Windows originals. `Design.swift` copies theme values and the original vector paths used in the interface.

Windows saved files use executable paths and monitor names. Mac saved files are intentionally separate (`saved-layout-macos.json`, schema 1) and use bundle IDs and display UUIDs. Ratios and behavior can be shared; application and monitor identities are platform-specific. No Windows settings or saved files are rewritten by this app.

## Current limits

This is the first Mac milestone, not full Windows feature parity. Native title-bar swaps and timed edge splits, gap grips, native-border resize tracking, backdrop dimming, thumbnail transitions, configurable shortcuts, floating-window release controls and automatic update installation remain to be integrated. Settings identify these limits instead of exposing inactive controls.

Minimum window sizes use a conservative 320 × 240 point fallback because a universal minimum-size AX attribute is unavailable. An app may still refuse a resize; the controller checks actual bounds and attempts rollback. Writes across multiple apps cannot be atomic. Restoration is best effort when an app exits or access is revoked. Hard crashes cannot restore the session-only original-position snapshot. No automatic app launching, Spaces switching or full-screen management is performed.

## Validation

See [VALIDATION.md](VALIDATION.md) for actual checks and outstanding physical testing. Engine tests and onboarding screenshots do not prove third-party Accessibility control.

Render the real SwiftUI onboarding screens without arranging any windows:

```sh
artifacts/macos/Bento.app/Contents/MacOS/Bento --render-preview /tmp/bento-preview
```

This renders eight PNGs (four steps in light and dark). `--smoke` exits before window discovery or arrangement. GitHub Actions builds an artifact; it does not publish a release or require signing secrets.
