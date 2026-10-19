# Windows 0.3.10 release result — 2026-10-19

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
