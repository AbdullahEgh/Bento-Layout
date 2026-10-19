# Windows release results — 2026-10-19

## Drag preview and Windows Snap 0.3.12 — published

Release: https://github.com/AbdullahEgh/Bento-Layout/releases/tag/v0.3.12

Source: `e5fbe45df6ce150cdd45ef22915dcb9155c5be9f`. Windows ZIP SHA-256: `d02f81e16dffeeff164ec1b5ec3b44e917ea3bb9c6d2fe2895b250528ff9d6e5`.

[Tag CI and publication](https://github.com/AbdullahEgh/Bento-Layout/actions/runs/39197339211) succeeded: test job `117882836676`, release job `117883313251`. All repeated gates, uploaded digests, reused Mac asset and latest-feed checks passed. A separate public ZIP/sidecar download passed `verify-windows-release.py` for identity, numeric version, archive digest and every payload hash. The bridge independently confirmed stable public `/releases/latest` is 0.3.12 and matched GitHub's asset digest. Exact public Windows binary/updater checks are being performed separately on CloudPC; no installed replacement or physical-mouse certification is claimed.

Focused CloudPC commit `17d84345561469c0af3c48d7a3973d5447761add` is integrated as `77bc9bb`; transferred source and test blobs match. Drag previews now include every projected target-monitor slot, plus changed source-monitor regions. The moving window has a stronger outline; pooled panels share one dimmer per affected monitor. The existing `SuppressWindowsSnap` preference is exposed in Workspace as “Disable Windows Snap,” using the same restore-on-Off/quit lease. Grips and desktop membership code are unchanged.

The regression first failed against released behavior with “Expected 2; got 1” (186 passed, one failed). Final CloudPC build has zero warnings/errors; real-desktop native 190/0, portable core 43/0, settings smoke 6/0 and five-window real-desktop preview smoke 6/0. The latter checks all five slots through swap, held split and reentry, native frames unchanged until drop, one shared dimmer below every panel, cleanup, and native pointer hit-through. It also verifies the Workspace toggle against the actual Windows Snap setting and exact restoration on toggle-off, Bento Off and disposal; user preferences were restored afterward.

A new pointer assertion exposed real interception by preview HWNDs lacking the layered style. WPF-owned `AllowsTransparency=true` fixes it; native style/opacity experiments were removed. CloudPC visually inspected the translucent rounded previews; physical mouse routing was not certified. The installed application and unpublished `76cc4a6` work are preserved.

[CI 39197127756](https://github.com/AbdullahEgh/Bento-Layout/actions/runs/39197127756), source `6c7e2e23316dbc0b219768cb1c88b0d09ef5fe82`, passed build/package, native fixtures, portable core, settings smoke, five-window preview smoke and the actual package check against the shipped updater selector. Tag publication repeated these checks successfully.

## Activation hotfix 0.3.11 — published

Release: https://github.com/AbdullahEgh/Bento-Layout/releases/tag/v0.3.11

Source: `2d01ac48b2ea2274308e078932cbf60fecf0cf87`. Windows ZIP SHA-256: `d973a58f7bb64dcafbaa06314f26c9ceea7439783d71b9661932638d7154ff0a`.

Tag [CI and publication](https://github.com/AbdullahEgh/Bento-Layout/actions/runs/39194651344) succeeded: test job `117874666907`, publication job `117875099380`. The publication verified all uploaded digests and latest-feed identity before completion. A separate public ZIP/sidecar download passed `tools/verify-windows-release.py`, including every internal file hash. The bridge chat independently confirmed `/releases/latest` is stable 0.3.11 and matched the GitHub asset digest. Mac 0.2.40 ZIP is reused unchanged. CloudPC's installed 0.3.6 live update query later hit GitHub's anonymous API rate limit; no installed app replacement/restart is claimed.

CloudPC subsequently verified the exact public package using the actual installed 0.3.6 updater's `DownloadAsync` and `Stage`: archive digest, AppId, platform, version and all 14 payload hashes passed. Its old `ParseRelease` selected Windows 0.3.11 from a projection of the captured actual release asset metadata, including the Mac asset. Only released `Bento.dll`, `Bento.Core.dll` and `Bento.Windows.dll` were copied into the isolated test harness; assembly version was 0.3.11.0. The full native suite passed 187/0 with those released assemblies, including real desktop adapter Settings/tray activation, native window geometry and Off restoration. The installed application was not replaced. Live `CheckAsync` remained blocked by anonymous API rate limiting at this observation; physical mouse routing remains unverified.

CloudPC reproduced the 0.3.10 production desktop adapter failing ten out of ten samples: `GetWindowDesktopId` on the invisible probe returned `0x8002802B`, while current-desktop membership returned success. The earlier fixtures bypassed this real adapter. Do not treat the published 0.3.10 fixture results as activation validation.

The focused fix from CloudPC commit `0fdbc8226bae1ffd02e461a46df6190729659aac` is integrated as `0e16e32`. All four transferred file blobs match. It reads Explorer's desktop identity using the locations documented by Microsoft's FancyZones source, validates complete nonempty GUIDs, only permits a single-desktop fallback, and retains COM application membership plus current-identity checks before and after membership queries. Unknown identity defers arrangement; transient integration failures can retry.

CloudPC evidence: build zero warnings/errors; native suite 187 passed, zero failed twice; portable core 42 passed; settings smoke six passed. The new native regression uses the actual desktop adapter and routes the Settings button event and tray action, asserts three disposable windows' native frames, and checks Off restoration. Unknown/change/recovery observations are also covered. Physical mouse input was blocked by Computer Use reporting unavailable input geometry, so this is not physical click certification. Visible disposable windows reflowed across a reported monitor change from 1260×2736 at 200% to 1330×998 at 100%; this is not multi-monitor hardware certification.

Earlier untouched CloudPC tests produced 182/3 then 183/2. Two edge-drag test points were within the DPI-scaled screen-edge movement strip; these fixture points now scale with the monitor. A grip assertion now follows the selected equivalent seam. An initial intermittent native-resize failure remains unexplained; subsequent original and scaled offsets passed. No production resize cause is claimed.

Installed CloudPC 0.3.6 was preserved and starts active. Separate unpublished shortcut/backdrop changes at `76cc4a6` remain excluded from this activation hotfix.

Hosted CI run `39194155322` built successfully and passed 186 checks; its only failure was the live desktop adapter, because that runner exposes no usable Explorer desktop identity. The live regression now requires explicit `Bento.Tests.exe --native --real-desktop` on an interactive Windows desktop. Ordinary headless native runs print an explicit NOT RUN line; they do not count this regression as passing. The separately recorded CloudPC 187/0 is required release evidence. Production identity checks are unchanged.

CI [39194442467](https://github.com/AbdullahEgh/Bento-Layout/actions/runs/39194442467), source `e19de4f012be3fdac7253975ff0f790592774988`, passed build/package, headless native fixtures, portable core, settings smoke and the actual package compatibility check against the shipped OTA selector. Tag publication repeated these gates successfully.

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
