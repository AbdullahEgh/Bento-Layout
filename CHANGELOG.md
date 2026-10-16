# Bento releases

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
