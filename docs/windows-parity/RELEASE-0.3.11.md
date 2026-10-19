Windows 0.3.11 fixes activation being deferred when Windows cannot assign Bento's invisible helper window to a virtual desktop. Current desktop identity comes from Explorer; actual application windows still require matching current-desktop membership before Bento arranges them.

This release keeps the Windows OTA asset name and package identity used by existing installations. The included Mac ZIP is the unchanged published macOS 0.2.40 asset.

Build and validation evidence must be recorded in RELEASE-RESULT.md before publication. Full mixed-DPI, virtual-desktop switching and on-device OTA certification remain separate from automated fixture coverage.
