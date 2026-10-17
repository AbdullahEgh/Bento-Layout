import AppKit

@MainActor final class DesktopBackdrop {
    private var panels: [NSPanel] = []
    private var fade: Timer?
    private var target = 0.0
    private(set) var opacity = 0.0
    func show(darkness: Int, animated: Bool = true) {
        guard darkness > 0 else { hide(animated: animated); return }
        if panels.count != NSScreen.screens.count {
            hide(animated: false)
            panels = NSScreen.screens.map { _ in
                let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                panel.isReleasedWhenClosed = false; panel.ignoresMouseEvents = true
                panel.isOpaque = false; panel.hasShadow = false; panel.hidesOnDeactivate = false
                panel.backgroundColor = .black; panel.alphaValue = 0
                panel.level = NSWindow.Level(rawValue: NSWindow.Level.normal.rawValue - 2)
                panel.collectionBehavior = [.stationary, .ignoresCycle]
                return panel
            }
        }
        for (panel, screen) in zip(panels, NSScreen.screens) {
            if panel.frame != screen.frame { panel.setFrame(screen.frame, display: true) }
            if !panel.isVisible { panel.orderBack(nil) }
        }
        transition(to: Double(darkness) / 100, animated: animated)
    }
    func hide(animated: Bool = true) { transition(to: 0, animated: animated) }
    private func transition(to value: Double, animated: Bool) {
        let animate = animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if target == value && (animate || fade == nil) { return }
        fade?.invalidate(); fade = nil; target = value
        guard animate, !panels.isEmpty else { apply(value); return }
        let start = ProcessInfo.processInfo.systemUptime, from = opacity
        fade = Timer(timeInterval: 1 / 60, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { timer.invalidate(); return }
                let t = min(1, (ProcessInfo.processInfo.systemUptime - start) / 0.18)
                self.apply(from + (value - from) * t * t * (3 - 2 * t))
                if t >= 1 { timer.invalidate(); self.fade = nil }
            }
        }
        RunLoop.main.add(fade!, forMode: .common)
    }
    private func apply(_ value: Double) {
        opacity = value
        panels.forEach { $0.alphaValue = value }
        if target == 0 && value <= 0 { panels.forEach { $0.orderOut(nil) }; panels.removeAll() }
    }
}
