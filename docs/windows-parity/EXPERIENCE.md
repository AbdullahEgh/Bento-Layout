# Bento experience contract for Windows

Baseline: Mac source `7925944`, 2026-10-18. This specifies the desired Windows result. “Must” is acceptance behavior, not evidence that the current Windows implementation already does it. Recent explicit user choices take precedence over old release notes. Preserve the experience; implement native Windows mechanisms.

## 1. Product and native shell

Bento arranges real application windows into an adaptive, gap-separated split layout on the desktop. App content remains usable, native focus is respected, and helpers do not replace windows with a dashboard. No per-app screen-resolution changes, forced app zoom, or disabling window shadows to manufacture a fit. The minimum-size/rounding policy applies to all apps, not a hard-coded Terminal exception.

Windows 11 x64, existing C#/.NET 10/WPF/Win32 architecture. Use Windows title bars, tray, keyboard naming, taskbar and Task View. Keep original Bento artwork. Use Windows backdrop materials when supported; Liquid Glass is a Mac implementation detail, not a Windows dependency. Match the neutral frosted result with a readable solid fallback when transparency is unavailable or disabled.

## 2. State model and persistence

Keep these distinct: Off, Active, Paused, interacting, applying a native transaction, desktop overview/transition, fullscreen reservation, and shutting down. Pause is the user-facing name; old `pinned` fields need not force a risky rename.

| Action/state | Window behavior | State retained |
| --- | --- | --- |
| Enable, first use this session | Discover eligible current-desktop windows; arrange by recent use and feasibility | Original placement/minimized ownership, layout and history |
| Off without explicit session save | Restore pre-Bento placements; restore only Bento-owned minimizations | Automatic session tree for next enable |
| Off after Save for This Session | Keep arranged placements; do not treat this as persistent profile storage | Explicit save until process exits; Bento-owned minimizations handled by normal Off cleanup |
| Restore Window Positions | Explicitly restore originals even when a session save exists | Clear/transition active state consistently |
| Enable again | Reconcile last valid tree with live identities; retain slots/ratios/display ownership as closely as feasible | Do not blindly run a fresh auto-layout |
| Pause | Preserve current tree; dim its members; new apps float above | Desktop-specific membership and pause state |
| Resume | Minimize eligible floating apps above the paused Bento, then resume its preserved layout | A subsequently restored/new app can join normally |
| Quit or Install and Restart | Leave every native window's current frame and minimized state unchanged | Session layout/history end; persistent preferences survive |
| New process | Hiding options off; no prior-process layout loaded | Persistent ordinary settings and crash recovery journal only |

Session memory must include tree identities/ratios, original placements, overflow ownership, floating exclusions, focus recency, explicit save, Pause membership, fullscreen reservations and pre-work-area-change geometry, scoped appropriately by desktop and display. Do not overwrite the original snapshot on each layout refresh.

Stopping, exiting and pausing are different operations. Quit/update must invalidate timers, queued reconciliation, delayed validation and stale gesture callbacks before teardown. Let an already executing native write finish; do not roll a held grip back or restore windows as a shutdown side effect. Restore Bento-owned OS preference overrides, remove helpers, and retain a recoverable error path if cleanup fails. A failed installer preparation must let Bento resume safely; a retry must not lose its continuation or require duplicate clicks.

## 3. Eligibility, activation and admission

- Use stable native window identity plus process/lifetime checks; an HWND alone can be recycled. Keep windows on their own monitor and virtual desktop unless the user's gesture moves them.
- Exclude Bento Settings, Bento helpers, Windows Settings, shell/taskbar/desktop surfaces, tooltips and unsuitable transient/tool windows. Do not blanket-exclude File Explorer merely because `explorer.exe` also owns the shell. Exclusions apply to activation, normal admission, drag targeting, Pause and Resume.
- Closed, minimized, hidden/cloaked, fullscreen and non-resizable windows need distinct treatment. A fullscreen member is reserved, not mistaken for a closed window. Protected/elevated windows that cannot be controlled must fail clearly and leave a valid workspace; do not require blanket elevation.
- First activation favors recent apps, with the most recent app getting a useful largest slot where feasible. Maximize usable app count before sacrificing fitting apps merely to enlarge the primary. Respect asymmetric limits and portrait displays.
- Opening/restoring through taskbar, Start, shortcuts or another app must trigger admission. A non-focused but newly visible eligible app also joins. Restoring overflow prioritizes that app.
- Try existing fitting geometry/local insertion first. If fragmented slots cannot individually fit an app, compute a feasible reflow before eviction. Search both split axes and alternate groupings; a failed first tree is not proof that the display lacks capacity.
- If needed, minimize least-recently-used eligible apps, only as many as needed. Prefer exact replacement of an idle slot if feasible, leaving neighbors untouched. An individually impossible incoming app must not evict otherwise usable apps.
- Overflow disabled: retain a valid layout and communicate inability to fit; never overlap or silently drop a window from accounting.
- Plan in memory before native writes. Bounded corrections for newly observed native limits; identical failed inputs do not repeatedly trigger re-layout. A genuine change in membership, limits, geometry or user intent invalidates that failure cache.
- An empty workspace after minimize/fullscreen stays ready for restored windows; it must not leave Bento unable to run.

## 4. Geometry and native size constraints

Use immutable binary split trees with stable identities. Horizontal axis means left/right children; vertical means top/bottom. Removing a leaf promotes its sibling. Aggregate child minima, subtract the gap once per split, clamp only to feasible boundaries, and round deterministically. Preview and commit must use identical geometry. Every included app appears once, positive-sized, within its monitor's usable area, without overlap.

Windows engine coordinates remain physical pixels, including negative origins. WPF visuals are per-monitor DIPs. Convert explicit boundaries, not entire mixed-DPI trees implicitly. Mac point constants below are visual/interaction references: use DIPs and convert to engine pixels per monitor. Include DWM visible frame versus invisible resize borders, window DPI changes and accepted native frame measurements.

Current window size is not automatically its minimum. Read reliable Windows tracking limits with bounded calls and validate accepted sizes. Learn only the axis actually refusing a resize. Position failure, animation-in-progress, taskbar transition or a large current frame must not poison both minima. Smaller observed accepted dimensions invalidate stale learned restrictions.

Mac baseline tolerates origins within 2 points and 0–32 points of cell/grid slack (up to 2 points overshoot). For a 3–32-point overshoot, one inward correction can avoid falsely rejecting a cell-rounded window. Port the policy with explicit DPI scaling and Windows tests, not blind pixel constants. Reclaim harmless small slack by moving an adjacent divider only if observed validation improves alignment; do not change membership or unrelated splits.

Native writes across processes are not atomic. Capture rollback geometry, apply changed windows, validate actual results and commit history only on success. Late rebounds get bounded repair in the committed tree, not a fresh packing algorithm. History, display, gesture, activation or shutdown changes invalidate old repair tasks.

## 5. Work area, taskbar and repeated hide/show

Translate “Hide Dock & Menu Bar” to **Hide Taskbar**. Windows has no global Mac menu bar; do not hide application title/menu bars or add a fake second control. Hiding is session-only and controlled through the same model from tray and Settings.

- Calculate usable bounds per monitor from actual shell reservations, taskbar state and other appbars; do not simply assume the main taskbar rectangle is the only reservation.
- Reclaim genuinely hidden reserved space promptly. On showing the taskbar, squeeze the existing tree into the new work area while preserving joins, identities and relative structure where constraints allow.
- Keep a separate pre-squeeze baseline. Repeating hide/show must not progressively change the layout or start a new tree. Re-expanding must restore the closest original geometry.
- Combine intermediate shell geometry observations into one settled layout update; avoid the visible “fit once, fit again” sequence. Do not learn app minima from transient shell clamping.
- Taskbar size, edge, monitor, auto-hide state, DPI and display changes trigger a bounded work-area update without requiring Refresh. Refresh only affected displays/windows.
- During drag, slot highlights and grips use the same committed area/gap/margin as the layout. Temporary taskbar reveal must not produce wrong targets. Reconcile after a stable transition.
- Journal original OS values before changes. Restore only Bento-owned values and preserve manual changes made by the user during the session. Recover an interrupted journal next launch. Do not repeatedly restart Explorer as routine geometry synchronization.
- Windows taskbar state may be shell-global rather than desktop-local. Keep workspace trees separate, and verify that switching desktops/fullscreen does not reassert visibility or interfere with the shell. Capability limitations must be documented and tested.

## 6. Window drag, swaps and split preview

Bind the gesture to the real window under the initial pointer, not stale focus. Use committed geometry as the initial baseline. Settings must never accidentally bind to an underlying tiled app.

Managed window: quick center drop swaps; held edge drop splits left/right/top/bottom. Default hold 900 ms, configurable 0–2000. Leaving the target, moving to center, cancelling or changing geometry resets hold appropriately. A return to the old native frame by itself is not cancellation. Include the final release sample even for fast gestures.

Floating window: center drop inserts alongside the target (right for a wide slot, bottom for tall), preserving the occupant. Empty monitor accepts a valid drop. Gap/outside/invalid drops restore the committed arrangement; Escape cancels. Source/target closing mid-gesture recovers surviving windows safely.

Outermost 20-DIP physical screen edge on the source's own display exchanges whole eligible sibling sections. Example: a large right slot moves left while the two vertically stacked left slots move right, retaining internal sizes and splits. Use measured clamped proportions, not a stale ratio. Already-outermost sections do nothing. Normal interior drop behavior remains unchanged; another monitor's edge must not accidentally move the original display's section.

Preview uses neutral native frost, gentle thin outline, stronger split indication, and warm amber conflict tint. No blue indicators, labels, icons, badges or harsh outlines. Show destination plus only changed neighbors from the actual proposed final tree. A full-display black dim layer at 45% sits underneath the destination/split overlays and above ordinary background windows while previewing. Remove the earlier extra per-slot background wash; keep the glass surface itself. Fade in/out together; all preview helpers are nonactivating and click-through. Reuse panels rather than allocating/repainting continuously.

While dragging any ordinary window, including excluded Settings, suppress resize grips until release. Settings do not produce drop targets or re-layout Bento.

## 7. Local and universal grips — geometry before visuals

Do not expose only the dividers of the stored tree. Derive equivalent slicing trees that preserve every leaf rectangle and provide valid local and shared seams. Include newly formed rectangular subgroups, not only original tree descendants. A partial group of two or more sections can have a shared grip beside an unrelated full-height column.

- One two-app boundary uses the **short specific** design. A shared seam that moves multiple sections uses the **long universal** design. Classification is functional containment/shared geometry, not “any line that spans a screen.”
- Generate shared/local options immediately on activation when geometry allows; snapping is not required to unlock them.
- A 2×2 aligned layout exposes a whole-row boundary and left/right local portions; the perpendicular boundary likewise exposes whole-column and upper/lower portions.
- A local drag changes only its valid section; unrelated panes remain fixed. A universal drag moves the shared boundary together. Fixing one direction must not unnecessarily remove a valid perpendicular option.
- Choose one equivalent tree on pointer-down and keep that gesture basis through release. Preserve off-center grab offset; no jump to cursor center. Apply coalesced latest pointer geometry directly and include mouse-up. One undo entry per completed gesture; cancellation restores its starting tree.
- Offer only feasible movable handles. Real app limits clamp correctly; stale learned limits must not prevent a known-feasible size.
- Manual native border resizing chooses the smallest valid local section touching the changed edge. Do not resize an unrelated whole row/column merely because an ancestor in the stored tree owns that axis.

### Exact visual and input hierarchy

| Property | Reference |
| --- | --- |
| Specific pill | 80 DIP length, 4 DIP thickness, rounded radius 2, 100% ink when visible/held |
| Universal line | Full valid joined span, 4 DIP endpoint inset, same 4 DIP thickness, 45% ink |
| Local pills on universal line | 100%; full line interrupted with 8 DIP breathing gaps beside pills |
| Local target | ±80 DIP along seam from local center (160 total), clipped to its gap; larger than visible pill |
| Rest of shared seam | Universal hit target; direct line grabbing works |
| Standalone two-app seam | Full exposed gap remains hittable even though ink is short |
| Hover/held | Hidden idle, gentle appearance on hover; held specific ink stays 100% even if pointer leaves old panel |
| Ink | Prefer bright white on black dim; maintain contrast under supported appearance settings |
| Hit versus appearance | Separate; cue/fade/segmentation must not resize or relocate hit targets |

When local targets overlap, use deterministic nearest-center then span/identity tie-breaking. Do not let an enlarged target consume the entire universal remainder. Hit testing excludes any portion covered by a higher application window.

## 8. Snap, break and rejoin

Snap adjoining parallel seams within 12 DIP when the final geometry can match **exactly** without violating minima. Keep the stationary section fixed; only move the dragged seam. A clamped near-match is not a join. Pulling away breaks the join; both axes behave symmetrically. Recompute equivalent handles so perpendicular local resize becomes available again.

Examples requiring explicit tests:

1. Raise bottom-right ChatGPT until its top aligns with bottom-left Notes. It snaps exactly; the lower row now exposes the left/right resizing option.
2. The left two columns join at their lower boundary beside an unrelated full-height third app. The joined lower subgroup grip must activate even though it is not a full-screen line.
3. A three-slot partial group supports a shared seam, not only two-slot or full-width groups.

Only the newly joined universal seam connected to the dragged grip receives a cue. Do not pulse every seam, perpendicular seams, unrelated existing joins, or a shared grip merely because it moved. Cue uses the same thickness and full applicable span, holds briefly (reference 180 ms), then gently fades (370 ms). Preserve the latest opacity choice during the cue: universal 45%, specific 100%. “Full opacity” in older requests is superseded by this explicit hierarchy. Do not flash the whole display.

## 9. Dimming, Z order, focus and Pause

Active backdrop is neutral **black**, with configured darkness, fades on entry/exit and retains native app shadows. Layer order from back to front: unrelated underlying windows → Bento backdrop → grips → Bento app windows → floating apps/Settings. Grips must remain above a window lying beneath the Bento backdrop, but beneath any app above Bento. Do not solve this with globally always-on-top grips. Keep helpers out of taskbar, Alt+Tab and task switching.

Pause is available whenever a valid Bento can be active. If necessary establish it first; serialize overlapping requests and honor latest intent. On entering Pause, dim all members immediately; do not auto-uncover the previously focused app. Reference per-member black tint is 30%, separate from the configurable desktop backdrop. Floating/new apps remain above that dimmed workspace and do not join it.

A **single click** on a paused Bento app brings it above its tint immediately and delivers normal interaction—no swallowed first click or double-click requirement. Resume minimizes eligible floating windows above Bento, excludes system/Bento Settings, removes Pause dimming, and restores normal admission. Opening/restoring those apps afterward must interact with Bento again. Tray uses a distinct paused icon; its single click resumes rather than switching Off.

## 10. Virtual desktops, fullscreen and interruptions

Each virtual desktop has its own active state, Pause state and session layout. New desktops start Off. Never combine windows from multiple desktops. Keep helpers on the correct desktop and display. A desktop switch cancels/invalidates stale native work before it can write to another desktop.

Task View, Alt+Tab/overview transitions, lock/unlock and shell interruptions must suppress grips/hit handling and avoid interpreting temporarily missing windows as closed. Restore helpers and reconcile when the real desktop is stable. Do not steal focus, switch desktops automatically, or overlay fullscreen apps.

If a Bento member enters fullscreen, preserve its slot/tree reservation. Do not move the fullscreen app or force the taskbar to appear. Other visible desktop members can use feasible temporary geometry; on return restore the prior tree as closely as live membership and minima allow. Returning to the desktop triggers reconciliation without manual Refresh. Closing a reserved app releases its reservation. Maximizing is not automatically the same as fullscreen: test both separately on Windows.

## 11. Lifecycle speed, animation and efficiency

Confirmed close/minimize events take a fast path to local branch collapse; do not require two slow full scans. Ambiguous disappearance during Task View/desktop switching still needs protection. New/restored apps request an early scan. Event callbacks coalesce onto the UI/controller thread; a slow periodic reconciliation can recover missed events.

Animate ordinary layout changes, close collapse, swaps, split, On/Off, return and live setting changes as one coordinated batch. Mac reference uses minimum-jerk easing `t³(6t²−15t+10)`, no overshoot, zero endpoint velocity/acceleration. Default 140 ms; configured 80–400 ms, return/cancel reference at least 320 ms. Honor existing saved duration, animations-off, Windows animation settings and reduced motion. Grip dragging itself tracks the pointer directly.

Use a shared animation clock, not serial per-app animations. Skip stale intermediate frames for slow apps and always apply the authoritative final frame. Keep focus, Z order, input and shadows correct. Existing DWM thumbnail transitions may remain if they achieve the same result; unsupported/protected content falls back to safe direct placement, never blank frozen proxies.

Cache equivalent-handle geometry by tree including minima, work area, gap and display. Reuse unchanged results across hover/focus/menu updates. Cache successful and infeasible drag proposals; invalidate when relevant inputs change. Share native enumeration/occlusion snapshots within a sample. Stop high-frequency sampling when inactive, in overview or shutting down. Update only changed helpers/windows; release hooks/timers/resources.

Mac geometry microbenchmark measured about 80 ms uncached versus 0.44 ms cached for 250 identical requests. This is **not** a whole-app speedup or Windows performance result. Measure Windows idle CPU, memory/private bytes, handle/GDI counts, input-to-layout latency, frame pacing and long-session resource growth before and after.

## 12. Tray, Settings and onboarding

Compact tray menu order with icons: Pause/Resume Bento; Turn Bento On/Off; Hide Taskbar; separator; Undo Layout Change; Settings; separator; Quit Bento. Keep less frequent actions in Settings. Single click toggles On/Off normally and resumes while paused. Hold 550 ms toggles taskbar hiding while active exactly once and consumes release (must not also toggle Bento). Escape/cancel/lost capture cannot leave the press stuck.

Tray states: inactive dim outline (45%), active filled, paused distinct; adapt ink to Windows taskbar contrast. Never make the off icon unclickable. Clear tooltips state click/hold effects.

Settings pages: Workspace, Gestures, Updates, What's New, About. Native readable title bar in light/dark; no glass/titlebar artifacts. Responsive grouping, trailing/right-aligned toggles including Pause; readable labels, icons for controls, accessible names/focus and keyboard navigation. Settings and Windows Settings always float outside layout.

Workspace: current status/counts (arranged/minimized/outside), On/Off, Restore Window Positions; Pause; refresh/status; Layout & spacing; Desktop space; Appearance & motion; General/start at login; session save/use/clear; Arrange All Windows; Undo/Redo. Use explanatory “Stop Arranging Selected Window” if exposing release behavior, never ambiguous “Release active window.” Released windows remain outside until explicitly included again.

Defaults: gap 8 DIP (4–32 step 2), margin 8 DIP (0–64 step 2), background black 50% (0–100 step 5), overflow minimization on, animation on/140 ms (80–400 step 20), hold-to-split 900 ms (0–2000 step 100), theme System/Light/Dark, hiding off each process, startup checks opt-in. Preserve existing valid user settings; do not reset them to new defaults. Ctrl+Alt+B default shortcut; configurable modifier+letter/digit, disableable, registration conflict surfaced while tray remains usable. Start at login is opt-in, per-user, with correct quoted installation path.

Gap/margin edits update live (reference 120 ms coalescing), wait for active gestures, and use applied—not pending—values for preview/hit geometry. All controls use the same state path; no tray-only or Settings-only behavior.

Onboarding explains actual native Windows behavior, permissions/control limitations and shortcuts, has a preview route, finishes explicitly, can reopen from About, and respects theme/accessibility. Do not show Mac Accessibility permission steps on Windows or imply admin rights are required for normal apps.

## 13. Updates, history and release contents

Compact impact-focused bullet points per release, newest release in What's New; Update Log lists each release's points and installation history. Update popup must show the release being installed. No huge changelog dump or claims about unsupported Windows features.

Check/download/ready/install/restart/failure/retry have clear states. One action advances installation; repeated clicks coalesce. Keep windows and minimized states unchanged on update/quit, including other desktop sessions. Settings survive; session saves end. Verify package identity, version, file hashes, safe paths and trusted release source before replacing files; preserve backup/rollback and report errors. Existing Windows hash checks are integrity checks, not equivalent to Mac publisher signatures—document this distinction and plan publisher verification explicitly rather than claiming signed Windows OTA.

Each shared GitHub release includes `Bento-macos-universal.zip` and `Bento-win-x64.zip`. State both embedded app versions, system requirements and which features changed on each platform. Do not relabel an older Windows binary as the new parity build. Ensure Windows update discovery handles the repository's `macos-v...` tags by reading Windows package metadata; compare the Windows app version, not the Mac tag. Do not overwrite an already-published signed Mac asset or regenerate Mac signing identity. Validate actual install/relaunch on PC, not just upload success.
