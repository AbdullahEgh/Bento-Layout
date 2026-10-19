# Windows release results — 2026-10-19

## Activation hotfix 0.3.11 — validation in progress

CloudPC reproduced the 0.3.10 production desktop adapter failing ten out of ten samples: `GetWindowDesktopId` on the invisible probe returned `0x8002802B`, while current-desktop membership returned success. The earlier fixtures bypassed this real adapter. Do not treat the published 0.3.10 fixture results as activation validation.

The focused fix from CloudPC commit `0fdbc8226bae1ffd02e461a46df6190729659aac` is integrated as `0e16e32`. All four transferred file blobs match. It reads Explorer's desktop identity using the locations documented by Microsoft's FancyZones source, validates complete nonempty GUIDs, only permits a single-desktop fallback, and retains COM application membership plus current-identity checks before and after membership queries. Unknown identity defers arrangement; transient integration failures can retry.

CloudPC evidence: build zero warnings/errors; native suite 187 passed, zero failed twice; portable core 42 passed; settings smoke six passed. The new native regression uses the actual desktop adapter and routes the Settings button event and tray action, asserts three disposable windows' native frames, and checks Off restoration. Unknown/change/recovery observations are also covered. Physical mouse input was blocked by Computer Use reporting unavailable input geometry, so this is not physical click certification. Visible disposable windows reflowed across a reported monitor change from 1260×2736 at 200% to 1330×998 at 100%; this is not multi-monitor hardware certification.

Earlier untouched CloudPC tests produced 182/3 then 183/2. Two edge-drag test points were within the DPI-scaled screen-edge movement strip; these fixture points now scale with the monitor. A grip assertion now follows the selected equivalent seam. An initial intermittent native-resize failure remains unexplained; subsequent original and scaled offsets passed. No production resize cause is claimed.

Installed CloudPC 0.3.6 was preserved and starts active. Separate unpublished shortcut/backdrop changes at `76cc4a6` remain excluded from this activation hotfix. CI, packaged OTA verification and publication for 0.3.11 are pending.

## Historical 0.3.10 release

Published: https://github.com/AbdullahEgh/Bento-Layout/releases/tag/v0.3.10

Windows download: https://github.com/AbdullahEgh/Bento-Layout/releases/download/v0.3.10/Bento-win-x64.zip

Tag source: `5fc28f155e4e1804d2be224ad1656cc98b798934`. Development and publication repairs remain on `windows/mac-parity-release`; the release tag was not rewritten.

Verified Windows SHA-256: `0fc2934c9e7cd68b2c4793bd88a89e540bea13d4cdf3991780b4f94f0ccb5d0d`.

The complete Windows solution builds with zero warnings/errors. The tag's Windows test job passed native/core fixtures, settings smoke and actual-package compatibility with the frozen shipped 0.3.9 OTA selector:
https://github.com/AbdullahEgh/Bento-Layout/actions/runs/39191695339/job/117865705766

The initial publication job created a draft but then used the public tag lookup endpoint, which returned 404 for that draft. The recovery job verified the successful test job against the immutable release commit, downloaded its exact artifact, independently verified all package hashes, compared the reused Mac archive with its original published digest, and checked every uploaded draft digest by authenticated release ID before publication:
https://github.com/AbdullahEgh/Bento-Layout/actions/runs/39192069979

A separate public download after publication verified the Windows ZIP, sidecar and internal manifest/file hashes. GitHub `/releases/latest` returns stable `v0.3.10`, exact archive `Bento-win-x64.zip`, AppId `Bento.Windows`, Platform `win-x64`, version `0.3.10`. Existing installed 0.3.9 clients can select this bootstrap through their original updater. The new updater supports per-platform metadata on later shared releases. Settings path, executable identity and trusted replacement helper are preserved. No installed application was operated.

The Mac archive is copied unchanged from Mac 0.2.40, SHA-256 `b72793189b6ff4c92227786a14b9041a508a70002380f7d0f59012c8029e4a2b`; no new Mac build/version/feed publication was invented.

Remaining QA: physical input, actual virtual desktops/Task View, mixed-DPI hardware and on-device OTA replacement/restart. A later coordination message identified CloudPC chat **Build Bento Windows Window Manager**, `01a14120-93bb-7902-ae16-859186ea54af`, host `remote-control:env_e_6aa0fb7d89b08333bd4a343241259d7f`, checkout `C:\Users\Abdullah\Bento Layout`, with unpublished commit `76cc4a6`. That commit was not available during this port and is not included in 0.3.10. The owning chat is auditing it and running CloudPC checks; those changes must be compared before a follow-up release.

Default branch remains unchanged: automatic approval review rejected the optional direct push to main as an additional protected-branch mutation. The approved staging branch and release tag were published instead. Main integration requires separate explicit approval; it is not required for current OTA discovery/download.
