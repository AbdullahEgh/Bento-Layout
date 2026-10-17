import AppKit

@MainActor final class DesktopBackdrop {
    private var panels: [NSPanel] = []
    func show(darkness: Int) {
        guard darkness > 0 else { hide(); return }
        if panels.count != NSScreen.screens.count {
            hide()
            panels = NSScreen.screens.map { _ in
                let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                panel.isReleasedWhenClosed = false; panel.ignoresMouseEvents = true
                panel.isOpaque = false; panel.hasShadow = false; panel.hidesOnDeactivate = false
                panel.level = NSWindow.Level(rawValue: NSWindow.Level.normal.rawValue - 2); panel.collectionBehavior = [.stationary, .ignoresCycle]
                return panel
            }
        }
        for (panel, screen) in zip(panels, NSScreen.screens) {
            // Pure black at high opacity swallows the WindowServer's black drop
            // shadows. Keep a neutral luminance floor so native shadows remain visible.
            let color = NSColor(white: 0.12, alpha: CGFloat(darkness) / 100)
            if panel.backgroundColor != color { panel.backgroundColor = color }
            if panel.frame != screen.frame { panel.setFrame(screen.frame, display: true) }
            // Above the desktop, behind ordinary application windows; never activates.
            if !panel.isVisible { panel.orderBack(nil) }
        }
    }
    func hide() { panels.forEach { $0.orderOut(nil) }; panels.removeAll() }
}
