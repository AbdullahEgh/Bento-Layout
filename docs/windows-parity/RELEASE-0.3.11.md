Windows 0.3.11 fixes activation being deferred when Windows cannot assign Bento's invisible helper window to a virtual desktop. Current desktop identity comes from Explorer; actual application windows still require matching current-desktop membership before Bento arranges them.

This release keeps the Windows OTA asset name and package identity used by existing installations. The included Mac ZIP is the unchanged published macOS 0.2.40 asset.

Windows CI passed build/package, native fixtures, portable core, settings smoke and packaged legacy-updater compatibility. CloudPC separately passed the real desktop adapter and controller activation regression with disposable windows (187 checks total). Hosted CI has no initialized Explorer desktop identity and explicitly reports that live-desktop check as not run. See RELEASE-RESULT.md for evidence and scope. Physical clicks, virtual-desktop switching, mixed-DPI hardware and on-device OTA replacement remain unverified.
