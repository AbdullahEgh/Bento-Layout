import AppKit
import ApplicationServices
import BentoCore

// Observe pointer state and the focused AX window; no event tap intercepts application
// input. Only gap panels receive mouse events. External window content remains usable.
struct DesktopInput {
    var point: Point; var pressed: Bool; var escape: Bool; var time: Double
    @MainActor static func current() -> DesktopInput {
        DesktopInput(point: DesktopCoordinates.pointer(), pressed: CGEventSource.buttonState(.combinedSessionState, button: .left), escape: CGEventSource.keyState(.combinedSessionState, key: 53), time: ProcessInfo.processInfo.systemUptime)
    }
}
@MainActor final class DesktopInteractions {
    private let model: WorkspaceController
    private let input: () -> DesktopInput
    private let trace: ((String) -> Void)?
    private var pulse: Timer?
    private var spaceObserver: NSObjectProtocol?
    private var grips: [UUID: GapPanel] = [:]
    private let preview = DestinationPanel()
    private let backdrop = DesktopBackdrop()
    private var wasPressed = false, waitForRelease = false, finishing = false
    private var pressedWindow: ManagedWindow?
    private var pressedFrame: Rect?
    private var pressPoint = Point(0, 0)
    private var session: DropSession?
    private var snapshot: Workspace?
    private var candidate: Workspace?
    private var nativeResize = false
    private var grip: (display: String, divider: Divider)?
    private var pending: Workspace?
    private var liveTask: Task<Void, Never>?
    private var liveFailure = false
    init(model: WorkspaceController, input: (() -> DesktopInput)? = nil, automaticSampling: Bool = true, trace: ((String) -> Void)? = nil) {
        self.model = model; self.input = input ?? { DesktopInput.current() }; self.trace = trace
        guard automaticSampling else { return }
        pulse = Timer(timeInterval: 1 / 45, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.sample() } }
        RunLoop.main.add(pulse!, forMode: .common)
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                await self.finish(cancel: true); self.removeHelpers()
                if self.model.active { await self.model.arrange(preserving: true) }; self.synchronize()
            }
        }
    }
    var helperFrames: [Rect] { grips.values.map { DesktopCoordinates.engine($0.frame) } }
    func synchronize() {
        guard model.active, model.permission, !model.interacting else { if !model.interacting { removeHelpers() }; return }
        updateGrips(model.history.current)
    }
    private func areas() -> [String: Rect] { Dictionary(uniqueKeysWithValues: DisplayArea.all(margin: model.settings.margin).map { ($0.id, $0.bounds) }) }
    private func removeHelpers() { grips.values.forEach { $0.orderOut(nil) }; grips.removeAll(); preview.orderOut(nil); backdrop.hide() }
    private func updateGrips(_ workspace: Workspace) {
        backdrop.show(darkness: model.settings.backgroundDarkness)
        let displays = areas(); var retained = Set<UUID>()
        for (display, root) in workspace.roots {
            guard let area = displays[display], let layout = try? LayoutEngine.calculate(root, in: area, gap: model.settings.gap) else { continue }
            for divider in layout.dividers {
                retained.insert(divider.id)
                let panel: GapPanel
                if let existing = grips[divider.id] { panel = existing }
                else {
                    panel = GapPanel(axis: divider.axis)
                    panel.gripView.onBegin = { [weak self] in self?.beginGrip(display: display, id: divider.id) ?? false }
                    panel.gripView.onDrag = { [weak self] in self?.moveGrip() }
                    panel.gripView.onEnd = { [weak self] cancel in Task { await self?.finish(cancel: cancel) } }
                    grips[divider.id] = panel
                }
                panel.setFrame(DesktopCoordinates.appKit(divider.bounds), display: true)
                panel.gripView.animate = model.settings.animate
                panel.gripView.duration = Double(model.settings.animationMS) / 1000
                panel.gripView.lightInk = model.settings.backgroundDarkness >= 40 || NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                panel.gripView.dragging = grip?.divider.id == divider.id
                panel.gripView.needsDisplay = true
                if !panel.isVisible { panel.orderFrontRegardless() }
            }
        }
        for id in Array(grips.keys) where !retained.contains(id) { grips[id]?.orderOut(nil); grips.removeValue(forKey: id) }
    }
    func sample() {
        let pressed = input().pressed
        defer { wasPressed = pressed }
        guard !finishing else { return }
        if waitForRelease { if !pressed { waitForRelease = false }; return }
        guard model.active, model.permission else {
            if snapshot != nil { Task { await finish(cancel: true) } } else { removeHelpers() }
            return
        }
        if snapshot != nil && input().escape {
            waitForRelease = true; Task { await finish(cancel: true) }; return
        }
        if grip != nil { return }
        guard !model.busy else { return }
        if pressed {
            if !wasPressed { pressedWindow = nil; pressedFrame = nil; pressPoint = input().point; trace?("Pointer down: \(pressPoint)") }
            if pressedWindow == nil, let window = model.system.focusedWindow(in: model.windows), model.history.current.windows.contains(where: { $0.windowID == window.id }) {
                pressedWindow = window; pressedFrame = model.system.frame(of: window.element)
            }
            guard let window = pressedWindow, let before = pressedFrame, let current = model.system.frame(of: window.element) else { return }
            if snapshot == nil {
                let moved = abs(before.x - current.x) > 2 || abs(before.y - current.y) > 2
                let resized = abs(before.width - current.width) > 2 || abs(before.height - current.height) > 2
                guard moved || resized, let source = model.history.current.windows.first(where: { $0.windowID == window.id }) else { return }
                snapshot = model.history.current; session = DropSession(workspace: model.history.current, source: source)
                let onBorder = abs(pressPoint.x - before.x) <= 6 || abs(pressPoint.x - before.right) <= 6 || abs(pressPoint.y - before.y) <= 6 || abs(pressPoint.y - before.bottom) <= 6
                nativeResize = resized && (!moved || onBorder); model.interacting = true
                trace?(nativeResize ? "Native resize detected" : "Native title-bar drag detected")
                grips.values.forEach { $0.orderOut(nil) }
            }
            if nativeResize { updateNativeResize(window: window, frame: current) }
            else { updateDrop() }
        } else if wasPressed {
            if snapshot != nil {
                // Native Escape normally restores the source frame; don't turn an OS
                // cancellation into a swap simply because the pointer remains over a slot.
                let returned = pressedWindow.flatMap { model.system.frame(of: $0.element) } == pressedFrame
                if !nativeResize { updateDrop() }
                Task { await finish(cancel: returned) }
            } else { pressedWindow = nil; pressedFrame = nil }
        }
    }
    private func updateDrop() {
        do {
            if let proposal = try session?.propose(pointer: input().point, areas: areas(), gap: model.settings.gap, hold: model.settings.splitHold, now: input().time) {
                candidate = proposal.workspace; preview.present(proposal)
            } else { candidate = nil; preview.orderOut(nil) }
        } catch { candidate = nil; preview.orderOut(nil) }
    }
    private func updateNativeResize(window: ManagedWindow, frame: Rect) {
        guard var next = snapshot else { return }
        for (display, root) in next.roots where root.windows.contains(where: { $0.windowID == window.id }) {
            guard let area = areas()[display] else { continue }
            do { next.roots[display] = try InteractionGeometry.resizeWindow(root, windowID: window.id, requested: frame, area: area, gap: model.settings.gap); candidate = next }
            catch { candidate = nil }
        }
    }
    func beginGrip(display: String, id: UUID) -> Bool {
        guard model.active, model.permission, !model.busy, !model.interacting, !finishing,
              let root = model.history.current.roots[display], let area = areas()[display],
              let divider = try? LayoutEngine.calculate(root, in: area, gap: model.settings.gap).dividers.first(where: { $0.id == id }) else { return false }
        snapshot = model.history.current; candidate = snapshot; grip = (display, divider)
        model.interacting = true; liveFailure = false; preview.orderOut(nil)
        return true
    }
    func moveGrip() {
        guard !finishing, !liveFailure, let grip, let original = snapshot, let area = areas()[grip.display] else { return }
        do {
            let next = try InteractionGeometry.resize(original, display: grip.display, divider: grip.divider, pointer: input().point, area: area, gap: model.settings.gap)
            candidate = next; pending = next; updateGrips(next)
            if liveTask == nil {
                liveTask = Task { @MainActor [weak self] in
                    guard let self else { return }
                    while let next = self.pending {
                        self.pending = nil
                        do { try await self.model.apply(next, displays: DisplayArea.all(margin: self.model.settings.margin), liveResize: true) }
                        catch { self.liveFailure = true; self.pending = nil; self.model.message = error.localizedDescription; break }
                    }
                    self.liveTask = nil
                    if self.liveFailure { Task { await self.finish(cancel: true) } }
                }
            }
        } catch { model.message = error.localizedDescription }
    }
    func finish(cancel: Bool) async {
        guard !finishing, let original = snapshot else { return }
        finishing = true; pending = nil; preview.orderOut(nil)
        if let liveTask { await liveTask.value }
        let next = cancel || liveFailure ? original : candidate ?? original
        trace?("Gesture finish: cancel=\(cancel), candidate=\(candidate != nil)")
        do { try await model.finishInteraction(next, commit: !cancel && !liveFailure && candidate != nil) }
        catch {
            let failure = error.localizedDescription
            do { try await model.finishInteraction(original, commit: false); model.message = failure }
            catch { model.message = "\(failure) Restoring the committed layout also failed: \(error.localizedDescription)" }
        }
        snapshot = nil; candidate = nil; session = nil; grip = nil; pressedWindow = nil; pressedFrame = nil
        liveTask = nil; liveFailure = false; nativeResize = false; model.interacting = false; finishing = false
        model.onStateChange?()
        synchronize()
    }
}

// Separate click-through panels outline every affected slot without covering the
// desktop in one opaque overlay. Their geometry comes from the committed candidate.
@MainActor final class DestinationPanel {
    private var panels: [PreviewSlotPanel] = []
    func orderOut(_ sender: Any?) { panels.forEach { $0.orderOut(sender) } }
    func present(_ proposal: DropProposal) {
        let rectangles = [proposal.bounds] + proposal.neighbors
        while panels.count < rectangles.count { panels.append(PreviewSlotPanel()) }
        for (index, panel) in panels.enumerated() {
            guard index < rectangles.count else { panel.orderOut(nil); continue }
            let primary = index == 0
            panel.slotView.primary = primary
            panel.slotView.progress = proposal.waitingForSplit ? proposal.progress : nil
            panel.slotView.caption = primary ? (proposal.waitingForSplit ? "Hold to split" : proposal.placement == .center ? "Release to swap" : "Release to split") : ""
            panel.setFrame(DesktopCoordinates.appKit(rectangles[index]), display: true)
            panel.slotView.needsDisplay = true
            if !panel.isVisible { panel.orderFrontRegardless() }
        }
    }
}

@MainActor private final class PreviewSlotPanel: NSPanel {
    let slotView = PreviewSlotView()
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isReleasedWhenClosed = false; isOpaque = false; backgroundColor = .clear
        ignoresMouseEvents = true; hasShadow = false; level = .floating; hidesOnDeactivate = false
        collectionBehavior = [.stationary, .ignoresCycle]; contentView = slotView
        setAccessibilityLabel("Bento destination preview")
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor final class PreviewSlotView: NSView {
    var primary = true, caption = "Release to split"
    var progress: Double?
    override func draw(_ dirtyRect: NSRect) {
        NSBezierPath(rect: bounds).addClip()
        NSColor.clear.setFill(); bounds.fill(using: .copy)
        let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 10, yRadius: 10)
        let accent = NSColor(calibratedRed: 0.24, green: 0.78, blue: 0.73, alpha: 1)
        accent.withAlphaComponent(primary ? 0.18 : 0.06).setFill(); outline.fill()
        (primary ? accent : NSColor.white.withAlphaComponent(0.8)).setStroke()
        outline.lineWidth = primary ? 2 : 1.5
        if !primary { outline.setLineDash([6, 4], count: 2, phase: 0) }
        outline.stroke()
        guard primary else { return }
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.white]
        let title = caption as NSString, textSize = title.size(withAttributes: attributes)
        let width = min(bounds.width - 16, textSize.width + 28), height: CGFloat = progress == nil ? 36 : 42
        let chip = NSRect(x: bounds.midX - width / 2, y: bounds.midY - height / 2, width: width, height: height)
        NSColor(calibratedWhite: 0.08, alpha: 0.94).setFill(); NSBezierPath(roundedRect: chip, xRadius: 10, yRadius: 10).fill()
        title.draw(in: NSRect(x: chip.minX + 14, y: chip.midY - textSize.height / 2 + (progress == nil ? 0 : 3), width: width - 28, height: textSize.height), withAttributes: attributes)
        if let progress {
            let track = NSRect(x: chip.minX + 14, y: chip.minY + 6, width: width - 28, height: 2)
            NSColor.white.withAlphaComponent(0.2).setFill(); NSBezierPath(roundedRect: track, xRadius: 1, yRadius: 1).fill()
            accent.setFill(); NSBezierPath(roundedRect: NSRect(x: track.minX, y: track.minY, width: track.width * progress, height: 2), xRadius: 1, yRadius: 1).fill()
        }
    }
}

@MainActor final class GapPanel: NSPanel {
    let gripView: GripView
    init(axis: Axis) {
        gripView = GripView(axis: axis)
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isReleasedWhenClosed = false; isOpaque = false; backgroundColor = .clear
        hasShadow = false; level = .normal; hidesOnDeactivate = false
        collectionBehavior = [.stationary, .ignoresCycle]; contentView = gripView
        setAccessibilityLabel("Bento resize divider")
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor final class GripView: NSView {
    let axis: Axis
    var onBegin: (() -> Bool)?, onDrag: (() -> Void)?, onEnd: ((Bool) -> Void)?
    var animate = true, lightInk = true
    var duration = 0.18
    var dragging = false { didSet { if oldValue != dragging { transition() } } }
    var hovering = false { didSet { if oldValue != hovering { transition() } } }
    private var displayedLength = 40.0, displayedAlpha = 0.3
    private var animation: Timer?
    private var tracking: NSTrackingArea?
    init(axis: Axis) { self.axis = axis; super.init(frame: .zero); setAccessibilityElement(true); setAccessibilityRole(.splitter); setAccessibilityLabel("Resize neighboring windows") }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unsupported") }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func updateTrackingAreas() {
        super.updateTrackingAreas(); if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: bounds, options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited], owner: self)
        addTrackingArea(tracking!)
    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: axis == .horizontal ? .resizeLeftRight : .resizeUpDown) }
    override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }
    override func mouseDown(with event: NSEvent) { dragging = onBegin?() ?? false; needsDisplay = true }
    override func mouseDragged(with event: NSEvent) { if dragging { onDrag?() } }
    override func mouseUp(with event: NSEvent) { if dragging { onDrag?(); onEnd?(false) }; dragging = false; needsDisplay = true }
    override func cancelOperation(_ sender: Any?) { if dragging { onEnd?(true) }; dragging = false; needsDisplay = true }
    private func transition() {
        animation?.invalidate()
        let oldLength = displayedLength, oldAlpha = displayedAlpha
        let length = dragging ? 104.0 : 40.0, alpha = hovering || dragging ? 0.85 : 0.3
        guard animate, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { displayedLength = length; displayedAlpha = alpha; needsDisplay = true; return }
        let start = ProcessInfo.processInfo.systemUptime
        animation = Timer(timeInterval: 1 / 60, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { timer.invalidate(); return }
                let t = min(1, (ProcessInfo.processInfo.systemUptime - start) / self.duration), eased = t * t * (3 - 2 * t)
                self.displayedLength = oldLength + (length - oldLength) * eased
                self.displayedAlpha = oldAlpha + (alpha - oldAlpha) * eased
                self.needsDisplay = true
                if t >= 1 { timer.invalidate() }
            }
        }
        RunLoop.main.add(animation!, forMode: .common)
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill(); dirtyRect.fill(using: .copy)
        guard displayedAlpha > 0 else { return }
        let length = min(displayedLength, axis == .horizontal ? bounds.height : bounds.width)
        let rect = axis == .horizontal ? NSRect(x: bounds.midX - 1, y: bounds.midY - length / 2, width: 2, height: length) : NSRect(x: bounds.midX - length / 2, y: bounds.midY - 1, width: length, height: 2)
        (lightInk ? NSColor.white : .black).withAlphaComponent(displayedAlpha).setFill(); NSBezierPath(roundedRect: rect, xRadius: 1, yRadius: 1).fill()
    }
}
