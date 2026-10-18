# Local Windows port status — 2026-10-18

Partial implementation; **not feature parity or a validated Windows build**.

## Baselines and preservation

- Isolated local clone: `/Users/abdullah/Documents/Codex/2026-10-18/task-2/Bento-Layout`, branch `windows/mac-parity-local`, starting at `bd11c97b3f82f2a8234d40d69d2fd44186244c24`.
- Original checkout: `/Users/abdullah/.codex/.chatgpt-projects/g-p-6ac8a40539bc819197b2c7f3eafc27eb/Bento-Layout`. Its uncommitted `VALIDATION.md` edit was left untouched. No running Bento app was operated.
- Verified published Mac release: [macos-v0.2.40](https://github.com/AbdullahEgh/Bento-Layout/releases/tag/macos-v0.2.40), source `7925944343da9c250862c78abb988b9e08835240`. Direct release page confirms quit/update preservation and local/group grips. The web release index lagged at 0.2.39, so latest Mac status cannot be certified solely from that index.
- [GitHub latest](https://github.com/AbdullahEgh/Bento-Layout/releases/latest) redirects to Windows `v0.3.9`, commit `eae0eda`, which is an ancestor of this checkout. Latest Windows source changes in this checkout are from that commit.
- Fresh Git fetch/clone failed: `Could not resolve host: github.com`. No permission expansion attempted. Remote unpublished/new branch changes remain unknown. Review/rebase against fresh remote and the PC checkout before integration.

## Concise parity checklist

| Feature | Local result | Validation |
| --- | --- | --- |
| Quit/update preserve frames and minimized apps | Implemented in `BentoController.Dispose`; updater already calls application shutdown | Two native regression cases added, not executed |
| Quit during a live grip gesture | Discard rollback snapshots; stop timers and invalidate queued callbacks before helper teardown | Regression requires actual moved frames before disposal and unchanged frames afterward; not executed |
| Explicit Off / Restore originals | Existing RestoreAll path retained | Existing native tests, not executed here |
| Equivalent local/group grips, partial groups, snapping/rejoin and cache | Missing; source map in IMPLEMENTATION.md | Not implemented or verified |
| Layout reflow, native minima/rounding, section-edge moves | Existing Windows behavior differs from Mac contract | Not ported or verified |
| Session-only automatic/explicit layout saves | Existing disk load/save remains | Not ported; legacy files untouched |
| Pause/resume, dimming and click-through focus | Missing | Not ported |
| Per-desktop state, Task View and fullscreen reservations | Missing/incomplete | Requires Windows API work and interactive validation |
| Taskbar lease, long press, updated settings/onboarding and motion | Missing | Not ported |
| Cross-platform release selection | Existing parser only handles Windows version tags | Not changed; latest presently points to compatible v0.3.9 |

## Patch behavior

Quit no longer calls RestoreAll. It marks the controller disposed first, stops sampling, clears the gesture without native rollback, and then releases helpers, transitions, hooks and the snap lease. Queued dispatcher work checks disposal again at execution; hotkey, timer, settings-close and drag callbacks cannot resume arrangement after teardown. Disposal is idempotent. Settings save behavior and explicit Off remain separate. README exit semantics updated.

## Validation and blockers

- `git diff --check`: PASS.
- `dotnet build Bento.slnx -p:EnableWindowsTargeting=true`: BLOCKED, exit 127 (`command not found: dotnet`). No SDK at standard install locations. No SDK installed under this task's no-permission-expansion scope.
- No C# compilation or automated test pass claimed. No Mac sources changed. Mac tests would not establish correctness of this Windows patch.
- Required next environment: .NET 10 SDK for compilation; interactive Windows 11 for `./build.ps1 -NativeTests`, the two added shutdown tests, update/restart validation, settings-close pending changes, queued native events, mixed DPI, and actual mouse/touch capture loss. A local Windows run needs no remote CI; no remote run was requested.
- Full parity implementation remains blocked on a fresh remote/PC baseline plus build-capable environment. This focused patch is reviewable but not release-ready. No push, PR, remote CI, release, credentials or remote mutation occurred.

## Supported conversation inventory

- Mac development: **Show grabber and free Bento space**, `01a1460f-0560-7141-8155-cc6ff1a1fdbb`, host `local`.
- Prior Mac planning: **Plan macOS Bento Layout port**, `01a1423f-c903-7281-a75e-5b8c236e9380`, host `local`.
- Windows development owner: not identified in supported inventory. No private session-storage files inspected and no owner inferred.
