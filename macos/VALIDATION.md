# macOS validation — 2026-10-16

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

## Not yet verified

- **Live third-party window movement/restoration has not been run.** Accessibility permission has not been granted to this development app. Engine tests, code review and screenshots do not establish native adapter correctness.
- Safari/Finder/Notes and other real applications accepting frames, asynchronous resize refusals, native rollback failures, minimization/reopen identity, permission revocation, focus behavior and normal-quit restoration need an interactive pass.
- Multiple physical displays, Retina/non-Retina mixtures, negative display origins, hot-plugging, Dock changes, Spaces changes and lock/unlock need hardware testing. The engine's negative-origin tests do not prove OS coordinate conversion.
- The hotkey's registration path exists; a physical Control–Option–B press has not been verified.
- Windows shared-fixture harness changes have not been compiled here. The added Windows workflow is prepared to run them; no remote CI result is claimed.
- Native drag-to-swap/split, grips and native-border resize tracking remain unimplemented. The gesture policy tests apply to the pure engine only.
- Intel builds, macOS 15 runtime compatibility, VoiceOver walkthrough, Developer ID signing, notarization, online release downloads and long-running performance remain unverified.

## Next interactive pass

Launch the stable `Bento.app` bundle and grant it Accessibility in System Settings. Start with disposable application windows. Record their original rectangles; explicitly arrange; check actual frame acceptance and focus; toggle off and verify restoration. Repeat with a rejected resize, close/minimize/reopen, display changes and quit. Native gesture work should follow that adapter proof. Do not turn on Screen Recording to test this milestone; it does not use screen capture.
