import AppKit
import ApplicationServices

/// Event-driven Dock observation; no input interception or Space manipulation.
/// Dock notification names: https://github.com/asmvik/yabai/blob/master/src/mission_control.c
/// Initial AX group: https://github.com/Hammerspoon/hammerspoon/blob/master/extensions/spaces/spaces.lua
@MainActor final class DesktopOverviewMonitor {
    private var observer: AXObserver?
    private var dock: AXUIElement?
    private var dockPID: pid_t?
    private var launchObserver: NSObjectProtocol?
    private var active = false
    private let changed: (Bool) -> Void
    private let notifications = ["AXExposeShowAllWindows", "AXExposeShowFrontWindows", "AXExposeShowDesktop", "AXExposeExit"]
    init(changed: @escaping (Bool) -> Void) {
        self.changed = changed
        launchObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication, app.bundleIdentifier == "com.apple.dock" else { return }
            Task { @MainActor in self?.connect() }
        }
        connect()
    }
    func connect(force: Bool = false) {
        guard AXIsProcessTrusted(), let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return }
        if app.processIdentifier == dockPID, !force {
            if active, let dock { refreshVisibility(dock) }
            return
        }
        if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes) }
        observer = nil; dock = nil; dockPID = nil
        var next: AXObserver?
        guard AXObserverCreate(app.processIdentifier, { _, _, notification, context in
            guard let context else { return }
            let monitor = Unmanaged<DesktopOverviewMonitor>.fromOpaque(context).takeUnretainedValue()
            let visible = (notification as String) != "AXExposeExit"
            Task { @MainActor [weak monitor] in monitor?.update(visible) }
        }, &next) == .success, let next else { return }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.05)
        let context = Unmanaged.passUnretained(self).toOpaque()
        var accepted = false
        for name in notifications {
            if AXObserverAddNotification(next, element, name as CFString, context) == .success { accepted = true }
        }
        guard accepted else { return }
        observer = next; dock = element; dockPID = app.processIdentifier
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(next), .commonModes)
        refreshVisibility(element)
    }
    private func refreshVisibility(_ element: AXUIElement) {
        // Failed AX reads are unknown, not evidence that Mission Control closed.
        var children: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success else { return }
        let visible = (children as? [AXUIElement] ?? []).contains { child in
            var identifier: CFTypeRef?
            AXUIElementCopyAttributeValue(child, kAXIdentifierAttribute as CFString, &identifier)
            return identifier as? String == "mc"
        }
        update(visible)
    }
    private func update(_ value: Bool) {
        guard active != value else { return }
        active = value; changed(value)
    }
    deinit {
        if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes) }
        if let launchObserver { NSWorkspace.shared.notificationCenter.removeObserver(launchObserver) }
    }
}
