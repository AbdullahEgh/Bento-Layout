# macOS 0.2.0 validation — 2026-10-16

Current revision adds native interaction wiring, signed GitHub OTA and temporary activation preferences. The sections below the historical heading describe the earlier 0.1.0 milestone.

| Check | Actual result |
| --- | --- |
| Debug and optimized universal build | Passed; executable contains arm64 and x86_64, both with macOS 15 minimum deployment target |
| App and embedded Sparkle helper signatures | Ad-hoc signatures verified with deep/strict checks; Developer ID is optional |
| Core XCTest suite | 22 tests passed, including geometry/gesture cases, seeded 1,000-operation exercise, preference rollback/recovery and official Sparkle archive signing |
| Disposable native interaction harness | 22 checks passed against real in-process NSWindows using the production controller and gap panels, injected window/preferences backends and supplied pointer samples |
| Native harness coverage | Arrangement, gap-only helper bounds, center swap, held-edge split, Escape restoration, live grip commit/cancel, inner-border resize, undo/redo, rejected-write rollback, deactivate/restore, activation options, and cancellation during activation |
| OTA without Developer ID | Passed: copied ad-hoc app, temporary Ed25519 seed, generated signed feed/archive with official Sparkle tools, verified signed feed and app-embedded public key/archive relation, and rejected a corrupted archive. No production Keychain key was created |
| External Accessibility adapter | 11 checks passed on a separate fixture process: discovery, arrangement, four split directions, swap, neighbor resize, undo/redo and original-position restoration. The native API was used directly, with the process allowlist preventing user-window access |
| New settings screens | Rendered Workspace/Gestures/Updates in light/dark and visually checked; activation options are visible near the top of Workspace |
| Package smoke, shell syntax and whitespace | Passed |

The OTA fixture caught an incorrect fixture key representation and a macOS XML import issue; both were fixed before the successful run. Sparkle's current exported private-key format is the base64-encoded 32-byte Ed25519 seed. Temporary fixture keys are removed automatically.

The native harness changes only its own disposable windows. It proves controller-to-native-fixture geometry and rollback, not physical global mouse/keyboard routing or third-party Accessibility compatibility. The real Dock/menu-bar/WindowManager backend has **not** been activated during these tests. Its preference keys are OS-dependent; real system-setting effects, notification behavior and Dock restart recovery need interactive validation. No user's desktop preferences were changed by the harness or OTA fixture.

The production Ed25519 key is provisioned in Keychain and, with explicit owner approval, in the encrypted GitHub Actions signing secret. GitHub is authenticated as the repository owner. Online release publication and install/relaunch are recorded separately from the offline signature fixture. A paid Apple developer account is not needed for Ed25519-signed GitHub OTA. Intel code was built, not run on Intel hardware. Third-party AX movement, physical drag/hold/grip capture/Escape, multiple physical displays and longer sessions remain to be validated.

## Historical 0.1.0 validation

Development preview built locally on Apple Silicon with the installed Swift 6.4 toolchain and macOS SDK. SwiftPM uses Swift 5 language mode for this initial port and targets macOS 15+. The Windows base is commit `4069b23`; Windows-native results in the root validation document are historical, not rerun on this Mac.

| Check | Actual result |
| --- | --- |
| Native debug build | Passed |
| Optimized release build and standalone app packaging | Passed |
| Local ad-hoc app signature | Verified with strict/deep verification; no Developer ID notarization claimed |
| Swift XCTest suite | 11 tests passed, 0 failures |
| Shared geometry contract | All five fixtures exercised: negative origin, odd-size ties-to-even rounding, nested tree, minimum clamping, impossible arrangement |
| Automatic arrangement | Engine invariants pass for 1–12 windows, portrait display and asymmetric minimum constraints |
| Mutation and history | Four insertion directions, cross-display swap, removal/collapse, preserved split ratios, bounded undo/redo and redo-branch invalidation pass |
| Gesture policy | Quick edge drop, hold threshold, boundary jitter, cancellation/reset and target-display change pass in pure engine tests |
| Stress exercise | Seeded 1,000 insert/remove/resize operations pass bounds, minimum-size and no-overlap checks |
| Layout serialization | Codable tree round trip passed |
| Packaged startup smoke | Passed; exits before discovery or movement |
| Resource artwork | PNG SHA-256 matches the original Windows artwork exactly |
| Onboarding renders | Packaged app generated eight native SwiftUI PNGs, all four steps in light/dark; visually inspected. A truncated playground heading was fixed and renders regenerated |
| Running app onboarding | Welcome → Accessibility → safe playground verified through native UI. Add-window and swap controls visually changed the illustrated composition without moving real windows |
| Permission gating | Without Accessibility approval, onboarding offers a preview and disables first arrangement |
| Plist and patch checks | Plist valid; Git whitespace checks pass |

The first isolated renderer run crashed after writing its first screenshot because AppKit released a closed temporary render window twice. Temporary windows now use `isReleasedWhenClosed = false`; the packaged renderer completed all eight screens and exited successfully.

Restricted execution initially prevented Swift cache writes and nested SwiftPM manifest sandboxing. The build helper now supports checkout-local caches and an explicit build-only sandbox override. Release debug-symbol generation and native window rendering required running the local build/renderer outside the outer execution sandbox. No macOS privacy setting was changed.

## Historical 0.1.0 checks that were outstanding

- **Live third-party window movement/restoration has not been run.** Accessibility permission has not been granted to this development app. Engine tests, code review and screenshots do not establish native adapter correctness.
- Safari/Finder/Notes and other real applications accepting frames, asynchronous resize refusals, native rollback failures, minimization/reopen identity, permission revocation, focus behavior and normal-quit restoration need an interactive pass.
- Multiple physical displays, Retina/non-Retina mixtures, negative display origins, hot-plugging, Dock changes, Spaces changes and lock/unlock need hardware testing. The engine's negative-origin tests do not prove OS coordinate conversion.
- The hotkey's registration path exists; a physical Control–Option–B press has not been verified.
- Windows shared-fixture harness changes have not been compiled here. The added Windows workflow is prepared to run them; no remote CI result is claimed.
- Native drag-to-swap/split, grips and native-border resize tracking remain unimplemented. The gesture policy tests apply to the pure engine only.
- Intel builds, macOS 15 runtime compatibility, VoiceOver walkthrough, Developer ID signing, notarization, online release downloads and long-running performance remain unverified.

## Next interactive pass

Launch the stable `Bento.app` bundle and grant it Accessibility in System Settings. Start with disposable application windows. Record their original rectangles; explicitly arrange; check actual frame acceptance and focus; toggle off and verify restoration. Repeat with a rejected resize, close/minimize/reopen, display changes and quit. Native gesture work should follow that adapter proof. Do not turn on Screen Recording to test this milestone; it does not use screen capture.

## Current interactive limits

Physical mouse/keyboard routing is not established by the supplied-pointer harness or the real AX fixture. The desktop-control attempt changed the active virtual-display/window geometry during testing; it did not provide a reliable physical gesture result. The current Remio virtual display can be narrow/portrait. Starting minima were reduced to 160 × 120 and actual application restrictions are learned from rejected native sizes, followed by bounded reflow retries. All 22 native fixture checks and all 11 external AX checks then passed on the narrow display.

Start at login is implemented with SMAppService on Mac and the per-user Run entry on Windows. The option remains off unless selected. A complete sign-out/sign-in cycle has not been performed. Windows compilation/tests run in the repository workflow rather than on this Mac.

## Published 0.2.0 deployment

GitHub Mac/Windows builds and the signed Mac release workflow passed at `9c40363`. The Windows build reported 91 checks, no warnings/errors. Mac 0.2.0 build 101, the public signed feed and its archive were downloaded and independently verified against the embedded production key. The installed `/Applications/Bento.app` subsequently changed from build 2 to build 101 and relaunched through Sparkle’s update flow. The owner then reported missing activation; the installed app’s own UI showed Accessibility denied and Arrange disabled. The desktop-control tool is not approved for System Settings, so granting/regranting access requires the owner.

The 0.2.1 follow-up makes that state explicit and removes the floating settings level. Windows 0.3.6 removes the periodic settings raise, with a separate HWND-order regression check in CI.

## 0.2.2 partial arrangement

26 core tests passed, including oversized-window exclusion, total-capacity overflow, edited-tree preservation, refreshed learned minima and invalid-input rejection. The 33-check native fixture passed with disposable windows only. New native cases cover known oversized windows receiving no writes, a native resize clamp being learned and rolled back, fitting windows remaining active, skipped-window movement surviving deactivation, reconsideration when a window fits again, and no persistent frame/preference changes when none fit, and a window that consistently refuses resize requests. The 11 external Accessibility checks also passed against the isolated fixture app. Physical drag routing retains the limitations documented above.

On the installed 0.2.1 process, direct Accessibility queries succeeded after restart (AXIsProcessTrusted true, AXWindows result success). Activation then failed on window capacity. This release addresses that failure rather than requesting additional permissions.
