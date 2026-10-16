# Bento releases

## macOS 0.2.3 — October 2026

- Also skip windows that refuse native resize requests, after verifying rollback. An unresponsive or incompatible window does not block fitting windows.

## macOS 0.2.2 — October 2026

- Arrange fitting windows instead of rejecting the whole desktop when one window is too large. Preserve usable edited layouts and leave overflow windows floating.
- Learn native minimum sizes through bounded, rolled-back attempts, then retry with a fitting subset.
- Show arranged and floating counts with the names of skipped windows. Reconsider them when windows close or displays change.
- Keep skipped windows out of restore snapshots so later user movement is preserved.

## Windows 0.3.6 / macOS 0.2.1 — October 2026

- Settings use normal window stacking on both systems. Windows background maintenance no longer raises settings over another app.
- Mac Workspace distinguishes missing Accessibility access from Bento being off, shows the exact installed app path, and places activation errors beside Arrange.
- The Mac menu-bar control stays clickable while off and opens permission guidance when access is missing. Permission changes refresh automatically.

## Windows 0.3.5 — October 2026

- Add Workspace → Start at login, saved through Windows' per-user Run entry.
- Login launches keep settings closed and open Bento in the tray.
- Keep left-click toggle and right-click menu behavior.

## macOS 0.2.0 — October 2026

- Native Mac app, original Bento artwork, four-screen onboarding, real-window layout, swaps, four-direction edge splits, gap and native-border resizing.
- Left-click the menu-bar icon to toggle and resume edited layouts; right-click for arrange, release, save, restore, undo/redo, settings and updates.
- Configurable shortcut, background darkness, reduced-motion-aware native animation and animated grips.
- Temporary Dock/menu-bar/edge-tiling settings with restoration, and optional Start at login using Apple's Login Items service.
- Free Ed25519-signed Sparkle releases and feed hosted in this repository; separate Mac publishing workflow.

## 0.3.4 — October 2026

- Click the tray icon to toggle Bento and restore the positions captured before activation; resume the latest edited Bento layout when re-enabled.
- Change or disable Toggle Bento shortcut in Gestures; Ctrl+Alt+B toggles by default, with Arrange all windows available separately in the app and tray.
- Save Bento stores a reusable split tree locally, matching reopened applications and retaining surviving regions when windows are missing.
- Add distinct filled active and outlined inactive tray icons, with grouped menu actions and Windows-synced colors.
- Extend held grabbers to 104 DIPs and animate hover, extension and release over 120 ms while retaining the same 2-DIP thickness.
- Reuse divider windows across resize commits so release animation stays continuous; respect reduced-motion settings.
- Restore pre-Bento positions on a normal exit.
- Verify 123 layout, saved-layout, animation, updater and native desktop checks with zero build warnings or errors.

## 0.3.3 — October 2026

- Resize real application windows continuously during divider dragging; cancellation restores the starting geometry and release creates one undo entry.
- Keep active grabbers 2 DIPs thick, extending only their length to 72 DIPs.
- Keep grabbers above the background dimmer, below settings, and fully opaque when revealed.
- Refine the acrylic slot with matching rounded corners, a soft highlight, and subtle inner and outer edges.
- Verify 117 checks, including real Windows hit detection after another application covers a grabber, live geometry, cancellation and stacking order.

## 0.3.2 — October 2026

- Add background darkness beneath the layout, adjustable from clear to black with a 50% default.
- Illustrate each setting and primary action with an original vector icon.
- Add a separate What's New screen showing only the latest release, with older releases and installation history in a nested Update Log.
- Replace the full divider-drag guide with a 72-DIP solid grabber; the idle hover grip remains 40 DIPs.
- Keep the dimmer beneath applications and remove it on pause or exit; adjust grabber contrast to the dimmed wallpaper.
- Verify 116 layout, interaction and native desktop checks, including grabber cancellation and desktop background dimming.

## 0.3.1 — October 2026

- Anchor split highlights to the existing target slot, before removing or reflowing the dragged window.
- Replace slot instructions and progress bars with a text-free Windows acrylic surface that follows system appearance.
- Increase the default split hold to 900 ms, configurable up to 2000 ms; preserve custom delay settings.
- Fix dark-mode heading and dropdown text and update appearance when Windows preferences change.
- Reveal only the hovered or touched divider; lengthen its grip from 24 to 40 DIPs and adapt its ink to the wallpaper beneath it.
- Keep divider windows below the settings interface and support touch-driven divider resizing.
- Verify with 112 passing checks on an interactive Windows desktop, including external HWND geometry and preview timing.

## 0.3.0 — October 2026

- Hold at a target edge to split, with a progress indicator, edge hysteresis and configurable delay.
- Quick drops swap windows; recursive layouts retain every managed window.
- Animate temporary DWM window copies while applying each application's final size once.
- Add the Workspace, Gestures and Updates interface, light/dark appearances and original icons.
- Add optional temporary Windows edge-snap suppression with original-setting restoration.
- Add GitHub release checks, verified local update packages, rollback and installation history.

## 0.2.1 — October 2026

- Cache previews within a destination zone and reuse application minima at drag start.

## 0.2.0 — October 2026

- Arrange real Windows applications automatically using recursive layouts.
- Add native dragging, swapping, splitting, divider resizing, undo/redo and a minimal tray interface.
