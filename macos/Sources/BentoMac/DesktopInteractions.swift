import AppKit
import QuartzCore
import ApplicationServices
import BentoCore
import OSLog

@MainActor enum InteractionDiagnostics {
    private static let logger = Logger(subsystem: "com.abdullahegh.bento", category: "Interaction")
    static func record(_ event: String) { logger.notice("\(event, privacy: .public)") }
}

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
    private var swapsSections = false
    private var nativeResize = false
    private var grip: (display: String, divider: Divider)?
    private var gripStart = Point(0, 0)
    private var pending: Workspace?
    private var liveTask: Task<Void, Never>?
    private var liveFailure = false
    private var gestureAreas: [String: Rect]?
    private var gestureScreens: [String: Rect] = [:]
    private var lastSamplePoint: Point?
    private var escapeMonitor: Any?
    private var escapeRequested = false
    private var releasePending = false
    private var hoverNeedsUpdate = true
    init(model: WorkspaceController, input: (() -> DesktopInput)? = nil, automaticSampling: Bool = true, trace: ((String) -> Void)? = nil) {
        self.model = model; self.input = input ?? { DesktopInput.current() }; self.trace = trace ?? (automaticSampling ? { InteractionDiagnostics.record($0) } : nil)
        guard automaticSampling else { return }
        pulse = Timer(timeInterval: 1 / 45, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.sample() } }
        RunLoop.main.add(pulse!, forMode: .common)
        escapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return }
            MainActor.assumeIsolated { self?.escapeRequested = true }
        }
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                await self.finish(cancel: true); self.removeHelpers()
                if self.model.active { await self.model.arrange(preserving: true, automatic: true) }; self.synchronize()
            }
        }
    }
    var helperFrames: [Rect] { grips.values.map { DesktopCoordinates.engine($0.frame) } }
    func synchronize() {
        guard model.active, model.permission, !model.interacting else { if !model.interacting { removeHelpers() }; return }
        updateGrips(model.history.current)
    }
    private func areas() -> [String: Rect] { if let gestureAreas { return gestureAreas }; return Dictionary(uniqueKeysWithValues: model.displayAreas().map { ($0.id, $0.bounds) }) }
    private func removeHelpers() { grips.values.forEach { $0.orderOut(nil) }; grips.removeAll(); preview.orderOut(nil); backdrop.hide() }
    private func updateGrips(_ workspace: Workspace) {
        hoverNeedsUpdate = true
        backdrop.show(darkness: model.settings.backgroundDarkness)
        let displays = areas(); var retained = Set<UUID>()
        for (display, root) in workspace.roots {
            guard let area = displays[display], let layout = try? LayoutEngine.calculate(root, in: area, gap: model.layoutGap) else { continue }
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
                let frame = DesktopCoordinates.appKit(divider.bounds)
                if panel.frame != frame { panel.setFrame(frame, display: true) }
                panel.gripView.animate = model.settings.animate
                panel.gripView.duration = Double(model.settings.animationMS) / 1000
                let lightInk = model.settings.backgroundDarkness >= 40 || NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                if panel.gripView.lightInk != lightInk { panel.gripView.lightInk = lightInk; panel.gripView.needsDisplay = true }
                panel.gripView.dragging = grip?.divider.id == divider.id
                if !panel.isVisible { panel.orderFrontRegardless() }
            }
        }
        for id in Array(grips.keys) where !retained.contains(id) { grips[id]?.orderOut(nil); grips.removeValue(forKey: id) }
    }
    func sample() {
        let state = input(), pressed = state.pressed
        defer { wasPressed = pressed; lastSamplePoint = state.point }
        guard !finishing else { return }
        if waitForRelease { if !pressed { waitForRelease = false }; return }
        guard model.active, model.permission else {
            if snapshot != nil { Task { await finish(cancel: true) } } else { removeHelpers() }
            return
        }
        if snapshot != nil && (state.escape || escapeRequested) {
            escapeRequested = false; waitForRelease = pressed
            trace?("gesture cancelled: Escape")
            Task { await finish(cancel: true) }; return
        }
        guard !releasePending else { return }
        if !pressed && !wasPressed && snapshot == nil && !hoverNeedsUpdate && lastSamplePoint == state.point { return }
        hoverNeedsUpdate = false
        for panel in grips.values {
            panel.gripView.hovering = panel.isVisible && DesktopCoordinates.engine(panel.frame).contains(state.point)
        }
        if grip != nil { return }
        guard !model.busy, !model.activating else { return }
        if pressed && !wasPressed {
            pressedWindow = nil; pressedFrame = nil; pressPoint = state.point; escapeRequested = false
            // Bento's settings controls may cover a tiled slot. Never bind a
            // settings click or slider drag to a window underneath our own UI.
            guard model.system.tracksDesktopPointer else { return }
            gestureAreas = nil; gestureAreas = areas()
            gestureScreens = Dictionary(uniqueKeysWithValues: DisplayArea.all(margin: 0, fullScreen: true).map { ($0.id, $0.bounds) })
            pressedWindow = model.system.window(at: pressPoint, in: model.windows)
            if pressedWindow == nil {
                for (display, root) in model.history.current.roots {
                    guard let area = gestureAreas?[display], let region = try? LayoutEngine.calculate(root, in: area, gap: model.layoutGap).regions.first(where: { $0.bounds.contains(pressPoint) }) else { continue }
                    pressedWindow = model.windows.first { $0.id == region.window.windowID }; break
                }
            }
            if pressedWindow == nil, let focused = model.system.focusedWindow(in: model.windows),
               model.system.frame(of: focused.element)?.contains(pressPoint) == true { pressedWindow = focused }
            if let window = pressedWindow {
                for (display, root) in model.history.current.roots {
                    guard let area = gestureAreas?[display], let region = try? LayoutEngine.calculate(root, in: area, gap: model.layoutGap).regions.first(where: { $0.window.windowID == window.id }) else { continue }
                    // A fast drag may already have moved before this first sample.
                    pressedFrame = region.bounds; break
                }
                if pressedFrame == nil { pressedFrame = model.system.frame(of: window.element) }
                model.recordInteraction(window)
                trace?("pointer down window=\(window.id) at=\(pressPoint)")
            }
        }
        guard pressed || wasPressed else { return }
        guard let window = pressedWindow, let before = pressedFrame else {
            if !pressed { gestureAreas = nil }; return
        }
        // Hold progress needs time samples, not repeated AX position/size reads.
        if pressed, snapshot != nil, lastSamplePoint == state.point {
            if !nativeResize { updateDrop(state: state) }; return
        }
        guard let current = model.system.frame(of: window.element) else {
            if !pressed, snapshot != nil { Task { await finish(cancel: true) } }
            return
        }
        if snapshot == nil {
            let moved = abs(before.x - current.x) > 2 || abs(before.y - current.y) > 2
            let resized = abs(before.width - current.width) > 2 || abs(before.height - current.height) > 2
            let pointerMoved = abs(state.point.x - pressPoint.x) >= 4 || abs(state.point.y - pressPoint.y) >= 4
            if (moved || resized) && pointerMoved {
                let original = model.history.current.reconciled(with: model.windows.map(\.leaf))
                let source = original.windows.first(where: { $0.windowID == window.id }) ?? window.leaf
                snapshot = original; session = DropSession(workspace: original, source: source)
                let onBorder = abs(pressPoint.x - before.x) <= 6 || abs(pressPoint.x - before.right) <= 6 || abs(pressPoint.y - before.y) <= 6 || abs(pressPoint.y - before.bottom) <= 6
                nativeResize = original.windows.contains(where: { $0.windowID == window.id }) && resized && onBorder; model.interacting = true
                trace?(nativeResize ? "native resize started" : "native drag started")
                grips.values.forEach { $0.orderOut(nil) }
            }
        }
        if snapshot != nil {
            if nativeResize { updateNativeResize(window: window, frame: current) }
            else { updateDrop(state: state) }
            if !pressed {
                // Frame equality is not cancellation: native snapping can restore
                // the source while a valid destination is still under the pointer.
                releasePending = true
                Task {
                    // Let the other app finish its native mouse-up before Bento
                    // writes the final bounds. Freeze the preview during this handoff.
                    try? await Task.sleep(for: .milliseconds(35))
                    await finish(cancel: false)
                }
            }
        } else if !pressed { pressedWindow = nil; pressedFrame = nil; gestureAreas = nil }
    }
    private func updateDrop(state: DesktopInput) {
        do {
            preview.animate = model.settings.animate
            if let proposal = try session?.propose(pointer: state.point, areas: areas(), gap: model.layoutGap, hold: model.settings.splitHold, now: state.time, screenBounds: gestureScreens) {
                if candidate != proposal.workspace { trace?("drop proposal=\(proposal.placement.rawValue) section=\(proposal.swapsSections) bounds=\(proposal.bounds)") }
                candidate = proposal.workspace; swapsSections = proposal.swapsSections; preview.present(proposal)
            } else {
                candidate = nil
                if let bounds = session?.conflictBounds { preview.presentConflict(bounds) } else { preview.orderOut(nil) }
            }
        } catch { candidate = nil; preview.orderOut(nil) }
    }
    private func updateNativeResize(window: ManagedWindow, frame: Rect) {
        guard var next = snapshot else { return }
        for (display, root) in next.roots where root.windows.contains(where: { $0.windowID == window.id }) {
            guard let area = areas()[display] else { continue }
            do { next.roots[display] = try InteractionGeometry.resizeWindow(root, windowID: window.id, requested: frame, area: area, gap: model.layoutGap); candidate = next }
            catch { candidate = nil }
        }
    }
    func beginGrip(display: String, id: UUID) -> Bool {
        guard model.active, model.permission, !model.busy, !model.interacting, !finishing, !releasePending,
              let root = model.history.current.roots[display], let area = areas()[display],
              let divider = try? LayoutEngine.calculate(root, in: area, gap: model.layoutGap).dividers.first(where: { $0.id == id }) else { return false }
        gestureAreas = areas()
        snapshot = model.history.current.reconciled(with: model.windows.map(\.leaf)); candidate = snapshot; grip = (display, divider)
        gripStart = input().point
        model.interacting = true; liveFailure = false; preview.orderOut(nil)
        grips[id]?.gripView.dragging = true
        return true
    }
    func moveGrip() {
        guard !finishing, !liveFailure, let grip, let original = snapshot, let area = areas()[grip.display] else { return }
        do {
            let next = try InteractionGeometry.resize(original, display: grip.display, divider: grip.divider, pointer: input().point, area: area, gap: model.layoutGap, grabbedAt: gripStart)
            guard next != candidate else { return }
            candidate = next; pending = next
            if liveTask == nil {
                liveTask = Task { @MainActor [weak self] in
                    guard let self else { return }
                    while let next = self.pending {
                        self.pending = nil
                        do {
                            try await self.model.apply(next, displays: self.model.displayAreas(), liveResize: true)
                            // Move the hit surface with the applied sample, not ahead
                            // of the windows while a newer sample is still queued.
                            self.updateGrips(next)
                        }
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
        finishing = true
        if cancel { pending = nil; preview.orderOut(nil) }
        if let liveTask { await liveTask.value }
        let disappeared = original.windows.filter { leaf in
            guard let window = model.windows.first(where: { $0.id == leaf.windowID }) else { return true }
            return !model.system.isAlive(window)
        }
        let recovery = disappeared.reduce(original) { $0.removing($1.windowID) }
        let next = !disappeared.isEmpty || cancel || liveFailure ? recovery : candidate ?? recovery
        if !disappeared.isEmpty { trace?("gesture target/source closed; recovering remaining windows count=\(disappeared.count)") }
        let started = ProcessInfo.processInfo.systemUptime
        trace?("gesture finishing cancel=\(cancel) candidate=\(candidate != nil)")
        if !cancel, !liveFailure, candidate != nil, let window = pressedWindow, let frame = pressedFrame,
           !original.windows.contains(where: { $0.windowID == window.id }) {
            model.rememberOriginal(window, frame: frame)
        }
        do { try await model.finishInteraction(next, commit: !disappeared.isEmpty || !cancel && !liveFailure && candidate != nil, animate: cancel || liveFailure || (grip == nil && !nativeResize)) }
        catch {
            trace?("gesture commit rejected; rolling back")
            let failure = error.localizedDescription
            do { try await model.finishInteraction(recovery, commit: false); model.message = failure }
            catch { model.message = "\(failure) Restoring the committed layout also failed: \(error.localizedDescription)" }
        }
        trace?("gesture settled elapsedMS=\(Int((ProcessInfo.processInfo.systemUptime - started) * 1000)) committed=\(!cancel && !liveFailure && model.message == nil && model.history.current != original)")
        preview.orderOut(nil)
        gestureAreas = nil; gestureScreens = [:]; escapeRequested = false; releasePending = false
        snapshot = nil; candidate = nil; swapsSections = false; session = nil; grip = nil; pressedWindow = nil; pressedFrame = nil
        liveTask = nil; liveFailure = false; nativeResize = false; model.interacting = false; finishing = false
        model.onStateChange?()
        synchronize()
    }
}

// Separate click-through panels softly fill each affected slot without covering the
// desktop in one opaque overlay. Their geometry comes from the committed candidate.
@MainActor final class DestinationPanel {
    private let reduceMotion: () -> Bool
    init(reduceMotion: @escaping () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }) { self.reduceMotion = reduceMotion }
    private var panels: [PreviewSlotPanel] = []
    var animate = true
    private var motion: Timer?
    private var hiding = false
    private struct Transition { let panel: PreviewSlotPanel; let from: NSRect; let to: NSRect; let alpha: CGFloat; let targetAlpha: CGFloat }
    private var transitions: [Transition] = []
    private var started = 0.0
    private func transition(to rectangles: [Rect]) {
        motion?.invalidate(); motion = nil
        hiding = rectangles.isEmpty
        while panels.count < rectangles.count { panels.append(PreviewSlotPanel()) }
        transitions = panels.enumerated().map { index, panel in
            let destination = index < rectangles.count ? DesktopCoordinates.appKit(rectangles[index]) : panel.frame
            if !panel.isVisible && index < rectangles.count {
                panel.alphaValue = 0; panel.setFrame(destination.insetBy(dx: 5, dy: 5), display: true); panel.orderFrontRegardless()
            }
            return Transition(panel: panel, from: panel.frame, to: destination, alpha: panel.alphaValue, targetAlpha: index < rectangles.count ? 1 : 0)
        }
        started = ProcessInfo.processInfo.systemUptime
        if !animate || reduceMotion() { advance(progress: 1); return }
        motion = Timer(timeInterval: 1 / 60, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { timer.invalidate(); return }
                let t = min(1, (ProcessInfo.processInfo.systemUptime - self.started) / 0.12)
                self.advance(progress: t)
                if t >= 1 { timer.invalidate(); self.motion = nil }
            }
        }
        RunLoop.main.add(motion!, forMode: .common)
    }
    private func advance(progress: Double) {
        let t = progress * progress * (3 - 2 * progress)
        for item in transitions {
            func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * t }
            let frame = NSRect(x: mix(item.from.minX, item.to.minX), y: mix(item.from.minY, item.to.minY), width: mix(item.from.width, item.to.width), height: mix(item.from.height, item.to.height))
            if item.panel.frame != frame { item.panel.setFrame(frame, display: true) }
            let alpha = mix(item.alpha, item.targetAlpha)
            if item.panel.alphaValue != alpha { item.panel.alphaValue = alpha }
            if progress >= 1 && item.targetAlpha == 0 { item.panel.orderOut(nil) }
        }
    }
    private var lastProposal: DropProposal?
    private var lastConflict: Rect?
    func orderOut(_ sender: Any?) { if !hiding && panels.contains(where: { $0.isVisible }) { transition(to: []) }; lastProposal = nil; lastConflict = nil }
    func presentConflict(_ bounds: Rect) {
        guard lastConflict != bounds || panels.first?.isVisible != true else { return }
        lastConflict = bounds; lastProposal = nil
        if panels.isEmpty { panels.append(PreviewSlotPanel()) }

        let panel = panels[0]
        panel.slotView.primary = true; panel.slotView.conflict = true; panel.slotView.progress = nil
        panel.slotView.needsDisplay = true; transition(to: [bounds])
    }
    func present(_ proposal: DropProposal) {
        guard lastProposal != proposal || panels.first?.isVisible != true else { return }
        let geometryChanged = lastConflict != nil || lastProposal?.bounds != proposal.bounds || lastProposal?.neighbors != proposal.neighbors
        lastProposal = proposal; lastConflict = nil
        let rectangles = [proposal.bounds] + proposal.neighbors
        while panels.count < rectangles.count { panels.append(PreviewSlotPanel()) }
        for (index, panel) in panels.enumerated() {
            guard index < rectangles.count else { continue }
            let primary = index == 0
            let progress = primary && proposal.waitingForSplit ? proposal.progress : nil
            let changed = panel.slotView.primary != primary || panel.slotView.progress != progress || panel.slotView.conflict || panel.slotView.placement != proposal.placement || panel.slotView.swapsSections != proposal.swapsSections
            panel.slotView.primary = primary
            panel.slotView.progress = progress
            panel.slotView.conflict = false
            panel.slotView.placement = proposal.placement
            panel.slotView.swapsSections = proposal.swapsSections
            if changed { panel.slotView.needsDisplay = true }
        }
        if geometryChanged { transition(to: rectangles) }
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
    var primary = true { didSet { if oldValue != primary { updateAppearance() } } }
    var conflict = false { didSet { if oldValue != conflict { updateAppearance() } } }
    var swapsSections = false { didSet { if oldValue != swapsSections { updateAppearance() } } }
    var placement = Placement.center { didSet { if oldValue != placement { updateAppearance() } } }
    var progress: Double? { didSet { if oldValue != progress { updateAppearance() } } }
    private let frost: BentoFrostView
    private let wash = CAGradientLayer()
    private let glow = CALayer()
    private let outline = CALayer()
    var isSplitting: Bool { !conflict && !swapsSections && (placement != .center || progress != nil) }
    var materialKind: BentoFrostView.Kind { frost.kind }
    // Fixture overrides exercise both native glass and the macOS 15 / accessibility fallback.
    init(frame: NSRect = .zero, allowGlass: Bool = true, reduceTransparency: Bool? = nil) {
        frost = BentoFrostView(radius: 18, allowGlass: allowGlass, reduceTransparency: reduceTransparency)
        super.init(frame: frame)
        wantsLayer = true; layer?.backgroundColor = NSColor.clear.cgColor
        layer?.addSublayer(glow)
        addSubview(frost)
        frost.ink.layer?.addSublayer(wash); frost.ink.layer?.addSublayer(outline)
        outline.cornerRadius = 17.5; outline.borderWidth = 0.8
        wash.cornerRadius = 18; wash.masksToBounds = true
        wash.startPoint = CGPoint(x: 0.15, y: 1); wash.endPoint = CGPoint(x: 0.85, y: 0)
        glow.cornerRadius = 18; glow.shadowRadius = 18; glow.shadowOffset = .zero
        updateGeometry(); updateAppearance()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unsupported") }
    override func layout() { super.layout(); updateGeometry() }
    override func setFrameSize(_ newSize: NSSize) { super.setFrameSize(newSize); updateGeometry() }
    private func updateGeometry() {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        let frame = NSRect(x: 6, y: 6, width: max(0, bounds.width - 12), height: max(0, bounds.height - 12))
        frost.frame = frame; wash.frame = NSRect(origin: .zero, size: frame.size); glow.frame = frame
        outline.frame = wash.bounds.insetBy(dx: 0.5, dy: 0.5)
        glow.shadowPath = CGPath(roundedRect: glow.bounds, cornerWidth: 18, cornerHeight: 18, transform: nil)
        CATransaction.commit()
    }
    private func updateAppearance() {
        // Native glass and a quiet neutral edge carry placement and splitting.
        // A warm tint appears only when the destination cannot fit.
        let accent: NSColor = conflict ? .systemOrange : .white
        let strength: Double = primary ? (conflict ? 0.16 : isSplitting ? 0.06 + (progress ?? 1) * 0.04 : 0.045) : 0.02
        frost.tint = conflict ? accent.withAlphaComponent(0.12) : nil
        CATransaction.begin(); CATransaction.setDisableActions(true)
        wash.colors = [accent.withAlphaComponent(strength).cgColor, accent.withAlphaComponent(strength * 0.30).cgColor]
        outline.borderColor = accent.withAlphaComponent(primary ? 0.38 : 0.16).cgColor
        glow.backgroundColor = accent.withAlphaComponent(strength * 0.20).cgColor
        glow.shadowColor = accent.cgColor; glow.shadowOpacity = primary ? 0.10 : 0.035
        CATransaction.commit()
    }
}

@MainActor final class GapPanel: NSPanel {
    let gripView: GripView
    init(axis: Axis) {
        gripView = GripView(axis: axis)
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isReleasedWhenClosed = false; isOpaque = false; backgroundColor = .clear
        // Above the dimming panel (-2), below ordinary app windows (0).
        // App content and shadows cover both the input surface and the grip ink.
        hasShadow = false; level = NSWindow.Level(rawValue: NSWindow.Level.normal.rawValue - 1); hidesOnDeactivate = false
        ignoresMouseEvents = false; acceptsMouseMovedEvents = true
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
    private var displayedLength = 40.0, displayedAlpha = 0.0
    var visibleInk: Double { displayedAlpha }
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
        let length = dragging ? 104.0 : 40.0, alpha = hovering || dragging ? 0.85 : 0.0
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
        // A fully transparent WindowServer surface is click-through. Keep a
        // one-alpha input surface across the gap, independently of the hidden ink.
        NSColor.black.withAlphaComponent(1.0 / 255).setFill(); dirtyRect.fill(using: .copy)
        guard displayedAlpha > 0 else { return }
        let length = min(displayedLength, axis == .horizontal ? bounds.height : bounds.width)
        let rect = axis == .horizontal ? NSRect(x: bounds.midX - 1, y: bounds.midY - length / 2, width: 2, height: length) : NSRect(x: bounds.midX - length / 2, y: bounds.midY - 1, width: length, height: 2)
        (lightInk ? NSColor.white : .black).withAlphaComponent(displayedAlpha).setFill(); NSBezierPath(roundedRect: rect, xRadius: 1, yRadius: 1).fill()
    }
}
