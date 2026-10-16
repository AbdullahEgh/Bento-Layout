Bento for macOS 0.2.11 improves grabber visibility and makes room for apps opened from the Dock.

- Show resize grabbers on hover and keep them visible while clicked or dragged.
- Keep grabbers visible above native window shadows, including after layout changes.
- Give newly opened and restored windows space by minimizing the least recently used windows when needed.
- Preserve edited layouts when every window fits, and keep minimized overflow from displacing a restored window.
- Reuses the permanent app identity and OTA signing key.

Validated locally with 35 core tests and 66 isolated native interaction checks. Physical Dock and pointer testing against third-party apps remains separate.
