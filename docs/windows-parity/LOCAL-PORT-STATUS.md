# Local Windows port status — 2026-10-18

**Local source port and targeted static review complete; uncompiled and not release-ready. No Windows runtime validation is claimed.**

## Checkout and baselines

- Isolated clone: `/Users/abdullah/Documents/Codex/2026-10-18/task-2/Bento-Layout`, branch `windows/mac-parity-local`, based on `bd11c97b3f82f2a8234d40d69d2fd44186244c24`.
- Original checkout: `/Users/abdullah/.codex/.chatgpt-projects/g-p-6ac8a40539bc819197b2c7f3eafc27eb/Bento-Layout`, still on `codex/macos-native-preview` at `bd11c97`. Its only dirty file remains `VALIDATION.md`; it was not edited or copied over. No running Bento application was operated.
- Published Mac baseline independently confirmed by the [0.2.40 release page](https://github.com/AbdullahEgh/Bento-Layout/releases/tag/macos-v0.2.40): `7925944343da9c250862c78abb988b9e08835240`. The page describes local/group grips and preserving frames/minimized apps on quit/update. The release index lagged at 0.2.39, so absence of a newer Mac release is **not certified**.
- [GitHub latest](https://github.com/AbdullahEgh/Bento-Layout/releases/latest) redirected to Windows `v0.3.9`, commit `eae0eda`, an ancestor of this checkout. This checkout's last Windows source changes before this task were at that commit.
- Initial HTTPS clone and a later `git ls-remote https://github.com/AbdullahEgh/Bento-Layout.git HEAD` both failed with exit 128:

```text
fatal: unable to access 'https://github.com/AbdullahEgh/Bento-Layout.git/': Could not resolve host: github.com
```

The web tool could read the release pages but could not fetch the branch tree (`Failed to fetch restricted URL`) or commits endpoint. Therefore fresh branch heads, unpublished PC changes and remote conflict status remain unknown. No permission expansion attempted. The clone's `origin` points at the existing local checkout, not GitHub.

## Local implementation milestones

- `b4b77e1` preserved unchanged: quit/update keeps current native frames and minimized state, including held grip geometry. Disposal is idempotent; timers/queued callbacks/capture loss cannot resume arrangement or roll windows back.
- `354031e`: pure C# equivalent-tree seams, deterministic alternate IDs, local versus group hit selection with DPI-scaled local range, cache invalidation, exact feasible snapping, local native-border resize, section moves, seam-preserving work-area reflow, bounded capacity search, session snapshots and release metadata parsing. Includes a portable .NET-only regression executable alongside the existing Windows harness.
- Integration after that commit wires these modules into WPF/Win32. See the final local branch head for the integration commit. No binary version bump or package was produced.

## Final source parity checklist

Source review is complete for this local implementation. **Compilation, native behavior and acceptance certification remain pending.** All ACCEPTANCE.md runtime cases remain unchecked.

| Area | Local source implementation | Validation still required |
| --- | --- | --- |
| Layout/admission | Equivalent local/group seams, exact feasible snap, native border resize, edge section moves, seam-preserving reflow, bounded capacity/LRU search, retained edits and idle-slot reuse | Native mouse/touch, refusing/hung apps, large layouts, mixed DPI |
| Grips/preview | 80-DIP pills, shared/local opacity, selective joining cue, cached accepted/rejected previews scoped to workspace, sibling-close invalidation | Capture/cancel, occlusion, Z order, timing and resource measurements |
| Sessions/persistence | Desktop-scoped history, original/minimized ownership, exclusions, session Save/Use/Clear, remembered geometry, overflow and fullscreen reservations | Actual desktop switching, pinned windows, handle reuse and app restoration |
| Quit/update | Preserve current frames/minimization including live resize; stop callbacks before WPF close; flush latest preferences without geometry | Real quit/update/restart and pending UI callbacks |
| Pause | Per-member pass-through tint, click/focus reveal, resume floating-window minimization and held admission | Physical first-click delivery, focus/Z order, app-specific behavior |
| Native fitting | Bounded cell slack, inward correction, independent minimum hints, bounded seam repair and settled retry | Actual native constraints and post-settle frames |
| Shell | Real desktop GUID probe, membership gates, Task View/lock deferral, taskbar owned-bit lease and durable recovery | Windows COM/PInvoke compilation, Explorer restart, taskbar/multimon journal recovery |
| Settings/tray | Compact Pause/OnOff/taskbar/Undo tray, consumed long press, session actions, onboarding/About, deferred settings, DIP spacing, minimum-jerk motion | Interactive Windows UI and accessibility smoke tests |
| Releases | Explicit Windows sidecar version/digest, legacy tags, ZIP manifest checks; local packaging/workflow text | Build/package hashes, install/rollback; legacy bootstrap and publishing outside authorization |

Public Windows APIs do not provide a universal Task View/fullscreen transition event. A presentation with no observable native frame/style change cannot be distinguished from the previous window state. Unknown/shared desktop identity defers writes. The new invisible desktop probe and pinned-window behavior require real Windows verification; simulated fixtures are not proof of those capabilities.

## Final review and evidence

- Preserved commits: `b4b77e1`, `354031e`, `f828dcf`, `15f6db4`; the final review commit follows these on the same branch.
- Reviewed controller entry points: membership/create/destroy, incoming drag and native resize, shared grip release/cancel, fullscreen projection/return, Off/Restore, work-area changes, deferred preferences, quit/update/session-ending, callback disposal and shell ownership.
- Fixed repeated overflow rebuilding, original-position restoration, stale handles/history, fullscreen writes while Off, per-desktop queued work, preference ordering, sibling-close proposal caches, final resize fullscreen inference, provenance on Settings/rollback paths, partial construction cleanup, native callback exceptions, probe leaks and shutdown ordering.
- Added pure regression fixtures for workspace-scoped positive/negative caches and own-frame fullscreen classification. Added native sibling-close preview regression alongside quit, Pause, simulated desktop/fullscreen and session cases. **No C# regression has run.**
- `git diff --check` and project/solution XML/reference checks pass. Mac source/shared fixtures remain unchanged.
- `dotnet build Bento.slnx -p:EnableWindowsTargeting=true` and portable regression command are blocked with exit 127: `dotnet` is absent. No SDK installed.
- Unchanged Mac reference tests: 91 passed, zero failures after excluding Sparkle archive-signature test requiring absent `sign_update`. The full attempt had that one failure. Logs: [full](evidence/mac-reference-full.log), [filtered](evidence/mac-reference-core.log). This does not validate C# or Windows.
- No remote writes, CI dispatch, PR, release, credentials, installation or running Bento operation occurred.

## Exact remaining blockers and commands

Fresh GitHub/PC baseline access remains unavailable (DNS failure above); compare/fetch before integration. A .NET 10 build environment and interactive Windows 11 fixture environment are required:

```sh
dotnet run --project tests/Bento.Core.Tests/Bento.Core.Tests.csproj -c Release
dotnet build Bento.slnx -p:EnableWindowsTargeting=true
```

```powershell
.\build.ps1 -NativeTests
.\tests\Bento.Tests\bin\Release\net10.0-windows\Bento.Tests.exe --settings-order-smoke
```

Then execute the acceptance checklist for physical grips/native resize, desktop/Task View/lock/pinning, fullscreen, mixed DPI, taskbar recovery/manual overrides, Pause click delivery, overflow, session Off/Restore, and quit/update while dragging or editing preferences. Build and verify ZIP/sidecar locally before any installation test. Remote CI and publication require separate approval.

## Supported conversation evidence

The supported inventory identifies **Show grabber and free Bento space**, ID `01a1460f-0560-7141-8155-cc6ff1a1fdbb`, host `local`, under the same Vibe Coding project directory. Its readable history includes the user's Mac grabber/overflow request and the generation/commit of this repository's parity handoff at `bd11c97` on `codex/macos-native-preview`. Direct checkout reads reconfirmed that branch and commit. This is evidence of Mac development context, not proof that it is the only owner or that no later private work exists.

Prior planning chat: **Plan macOS Bento Layout port**, `01a1423f-c903-7281-a75e-5b8c236e9380`, host `local`. Windows development owner was not identified in supported inventory. No private session-storage files inspected, no owner invented, and no messages sent to those chats.
