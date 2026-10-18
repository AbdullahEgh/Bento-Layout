# Source review checkpoint

Work continues from `f828dcf` on `windows/mac-parity-local`. This checkpoint is **not completion, a compiled Windows build, or a claim that every remaining task is blocked**.

Implemented in source during this continuation:

- Core native-frame acceptance, one inward correction, independent learned minimum hints and bounded seam-alignment proposals.
- Pause state, first-click observation without consuming input, per-member pass-through tint, resume minimization and held admission until taskbar restore.
- Desktop-scoped history, originals, ownership, exclusions, saves, interaction recency and fullscreen references. A verified shell probe obtains real desktop GUIDs; unknown/shared identity defers writes. Native writes validate process and desktop membership.
- Fullscreen reservation/projection/return; distinguish maximization and Bento's own full-sized allocation from a detected presentation transition. Modes with no observable native frame/style change remain a capability limitation.
- Taskbar autohide bit ownership, durable recovery journal, compare-before-restore, preservation of unrelated/manual changes, and stable work-area sampling.
- Selective connected join cues with unchanged local/shared opacity hierarchy; compact Pause-first tray and consumed long press.
- Session controls, deferred settings, onboarding/About, DPI-scaled spacing and snap distances.

New focused tests are in `tests/Bento.Tests/PlatformParityTests.cs`, linked into the portable core harness. Additional Windows fixture regressions cover Pause/resume, a simulated desktop switch during a held grip and simulated fullscreen return. **No C# test has run.**

Earlier source issues found and fixed in this continuation include repeated overflow tree rebuilding, restoring overflow to its last Bento position instead of its original position, recycled-handle history/snapshot invalidation, accidental movement while Off during fullscreen return, stale per-desktop queued callbacks, and pending preferences lost or reordered on shutdown.

Review is still in progress. Before any completion claim, finish these checks/fixes:

- Invalidate all gesture proposal caches when another member closes; review native resize/grip cancellation and fullscreen inference at the final release sample.
- Verify close/minimize fast-path reapplication, fullscreen/reference reconciliation and deferred settings paths through every controller entry point.
- Review callback exceptions, pointer-hook lifetime, invisible desktop probes and taskbar journal recovery/verification failures.
- Add remaining targeted regressions where those reviews expose defects; update LOCAL-PORT-STATUS.md to reflect the final source state.
- Compile both core and Windows targets and run the regression harness once tooling is available. New native code, UI, COM definitions and P/Invoke layouts remain uncompiled.

Tool state: tools are responsive, no execution call is stuck. `dotnet` is absent from PATH and the searched existing installation locations. No SDK installed. `git ls-remote https://github.com/AbdullahEgh/Bento-Layout.git HEAD` previously failed with `Could not resolve host: github.com`; fresh remote/PC baseline remains unknown. No remote writes, CI dispatch, PR, release or installed Bento operation occurred. Mac sources remain untouched.
