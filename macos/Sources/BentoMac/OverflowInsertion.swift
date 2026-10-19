import AppKit
import BentoCore

/// Only Bento-owned overflow is offered here. Already-minimized user windows
/// never enter this queue; native windows remain minimized throughout dragging.
@MainActor final class OverflowInsertion {
    private let model: WorkspaceController
    private let changed: () -> Void
    private var panel: InsertionPanel?
    private var canvas: InsertionCanvas?
    private var dismissed = Set<UUID>()
    private var source: ManagedWindow?
    private var snapshot: Workspace?
    private var candidate: Workspace?
    private var timer: Timer?
    private var committing = false
    init(model: WorkspaceController, changed: @escaping () -> Void) { self.model = model; self.changed = changed }
    var visible: Bool { panel?.isVisible == true }
    private var waiting: [ManagedWindow] {
        model.minimizedByBento.values.filter { model.waitingForInsertion.contains($0.id) && model.system.isAlive($0) && model.system.isMinimized($0) }
            .sorted { $0.application == $1.application ? $0.id.uuidString < $1.id.uuidString : $0.application < $1.application }
    }
    func synchronize() {
        guard !committing, source == nil else { return }
        guard model.active, !model.pinned, !model.activating, !model.shuttingDown,
              !model.desktopOverviewActive, !model.switchingDesktop, model.desktopIsCurrent() else { hide(); return }
        let windows = waiting, ids = Set(windows.map(\.id))
        guard !windows.isEmpty, !ids.isSubset(of: dismissed) else { hide(); return }
        if panel == nil {
            let bounds = NSScreen.screens.reduce(CGRect.null) { $0.union($1.frame) }
            guard !bounds.isNull else { return }
            let p = InsertionPanel(contentRect: bounds, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.title = "Bento Waiting Apps"
            p.isReleasedWhenClosed = false; p.isOpaque = false; p.backgroundColor = .clear
            p.hasShadow = false; p.hidesOnDeactivate = false; p.level = .modalPanel
            p.collectionBehavior = [.stationary, .ignoresCycle]
            let view = InsertionCanvas(frame: NSRect(origin: .zero, size: bounds.size))
            view.begin = { [weak self] id in self?.begin(id) }
            view.move = { [weak self] in self?.update() }
            view.end = { [weak self] in self?.end() }
            view.cancel = { [weak self] in self?.dismiss() }
            p.contentView = view; panel = p; canvas = view
        }
        canvas?.windows = windows
        canvas?.toolTip = windows.map { "\($0.application): \($0.title)" }.joined(separator: "\n")
        canvas?.slots = slots(model.history.current)
        canvas?.selected = nil; canvas?.dragged = nil
        canvas?.needsDisplay = true
        model.insertingOverflow = true
        if let panel, !panel.isVisible {
            panel.alphaValue = 0; panel.makeKeyAndOrderFront(nil)
            if let canvas { panel.makeFirstResponder(canvas) }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22; panel.animator().alphaValue = 1
            }
        }
    }
    func hide() {
        timer?.invalidate(); timer = nil
        if source != nil && !committing { model.interacting = false }
        source = nil; snapshot = nil; candidate = nil
        panel?.orderOut(nil); panel = nil; canvas = nil; model.insertingOverflow = false
    }
    private func dismiss() {
        dismissed.formUnion(waiting.map(\.id)); hide(); changed()
    }
    private func slots(_ workspace: Workspace) -> [Rect] {
        model.interactionAreas().flatMap { area in
            (try? LayoutEngine.calculate(workspace.roots[area.id], in: area.bounds, gap: model.layoutGap).regions.map(\.bounds)) ?? [area.bounds]
        }
    }
    private func begin(_ id: UUID) {
        guard !model.busy, !model.activating, !committing, let window = waiting.first(where: { $0.id == id }) else { return }
        source = window; snapshot = model.history.current
        model.interacting = true
        canvas?.dragged = id; update()
        timer = Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
    }
    private func update() {
        guard let source, let snapshot, model.desktopIsCurrent(), !model.desktopOverviewActive,
              model.history.current == snapshot, model.system.isAlive(source) else { return }
        let pointer = DesktopCoordinates.pointer()
        let areas = Dictionary(uniqueKeysWithValues: model.interactionAreas().map { ($0.id, $0.bounds) })
        candidate = nil; canvas?.selected = nil
        do {
            // Waiting apps replace one complete slot. No split or reflow is
            // attempted: the old occupant becomes the next minimized candidate.
            for (display, area) in areas where area.contains(pointer) {
                let regions = try LayoutEngine.calculate(snapshot.roots[display], in: area, gap: model.layoutGap).regions
                guard let target = regions.first(where: { $0.bounds.contains(pointer) }) else { continue }
                let next = try snapshot.placing(source.leaf, on: display, target: target.window.id, placement: .center)
                _ = try LayoutEngine.calculate(next.roots[display], in: area, gap: model.layoutGap)
                candidate = next; canvas?.selected = target.bounds
            }
        } catch { candidate = nil }
        canvas?.slots = slots(candidate ?? snapshot)
        canvas?.needsDisplay = true
    }
    private func end() {
        timer?.invalidate(); timer = nil; update()
        guard let source, let snapshot, let candidate else {
            self.source = nil; self.snapshot = nil; model.interacting = false; canvas?.dragged = nil; synchronize(); return
        }
        committing = true; canvas?.dragged = nil
        Task { @MainActor in
            _ = await model.insertOverflow(source.id, into: candidate, from: snapshot)
            committing = false; self.source = nil; self.snapshot = nil; self.candidate = nil
            synchronize(); changed()
        }
    }
}

@MainActor private final class InsertionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
@MainActor private final class InsertionCanvas: NSView {
    var windows: [ManagedWindow] = []
    var slots: [Rect] = [], selected: Rect?, dragged: UUID?
    var begin: ((UUID) -> Void)?, move: (() -> Void)?, end: (() -> Void)?, cancel: (() -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    private func local(_ rect: Rect) -> NSRect {
        let frame = DesktopCoordinates.appKit(rect)
        return frame.offsetBy(dx: -(window?.frame.minX ?? 0), dy: -(window?.frame.minY ?? 0))
    }
    private var tiles: [(ManagedWindow, NSRect)] {
        // Keep the queue centered on the pointer's display, not between monitors.
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let area = (screen?.frame ?? bounds).offsetBy(dx: -(window?.frame.minX ?? 0), dy: -(window?.frame.minY ?? 0))
        let columns = max(1, min(windows.count, Int(area.width / 100)))
        let rows = max(1, (windows.count + columns - 1) / columns)
        return windows.enumerated().map { index, window in
            let row = index / columns, col = index % columns
            let count = min(columns, windows.count - row * columns)
            return (window, NSRect(x: area.midX - CGFloat(count * 96) / 2 + CGFloat(col * 96) + 7,
                                  y: area.midY + CGFloat(rows * 96) / 2 - CGFloat((row + 1) * 96) + 7, width: 82, height: 82))
        }
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.48).setFill(); bounds.fill()
        if dragged != nil {
            for slot in slots {
                let r = local(slot).insetBy(dx: 1, dy: 1)
                let active = slot == selected
                NSColor.white.withAlphaComponent(active ? 0.22 : 0.035).setFill()
                let path = NSBezierPath(roundedRect: r, xRadius: 12, yRadius: 12); path.fill()
                NSColor.white.withAlphaComponent(active ? 0.65 : 0.15).setStroke(); path.lineWidth = 1; path.stroke()
            }
        }
        for (app, tile) in tiles where dragged == nil || dragged == app.id {
            var rect = tile
            if dragged == app.id {
                let point = convert(window?.convertPoint(fromScreen: NSEvent.mouseLocation) ?? .zero, from: nil)
                rect.origin = NSPoint(x: point.x - 41, y: point.y - 41)
            }
            NSColor.white.withAlphaComponent(0.16).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 16, yRadius: 16).fill()
            let icon = NSRunningApplication(processIdentifier: app.pid)?.icon ?? NSImage(named: NSImage.applicationIconName)
            icon?.draw(in: NSRect(x: rect.minX + 19, y: rect.minY + 26, width: 44, height: 44))
            let textStyle = NSMutableParagraphStyle(); textStyle.alignment = .center; textStyle.lineBreakMode = .byTruncatingTail
            (app.title as NSString).draw(in: NSRect(x: rect.minX + 5, y: rect.minY + 6, width: 72, height: 15),
                withAttributes: [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.white.withAlphaComponent(0.9), .paragraphStyle: textStyle])
        }
    }
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let tile = tiles.first(where: { $0.1.contains(point) }) { begin?(tile.0.id) }
        else { cancel?() }
    }
    override func mouseDragged(with event: NSEvent) { if dragged != nil { move?() } }
    override func mouseUp(with event: NSEvent) { if dragged != nil { end?() } }
    override func keyDown(with event: NSEvent) { if event.keyCode == 53 { cancel?() } else { super.keyDown(with: event) } }
}
