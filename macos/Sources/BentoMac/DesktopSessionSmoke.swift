import AppKit
import BentoCore

@MainActor enum DesktopSessionSmoke {
    static func run(system: FixtureWindowSystem, initial: [Rect], output: URL) async throws -> [String] {
        var passed: [String] = []
        func check(_ condition: Bool, _ label: String) throws {
            guard condition else { throw NSError(domain: "BentoDesktopSmoke", code: 1, userInfo: [NSLocalizedDescriptionKey: label]) }
            passed.append(label)
        }
        try check(DesktopIdentity.current() != nil, "The running macOS resolves a stable read-only desktop identity")
        try check(["power", "arrow.uturn.backward", "menubar.dock.rectangle", "pin", "gearshape", "xmark.circle"].allSatisfy {
            NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil
        }, "Every menu action has an available native symbol")
        for _ in 0..<20 {
            if DesktopIdentity.containsWindow(system.records[0].1.windowNumber) == true { break }
            try? await Task.sleep(for: .milliseconds(25))
        }
        try check(DesktopIdentity.containsWindow(system.records[0].1.windowNumber) == true,
            "Read-only membership resolves a native window on the current desktop")
        var settings = MacSettings(); settings.animate = false; settings.minimizeOverflow = true
        let model = WorkspaceController(system: system, settings: settings,
            preferences: ActivationOverrides(backend: FixturePreferences(), journal: output.appendingPathComponent("desktop-sessions.json")),
            persistSettings: { _ in }, backgroundMonitoring: false)
        await model.arrange()
        let remembered = model.history.current
        await model.stop()
        try check(system.records.map { DesktopCoordinates.engine($0.1.frame) } == initial, "Automatic layout memory restores normal frames when Bento stops")
        await model.toggleLayout()
        try check(model.history.current == remembered, "An unedited automatically remembered layout resumes without an explicit save")
        await model.stop()
        let incoming = system.records[2].0
        system.undiscovered = [incoming.id]
        await model.arrange()
        let nativeArea = model.displayAreas()[0]
        let cellHeight = max(150, ((nativeArea.bounds.height - model.layoutGap) / 2 / 15 - 1) * 15 + 5)
        let alignmentArea = Rect(nativeArea.bounds.x, nativeArea.bounds.y, nativeArea.bounds.width, cellHeight * 2 + model.layoutGap)
        system.areaOverride = [DisplayArea(id: nativeArea.id, name: nativeArea.name, bounds: alignmentArea)]
        let first = system.records[0].0, second = system.records[1].0
        system.nativeGrid[first.id] = Size(1, 15)
        let split = LayoutNode.split(id: UUID(), axis: .vertical, ratio: 0.5, first: .window(first.leaf), second: .window(second.leaf))
        try await model.finishInteraction(Workspace(roots: [nativeArea.id: split]), commit: true)
        let firstFrame = system.frame(of: first.element)!, secondFrame = system.frame(of: second.element)!
        try check(secondFrame.y - firstFrame.bottom == model.layoutGap,
            "Cell-sized native windows align the shared divider and give spare pixels to their neighbor")
        system.nativeGrid.removeAll(); system.areaOverride = nil
        await model.arrange(preserving: true); await model.setPinned(true)
        var pinRefreshes = 0
        model.onStateChange = { pinRefreshes += 1 }
        system.focused = first
        model.applicationActivated(first.pid)
        try check(pinRefreshes > 0, "Focusing a pinned app refreshes its dim layer without moving windows")
        model.onStateChange = nil; system.focused = nil
        let pinned = model.history.current, incomingFrame = system.frame(of: incoming.element)
        system.undiscovered.removeAll(); system.writes.removeAll()
        await model.arrange(preserving: true)
        try check(model.history.current == pinned && system.frame(of: incoming.element) == incomingFrame
            && system.writes[incoming.id] == nil && !system.isMinimized(incoming), "Pin Bento leaves newly visible apps floating without moving or minimizing them")
        try check(!model.canArrangeWindow(incoming.id), "Pin Bento excludes floating windows from drag admission")
        await model.setPinned(false)
        try check(model.history.current == pinned && system.isMinimized(incoming), "Unpinning minimizes floating windows and preserves the pinned layout")
        let compactArea = model.displayAreas()[0]
        let originalTree = model.history.current
        system.areaOverride = [DisplayArea(id: compactArea.id, name: compactArea.name,
            bounds: Rect(compactArea.bounds.x, compactArea.bounds.y + 25, compactArea.bounds.width, 200))]
        await model.arrange(preserving: true)
        try check(Set(model.history.current.windows.map(\.windowID)) == Set(originalTree.windows.map(\.windowID)) && system.isMinimized(incoming),
            "A tighter work area keeps existing membership without readmitting minimized windows")
        system.areaOverride = nil
        await model.arrange(preserving: true)
        try check(model.history.current == originalTree, "Restoring usable space restores the original split ratios and membership")
        system.undiscovered = Set(model.history.current.windows.map(\.windowID))
        await model.arrange(preserving: true)
        try check(model.history.current == originalTree, "Temporary discovery loss preserves live nonminimized layout members")
        system.undiscovered.removeAll()
        system.outsideDesktop = [first.id]; system.undiscovered = [first.id]
        await model.arrange(preserving: true)
        try check(!model.history.current.windows.contains { $0.windowID == first.id },
            "A window moved to another desktop is not retained as a transient interruption")
        system.outsideDesktop.removeAll(); system.undiscovered.removeAll()
        await model.stop()
        system.undiscovered = [incoming.id]
        await model.arrange(); await model.setPinned(true)
        let desktopA = model.history.current
        system.writes.removeAll()
        await model.desktopDidChange()
        try check(model.history.current == desktopA && system.writes.isEmpty,
            "Duplicate desktop notifications do not reset history or rewrite windows")
        system.writes.removeAll(); system.fixtureDesktop = "fixture-second"
        system.undiscovered = Set(system.records.prefix(2).map { $0.0.id })
        await model.desktopDidChange()
        try check(!model.active && !model.pinned && model.history.current.windows.isEmpty && system.writes.isEmpty,
            "A new desktop starts independently without restoring or moving the previous desktop's windows")
        await model.arrange()
        try check(model.history.current.windows.map(\.windowID) == [incoming.id], "The second desktop arranges only its own visible windows")
        system.fixtureDesktop = "fixture-main"; system.undiscovered = [incoming.id]; system.writes.removeAll()
        await model.desktopDidChange()
        try check(model.active && model.pinned && model.history.current == desktopA && system.writes[incoming.id] == nil,
            "Returning to a desktop restores its own layout and Pin state without touching another desktop")
        await model.stopAllDesktops()
        system.undiscovered.removeAll()
        try check(system.records.map { DesktopCoordinates.engine($0.1.frame) } == initial, "Ending all desktop sessions restores each window's own original geometry")
        model.busy = true
        let queuedPin = Task { await model.setPinned(true) }
        await Task.yield()
        try check(!model.active && !model.pinned, "Pin waits for an in-progress transaction instead of overlapping it")
        model.busy = false
        await queuedPin.value
        try check(model.active && model.pinned, "A queued Pin request can activate Bento from off without being discarded")
        await model.stopAllDesktops()
        let backdrop = DesktopBackdrop()
        backdrop.show(darkness: 90, animated: false)
        try check(backdrop.opacity == 0.9, "Black backdrop uses the requested darkness")
        backdrop.hide(animated: true)
        backdrop.show(darkness: 50, animated: false)
        try check(backdrop.opacity == 0.5, "A new backdrop appearance cancels an interrupted fade-out")
        backdrop.hide(animated: false)
        try check(backdrop.opacity == 0, "Backdrop removal completes without leaving a dark panel")
        return passed
    }
}
