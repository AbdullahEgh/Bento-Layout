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
        let pinned = model.history.current, incomingFrame = system.frame(of: incoming.element)
        system.undiscovered.removeAll(); system.writes.removeAll()
        await model.arrange(preserving: true)
        try check(model.history.current == pinned && system.frame(of: incoming.element) == incomingFrame
            && system.writes[incoming.id] == nil && !system.isMinimized(incoming), "Pin Bento leaves newly visible apps floating without moving or minimizing them")
        try check(!model.canArrangeWindow(incoming.id), "Pin Bento excludes floating windows from drag admission")
        await model.setPinned(false)
        try check(model.history.current.windows.count == 3, "Unpinning admits floating windows using available space")
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
