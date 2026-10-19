import AppKit
import ApplicationServices
import BentoCore

@MainActor enum ResizeHandleSmoke {
    static func run(system: FixtureWindowSystem, output: URL) async throws -> [String] {
        var passed: [String] = []
        func check(_ ok: Bool, _ label: String) throws {
            guard ok else { throw NSError(domain: "BentoResizeSmoke", code: 1, userInfo: [NSLocalizedDescriptionKey: label]) }
            passed.append(label)
        }
        let extra = NSWindow(contentRect: NSRect(x: 200, y: 100, width: 420, height: 320), styleMask: [.titled, .resizable, .closable], backing: .buffered, defer: false)
        extra.isReleasedWhenClosed = false; extra.title = "Bento independent seam fixture"; extra.orderFrontRegardless()
        let record = ManagedWindow(element: AXUIElementCreateApplication(-1005), pid: ProcessInfo.processInfo.processIdentifier,
            title: extra.title, application: "Bento Fixture", bundleID: "com.abdullahegh.bento.fixture", frame: DesktopCoordinates.engine(extra.frame))
        record.minimum = Size(600, 641)
        record.reconcileObservedMinimum()
        try check(record.minimum == Size(record.frame.width, record.frame.height),
            "Observed smaller native dimensions remove stale learned constraints on both axes")
        record.minimum = Size(160, 120)
        record.reconcileObservedMinimum()
        try check(record.minimum == Size(160, 120), "A larger observed frame never raises a window minimum")
        record.updateReportedMinimum(Size(100, 90))
        try check(record.minimum == Size(100, 90), "Reported small-window limits are not inflated by the initial fallback")
        record.learnMinimum(width: 360)
        record.updateReportedMinimum(Size(100, 90))
        try check(record.minimum == Size(360, 90), "Optimistic reported limits retain an observed refused axis without restricting the other axis")
        record.reconcileObservedMinimum(Rect(0, 0, 240, 180))
        record.updateReportedMinimum(Size(100, 90))
        try check(record.minimum == Size(240, 90), "Smaller accepted frames invalidate stale observed minimum evidence")
        record.minimum = Size(160, 120)
        system.records.append((record, extra))
        defer { system.records.removeLast(); extra.close() }
        let cue = GripView(axis: .vertical)
        cue.frame = NSRect(x: 0, y: 0, width: 700, height: 14)
        let cueBounds = cue.bounds
        cue.shared = true; cue.localCenters = [175, 525]
        cue.showJoinCue()
        try? await Task.sleep(for: .milliseconds(150))
        try check(cue.visibleJoinCue == 1 && cue.bounds == cueBounds && cue.visibleInk == 0,
            "Joined boundary cue starts fully visible without changing hit areas or idle hover ink")
        if let bitmap = cue.bitmapImageRepForCachingDisplay(in: cue.bounds) {
            cue.cacheDisplay(in: cue.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])?.write(to: output.appendingPathComponent("segmented-grip.png"))
        }
        try? await Task.sleep(for: .milliseconds(600))
        try check(cue.visibleJoinCue == 0, "Joined boundary cue fades away automatically")
        var settings = MacSettings(); settings.animate = false
        let model = WorkspaceController(system: system, settings: settings,
            preferences: ActivationOverrides(backend: FixturePreferences(), journal: output.appendingPathComponent("resize-handles.json")),
            persistSettings: { _ in }, backgroundMonitoring: false)
        await model.arrange()
        let display = model.displayAreas()[0], area = display.bounds
        let leaves = system.records.map { LayoutNode.window($0.0.leaf) }
        func split(_ axis: Axis, _ a: LayoutNode, _ b: LayoutNode) -> LayoutNode {
            .split(id: UUID(), axis: axis, ratio: 0.5, first: a, second: b)
        }
        let grid = Workspace(roots: [display.id: split(.horizontal, split(.vertical, leaves[0], leaves[1]), split(.vertical, leaves[2], leaves[3]))])
        try await model.finishInteraction(grid, commit: true, animate: false)
        var input = DesktopInput(point: Point(0, 0), pressed: false, escape: false, time: 0)
        let interactions = DesktopInteractions(model: model, input: { input }, automaticSampling: false)
        interactions.synchronize()
        let builds = interactions.handleCalculationCount
        for _ in 0..<20 { interactions.synchronize() }
        try check(interactions.handleCalculationCount == builds, "Unchanged helper refreshes reuse geometry without rebuilding split alternatives")
        let committedAreas = model.interactionAreas()
        let originalOverride = system.areaOverride
        for inset in [Rect(area.x, area.y + 24, area.width, area.height - 24),
                      Rect(area.x, area.y, area.width, area.height - 48),
                      Rect(area.x, area.y + 24, area.width, area.height - 72)] {
            system.areaOverride = [DisplayArea(id: display.id, name: display.name, bounds: inset)]
            try check(model.interactionAreas() == committedAreas,
                "Transient Dock/menu reveal keeps preview geometry anchored to committed slots: \(inset)")
        }
        system.areaOverride = originalOverride
        system.desktopPointerEnabled = false
        input.point = Point(area.x + 20, area.y + 20); input.pressed = true
        interactions.sample(); interactions.synchronize()
        try check(interactions.visibleGripCount == 0 && model.system.dividerWindowNumbers.isEmpty && !model.interacting,
            "Excluded Settings press hides grips without entering a layout gesture")
        input.pressed = false; interactions.sample()
        try check(interactions.visibleGripCount > 0 && !model.system.dividerWindowNumbers.isEmpty,
            "Releasing an excluded window restores grip visuals and input surfaces")
        system.desktopPointerEnabled = true
        let saved = model.history.current
        interactions.setOverviewActive(true)
        try check(interactions.visibleGripCount == 0 && model.system.dividerWindowNumbers.isEmpty,
            "Mission Control removes grip visuals and hit surfaces")
        system.writes.removeAll(); model.tick(); interactions.sample()
        try check(system.writes.isEmpty && model.history.current == saved && !model.interacting,
            "Mission Control suspends pointer gestures and automatic layout changes")
        interactions.setOverviewActive(false)
        try check(interactions.visibleGripCount > 0 && model.history.current == saved && interactions.handleCalculationCount == builds,
            "Leaving Mission Control restores the same grips and saved layout without rebuilding")
        input.pressed = false; interactions.sample()
        let layout = try LayoutEngine.calculate(grid.roots[display.id], in: area, gap: model.layoutGap)
        let x = layout.dividers[0].bounds.x + 1
        let bottom = layout.regions.first { $0.bounds.y > area.y }!.bounds
        let bottomY = bottom.y + bottom.height / 2
        let before = system.records.map { system.frame(of: $0.0.element)! }
        input.point = Point(x, bottomY); input.pressed = true; interactions.sample()
        try check(model.interacting, "Pointer input selects a local bottom-column grip on the existing gap")
        input.point.x -= 35; interactions.sample()
        await interactions.finish(cancel: false)
        input.pressed = false; interactions.sample()
        let after = system.records.map { system.frame(of: $0.0.element)! }
        try check(before[0] == after[0] && before[2] == after[2] && before[1] != after[1] && before[3] != after[3],
            "A bottom-section drag changes only the two bottom native windows")
        await model.undo(); interactions.synchronize()
        try check(model.history.current == grid, "Undo restores the original split structure after a local seam rotation")
        input.point = Point(x, area.bottom - 12); input.pressed = true; interactions.sample()
        input.point.x -= 25; interactions.sample()
        await interactions.finish(cancel: false)
        input.pressed = false; interactions.sample()
        try check(system.records.enumerated().allSatisfy { index, pair in system.frame(of: pair.0.element) != before[index] },
            "The joined gap away from local grip ink moves the complete native column")
        await model.undo(); interactions.synchronize()
        let midY = layout.dividers.first { $0.axis == .vertical }!.bounds.y + 1
        input.point = Point(area.x + area.width / 2, midY); input.pressed = true; interactions.sample()
        input.point.y += 25; interactions.sample()
        await interactions.finish(cancel: false)
        input.pressed = false; interactions.sample()
        let joined = try LayoutEngine.calculate(model.history.current.roots[display.id], in: area, gap: model.layoutGap)
        let top = joined.regions.filter { $0.bounds.y == area.y }
        try check(top.count == 2 && Set(top.map { $0.bounds.bottom }).count == 1 && top[0].bounds.bottom == midY - 1 + 25,
            "The longer center grip moves the full row with both native boundaries joined")
        await model.undo(); interactions.synchronize()
        input.point = Point(x, bottomY); input.pressed = true; interactions.sample()
        input.point.x -= 30; interactions.sample()
        await interactions.finish(cancel: true)
        input.pressed = false; interactions.sample()
        try check(model.history.current == grid && system.records.map { system.frame(of: $0.0.element)! } == before,
            "Cancelling a local grip restores the original tree and all native frames")
        input.point = Point(x, bottomY); input.pressed = true; interactions.sample()
        input.point.x -= 35; interactions.sample()
        await interactions.finish(cancel: false)
        input.pressed = false; interactions.sample()
        input.point = Point(x - 35, bottomY); input.pressed = true; interactions.sample()
        input.point.x = x - 6; interactions.sample()
        await interactions.finish(cancel: false)
        input.pressed = false; interactions.sample()
        try check(system.records.map { system.frame(of: $0.0.element)! } == before,
            "Dragging a separated section near its neighbor snaps the native panes into one continuous boundary")
        let snappedHandles = try ResizeHandles.calculate(model.history.current.roots[display.id]!, in: area, gap: model.layoutGap)
        try check(snappedHandles.contains { $0.divider.axis == .vertical && $0.divider.parent.x > area.x },
            "Joining column sections restores the perpendicular local row grip")
        let nativeWindow = system.records[0].0
        let priorPointed = system.pointed
        system.pointed = nativeWindow
        let nativeBefore = system.frame(of: nativeWindow.element)!
        nativeWindow.minimum.height = nativeBefore.height
        input.point = Point(nativeBefore.x + 80, nativeBefore.bottom - 1)
        input.pressed = true; interactions.sample()
        let smaller = Rect(nativeBefore.x, nativeBefore.y, nativeBefore.width, nativeBefore.height - 30)
        try system.write(nativeWindow, frame: smaller)
        input.point.y -= 30; interactions.sample()
        await interactions.finish(cancel: false)
        input.pressed = false; interactions.sample()
        try check(system.frame(of: nativeWindow.element)?.height == smaller.height && nativeWindow.minimum.height == smaller.height,
            "A native resize below a stale limit is retained instead of being clamped back by Bento")
        system.pointed = priorPointed
        await model.stopAllDesktops(); interactions.synchronize()
        let originalRecords = system.records
        for bundle in ["com.apple.systempreferences", "com.abdullahegh.bento"] {
            let old = system.records[2].0
            let ignored = ManagedWindow(element: old.element, pid: old.pid, title: "Settings fixture",
                application: "Settings", bundleID: bundle, frame: system.frame(of: old.element)!)
            system.records[2] = (ignored, system.records[2].1)
            let before = system.frame(of: ignored.element)
            await model.arrange(); await model.setPinned(true)
            try check(!model.history.current.windows.contains { $0.windowID == ignored.id },
                "Settings windows stay outside layout admission: \(bundle)")
            system.writes.removeAll()
            await model.setPinned(false)
            try check(!system.isMinimized(ignored) && system.writes[ignored.id] == nil && system.frame(of: ignored.element) == before,
                "Unpin leaves Settings visible and untouched: \(bundle)")
            await model.stopAllDesktops()
            system.records = originalRecords
        }
        var idleSamples = 0
        let idle = DesktopInteractions(model: model, input: { idleSamples += 1; return DesktopInput(point: Point(0, 0), pressed: false, escape: false, time: 0) }, observeOverview: false)
        idle.synchronize()
        try? await Task.sleep(for: .milliseconds(60))
        try check(!idle.pointerSamplingActive && idleSamples == 0, "Bento off has no pointer timer or pointer polling")
        let preShutdownFrames = system.records.map { DesktopCoordinates.engine($0.1.frame) }
        await model.arrange()
        let shutdownLayout = try LayoutEngine.calculate(model.history.current.roots[display.id], in: model.interactionAreas()[0].bounds, gap: model.layoutGap)
        let shutdownDivider = shutdownLayout.dividers[0]
        input.point = Point(shutdownDivider.bounds.x + 1, shutdownDivider.bounds.y + 1)
        try check(interactions.beginGrip(display: display.id, id: shutdownDivider.id), "Shutdown fixture begins an active divider gesture")
        let shutdownFrames = system.records.map { DesktopCoordinates.engine($0.1.frame) }
        system.writes.removeAll(); model.beginShutdownKeepingWindows()
        await interactions.abandonForShutdown(); await model.finishShutdownKeepingWindows()
        interactions.synchronize(); interactions.sample()
        try check(system.writes.isEmpty && system.records.map { DesktopCoordinates.engine($0.1.frame) } == shutdownFrames
            && interactions.visibleGripCount == 0 && !model.interacting,
            "Quit/update abandons a gesture without rollback writes and removes helper panels")
        model.resumeAfterShutdownFailure(); interactions.resumeAfterShutdownFailure()
        await model.arrange()
        try check(model.active && !model.shuttingDown, "A deferred installation can return to a usable Bento session")
        await model.stopAllDesktops()
        for (index, entry) in system.records.enumerated() { try system.write(entry.0, frame: preShutdownFrames[index]) }
        // Real WindowServer ordering with disposable surfaces, independent of AX.
        let stackRect = NSRect(x: 100, y: 100, width: 200, height: 150)
        let under = NSPanel(contentRect: stackRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        let tiled = NSPanel(contentRect: stackRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        let floating = NSPanel(contentRect: stackRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        for panel in [under, tiled, floating] { panel.isReleasedWhenClosed = false; panel.animationBehavior = .none; panel.level = .normal; panel.orderFrontRegardless() }
        let background = DesktopBackdrop()
        background.show(darkness: 30, animated: false, belowWindow: tiled.windowNumber)
        let handle = GapPanel(axis: .horizontal)
        handle.setFrame(stackRect, display: true); handle.level = .normal
        handle.order(.below, relativeTo: tiled.windowNumber)
        defer { background.hide(animated: false); for panel in [under, tiled, floating, handle] { panel.close() } }
        try? await Task.sleep(for: .milliseconds(40))
        let ordered = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let numbers = ordered.compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.intValue }
        let order = [floating.windowNumber, tiled.windowNumber, handle.windowNumber, under.windowNumber]
        let positions = order.compactMap { numbers.firstIndex(of: $0) }
        try check(positions.count == order.count && zip(positions, positions.dropFirst()).allSatisfy { $0 < $1 }
            && background.windowNumbers.allSatisfy { number in
                guard let i = numbers.firstIndex(of: number), let h = numbers.firstIndex(of: handle.windowNumber), let u = numbers.firstIndex(of: under.windowNumber) else { return false }
                return h < i && i < u
            },
            "Grips stack above dimmed underlying windows and below Bento members and floating apps: positions=\(positions), backdrop=\(background.windowNumbers.compactMap { numbers.firstIndex(of: $0) })")
        let rect = DesktopCoordinates.engine(stackRect), point = Point(rect.x + 30, rect.y + 30)
        let fixtureNumbers = Set(order + background.windowNumbers)
        func fixtureStack() -> [[String: Any]] {
            let entries = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
            return entries.filter { fixtureNumbers.contains(($0[kCGWindowNumber as String] as? NSNumber)?.intValue ?? -1) }
        }
        try check(!MacWindowSystem.dividerIsExposed(at: point, visible: fixtureStack(), dividerWindowNumbers: [handle.windowNumber]),
            "A floating app covering a grip prevents divider input")
        floating.orderOut(nil); tiled.orderOut(nil)
        try? await Task.sleep(for: .milliseconds(40))
        try check(MacWindowSystem.dividerIsExposed(at: point, visible: fixtureStack(), dividerWindowNumbers: [handle.windowNumber]),
            "An underlying normal window does not block the exposed grip above it")
        return passed
    }
}
