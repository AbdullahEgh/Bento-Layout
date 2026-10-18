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
        system.records.append((record, extra))
        defer { system.records.removeLast(); extra.close() }
        let cue = GripView(axis: .vertical)
        cue.frame = NSRect(x: 0, y: 0, width: 700, height: 14)
        let cueBounds = cue.bounds
        cue.showJoinCue()
        try? await Task.sleep(for: .milliseconds(150))
        try check(cue.visibleJoinCue > 0 && cue.bounds == cueBounds && cue.visibleInk == 0,
            "Joined boundary cue appears without changing the grip hit area or idle hover ink")
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
        let layout = try LayoutEngine.calculate(grid.roots[display.id], in: area, gap: model.layoutGap)
        let x = layout.dividers[0].bounds.x + 1
        let bottomY = area.y + area.height * 4 / 5
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
        return passed
    }
}
