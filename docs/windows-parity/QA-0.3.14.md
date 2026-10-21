# Windows experience QA — 0.3.14

Baseline: ca56e6e74e9d83d6adaf6cfa9744bc0af5dd84d6, paired Windows 0.3.13 / macOS 0.2.42. The Mac owner confirmed this was the latest authoritative source. Original Windows work at76cc4a6 is preserved separately.

## Findings and fixes

| Finding | Correction | Evidence |
| --- | --- | --- |
| The global toggle remained registered while its text field captured keys; an existing combination could activate Bento instead of being recorded. | Suspend registration during recording, commit on key release, restore on cancel/navigation/deactivation, and preserve the old binding on conflict. The field remains editable when the shortcut is disabled. | Native registration/conflict tests, recorder navigation regression, actual Computer Use keyboard capture of Ctrl+Alt+K followed by activation, and disabled-key verification. |
| The desktop background closed immediately when every member minimized. | Retain a hidden per-display background, fade out/in, reverse smoothly, and protect against stale fade callbacks. Desktop/session teardown still closes helpers immediately. | Real external-window minimize/restore regression and interrupted/repeated fade regression. |
| Custom controls hard-coded Apple blue and white accent text, ignoring Windows accent and contrast themes. | Use Windows accent with black/white text chosen by relative luminance, system contrast colors, Windows-shaped switches and visible keyboard focus. The tray uses the system renderer in contrast themes. | Dark Settings visual inspection, light/dark resource checks, accent foreground checks and 360-DIP responsive Settings test. |
| Drop preview acrylic ignored disabled Windows transparency and could retain an old backdrop after preference changes. | Honor the Windows preference, explicitly clear the native backdrop, and provide an opaque, readable contrast fallback. | Code-path review and existing native preview checks; physically changing OS accessibility settings was not part of this run. |
| Organizing cover was always dark and its spinner ignored reduced-motion/app-animation settings. | Follow OS light/dark/contrast appearance and stop animation when disabled. | Native organizing-cover regression and code-path review. |
| The shortcut field was below the initial view in Gestures. | Place Keyboard first and use direct Windows Settings headings. | Computer Use screenshot of the visible recorder and actual keyboard interaction. |
| A quick native caption drag remained outside the layout after release because its queued start sampled the already-moved frame. | Use the committed slot as a managed window's starting frame and capture the native release pointer before dispatch. | Actual physical drag failed before the fix and returned correctly afterward; queued-event regressions cover restoration, destination capture and undo. |

## Results

- Baseline native tests:192passed,0failed.
- Revised Release build:0warnings,0errors.
- Final native suite:197passed,0failed, including queued-event restoration, destination capture and undo.
- Portable core:43passed,0failed.
- Settings smoke:8passed,0failed. Existing settings were restored after inspection.
- Five external-process windows:7passed,0failed, including projected slots, split hold, native hit-through, placement and Windows Snap restoration.
- Physical input through Computer Use: recorded Ctrl+Alt+K, enabled it, observed Off→Active, disabled it, pressed it again and observed Active unchanged. The settings file independently showed disabled with the recorded combination.

Source logs in the owning PC checkout: qa-baseline-native.log, qa-build.log, qa-native.log, qa-core.log, qa-settings-final.log, qa-five.log.

Physical replay used five arranged external windows. Dragging the first caption from relative(200,15) to(400,300) moved it from(8,8,655,551) to(208,293,655,551). Before the fix, it remained displaced six seconds later. After the fix, the native observer recorded the same start/end movement and the frame returned to(8,8,655,551). Evidence: qa-physical-drag-failure.json and qa-physical-drag-fixed.json. Cross-window physical swap could not run because Computer Use rejected the end point outside the source window; no physical swap/long-hold pass is claimed.

## Remaining QA coverage

This is a verified fix batch, not complete parity sign-off. Physical long-hold divider/window dragging, Task View transitions, mixed-DPI hardware, third-party application sizing, actual OS contrast/transparency changes and OTA replacement/restart still need direct validation. Native fixtures exercise real external HWNDs but do not establish all of these behaviors. Earlier native resize timing uncertainty remains documented in the previous audit. Mac 0.2.42 is unchanged.

Windows design references: [Color in Windows](https://learn.microsoft.com/en-us/windows/apps/design/signature-experiences/color), [Contrast themes](https://learn.microsoft.com/en-us/windows/apps/design/accessibility/high-contrast-themes).
