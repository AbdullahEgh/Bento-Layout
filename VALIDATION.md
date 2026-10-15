# Validation — 2026-10-16

Actual execution on this Windows x64 desktop, OS build `10.0.26200.0`, using a workspace-local Microsoft .NET SDK `10.0.402`. The machine initially had .NET runtimes but no SDK. The official SDK was downloaded into `.tools/dotnet`; it is not part of the release.

| Check | Actual result |
| --- | --- |
| Release solution build, warnings treated as errors | Passed: 0 warnings, 0 errors |
| Deterministic engine/geometry/gesture/updater suite | 78 passed, 0 failed |
| Full suite with native desktop integration | 105 passed, 0 failed |
| Hold-to-split | All four directions, hold threshold, boundary jitter, target change and cancellation pass deterministic checks; production-controller hold changes real HWND placement |
| Quick edge drop | Passed: swaps before the hold threshold without splitting |
| Update transaction | Hash validation, traversal rejection, duplicate filename rejection, successful replacement and failed-startup rollback pass with temporary files |
| Snap takeover lifecycle | Original-value restoration and crash recovery pass with an injected system-setting backend; actual system mutation is not performed by the automated suite |
| New interface | Workspace, Gestures and Updates open and render; light/dark artifacts captured and inspected |
| Transition cleanup | Passed: temporary DWM hosts close after the animation |
| Automatic three-window native placement | Passed on activation: three distinct external WPF processes; actual DWM frame bounds match engine rectangles within 2 px |
| Interactive five-window placement | Passed: five distinct external fixture processes, with all five actual desktop bounds matching their assigned regions |
| Automatic distribution of 1–12 windows | Passed deterministic constraint and no-overlap checks |
| Direct region center swap and edge split | Passed via production controller; all windows retained and actual HWND bounds verified |
| Automatic open/minimize/restore/close handling | Passed using a fourth disposable process; minimized window remained minimized |
| Preserving customized ratios when membership is unchanged | Passed |
| Releasing a window and including it again with Auto arrange all | Passed |
| Global shortcut registration/release | Passed outside the development sandbox |
| No blueprint at rest | Passed: native windows arranged directly, no full-screen interaction layer and no visible drop preview |
| Application focus preserved | Passed across desktop arrangement |
| Desktop helper bounds | Passed: resize helper windows occupy only gaps, not application content |
| Single destination preview | Passed: exactly one target rectangle during a valid drag, hidden on cancellation; PNG rendered |
| Stable drop-zone preview | Passed: repeated pointer movement reuses its preview snapshot without moving external windows; changing/leaving a zone or starting another gesture invalidates it |
| Physical native title-bar drag | Center swap and left-edge split observed with three external fixtures at 200% DPI, using Windows' maximized-title-bar drag-out gesture; actual bounds matched committed layout |
| Native window border resizing | Passed: native size change translates to ancestor splits and updates neighboring HWND geometry |
| Cancel gesture without HWND movement | Passed |
| Divider commit, undo/redo, removal/expansion, restore all | Passed |
| Published application launch with `--smoke` | Passed: process exited with code 0 after two seconds |
| Framework-dependent publication | Produced `artifacts/Bento` and `artifacts/Bento-win-x64.zip`; approximately 300 KB uncompressed, excluding the .NET runtime |

The sandboxed native run initially exposed an environment limitation: `RegisterHotKey` returned Windows error 5 (access denied). The same registration check passed outside the sandbox. The complete suite now contains 105 checks. Version 0.3.0 retains the earlier drag-query and preview caching optimizations and adds hold gestures, transitions, interface and updater coverage.

One 0.3.0 test run loaded the application class to obtain styles, which also triggered the normal manager startup. This was corrected by loading only `Theme.xaml` into an isolated test Application. The final native run uses the fixture-only discovery source and passes all checks.

A new physical title-bar center-swap was verified at 225% DPI with matching native bounds, saved in `artifacts/physical-drag-0.3.0.json`. The desktop automation API cannot hold at the end of its drag operation, so it cannot independently prove the new timed gesture end to end. The hold timer and resulting native split are covered together by controller integration tests. The user was provided a replayable three-window session for direct hold testing.

During this revision, native geometry checks initially failed intermittently because an older Bento process was still running from `artifacts/Bento-win-x64/Bento.exe` and rearranging fixture windows once per second. Temporary diagnostics identified that competing process; it was stopped before final verification. Native tests now fail early if another Bento process is running. Temporary diagnostics were removed.

The automated tests use disposable fixtures and restore/close them; they do not arrange existing user applications. Integration tests supply gesture positions to the production controller and verify native effects. They also resize a fixture through native window control before applying the resulting neighbor reflow. They do **not** prove physical mouse capture or an actual key chord dispatch. A separate physical desktop session confirmed center swapping and left-edge splitting through native title-bar input; its final fixture bounds are saved in `artifacts/physical-drag-session-1.json`. Border/grip input attempts were inconclusive, so those paths are not claimed as physically verified. The published application's isolated startup smoke check uses an empty discovery source.

MindSpace's connected capabilities tool was called twice and returned `-32603: Internal error` both times. No MindSpace data was changed. Exact parity with its private auto-layout behavior remains unverified; the Windows implementation follows the user's stated automatic distribution, dragging and drag-to-split requirements, with zoom omitted.

## Requires further interactive Windows verification

- Right/top/bottom physical native title-bar drops, border resizing, gap-grip mouse capture, native Escape cancellation, and global shortcut activation. The single-target preview must remain click-through in those gestures.
- Two or more physical monitors with different DPI, negative origins, rotation, docking/undocking, resolution changes and taskbar changes. Negative-origin and odd-size arithmetic are covered by deterministic tests; hardware transitions are not.
- Elevated/protected applications, applications with unusual frames, asynchronous geometry handling, or changing minimum-size policies. The MVP rejects reported failures and attempts rollback.
- Long sessions, screen lock/unlock, remote desktop reconnection, and performance with many application windows.
- End-to-end installation through the separate updater process, release downloads from a published GitHub release, actual Windows Snap takeover, and subjective animation quality across heavy applications need additional interactive validation. Transaction/rollback tests do not imply publisher signing or online release availability.

## Deliberate milestone limits

- Layouts and undo history last for the running session; only settings are persisted.
- No installer, auto-start integration, virtual-desktop model, profile recovery, or application groups.
- WM_GETMINMAXINFO is bounded to 40 ms per queried window; an unresponsive application falls back to a conservative scaled minimum. An application may still refuse the resulting dimensions.
- Native apply/rollback is sequential, rather than a cross-process atomic transaction. Rollback can fail if a process exits or denies access. Cross-DPI commits may need two native moves to account for new frame metrics.
- Restoring a recycled HWND belonging to another process is skipped. Attempting to manage such a reused session handle produces a restart-Bento message.
- The platform-independent engine is `net10.0`; the included test executable and UI/native integration target Windows.

Reproduce with `build.ps1 -NativeTests -Publish` on an unrestricted interactive Windows desktop. Test output is authoritative; `dotnet test` does not run this dependency-free executable harness.
