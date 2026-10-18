import AppKit

@MainActor final class DesktopBackdrop {
    private var panels: [NSPanel] = []
    var windowNumbers: [Int] { panels.map(\.windowNumber) }
    private var fade: Timer?
    private var target = 0.0
    private(set) var opacity = 0.0
    func show(darkness: Int, animated: Bool = true, belowWindow: Int? = nil) {
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
            panel.level = belowWindow == nil ? NSWindow.Level(rawValue: -2) : .normal
            if let belowWindow { panel.order(.below, relativeTo: belowWindow) }
            else if !panel.isVisible { panel.orderBack(nil) }
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

// One click-through tint immediately above each pinned native window. New normal
// windows remain above these panels; no floating window level covers new apps.
@MainActor final class PinnedWindowTint {
    private var panels: [UUID: NSPanel] = [:]
    func hide() { panels.values.forEach { $0.orderOut(nil) }; panels.removeAll() }
    func show(windows: [ManagedWindow], visible: [[String: Any]]) {
        var retained = Set<UUID>()
        for window in windows {
            guard let info = visible.first(where: { entry in
                guard (entry[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == window.pid,
                      (entry[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                      let raw = entry[kCGWindowBounds as String] as? [String: Any],
                      let rect = CGRect(dictionaryRepresentation: raw as CFDictionary) else { return false }
                return abs(rect.minX - Double(window.frame.x)) <= 3 && abs(rect.minY - Double(window.frame.y)) <= 3
                    && abs(rect.width - Double(window.frame.width)) <= 3 && abs(rect.height - Double(window.frame.height)) <= 3
            }), let number = info[kCGWindowNumber as String] as? NSNumber else { continue }
            retained.insert(window.id)
            let panel: NSPanel
            if let existing = panels[window.id] { panel = existing }
            else {
                panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                panel.isReleasedWhenClosed = false; panel.ignoresMouseEvents = true
                panel.isOpaque = false; panel.hasShadow = false; panel.hidesOnDeactivate = false
                panel.backgroundColor = NSColor.black.withAlphaComponent(0.30)
                panel.level = .normal; panel.collectionBehavior = [.stationary, .ignoresCycle]
                panels[window.id] = panel
            }
            panel.setFrame(DesktopCoordinates.appKit(window.frame), display: true)
            panel.order(.above, relativeTo: number.intValue)
        }
        for id in Array(panels.keys) where !retained.contains(id) { panels[id]?.orderOut(nil); panels.removeValue(forKey: id) }
    }
}

// WindowServer lists front to back. Anchor helpers below the lowest Bento member,
// preserving every floating window above the workspace and covering windows below it.
@MainActor enum BentoWindowStack {
    static func anchor(windows: [ManagedWindow], visible: [[String: Any]]) -> Int? {
        visible.last(where: { info in
            guard (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0 else { return false }
            let number = (info[kCGWindowNumber as String] as? NSNumber)?.intValue
            return windows.contains { window in
                if let known = window.serverNumber { return known == number }
                guard (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == window.pid,
                      let raw = info[kCGWindowBounds as String] as? [String: Any],
                      let rect = CGRect(dictionaryRepresentation: raw as CFDictionary) else { return false }
                return abs(rect.minX - Double(window.frame.x)) <= 3 && abs(rect.minY - Double(window.frame.y)) <= 3
                    && abs(rect.width - Double(window.frame.width)) <= 3 && abs(rect.height - Double(window.frame.height)) <= 3
            }
        }).flatMap { ($0[kCGWindowNumber as String] as? NSNumber)?.intValue }
    }
}
