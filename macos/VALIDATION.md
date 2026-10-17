# macOS 0.2.18 responsive work areas and coordinated motion — 2026-10-17

50 core tests and 132 isolated native checks passed locally, including explicit animated and Reduce Motion preview cases. New core cases cover stale menu-bar reservations, hidden/left-side Docks, Dock size changes, camera-safe insets and negative screen coordinates. Native cases change work-area height and top inset repeatedly with fixed membership, verify every affected slot and split identity, and check that a settled area does not trigger repeated writes. A Dock-area change injected during a rejected AX transaction confirms that the new area remains eligible for retry; failure caching records the attempted area, not the area that appeared afterward. Geometry reads during animation are bounded independently of intermediate frame count. Existing delayed AX acceptance, minimum-size correction, rollback, Reduce Motion, resume, all drag directions, section moves, settings coalescing and OTA restoration checks remain green.

Preview checks cover transparent click-through entry, retargeting to the latest destination, fade cleanup and immediate geometry when animation is disabled. The composited preview render was inspected: translucent teal/amber fields with no strokes, text, symbols or badges. The selected-window exclusion action retains the last external selection when Bento takes focus and remains undoable. A simulated delayed native rebound repairs only the moved window, retains the split tree, and does not write during a new pointer gesture.

The first CI run exposed an assumption in the preview test: hosted runners enabled Reduce Motion, correctly producing an immediate preview rather than a fade. The fixture now supplies its motion policy explicitly and covers both policies without altering host accessibility settings.

These checks use disposable windows and supplied interaction samples. Live desktop preference and installed OTA validation are recorded separately; the fixture does not change user preferences or imply all physical interactions are certified.

# macOS 0.2.17 section movement, close animation and layering — 2026-10-17

49 core tests passed, including all four physical screen edges on negative-coordinate displays, a large window that cannot fit an individual stacked slot, preservation of clamped section sizes, repeated-sample caching, whole-group movement, round-trip geometry and separation from cross-display placement. The isolated native harness passed 117 checks, including section preview/animated commit/undo, animated branch collapse after a window closes, no writes to the closed window, no repeated reflow after settling, and grabber level -1 below app windows and above the dimming panel at -2. Existing normal swaps, held splits, live settings and bounded admission checks remain green.

The settings screens were rendered at 820- and 360-point widths in light and dark appearances. Workspace and Gestures renders were inspected for trailing switch alignment, wrapping, card grouping and control visibility. The right-click menu uses native section headers; its combined desktop toggle writes both preferences together and reflects independently selected values with a mixed state.

The production menu icon renderer was inspected in both states: dim white outline for off and solid white sections for active. Icons remain clickable in both states. These are supplied-input native interaction checks, not a claim that every physical title-bar interaction has been manually certified.

# macOS 0.2.10 OTA — 2026-10-16

[Release run 38947365617](https://github.com/AbdullahEgh/Bento-Layout/actions/runs/38947365617) and [macOS 15/26 compatibility run 38947365567](https://github.com/AbdullahEgh/Bento-Layout/actions/runs/38947365567) passed at `eae0eda`. The published archive/feed signature and stable app identity verified independently.

Updated the installed 0.2.9 app through Sparkle to 0.2.10. The installed version and permanent designated requirement verified, and the installed app reports Accessibility true without reapproval. The user resumed live pointer testing; a hands-off interval is pending after remote input interfered with updater control. No live hover/drag pass is claimed yet. Local evidence is in `artifacts/macos/live-0210/`.

# Split and resize UX review — unreleased, 2026-10-16

Local release build passed, with 32 core tests and 61 isolated native interaction checks. Added coverage for off-center grabs on both axes, odd/even gaps, minimum-size clamping, stationary pointer samples, rapid release retaining the newest queued sample, delayed native frame acceptance without a second animation, and final helper geometry. Results: `artifacts/macos/split-ux-review/results/results.json`.

[macOS 15/26 run 38940151055](https://github.com/AbdullahEgh/Bento-Layout/actions/runs/38940151055) passed at `3ec8874`, including universal builds, startup, native interaction checks, and the signed OTA fixture.

The live pointer test remains paused at the user's request. These checks use disposable fixture windows, leave external app windows and system preferences alone, and do not establish physical hover/drag feel. The installed 0.2.9 app is unchanged by this review.

# macOS 0.2.9 grabber input and responsive settings — 2026-10-16

[Release run 38911048468](https://github.com/AbdullahEgh/Bento-Layout/actions/runs/38911048468) and [macOS 15/26 run 38911047800](https://github.com/AbdullahEgh/Bento-Layout/actions/runs/38911047800) passed at `d0d3adc`: 31 core tests, universal build, and 56 isolated native interaction checks. The new checks verify nonzero background pixels across the otherwise hidden gap, native mouse-enter/press/exit/release handlers, and unchanged helper level below app windows and above the dimmer. These are fixture checks, not a claim of a physical pointer pass over every external app.

Rendered all five settings pages in light and dark modes at 820 and 360 points. A follow-up render harness creates the same resizable NSHostingController window, opens it at 820, then shrinks it to 360 and asserts the actual view width before capturing. All 20 renders passed; compact navigation, vertical control layout, and text wrapping were inspected. The desktop-control tool's border drags did not resize the installed window; the native resizing harness supplies this verification instead.

Installed 0.2.9 through the normal 0.2.8 Sparkle update UI. The installed version and permanent code requirement verified; Accessibility remained connected. The installed settings window's Zoom control is enabled and successfully expanded the window. Bento was left off; auto-hide choices were unchanged.

# macOS 0.2.8 live OTA and native motion validation — 2026-10-16

[Release run 38908676362](https://github.com/AbdullahEgh/Bento-Layout/actions/runs/38908676362) and [compatibility run 38908677509](https://github.com/AbdullahEgh/Bento-Layout/actions/runs/38908677509) passed at `11074b1`. macOS 15 and 26 passed; 31 core tests and 52 isolated native interaction checks include delayed native frame completion during activation and restoration. The published archive/feed signature and permanent app signing requirement were independently verified.

The installed 0.2.7 app updated through Sparkle to 0.2.8 with Accessibility still connected, without reapproval or manual replacement. On the current 630 × 1368 display, Dock-only activation completed with three windows arranged, one minimized to Dock, and none left alone. Deactivation returned to four eligible windows without a restoration error. All five desktop preference values returned exactly to baseline, including originally absent keys. Bento was left off and both auto-hide choices restored to their original off values. The prior 0.2.7 live checks below cover menu-only and combined auto-hide behavior; those preference paths are unchanged.

These checks validate this OTA upgrade and real-window acceptance on this Mac. Physical drag feel and subjective smoothness across other apps/displays remain manual validation limits.

# macOS 0.2.7 interaction validation — 2026-10-16

[Compatibility run 38906551873](https://github.com/AbdullahEgh/Bento-Layout/actions/runs/38906551873) at `888ac8a` passed on macOS 15 and 26: 31 core tests, universal compilation, startup, 50 isolated native checks and the signed OTA fixture. The native checks passed locally too. They cover eased activation/restoration with exact final frames, explicit Reduce Motion behavior, fully hidden idle grips and hover/grab visibility, below-application grip level, overflow minimization, Dock reopening, minimization refusal, and preservation of windows minimized before Bento activation. Core tests cover priority admission, motion endpoints and noncommitting conflict feedback.

The first Windows native pass caught restoration of a manually minimized window; restoring only removed windows still eligible for Bento fixed it. The Mac fixture now supplies Reduce Motion explicitly rather than depending on CI host accessibility preferences. Physical pointer routing and subjective animation smoothness retain the interactive limitations documented below. The installed 0.2.7 app retained Accessibility after OTA from 0.2.6. Live tests verified both hide options together and separately, and exact restoration of all five desktop preference keys (including absent values). Menu-only reclaimed the top 30 points; Dock-only reclaimed the bottom 47 points on the test display. An intermittent real-app arrangement/rollback failure during Dock-only testing prompted the bounded native-settling correction in 0.2.8; a repeated activation succeeded with four arranged and one minimized. These results do not establish physical pointer smoothness on every display.

# macOS 0.2.6 live OTA permission-retention test — 2026-10-16

**Passed:** the installed 0.2.5 app updated through Sparkle to 0.2.6 (build 109), retained Accessibility approval, and arranged real desktop windows. No Accessibility reset, settings toggle, reapproval or manual app replacement was performed during this test.

- Baseline: installed 0.2.5 reported Accessibility connected, four arranged windows and two left alone.
- [Release workflow 38900903661](https://github.com/AbdullahEgh/Bento-Layout/actions/runs/38900903661) passed at `4932189`: core tests, universal build, stable-identity checks and native interaction checks.
- The published ZIP/feed were independently downloaded and verified against the embedded Ed25519 key. Deep/strict code-signature verification passed for all architectures.
- Used Bento’s Check for updates → Install Update → Install and Relaunch. Sparkle restored the active layout before replacing the app. The installed plist and normal app UI changed to 0.2.6; the running PID changed from 57498 to 58044.
- The installed arm64 CDHash changed from `7e3ea452886bb6c87cb3c0b766dc4f4a11624f0b` to `5b6232b0989a6d6ff5f083dc0ce2f6cb3b5817ee`, while the designated requirement remained byte-for-byte identical, pinned to certificate SHA1 `086D088BE9D3A09AC9CAB42EDBED89CE7D9C0D68`.
- Immediately after relaunch, the app reported Accessibility connected and six eligible windows. Activation then completed with five arranged and one left alone. Turning Bento off completed without a restoration error. It was activated again afterward.
- macOS’s recent TCC log contained no Bento code-requirement mismatch. Existing login, spacing, appearance and activation preferences were preserved.

This verifies permission retention for the actual 0.2.5 → 0.2.6 OTA upgrade on this Mac. It does not establish behavior for every macOS version or future certificate changes. Window counts are the production controller’s results after native frame acceptance checks, not an independent measurement of every desktop rectangle.

## macOS 0.2.5 stable-signing validation — 2026-10-16

A persistent self-signed code identity was created without changing system certificate trust. An optimized universal build passed deep/strict signature verification for both architectures with the explicit certificate-pinned app requirement. A fixture changed its version and payload, producing a different code-directory hash, and still satisfied the original version's requirement. A tampered resource and an ad-hoc replacement signer were both rejected. Importing the encrypted backup into a disposable CI-style keychain and running the same checks also passed; the temporary keychain was deleted afterward. Startup and all 36 isolated native interaction checks passed on the new signed app.

With explicit owner approval, the encrypted identity backup and password were provisioned as GitHub Actions secrets. [Release workflow 38899813776](https://github.com/AbdullahEgh/Bento-Layout/actions/runs/38899813776) passed at `682bb60`, including 28 core tests, universal stable signing, cross-version identity verification and all 36 native interaction checks. The first release attempt stopped before publication because the runner keychain was absent from its search list; the corrected import setup passed on retry.

[Release 0.2.5](https://github.com/AbdullahEgh/Bento-Layout/releases/tag/macos-v0.2.5), build 108, was downloaded independently. Its archive/feed Ed25519 signature, certificate-pinned designated requirement, deep/strict signatures for both architectures and arm64/x86_64 executable were verified. Sparkle installed it over 0.2.4; the installed plist and live settings UI show 0.2.5, and `/Applications/Bento.app` passes the same stable-identity verification. Existing user settings were preserved. After installation, macOS still retained the old 0.2.4 code-hash requirement. An app-scoped Accessibility reset cleared that stale record, and the owner granted access again. The normal installed 0.2.5 process then reported Accessibility connected and four windows arranged with two left alone. Deactivation completed without a restoration error; after quitting and reopening, Accessibility remained connected, and activation again reported four arranged and two left alone. Bento was left active. This checks the controller result and permission across restart, not an independent measurement of every restored window frame. Live Accessibility retention was subsequently verified by the 0.2.5 → 0.2.6 OTA test recorded above. The existing 0.2.4 approval remained bound to an earlier code hash even after the owner re-added Bento; the macOS log explicitly reported a failed code-requirement match. Bento's stale Accessibility record was reset with Apple's app-scoped `tccutil` command. That reset grants no access. The owner has now approved the migration build’s stable identity.

## macOS 0.2.4 validation — 2026-10-16

At code commit `33be2cb`, all 28 core tests, 36 disposable native checks and 11 external Accessibility fixture checks passed locally. The native checks include one final frame write per arranged window, no writes for an unchanged reflow, asynchronous native restoration, four-way split/center behavior, grip commit/cancel, and oversized/refusing-window exclusion. Preview bounds now equal the final candidate geometry after source removal and minimum-size clamping. Native preview views and settings icons were rendered and visually checked; preview fill alpha is 0.18 so the destination remains visible through the overlay.

[GitHub compatibility run](https://github.com/AbdullahEgh/Bento-Layout/actions/runs/38890228259) passed on both macOS 15 and 26: core tests, universal build, startup, native interaction harness, and signed OTA fixture. Minimum supported macOS remains 15. Intel is cross-compiled, not runtime-tested on Intel hardware.

The installed 0.2.3 app successfully arranged four eligible windows while leaving one oversized window alone. With Dock/menu hiding enabled and edge snapping disabled, the corresponding macOS preference values changed as requested. Turning Bento off restored all five values exactly, including deleting keys originally absent. The temporary Dock/menu-hiding test choices were subsequently returned to off. A full login cycle has not been tested.

Menu-bar routing was reviewed: left-click and the shortcut use the same quiet toggle action, and right-click/Control-click opens the menu. The desktop-control tool is not approved for SystemUIServer, so a physical menu-bar click could not be automated. Physical drag routing retains the virtual-display limitations documented below. The separate external AX fixture proves native geometry writes, not physical pointer routing across arbitrary third-party apps.

[Release 0.2.4](https://github.com/AbdullahEgh/Bento-Layout/releases/tag/macos-v0.2.4), build 106, was published through the signed GitHub workflow. Its public ZIP and feed were downloaded and independently checked against the embedded Ed25519 public key; deep/strict code-signature verification passed and the executable contains arm64 and x86_64. Sparkle then installed it over 0.2.3 and relaunched `/Applications/Bento.app`; both the installed plist and app UI show 0.2.4. Windows `v0.3.6` remains the repository's latest release. The updated normal-launch app reports Accessibility blocked, so post-update desktop movement awaits re-enabling access. Installed settings icons were checked visually.

## Historical 0.2.0 validation


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

## 0.2.3 partial arrangement

26 core tests passed, including oversized-window exclusion, total-capacity overflow, edited-tree preservation, refreshed learned minima and invalid-input rejection. The 33-check native fixture passed with disposable windows only. New native cases cover known oversized windows receiving no writes, a native resize clamp being learned and rolled back, fitting windows remaining active, skipped-window movement surviving deactivation, reconsideration when a window fits again, and no persistent frame/preference changes when none fit, and a window that consistently refuses resize requests. The 11 external Accessibility checks also passed against the isolated fixture app. Physical drag routing retains the limitations documented above.

On the installed 0.2.1 process, direct Accessibility queries succeeded after restart (AXIsProcessTrusted true, AXWindows result success). Activation then failed on window capacity. This release addresses that failure rather than requesting additional permissions.

## Grabber visibility and Dock admission — 2026-10-16

35 core tests passed. The release app built and passed code-signature verification. The disposable native-window harness passed 66 checks, including pointer-polled hover visibility without mouse-enter events, hidden idle grips, click/drag visibility, full-display Dock restoration with least-recently-used eviction, stable subsequent reflow, and restoration of windows Bento did not previously minimize. Core regressions also cover multiple evictions, preservation of edited geometry when all windows fit, and an impossible incoming window leaving usable windows in place. Physical pointer routing and Dock clicks against third-party apps still need an interactive pass; the harness does not establish those results.

## Calmer admission, release notes and installer handoff — 2026-10-16

36 core tests and 71 isolated native checks passed locally. New coverage verifies exact idle-slot replacement with unchanged neighbor frames, one final write for incoming windows even with animations enabled, stopping after one correction when native windows refuse sizes, and installer completion retained across a blocked restore with duplicate clicks coalesced. The signed OTA fixture passed with embedded release notes and corruption rejection. The installed 0.2.11 updater was observed completing its earlier install after a delay; source changes remove its duplicate restoration and wait-before-cancellation paths. Real 0.2.12 installation and popup rendering will be verified after publication.

## Split and relocation QA — 0.2.13, 2026-10-16

A new native regression reproduced a valid drop returning to its old slot: the previous release treated a native frame rebound as cancellation even though a valid proposal remained and Escape was not pressed. The pre-fix harness failed that assertion; its trace ends with `cancel=true, candidate=true`. The corrected harness commits that same drop. Local evidence is in `artifacts/macos/split-qa/before/` and `after/`.

38 core tests and 81 isolated native checks passed locally. New coverage includes fast mouse-up before an intervening drag sample, stale AX focus with correct hit testing, committed geometry surviving membership refresh, held-pointer and queued-reconciliation races, transient missing live windows, source/target closure, Escape, final native border-resize samples, and portrait/landscape trailing edges. Every split direction keeps an identical cached candidate for 250 stationary samples, with one geometry build; repeated infeasible targets are cached too. A 200-sample stationary hold makes no additional native frame reads. Successful relocation writes each changed native window once even with animation enabled. The last native pass ran on the current portrait display.

Live transition tracing uses the local macOS `Interaction` log category without window titles or contents. This is evidence for supplied-pointer native checks, not a claim of physical pointer feel across third-party applications. The separate real AX fixture now has an isolated preference backend and journal so it cannot restore a live Bento session’s desktop overrides.

### 0.2.14 slot and resume regression QA

- Core suite: 40 passing tests, including saved display/slot identities, ratio retention, closed-leaf pruning, minimum refresh, floating insertion in both display orientations, and drops onto empty displays.
- Native controller and pointer-sampling harness: 89 passing checks. New cases cover stationary clicks on drifted frames, exact resume with a released window, stable background membership, floating-to-slot insertion, pre-drag restoration, overflow ownership across toggle, and one same-tree correction for a newly learned native minimum.
- Production tracing now includes requested and rejected native bounds; corrected gestures report the committed history rather than comparing stale minimum metadata.
- These pointer samples are supplied to the production interaction code using disposable native windows; they do not certify physical pointer routing in every third-party app. The release also includes separate process-scoped real Accessibility toggle and floating-membership checks.

### 0.2.15 relaunch continuation regression

The live 0.2.13 → 0.2.14 installation initially paused for restoration and subsequently completed through the updater. Reviewing the retry path identified an untested repeated Sparkle relaunch-delegate request after preparation: returning `true` with `installationPrepared == true` would discard its continuation and leave relaunch postponed. The delegate now returns `false` after preparation, allowing Sparkle to continue normally. The native harness exercises the first request, failed restoration, retry, successful continuation and second delegate decision.

Local 0.2.15 verification: 40 core tests and 91 isolated native checks passed. The updater checks now cover the repeated relaunch-delegate decision. External AX runs require the normal desktop manager to be closed so it cannot adopt or minimize fixture windows; runs made while it was active were rejected as interference, not counted as passing QA.

### 0.2.16 live desktop settings and adaptive workspace QA

- 46 core tests passed, including per-key live preference restoration, unchanged updates, manual OS choices, refresh failure recovery, and interrupted preference transitions.
- 111 isolated native checks passed. New checks cover coalesced and single-point gap changes, live margins and grabber geometry, desktop-drag deferral, held settings controls, rollback after a refused spacing write, live Dock/menu-bar/snapping and overflow settings, automatic adaptation to persistent native size changes, and cancellation during desktop updates.
- The planner tests cover reflowing fragmented slots before LRU eviction and excluding individually impossible apps before sacrificing usable windows.
- Separate-process Accessibility checks include live gaps and margins; real desktop preference and installed OTA checks are performed after publication. Fixture preference backends and settings persistence remain isolated from user configuration.
