# Local Windows port status — 2026-10-18

**Source port in progress, uncompiled and not release-ready. No Windows runtime validation is claimed.**

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

## Parity checklist

Everything in the implementation column below is source-reviewed only until C# compilation and Windows tests run. Existing ACCEPTANCE.md entries remain unchecked.

| Acceptance area | Implemented locally | Remaining / exact limits |
| --- | --- | --- |
| L05, R04: quit/update | Preserve live frames/minimization; invalidate queued work before teardown; flush pending ordinary preferences without applying geometry | Added ordinary-quit and live-grip quit regressions; update/restart, queued events and pending-settings close need live Windows checks |
| L02–L04, L06: session memory | No automatic `saved-layout.json` read/write; legacy file untouched; Save/Use/Clear for This Session; saved Off preserves placements; explicit Restore still restores originals; reconcile HWND+process ownership, minima and display removal | Desktop-specific ownership, released/overflow state across re-enable, same-process HWND reuse and full session isolation still need work; no complete session-parity claim |
| C02–C06: feasibility/admission | Try retained geometry and both-axis/grouping search before eviction; bounded Pareto search for up to eight apps; priority admission evicts least recently used; reuse a feasible evicted slot; impossible incoming app does not displace a valid layout | Native accepted-frame/minimum learning, hung/refusing-app repair, larger difficult arrangements and real taskbar restore admission unverified; membership still reconciles once per second |
| W02, G02/G09/G10: joined geometry | Derive local/shared seams, including partial groups, without moving windows; preserve coincident seams from a reference tree on work-area changes; invalidate reference on unrelated commits/settings changes | Taskbar lease and full repeated work-area transaction behavior not implemented; multi-monitor/DPI changes require runtime tests |
| G01/G03/G05–G08/G11: grips/resize | 80-DIP specific pills; segmented shared ink at 45% with local pills at 100%; pointer-down selects an equivalent tree; exact seam snap; native border chooses smallest equivalent section | Selective new-join cue still missing; physical mouse/touch capture, minimum clamps, occlusion and Z order unverified; native-border snap threshold still uses physical pixels |
| D03–D06/D08/D09: drag/preview | Physical-screen edge section movement; cache valid and invalid proposals for a gesture; neutral text/icon-free slot preview with temporary display dim; native drag of excluded windows suppresses grips, including own Settings events | Neighbor-slot previews, full invalidation on external identity/minimum changes and physical edge/cancel/Task View behavior incomplete/unverified |
| U05/U08: motion/efficiency | Minimum-jerk easing; new default 140 ms preserves saved duration; cached equivalent handles per display; avoid unchanged preview dim writes and repeated acrylic setup | Return/cancel timing, native batch behavior, resource/frame/input measurements and long-session profiling outstanding |
| R01/R02/R03: update discovery | Read latest 100 releases; use explicit Windows version metadata for shared tags; preserve legacy Windows-tag support; verify metadata and ZIP digests, and ZIP manifest version against selected release; local packaging/workflow edits include sidecar | Legacy Windows-tagged bootstrap release still required; none published. Actual build, metadata asset hashes, both-platform packaging, install/restart and rollback unverified |
| P01–P11: Pause/desktops/fullscreen | No new implementation | Per-member Pause dimming and single-click focus, resume minimization, per-virtual-desktop state, Task View/lock transitions and fullscreen reservations remain missing |
| U01–U04, W01/W03–W08 | Session controls added; Off labeled accurately instead of pretending to be Pause | Taskbar override journal/hiding, consumed long press, compact Pause-first tray, About/onboarding and complete Settings parity remain missing |
| C07–C10/G12 | Existing native controller retained | Native frame/cell-rounding fit and acceptance repair, selective join feedback and platform API adapters remain to implement |

## Test and review evidence

- `git diff --check`: PASS after source edits.
- All project XML, solution XML and project-reference paths: PASS static checks. Production controller has no `SavedBentoLayout.Load` or `SavedBentoLayout.Capture` calls. No Mac source or shared fixture changes.
- `dotnet build Bento.slnx -p:EnableWindowsTargeting=true`: BLOCKED, exit 127, `command not found: dotnet`.
- `dotnet run --project tests/Bento.Core.Tests/Bento.Core.Tests.csproj -c Release`: BLOCKED, exit 127, same error. No SDK installed.
- New pure regressions cover transposed grids, partial joins, local/group hit selection and DPI range, minima-safe snapping, native local resizing, cache keys, ink gaps, identity reconciliation, section moves, repeated reflow, capacity/LRU admission, idle-slot preservation, release version/digest selection and motion endpoints. They have **not run**.
- Native regressions added for quit preservation and session-save Off/Use/Restore. Existing grip expectations updated to 80 DIPs. They have **not run**.
- Mac reference core was copied into `/tmp/bento-parity-reference` with a dependency-free temporary package; repository Mac sources unchanged. First full run: 91 passes, one failure because the temporary package lacks Sparkle's `sign_update` executable. Rerun excluding `testOfficialSparkleArchiveSignatureAndCorruptionRejection`: **91 tests passed, zero failures**. Logs: [full attempt](evidence/mac-reference-full.log), [filtered successful run](evidence/mac-reference-core.log). This validates only unchanged Mac reference tests, not C# or Windows.
- Swift caches were redirected into `/tmp`; no SDK, signing identity, account credential or application installation was created. No push, PR, remote CI or release action occurred. Workflow edits are local text only.

## What remains possible without .NET

Not all further progress is blocked. Pure native-frame fitting/rounding rules, selective join-cue selection, richer session-state reconciliation, UI/tray state models and metadata/transaction fixtures can still be implemented and statically reviewed. Pause and taskbar/desktop capability adapters also need design and source work. Current changes should be compiled before adding more coupled native lifecycle behavior; claiming those areas complete from source review would be misleading.

The concrete external blockers are fresh Git/PC baseline access and compilation/runtime validation. Required next commands once a build-capable environment is authorized/available:

```sh
dotnet run --project tests/Bento.Core.Tests/Bento.Core.Tests.csproj -c Release
```

On an interactive Windows 11 environment, with disposable fixtures and no competing Bento manager:

```powershell
.\build.ps1 -NativeTests
.\tests\Bento.Tests\bin\Release\net10.0-windows\Bento.Tests.exe --settings-order-smoke
```

Then verify physical grip/local/group behavior, native border and screen-edge moves, explicit saved Off versus Restore, pending preferences on quit, normal and held-grip quit/update with overflow, own Settings drag suppression, mixed DPI and preview layer ordering. Packaging/update tests require a locally built ZIP and metadata; no remote CI is necessary. Fetch/rebase and compare with the PC checkout before integration. Release versioning, a legacy bootstrap and publishing remain outside current authorization.

## Supported conversation evidence

The supported inventory identifies **Show grabber and free Bento space**, ID `01a1460f-0560-7141-8155-cc6ff1a1fdbb`, host `local`, under the same Vibe Coding project directory. Its readable history includes the user's Mac grabber/overflow request and the generation/commit of this repository's parity handoff at `bd11c97` on `codex/macos-native-preview`. Direct checkout reads reconfirmed that branch and commit. This is evidence of Mac development context, not proof that it is the only owner or that no later private work exists.

Prior planning chat: **Plan macOS Bento Layout port**, `01a1423f-c903-7281-a75e-5b8c236e9380`, host `local`. Windows development owner was not identified in supported inventory. No private session-storage files inspected, no owner invented, and no messages sent to those chats.
