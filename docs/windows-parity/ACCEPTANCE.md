# Windows parity acceptance checklist

All entries are **unverified on Windows** at handoff. Check an item only after implementation and its specified verification. Keep evidence as commit/test name plus result artifact and environment; explicitly distinguish automated fixture checks from physical input checks.

For each entry record: Windows commit/version, implementation file, automated test/result, live result, remaining limitation. “Blocked” is not a pass.

## Lifecycle and sessions

| Status | ID | Scenario | Required result |
| --- | --- | --- | --- |
| [ ] | L01 | Enable with 2–12 eligible apps, unequal minima and recent-use order | All feasible apps included; primary useful/largest when feasible; no arbitrary eviction. |
| [ ] | L02 | Turn Off without explicit save; enable again | Original placements restored on Off; closest session tree reused on enable. |
| [ ] | L03 | Save for This Session, Off, enable, Clear Session Save, Off | Saved Off keeps placements; cleared save restores ordinary Off semantics. |
| [ ] | L04 | Restore Window Positions after explicit save | Original placements restored regardless of save. |
| [ ] | L05 | Quit and update while active, paused and in a held grip | No frame rollback, resize, move or unminimize; helpers/timers removed. |
| [ ] | L06 | Restart process with legacy saved-layout.json present | Ordinary settings survive; no old-process layout or hide options auto-loaded; legacy file untouched. |
| [ ] | L07 | Minimize all apps then restore one | Bento remains ready and restored app joins. |
| [ ] | L08 | Close/minimize one app during normal use | Prompt local collapse; unchanged branches stay unchanged; record latency. |
| [ ] | L09 | Transiently hide windows via Task View/desktop change | No false deletion, eviction or blank-layout replacement. |
| [ ] | L10 | Bento and Windows Settings open/move during active and paused states | Always excluded; no hidden app receives gesture; Resume does not minimize Settings. |
| [ ] | L11 | Window destroyed then HWND reused by another process | No old snapshot/identity applied to new window. |

## Capacity and native bounds

| Status | ID | Scenario | Required result |
| --- | --- | --- | --- |
| [ ] | C01 | New/restore app via taskbar, Start and shortcut | Admission without Refresh, including non-focused visible app. |
| [ ] | C02 | App fits only by other split axis or grouping | Planner finds valid candidate before minimizing anything. |
| [ ] | C03 | Fragmented space with feasible complete membership | Reflow retains all apps; no false no-space rejection. |
| [ ] | C04 | Crowded desktop, reopen overflow | Incoming app prioritized; minimum LRU eviction; exact idle-slot replacement when possible. |
| [ ] | C05 | Incoming app individually larger than display | Usable current apps remain; impossible app handled explicitly. |
| [ ] | C06 | Recent primary competes with fitting app count | No eviction solely to enlarge primary. |
| [ ] | C07 | Terminal cell rounding and another grid-sized client | Bounded inward fit/accepted slack; policy works without app-name special cases. |
| [ ] | C08 | App previously large accepts a smaller size later | Stale learned minimum clears on accepted smaller bounds; affected axis only. |
| [ ] | C09 | Hung/elevated/protected/refusing window | Bounded failure; no UI hang or endless random repositioning. |
| [ ] | C10 | Native delayed rebound after commit | Bounded same-tree repair only; stale repair invalidated by newer gesture/history. |
| [ ] | C11 | Overflow minimization off | Previous valid geometry retained with clear status if no fit. |
| [ ] | C12 | Negative monitor origins, portrait, mixed DPI and cross-monitor drag | Physical bounds correct; visual DIPs and native frame margins handled explicitly. |

## Work area and shell

| Status | ID | Scenario | Required result |
| --- | --- | --- | --- |
| [ ] | W01 | Hide/show taskbar from tray and Settings | Same state path; correct reclaimed area and return without Refresh. |
| [ ] | W02 | Repeat hide/show 10 times without other changes | No progressive drift, new tree or inflated minimum; exact original joins when feasible. |
| [ ] | W03 | Change taskbar reservation/monitor/display DPI | Only affected geometry reconciles; no stale available dimensions. |
| [ ] | W04 | Reveal auto-hidden taskbar during drag preview | Preview/commit share applied geometry; no misorganized slot highlights. |
| [ ] | W05 | Toggle while gesture/native animation is active | Coalesced after safe boundary; no double visible fit or stale callback. |
| [ ] | W06 | Manual OS preference change while Bento owns override | Manual choice wins on release; journal keeps original ownership correct. |
| [ ] | W07 | Interrupted OS override and restart | Recovery restores owned values; new session hide control off. |
| [ ] | W08 | Multiple taskbars/other appbars | Usable bounds exclude actual reservations; supported limitations recorded. |

## Grips and snapping

| Status | ID | Scenario | Required result |
| --- | --- | --- | --- |
| [ ] | G01 | Two-app divider on each axis | 80-DIP specific ink, 100%; entire exposed gap draggable. |
| [ ] | G02 | Aligned 2×2 immediately after activation | Long universal plus local pills available without prior snap. |
| [ ] | G03 | Pointer near local center versus rest of seam | ±80-DIP local hit range; universal remainder; deterministic overlap resolution. |
| [ ] | G04 | Hold universal while pointer leaves old panel | Local pills stay 100%, full line 45%; same thickness and no input-target change. |
| [ ] | G05 | Drag local top/bottom or left/right grip | Only corresponding section moves; unrelated panes unchanged. |
| [ ] | G06 | Native inner border resize | Smallest feasible local section changes; final release sample included. |
| [ ] | G07 | Near-align adjoining rows then pull away | Exact snap at 12-DIP threshold when feasible, reversible break; perpendicular handles restored. |
| [ ] | G08 | Transpose previous case for columns | Identical symmetric behavior. |
| [ ] | G09 | Left two columns align beside full-height third | Joined partial subgroup grip active; unrelated third unchanged. |
| [ ] | G10 | Shared partial group of three or more slots | Not restricted to two-slot groups or full-screen lines. |
| [ ] | G11 | Minimum clamp prevents exact snap | No false joined cue or impossible handle. |
| [ ] | G12 | Join one seam with other joins already present | Only dragged connected newly joined universal cues; no all-grip pulse. |
| [ ] | G13 | Move existing universal without a new join | No repeated snap cue. |
| [ ] | G14 | Off-center grab with odd gap, Escape, fast release | No jump; one history entry; accurate final/cancel geometry. |
| [ ] | G15 | Hover on gap covered by floating app | App receives click; hidden grip cannot steal it. |
| [ ] | G16 | Window behind Bento dim layer | Grips above dim and underlying window, below Bento/floating apps. |

## Drag and preview

| Status | ID | Scenario | Required result |
| --- | --- | --- | --- |
| [ ] | D01 | Center swap and held split in all four directions | Preview matches final tree; only changed neighbors indicated. |
| [ ] | D02 | Floating center insertion and empty monitor | No occupant ejected; right/bottom rule based on target aspect. |
| [ ] | D03 | Physical edge section swap: large right app, left stacked pair | Whole sections exchange, internal geometry retained; no minimum-size leaf-swap failure. |
| [ ] | D04 | Already outermost section and another-display edge | No unintended section rearrangement. |
| [ ] | D05 | Stationary hold, jitter, leave/reenter target | Stable cached geometry; hold resets correctly; bounded recomputation. |
| [ ] | D06 | Impossible target, gap/outside drop, Escape | Amber conflict or invalid target; committed layout retained/restored. |
| [ ] | D07 | Source/target closes mid-drag or quick release before next poll | Survivors valid, no duplicates/loss or phantom commits. |
| [ ] | D08 | Drag Settings or another excluded window | All resize grips suppressed until release; no Bento target/commit. |
| [ ] | D09 | Slot preview visual capture in light/dark/transparency-off | Neutral frost, gentle outline, full-display 45% black underlay; no old wash, blue, labels or icons. |

## Pause and desktop isolation

| Status | ID | Scenario | Required result |
| --- | --- | --- | --- |
| [ ] | P01 | Pause from active or inactive valid workspace | All members dim immediately, including previously focused member. |
| [ ] | P02 | Open new app while paused | Floats above dim; tree unchanged. |
| [ ] | P03 | Single-click a paused Bento app | App surfaces above tint on first click and receives interaction. |
| [ ] | P04 | Resume through tray single click or Settings | Eligible floating apps minimize; original tree returns; Settings excluded. |
| [ ] | P05 | Restore/open a floating app after Resume | Normal admission works again; no lingering exclusion. |
| [ ] | P06 | Rapid Pause/Resume requests | Latest intent wins, no stuck disabled control or stale dim. |
| [ ] | P07 | Switch among two populated and one empty desktop | Independent state/layout/Pause, new desktop Off, no cross-desktop writes. |
| [ ] | P08 | Task View, Alt+Tab, lock/unlock during drag/animation | Helpers inactive/hidden appropriately; no ghost hit areas or membership corruption. |
| [ ] | P09 | Fullscreen one Bento member then return | Slot reservation retained, no taskbar forced visible; nearest original tree restored. |
| [ ] | P10 | Close fullscreen member; maximize normal member separately | Reservation released on actual close; maximize not blindly treated as fullscreen. |
| [ ] | P11 | Display removal or desktop deletion | Safe explicit migration/reconciliation; no stale helpers or unintended app relocation. |

## UI, motion and performance

| Status | ID | Scenario | Required result |
| --- | --- | --- | --- |
| [ ] | U01 | Tray menu and click/hold/cancel states | Compact specified order/icons; paused click resumes; 550-ms hold consumed once. |
| [ ] | U02 | Workspace settings at compact and normal widths | Trailing toggles incl. Pause; native readable titlebar; no clipped actions. |
| [ ] | U03 | Change gap/margin/theme/darkness/duration live | Applied geometry stays synchronized; user preferences retained. |
| [ ] | U04 | Onboarding, shortcut conflict/disable, start at login | Windows-native wording; no fake Mac permissions; recoverable shortcut failure. |
| [ ] | U05 | On/Off, close, split, swap and cancelled return animation | Shared smooth easing/final frames, no serial jumps/overshoot; focus/shadows intact. |
| [ ] | U06 | Animations disabled, reduced motion, high contrast, no transparency | Readable supported fallbacks; no involuntary animated movement. |
| [ ] | U07 | Idle, paused, overview and active dragging profile | Record CPU/private bytes/handles/GDI/input latency/frame timings before and after. |
| [ ] | U08 | 250 unchanged geometry requests and repeated hover | Identical handles; cache hits; no native writes for unchanged layout. |
| [ ] | U09 | Long repeated drag/pause/desktop/update-error cycle | No timer/hook/helper leaks, stale tasks, resource growth or stuck state. |

## Updates and release

| Status | ID | Scenario | Required result |
| --- | --- | --- | --- |
| [ ] | R01 | Check from legacy Windows updater against shared GitHub release | Discover actual newer Windows version; migration route documented if legacy tag parser blocks OTA. |
| [ ] | R02 | Mac-tagged release and different embedded Windows version | Use Windows metadata/version; do not compare Mac version to Windows version. |
| [ ] | R03 | Download/stage tampered/wrong-platform/unsafe archive | Reject before replacement; preserve recoverable current installation. |
| [ ] | R04 | Install/restart with arranged/minimized apps, including other desktops | All frames/minimized states unchanged; no restore-on-dispose; one click advances. |
| [ ] | R05 | Install failure/retry/double click | Backup rollback, no lost continuation or duplicate updater processes. |
| [ ] | R06 | What's New, Update Log and popup | Compact per-release bullets and actual Windows changes/version. |
| [ ] | R07 | Release assets | Both Mac and Windows archives, actual embedded versions/hashes/requirements verified. |
| [ ] | R08 | Installed PC build after OTA | Verify installed version and real live behaviors; upload success alone is insufficient. |

## Final sign-off

- [ ] Every EXPERIENCE.md section mapped to evidence, including details beyond these representative scenarios.
- [ ] Existing PC work preserved and both platform test suites remain green where shared fixtures changed.
- [ ] Real Windows install/restart verified; any legacy bootstrap limitation explained.
- [ ] CPU/memory/frame claims supported by measurements, not geometry microbenchmarks alone.
- [ ] No unverified physical behavior or unsupported platform capability described as complete parity.
