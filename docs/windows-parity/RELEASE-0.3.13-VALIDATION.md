# Paired static-slot update — October 20, 2026

Mac release source: `66cb06446fe1d639524b0f044cc4af8d4e88466d`; Windows payload source: `99e0e7486b27cd9ff1d8f0e939d082bbae5ff9e9`. The intervening commits only correct an isolated Mac fixture capacity assumption and remove a scheduler-timing assumption from the initial grip-cue check; production behavior is unchanged.

## Changes carried to Windows

The existing `windows/mac-parity-release` history was merged without resetting its work. Its desktop sessions, local/shared grips, snap/rejoin, taskbar leases, fullscreen reservations, session layouts, first-click Pause focus, update preservation and release metadata remain the foundation.

This update adds static exact-size destination previews, brighter selected slots, dragged-window layering, rounded Pause shades, single-click Pause/Resume, native blue assets/controls, an organizing cover and spinner, and draggable overflow icons. Waiting insertion minimizes the displaced occupant only after a validated proposal; native rejection retains the source in the queue and remembers the refused bounds. Invalid previews retain the other slots. Native resize during Pause leaves the tree unchanged, and Resume reapplies the saved bounds even inside cell-size tolerance. Equivalent-tree and alternate-axis drop planning plus a held-seam swap avoid rejecting feasible placements. Work-area changes invalidate learned native minimum hints.

Organizing covers complex initial activation; ordinary Pause/Resume does not use it. Native fitting remains bounded: a new minimum can cause one replan per refusing app before overflow exclusion. This is not a claim that all third-party applications obey their reported constraints.

## Evidence

- macOS local signed universal app: 321 native checks passed after making the already-at-minimum fixture explicitly feasible on small CI desktops. The static-slot production build is installed at `/Applications/Bento.app` and Settings was verified with Accessibility connected. Test fixtures did not touch external applications or system preferences.
- Windows full solution cross-build: zero warnings/errors.
- Windows portable regressions: 43 passed.
- Windows native fixture suite: 190 passed, including organizing-spinner geometry, waiting replacement/rejection, Pause resize restoration, desktop sessions and fullscreen reservations.
- Windows packaged-OTA selector test: passed; Settings stacking: 6 passed; five-window drag preview suite: 4 passed.
- Final paired Windows release-job evidence: GitHub Actions run `39334932570`, job `118342253401`.
- macOS 15 and 26 compatibility: run `39334921266`; both passed 97 core tests, 321 native checks, startup and signed OTA fixtures.
- Signed Mac release: run `39334932570`, job `118342935537`; 321 native checks and stable signing identity passed. Published macOS 0.2.42 build 166, archive SHA-256 `9e4c293f94f574abf76887cd33d88d75128b032c91149e6d6fae90228f7604d0`. Downloaded archive and published feed verified locally.

Physical PC input, Task View/Explorer transitions, mixed-DPI hardware, representative third-party application sizing and on-device Windows OTA installation remain unverified. Do not interpret fixture passes as certification of every item in ACCEPTANCE.md.

## Release continuity

Both platform archives are uploaded before publication. The macOS signed feed remains its existing channel. Windows `v0.3.13` is published and marked latest after uploaded hashes were verified, preserving discovery by the original `/releases/latest` updater. Final tag run `39337259230` passed its test and release jobs. Both public archives and Windows metadata were downloaded/checked against GitHub asset digests; all packaged payload hashes passed. The Windows archive SHA-256 is `7bb1286605138fea0216d63b0c7aae4632a0ec1c0ae118f9d967349cb1aa1d06`. Explicit Windows metadata supports newer clients on shared-platform releases.

Published releases: [paired downloads / Windows OTA](https://github.com/AbdullahEgh/Bento-Layout/releases/tag/v0.3.13), [macOS OTA source](https://github.com/AbdullahEgh/Bento-Layout/releases/tag/macos-v0.2.42).
