# Implementation and verification plan

## Establish the actual PC baseline

Fetch `origin/codex/macos-native-preview` and read `docs/windows-parity/`. Inspect branch, dirty files and unpublished PC commits before integrating. The Mac checkout's Windows sources may be older than the PC chat's working tree. Preserve both. Record Windows baseline commit, installed version, OS build, display/DPI configuration and actual available capabilities. Record requirement status in ACCEPTANCE.md or a companion evidence report: not started, implemented, automated verified, live verified, blocked with fallback.

Do not make the user repeat product decisions already resolved in EXPERIENCE.md. Clarify only genuine conflicts or unavailable capabilities. No claim of full parity until every requirement has evidence or an explicit accepted platform limitation.

## Source-to-source map

Paths below are relative to repository root; read the source at baseline `7925944` when later Mac changes make comparison ambiguous.

| Behavior | Mac reference | Existing Windows starting point |
| --- | --- | --- |
| Tree, geometry, history | `macos/Sources/BentoCore/Layout.swift`, `Workspace.swift` | `src/Bento.Core/Layout.cs`, `Geometry.cs`, `Workspace.cs` |
| Recent-first capacity/admission | `AutoLayout.swift`, `CapacityPlanner.swift` | `src/Bento.Core/AutoLayout.cs`, `src/Bento.UI/BentoController.cs` |
| Reflow preserving joined seams | `LayoutReflow.swift` | New pure C# reflow module alongside core layout |
| Equivalent local/shared handles | `ResizeHandles.swift`, `ResizeHandleCache.swift` | `src/Bento.UI/DesktopDividerWindow.cs`; add pure C# handle calculation/cache |
| Snap, native resize, section move, drop proposal | `Interaction.swift` | `src/Bento.Core/DragIntent.cs`, `SlotPreview.cs`; `BentoController.cs` |
| Cell rounding/accepted size | `NativeFrameFit.swift`, `NativeSeamAlignment.swift` | `src/Bento.Windows/WindowController.cs`, `WindowCatalog.cs` |
| State, session, admission, work-area baselines | `macos/Sources/BentoMac/WorkspaceController.swift` | `src/Bento.UI/BentoController.cs`, `SavedBentoLayout.cs` |
| Native discovery/focus/minima/motion | `WindowSystem.swift` | `src/Bento.Windows/Native.cs`, `WindowCatalog.cs`, `WindowController.cs`, `DesktopEvents.cs` |
| Desktop identity/overview/fullscreen | `DesktopIdentity.swift`, `DesktopOverviewMonitor.swift`, controller reservations | New Windows capability adapter; discovery/controller integration |
| Grips, pointer lifecycle and slot previews | `DesktopInteractions.swift` | `DesktopDividerWindow.cs`, `DropPreviewWindow.cs`, controller drag paths |
| Dim/Pause/z-order | `DesktopBackdrop.swift` | `DesktopBackdropWindow.cs`, `WindowAppearance.cs`, controller |
| OS overrides/journal | `BentoCore/ActivationOverrides.swift`, `BentoMac/DesktopPreferences.swift`, `NativeDesktopVisibility.swift` | `src/Bento.Windows/WindowSnapping.cs`; add taskbar/session lease |
| Settings, chrome, onboarding | `SettingsView.swift`, `Onboarding.swift`, `Design.swift`, `Glass.swift` | `BentoWindow.cs`, `Settings.cs`, `AppTheme.cs`, `Theme.xaml` |
| Tray press/icons/menu | `BentoApp.swift`, `StatusIcon.swift`, `BentoCore/StatusPress.swift` | `TrayInterface.cs`, `AppIcons.cs`, `Symbols.cs` |
| Motion | `BentoCore/Interaction.swift` WindowMotion, native batch transition | `Bento.Core/Motion.cs`, `Bento.UI/DesktopTransition.cs`, `WindowThumbnail.cs` |
| Update and shutdown | `MacUpdater.swift`, `BentoApp.swift`, controller shutdown | `UpdateService.cs`, `Bento.Updater/Program.cs`, `BentoController.Dispose`, `App.xaml.cs` |
| Shared fixtures | `macos/Tests/BentoCoreTests`, smoke files | `tests/Bento.Tests`, `shared/fixtures/layout-v1.json` |

## Observed gaps in the repository Windows baseline

This is a source audit, not an assertion about unseen PC changes:

- `SavedBentoLayout.cs` writes/reads persistent `saved-layout.json` using path/title matching. Desired automatic and explicit layout memories are session-only; keep legacy file intact, migrate behavior without losing ordinary settings.
- `BentoController.Dispose()` calls `RestoreAll()` when automatic. Quit/update must instead preserve live geometry and minimized states; explicit Off/Restore retain restoration behavior.
- `TrayInterface.cs` has Arrange, Redo, Release, What's New and Updates in the primary menu, and a simple left-click toggle. Add Pause-first compact order, state icons and consumed long-press behavior.
- `Settings.cs` has no taskbar hiding or Pause state and defaults to 180 ms motion. Add session-scoped hiding/state; preserve saved timing. Do not serialize hide/Pause/layout state into next-launch settings.
- Existing divider generation does not contain the new equivalent-tree C# modules. Port geometry, hit selection, snap/rejoin and caching before changing visuals.
- Existing Windows README describes one-second membership updates, 40-DIP/2-DIP grips, persistent layouts and restoration on exit. Rewrite these descriptions only after implementing/verifying the replacement behavior.
- Existing HWND, min-track, DWM frame, DPI, updater and rollback code are useful foundations. Reuse them; audit their invariants rather than replacing them wholesale.
- Confirmed OTA compatibility gap: `UpdateService.CheckAsync` requests only `/releases/latest`; `ParseRelease` strips only `v`/`V` and parses the remaining tag as a Windows version. Consequently `macos-v0.2.40` is ignored even when it carries a Windows ZIP. Existing installations cannot receive a fix that relies solely on the new parser. Bootstrap with a newer Windows-compatible `v<WindowsVersion>` release selected as latest, containing both platform downloads; keep the existing Mac signed feed/archive intact. Test the old parser against the exact proposed release JSON before publishing. After that bridge, implement explicit Windows metadata and release-list selection so later Mac releases do not hide Windows updates. Do not claim OTA compatibility until this path is tested.

## Windows API boundaries to validate on the PC

Use documented APIs where possible, isolate interop and keep calls bounded. These are implementation starting points, not proof of behavior on every shell build.

- [IVirtualDesktopManager.IsWindowOnCurrentVirtualDesktop](https://learn.microsoft.com/windows/win32/api/shobjidl_core/nf-shobjidl_core-ivirtualdesktopmanager-iswindowoncurrentvirtualdesktop) checks window membership. Combine with native identity and desktop ID lookup. It is not a documented universal Task View visibility event or a full desktop enumeration API. Empty desktops, all-desktops windows and desktop deletion need explicit strategies and tests.
- [Microsoft's virtual desktop guidance](https://devblogs.microsoft.com/oldnewthing/20201123-00/?p=104476) limits what public desktop integration promises. Do not invent desktop GUIDs or silently merge sessions when identity is unavailable. Prefer safe deferral to writing windows on the wrong desktop; report the remaining capability gap.
- [SHAppBarMessage](https://learn.microsoft.com/windows/win32/api/shellapi/nf-shellapi-shappbarmessage) provides taskbar state and appbar operations. The main taskbar rectangle is not the complete usable area; account for monitor work areas and other appbars. Preserve unrelated state bits and user changes. Multi-monitor behavior needs live verification.
- [DWM window attributes](https://learn.microsoft.com/windows/win32/api/dwmapi/ne-dwmapi-dwmwindowattribute) support frame/cloak/material information depending on Windows version. A supported enum is not proof that a given WPF helper configuration renders the desired material. Test translucency, high contrast, transparency disabled and fallback.
- Use existing WinEvent integration for relevant create/show/hide/destroy/minimize/foreground/location events, with deduplication and UI-thread coordination. Do not treat every location event as user intent: Bento's own animation emits changes too.
- Task View/fullscreen detection must not depend only on a single undocumented window class or “covers monitor == fullscreen.” Isolate heuristics, verify shell versions, handle maximized normal apps separately, and suppress helpers conservatively during ambiguous transitions.
- Keep DWM shadows and ordinary window styles. Never turn all helpers topmost to solve stacking. Use explicit relative ordering and occlusion-aware input; validate with floating apps and native dialogs.

## Ordered work packages

1. **Baseline and contract tests:** capture current behavior and performance; add C# tests for shared fixtures, capacity, equivalent seams, hit precedence, snap and roundoff. Port the source algorithms as pure modules with deterministic output before wiring UI.
2. **Session/lifecycle correctness:** per-desktop state, eligibility/exclusions, Off versus Quit, fullscreen reservations, native identity, close/minimize admission and failure handling.
3. **Work-area transactions:** taskbar override journal, stable usable-area updates, saved squeeze baseline, minima invalidation, repeated hide/show without corruption.
4. **Interactions:** local/shared handles, independent native resize, partial subgroup joins, section-edge movement, drop cache, fast release/cancel and occlusion.
5. **Visual/focus parity:** segmented grips, selective snap cue, full-screen preview dim, native frost, shadows, Pause single-click behavior, tray/Settings/onboarding.
6. **Efficiency/motion:** event coalescing, caches, resource lifetime and coordinated animation; profile the same scenarios before/after and fix regressions.
7. **Release:** update Windows release notes/version, updater migration and package metadata; test install/restart; publish both platform assets with truthful platform versions.

Do not defer layout correctness in favor of a visual-only release. Make cohesive commits and keep the checklist/evidence current. Root VALIDATION.md had unrelated user edits in the Mac checkout during handoff—do not overwrite those; inspect the PC file before editing it.

## Validation and release gate

Existing commands on Windows:

```powershell
.\build.ps1
.\build.ps1 -NativeTests -Publish
.\tests\Bento.Tests\bin\Release\net10.0-windows\Bento.Tests.exe --settings-order-smoke
```

`Bento.Tests` is an executable harness, not a dotnet-test adapter. Native fixtures require an interactive desktop and no competing Bento manager; use disposable windows. Then perform physical input checks with File Explorer, Windows Terminal, browsers including Vivaldi, ChatGPT or an equivalent constrained client, Notes equivalent, Clock if resizable, Windows Settings and Bento Settings. Record skipped app-specific cases, not fabricated passes.

Add shared fixtures for both-axis 2×2 and partial 3-column joins, three-slot subgroups, both-axis feasible admission, repeat work-area squeeze/expand, cell rounding and section swaps. Both suites should consume common expected geometry where platform-independent. Keep native tests platform-specific.

Required evidence: test commands/results, before/after screenshots or short recordings for interaction changes, exact Windows build/DPI/monitor configuration, representative app results, unchanged-window write counts, bounded refusal behavior, idle/active resource measurements, and update preservation snapshots. Source test inventory is a coverage map, not a demand to copy every Mac API test literally.

Publish only a validated Windows build; do not reuse old archive bytes with a new version label. Confirm embedded Windows version, manifest hashes, updater selection under shared release tags, and actual installation. Preserve existing signed Mac archive/feed; a paired release may reuse that unchanged verified Mac build only if clearly labeled with its own version. No claim that signing or Mac tests certify Windows native behavior.
