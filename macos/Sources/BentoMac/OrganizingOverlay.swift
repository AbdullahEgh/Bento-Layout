import AppKit

/// A nonactivating cover: native fitting stays behind a full-display material,
/// without screenshots, screen-recording permission, or changing application focus.
@MainActor final class OrganizingOverlay {
    private var panels: [NSPanel] = []
    var visibleCount: Int { panels.filter(\.isVisible).count }

    func show() async {
        hide(animated: false)
        for screen in NSScreen.screens {
            let panel = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false
            panel.isOpaque = false; panel.backgroundColor = .clear
            panel.hasShadow = false; panel.hidesOnDeactivate = false
            panel.level = .screenSaver
            panel.collectionBehavior = [.stationary, .ignoresCycle]
            let blur = NSVisualEffectView(frame: NSRect(origin: .zero, size: screen.frame.size))
            blur.material = .fullScreenUI; blur.blendingMode = .behindWindow; blur.state = .active
            blur.autoresizingMask = [.width, .height]
            let tint = NSView(frame: blur.bounds)
            tint.wantsLayer = true; tint.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.18).cgColor
            tint.autoresizingMask = [.width, .height]; blur.addSubview(tint)
            let message = NSTextField(labelWithString: "Organizing Bento…")
            message.font = .systemFont(ofSize: 20, weight: .medium)
            message.textColor = .white.withAlphaComponent(0.9)
            message.alignment = .center; message.translatesAutoresizingMaskIntoConstraints = false
            blur.addSubview(message)
            NSLayoutConstraint.activate([
                message.centerXAnchor.constraint(equalTo: blur.centerXAnchor),
                message.centerYAnchor.constraint(equalTo: blur.centerYAnchor)
            ])
            panel.contentView = blur; panel.alphaValue = 0
            panel.orderFrontRegardless(); panels.append(panel)
        }
        let animate = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        await NSAnimationContext.runAnimationGroup { context in
            context.duration = animate ? 0.14 : 0
            for panel in panels { panel.animator().alphaValue = 1 }
        }
        // Present the cover before any window measurements or desktop changes.
        try? await Task.sleep(for: .milliseconds(30))
    }

    func hide(animated: Bool = true) {
        let retiring = panels; panels.removeAll()
        guard !retiring.isEmpty else { return }
        guard animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            retiring.forEach { $0.orderOut(nil) }; return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            retiring.forEach { $0.animator().alphaValue = 0 }
        } completionHandler: {
            MainActor.assumeIsolated { retiring.forEach { $0.orderOut(nil) } }
        }
    }
}
