# Bento for Windows

A native Windows 11 window manager built with C#/.NET 10, WPF and Win32. Real application windows automatically fill adaptive split-tree layouts directly on the desktop. Drag their native title bars to swap or split, and resize through their borders or the narrow gaps between windows. Independent implementation inspired by the requested MindSpace Bento Smart Layout behavior; no affiliation or bundled MindSpace code/assets.

## Run

On Windows 11 x64 with the **.NET 10 Desktop Runtime**:

```powershell
.\run.ps1
```

The built executable is `src/Bento.UI/bin/Release/net10.0-windows/Bento.exe`. A portable, framework-dependent release can be produced with `build.ps1 -Publish`; distribute the whole `artifacts/Bento` folder or `artifacts/Bento-win-x64.zip`. No administrator rights, service, Electron, cloud connection, telemetry, or third-party runtime dependencies. Run outside a restricted development sandbox to allow global shortcut registration.

## Automatic Bento layout

1. Open your applications. Launch Bento or press **Ctrl+Alt+B**. Eligible visible, non-minimized application windows are immediately moved and resized on their existing monitors.
2. Use the applications normally. Bento leaves their content exposed and keeps the active application focused.
3. Drag a real window by its title bar onto another window's region to swap them. **Hold near its left, right, top or bottom edge for 900 ms** to split it instead. A text-free frosted highlight divides the existing target slot when ready. The hold delay is configurable from 0 to 2000 ms.
4. Drag a small grip in a gap to resize neighboring regions. Resizing a native window's inner border also adjusts the corresponding split when released.

Newly opened and restored windows join automatically; minimized and closed windows leave the tree and their neighbors expand. Membership is checked once per second. Unchanged membership preserves customized splits and does not repeatedly resize native windows. New windows split the largest feasible region; a complete reflow is used when necessary to satisfy constraints.

The middle half of a region is its center zone. A drop in a gap or outside a monitor snaps a managed native window back into its committed region. Windows stay represented during swaps and splits. Minimum sizes can prevent a split or automatic arrangement; Bento reports the failure and retains the previous layout instead of silently omitting a window.

Bento 0.3.1 opens a compact interface with Workspace, Gestures and Updates pages. The desktop itself has no blueprint or full-monitor interaction layer. A temporary, text-free acrylic box highlights the existing destination slot and follows Windows appearance (a solid tint is used when the backdrop is unavailable). Gaps contain 40-DIP resize grips, revealed individually on hover or touch. Their black or white ink follows the local wallpaper color, and settings stays above them. Preview and grip windows do not activate. Native geometry changes once per commit, apart from the application's own move/resize gesture. DWM window copies animate the transition for 180 ms by default; protected or unsupported thumbnails fall back to direct placement. Reduced motion follows Windows and can also be selected in Bento.

| Action | Control |
| --- | --- |
| Open Bento settings and updates | Double-click the tray icon, or Tray → Open Bento |
| Arrange all windows immediately | Ctrl+Alt+B, Workspace → Arrange windows, or Tray → Arrange all windows |
| Swap windows | Drag a real window's title bar to another region's center |
| Split a region | Drag a real window's title bar to another region's edge and hold until the indicator fills |
| Resize neighbors | Drag the grip in a gap, or a native window's inner resize border |
| Release window and expand neighbor | Tray → Release active window |
| Undo / redo | Tray → Undo / Redo |
| Cancel a native move or resize | Windows' normal Esc gesture |
| Refresh open windows | Tray → Refresh windows |
| Change shortcut or window gap | Tray → Settings |
| Return managed windows to original positions | Tray → Restore all windows |
| Quit | Tray → Exit |

**Release active window** keeps that window floating until **Arrange all windows**. **Restore all windows** restores the originals and pauses automatic management until Bento is activated again. Exiting leaves applications in their arranged positions. Settings are stored locally in `%LOCALAPPDATA%/Bento/settings.json`; layout trees and undo history are session-only. Changing the shortcut requires at least one modifier and a letter/digit key. A registration failure is reported with its Windows error; the tray remains available.

**Let Bento handle edge snapping**, under Gestures, temporarily disables the Windows window-arrangement setting for all applications while Bento is active. It is off by default. Pausing, restoring windows or exiting restores the previous value. A journal recovers an interrupted session on the next launch; Windows sign-out also resets this session-only setting. It does not change security settings.

## Updates

The release source is [AbdullahEgh/Bento-Layout](https://github.com/AbdullahEgh/Bento-Layout). The repository is public and supports direct in-app checks and downloads. Packages can also be downloaded in a browser and selected with **Choose update file**. No GitHub credentials are collected by Bento. Optional startup checks are off by default.

Updates shows release notes and the last ten installation results. **Install and restart** validates all package file hashes, retains a backup and restores replaced files if copying or startup fails. Settings remain in Local AppData. GitHub downloads also require the release asset's SHA-256 digest. Checksums detect corruption, not publisher identity; local packages must come from your trusted Bento release source. This development release is not code-signed.

Publish `Bento-win-x64.zip` as a GitHub release asset with a tag matching the application version, for example `v0.3.1`. `build.ps1 -Publish` generates the required `bento-release.json` manifest. The updater is a small separate .NET process so it can replace files after Bento exits. It does not elevate privileges; use a writable portable installation folder.

## Build and test

Requires a **.NET 10 SDK** on Windows. The workspace-local SDK under `.tools/dotnet` is used if present; otherwise scripts use `dotnet` on PATH. The application itself runs offline. The SDK already includes all project references; no NuGet packages are used.

```powershell
.\build.ps1                       # Release build + deterministic engine/geometry tests
.\build.ps1 -NativeTests          # Also tests disposable external windows and lifecycle changes
.\build.ps1 -NativeTests -Publish # Validate and create portable release
```

Equivalent explicit commands:

```powershell
dotnet build Bento.slnx -c Release -m:1 -p:UseSharedCompilation=false
dotnet run --project tests/Bento.Tests -c Release --no-build
dotnet run --project tests/Bento.Tests -c Release --no-build -- --native
```

`Bento.Tests` is a dependency-free executable test harness, **not a dotnet test adapter**. It prints each check and returns a nonzero exit code on failure. Exit any running Bento tray app before native tests: another manager would compete over the fixture windows, and the suite now checks for that condition. Native tests require an interactive Windows desktop outside sandbox restrictions, register/release a test shortcut, and manipulate only disposable fixture processes. They verify native bounds, desktop focus, the absence of a blueprint, gap-only helper windows, one temporary destination preview, native-border resizing, and automatic opening/minimizing/restoring/closing. Gesture positions are supplied through the production controller; physical mouse/keyboard routing is not covered. The destination preview render is saved to `artifacts/drop-preview.png`.

For manual testing without rearranging existing applications, run `tests/Bento.Tests/bin/Release/net10.0-windows/Bento.Tests.exe --interactive`. This arranges three real fixture windows on the desktop and exits after ten minutes or Tray → Exit. Add `--windows 5 --hide-ui` for five windows with the settings interface initially hidden; counts from 3 to 12 are supported. Observed fixture geometry is written to `.tools/interactive-state.json`. The application's `--smoke` startup check uses an empty discovery source so it never arranges existing user windows.

## Architecture

| Project | Responsibility |
| --- | --- |
| `Bento.Core` (`net10.0`) | Automatic constraint-aware recursive distribution, immutable split trees, physical-pixel geometry, zone selection, insertion/removal/swap, resizing, bounded undo/redo |
| `Bento.Windows` (`net10.0-windows`) | HWND enumeration/filtering, cloaked-window exclusion, minimum tracking sizes with bounded message timeouts, DWM visible-frame compensation, original window placement, monitor work areas, DPI, global hotkeys, native drag events |
| `Bento.UI` | Desktop arrangement, automatic lifecycle synchronization, one temporary drop preview, gap-only resize grips, tray, compact settings, native apply/rollback coordination |
| `Bento.Updater` | Verifies staged files, waits for Bento to exit, applies a recoverable update, restarts the app and records the result |
| `Bento.Tests` | Engine invariants, native-border resize geometry, seeded 1000-operation exercise, optional real HWND/desktop integration |

Trees use horizontal (left/right) or vertical (top/bottom) binary splits. Removing a leaf promotes its sibling. Minimum constraints aggregate through each subtree; ratios are clamped to feasible pixel boundaries. Impossible layouts are rejected before native mutation. Preview snapshots never mutate the committed tree. Physical desktop pixels, including negative monitor origins, remain separate from WPF's monitor-local DIPs. Monitor work areas exclude the taskbar. Cross-monitor placements scale minimum constraints; DPI changes may need a second native adjustment at commit to account for new frame metrics.

Native changes capture rollback geometry and check whether applications accepted the requested bounds. Restoration is best effort if a process exits or denies access. HWND/process identity checks prevent restoring a recycled handle owned by another process. Bento runs at normal privileges: elevated or protected windows may refuse control and produce a clear error.

Original app artwork is in `src/Bento.UI/Assets`: an SVG master, a 1024 px PNG and a Windows ICO with seven resolutions. `tools/Make-Icons.ps1` regenerates the PNG/ICO. Interface symbols are original vector paths. Visual principles follow [Apple's Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/app-icons/) while the current implementation remains native WPF. Layout and gesture policies are platform independent; macOS window control and UI are future work.

## MVP scope and validation

See [VALIDATION.md](VALIDATION.md) for actual results and remaining hardware checks. This is a runnable first milestone, with no installer, startup registration, persistent workspace profiles, virtual-desktop integration, or application grouping. Physical title-bar tests confirmed center swap and left-edge splitting with three fixture windows. Other directions, border/grip input, mixed-DPI physical monitors, docking changes, elevated apps, and the hotkey gesture need broader interactive validation. App-specific size restrictions can reject a placement; the previous layout is retained.

Product reference: MindSpace’s Bento Smart Layout concepts as described in the project brief and follow-up request. Its connected capabilities tool returned an internal error twice, so exact parity with its private layout rules has not been verified. Implementation uses Microsoft's [SetWindowPos](https://learn.microsoft.com/windows/win32/api/winuser/nf-winuser-setwindowpos), [DWM frame bounds](https://learn.microsoft.com/windows/win32/api/dwmapi/ne-dwmapi-dwmwindowattribute), and [Per-Monitor DPI awareness](https://learn.microsoft.com/windows/win32/hidpi/setting-the-default-dpi-awareness-for-a-process).
