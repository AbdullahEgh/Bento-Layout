import AppKit
import ApplicationServices
import BentoCore

enum WindowFailure: LocalizedError {
    case permission, unavailable(String), rejected(String), minimumSize(String)
    var errorDescription: String? {
        switch self {
        case .permission: return "Allow Bento in System Settings → Privacy & Security → Accessibility, then return here."
        case .unavailable(let title): return "“\(title)” is no longer available."
        case .rejected(let title): return "“\(title)” did not accept its new size. Bento attempted to restore the previous positions."
        case .minimumSize(let apps): return "\(apps) needs more space than its Bento slot. Bento restored the previous positions; minimize a window or use a larger display."
        }
    }
}

// AX uses a top-left desktop origin; AppKit uses bottom-left. Keep this conversion
// at the OS boundary, including displays to the left of or above the primary display.
enum DesktopCoordinates {
    static var primaryTop: CGFloat { NSScreen.screens.first?.frame.maxY ?? 0 }
    static func engine(_ frame: NSRect) -> Rect {
        Rect(Int(frame.minX.rounded()), Int((primaryTop - frame.maxY).rounded()), Int(frame.width.rounded()), Int(frame.height.rounded()))
    }
    static func appKit(_ rect: Rect) -> NSRect { NSRect(x: CGFloat(rect.x), y: primaryTop - CGFloat(rect.bottom), width: CGFloat(rect.width), height: CGFloat(rect.height)) }
    static func pointer() -> Point { let p = NSEvent.mouseLocation; return Point(Int(p.x), Int(primaryTop - p.y)) }
}

private enum DockGeometry {
    private static var cached: Rect?
    private static var lastRead = -Double.infinity
    static func current() -> Rect? {
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastRead < 0.15 { return cached }
        lastRead = now; cached = nil
        guard AXIsProcessTrusted(), let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return nil }
        func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
            var value: CFTypeRef?
            return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
        }
        let app = AXUIElementCreateApplication(dock.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.05)
        guard let children = attribute(app, kAXChildrenAttribute) as? [AXUIElement],
              let list = children.first(where: { attribute($0, kAXRoleAttribute) as? String == kAXListRole }),
              let p = attribute(list, kAXPositionAttribute), let s = attribute(list, kAXSizeAttribute),
              CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &point), AXValueGetValue(s as! AXValue, .cgSize, &size),
              point.x.isFinite, point.y.isFinite, size.width.isFinite, size.height.isFinite else { return nil }
        cached = Rect(Int(point.x.rounded()), Int(point.y.rounded()), Int(size.width.rounded()), Int(size.height.rounded()))
        return cached
    }
}

struct DisplayArea: Equatable {
    let id: String; let name: String; let bounds: Rect
    static func all(margin: Int, fullScreen: Bool = false) -> [DisplayArea] {
        func flag(_ domain: CFString, _ key: String) -> Bool {
            CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
            return (CFPreferencesCopyValue(key as CFString, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? NSNumber)?.boolValue ?? false
        }
        let hideMenu = flag(kCFPreferencesAnyApplication, "_HIHideMenuBar")
        let hideDock = flag("com.apple.dock" as CFString, "autohide")
        let dock = hideDock ? nil : DockGeometry.current()
        return NSScreen.screens.map { screen in
            let number = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
            let uuid = CGDisplayCreateUUIDFromDisplayID(number).takeRetainedValue()
            return DisplayArea(id: CFUUIDCreateString(nil, uuid) as String, name: screen.localizedName, bounds: fullScreen ? DesktopCoordinates.engine(screen.frame).inset(margin) : DesktopWorkArea.calculate(frame: DesktopCoordinates.engine(screen.frame), visible: DesktopWorkArea.correctingDock(frame: DesktopCoordinates.engine(screen.frame), visible: DesktopCoordinates.engine(screen.visibleFrame), dock: dock), hideMenuBar: hideMenu && DesktopCoordinates.engine(screen.visibleFrame).y <= DesktopCoordinates.engine(screen.frame).y + Int(screen.safeAreaInsets.top.rounded(.up)), hideDock: hideDock, safeTop: Int(screen.safeAreaInsets.top.rounded(.up)), margin: margin))
        }
    }
}

final class ManagedWindow {
    let id: UUID; let element: AXUIElement; let pid: pid_t
    var title: String; let application: String; let bundleID: String
    var frame: Rect
    // AX has no universal minimum-size attribute. Start small enough for narrow
    // displays, then learn actual app constraints from verified native writes.
    var minimum = Size(160, 120)
    init(id: UUID = UUID(), element: AXUIElement, pid: pid_t, title: String, application: String, bundleID: String, frame: Rect) {
        self.id = id; self.element = element; self.pid = pid; self.title = title; self.application = application; self.bundleID = bundleID; self.frame = frame
    }
    var leaf: WindowLeaf { WindowLeaf(windowID: id, minimum: minimum) }
}

@MainActor class MacWindowSystem {
    private var known: [ManagedWindow] = []
    private let allowedPIDs: Set<pid_t>?
    init(allowedPIDs: Set<pid_t>? = nil) { self.allowedPIDs = allowedPIDs }
    var trusted: Bool { AXIsProcessTrusted() }
    var pointerPressed: Bool { CGEventSource.buttonState(.combinedSessionState, button: .left) }
    var tracksDesktopPointer: Bool { !NSApp.isActive }
    func window(at point: Point, in windows: [ManagedWindow]) -> ManagedWindow? {
        let desktop = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(desktop, 0.05)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(desktop, Float(point.x), Float(point.y), &hit) == .success,
              var element = hit else { return nil }
        // A title-bar button or text field may be returned instead of its window.
        for _ in 0..<12 {
            if let match = windows.first(where: { CFEqual($0.element, element) }) { return match }
            if let window = attribute(element, kAXWindowAttribute), CFGetTypeID(window) == AXUIElementGetTypeID(),
               let match = windows.first(where: { CFEqual($0.element, window) }) { return match }
            guard let parent = attribute(element, kAXParentAttribute), CFGetTypeID(parent) == AXUIElementGetTypeID() else { return nil }
            element = parent as! AXUIElement
        }
        return nil
    }
    func displayAreas(margin: Int) -> [DisplayArea] { DisplayArea.all(margin: margin) }
    /// Intermediate samples do not query AX geometry or wait on slow clients.
    /// The final write and settled verification still use the normal adapter path.
    func writeMotionFrame(_ window: ManagedWindow, frame: Rect, previous: Rect) throws {
        AXUIElementSetMessagingTimeout(window.element, 0.025)
        defer { AXUIElementSetMessagingTimeout(window.element, 0.15) }
        var size = CGSize(width: frame.width, height: frame.height), point = CGPoint(x: frame.x, y: frame.y)
        if frame.width != previous.width || frame.height != previous.height {
            guard let value = AXValueCreate(.cgSize, &size), AXUIElementSetAttributeValue(window.element, kAXSizeAttribute as CFString, value) == .success else { throw WindowFailure.rejected(window.title) }
        }
        if frame.x != previous.x || frame.y != previous.y {
            guard let value = AXValueCreate(.cgPoint, &point), AXUIElementSetAttributeValue(window.element, kAXPositionAttribute as CFString, value) == .success else { throw WindowFailure.rejected(window.title) }
        }
    }
    /// Chromium's enhanced AX mode animates native frame writes independently.
    /// Suspend it only for a Vivaldi transaction, preserve its previous value, and
    /// never interrupt built-in assistive technology. This does not enable a web AX tree.
    func beginFrameAdjustment(_ windows: [ManagedWindow]) -> () -> Void {
        guard !NSWorkspace.shared.isVoiceOverEnabled, !NSWorkspace.shared.isSwitchControlEnabled else { return {} }
        var restored: [AXUIElement] = [], seen = Set<pid_t>()
        for window in windows where window.bundleID == "com.vivaldi.Vivaldi" || window.bundleID.hasPrefix("com.vivaldi.Vivaldi.") {
            guard seen.insert(window.pid).inserted else { continue }
            let app = AXUIElementCreateApplication(window.pid)
            AXUIElementSetMessagingTimeout(app, 0.15)
            if attribute(app, "AXEnhancedUserInterface") as? Bool == true,
               AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanFalse) == .success { restored.append(app) }
        }
        return { for app in restored { _ = AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue) } }
    }
    func desktopSpaceReady() -> Bool {
        let hideMenu = (CFPreferencesCopyValue("_HIHideMenuBar" as CFString, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? NSNumber)?.boolValue ?? false
        return NSScreen.screens.allSatisfy { screen in
            let top = Int((screen.frame.maxY - screen.visibleFrame.maxY).rounded())
            let safe = Int(screen.safeAreaInsets.top.rounded(.up))
            return hideMenu ? top <= safe : top >= max(1, safe)
        }
    }
    func requestPermission() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }
    func openPermissionSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }
    func frame(of element: AXUIElement) -> Rect? {
        guard let p = attribute(element, kAXPositionAttribute), let s = attribute(element, kAXSizeAttribute),
              CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var position = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &position), AXValueGetValue(s as! AXValue, .cgSize, &size),
              position.x.isFinite, position.y.isFinite, size.width.isFinite, size.height.isFinite else { return nil }
        return Rect(Int(position.x.rounded()), Int(position.y.rounded()), Int(size.width.rounded()), Int(size.height.rounded()))
    }
    func discover() throws -> [ManagedWindow] {
        guard trusted else { throw WindowFailure.permission }
        let visible = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        var found: [ManagedWindow] = []
        for application in NSWorkspace.shared.runningApplications where application.activationPolicy == .regular && application.processIdentifier != ProcessInfo.processInfo.processIdentifier && !application.isHidden && (allowedPIDs == nil || allowedPIDs!.contains(application.processIdentifier)) {
            let app = AXUIElementCreateApplication(application.processIdentifier)
            AXUIElementSetMessagingTimeout(app, 0.15)
            guard let windows = attribute(app, kAXWindowsAttribute) as? [AXUIElement] else { continue }
            for element in windows {
                AXUIElementSetMessagingTimeout(element, 0.15)
                guard attribute(element, kAXSubroleAttribute) as? String == kAXStandardWindowSubrole,
                      attribute(element, kAXMinimizedAttribute) as? Bool != true,
                      attribute(element, "AXFullScreen") as? Bool != true,
                      let bounds = frame(of: element), bounds.width > 0, bounds.height > 0 else { continue }
                // AXWindows may include other Spaces. Public on-screen metadata limits
                // management to visible standard windows without reading screen pixels.
                let onScreen = visible.contains { info in
                    guard (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == application.processIdentifier,
                          (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                          let raw = info[kCGWindowBounds as String] as? [String: Any],
                          let frame = CGRect(dictionaryRepresentation: raw as CFDictionary) else { return false }
                    return abs(frame.minX - CGFloat(bounds.x)) <= 3 && abs(frame.minY - CGFloat(bounds.y)) <= 3 && abs(frame.width - CGFloat(bounds.width)) <= 3 && abs(frame.height - CGFloat(bounds.height)) <= 3
                }
                guard onScreen else { continue }
                var movable = DarwinBoolean(false), sizable = DarwinBoolean(false)
                guard AXUIElementIsAttributeSettable(element, kAXPositionAttribute as CFString, &movable) == .success,
                      AXUIElementIsAttributeSettable(element, kAXSizeAttribute as CFString, &sizable) == .success,
                      movable.boolValue && sizable.boolValue else { continue }
                let title = attribute(element, kAXTitleAttribute) as? String ?? application.localizedName ?? "Window"
                if let old = known.first(where: { $0.pid == application.processIdentifier && CFEqual($0.element, element) }) {
                    old.title = title; old.frame = bounds; found.append(old)
                } else {
                    found.append(ManagedWindow(element: element, pid: application.processIdentifier, title: title,
                        application: application.localizedName ?? "Application", bundleID: application.bundleIdentifier ?? application.bundleURL?.path ?? "", frame: bounds))
                }
            }
        }
        // Minimized/hidden/off-Space windows retain their session identity so a later
        // return cannot overwrite the original activation snapshot with tiled bounds.
        let retainedIDs = Set(known.map(\.id))
        known.append(contentsOf: found.filter { !retainedIDs.contains($0.id) })
        known.removeAll { !isAlive($0) }
        // WindowServer supplies front-to-back order. Unlike runningApplications,
        // this gives a useful recent-use baseline before Bento has focus history.
        func rank(_ window: ManagedWindow) -> Int {
            visible.firstIndex { info in
                guard (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == window.pid,
                      (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                      let raw = info[kCGWindowBounds as String] as? [String: Any],
                      let rect = CGRect(dictionaryRepresentation: raw as CFDictionary) else { return false }
                return abs(rect.minX - CGFloat(window.frame.x)) <= 3 && abs(rect.minY - CGFloat(window.frame.y)) <= 3
            } ?? Int.max
        }
        return found.enumerated().sorted {
            let a = rank($0.element), b = rank($1.element)
            return a == b ? $0.offset < $1.offset : a < b
        }.map(\.element)
    }
    func isAlive(_ window: ManagedWindow) -> Bool {
        guard NSRunningApplication(processIdentifier: window.pid)?.isTerminated == false else { return false }
        var role: CFTypeRef?
        return AXUIElementCopyAttributeValue(window.element, kAXRoleAttribute as CFString, &role) != .invalidUIElement
    }
    func isMinimized(_ window: ManagedWindow) -> Bool {
        attribute(window.element, kAXMinimizedAttribute) as? Bool ?? false
    }
    func setMinimized(_ window: ManagedWindow, _ minimized: Bool) throws {
        guard trusted else { throw WindowFailure.permission }
        guard AXUIElementSetAttributeValue(window.element, kAXMinimizedAttribute as CFString, minimized ? kCFBooleanTrue : kCFBooleanFalse) == .success else {
            throw WindowFailure.rejected(window.title)
        }
    }
    func focusedWindow(in windows: [ManagedWindow]) -> ManagedWindow? {
        guard let application = NSWorkspace.shared.frontmostApplication else { return nil }
        let app = AXUIElementCreateApplication(application.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.05)
        guard let focused = attribute(app, kAXFocusedWindowAttribute), CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        return windows.first { $0.pid == application.processIdentifier && CFEqual($0.element, focused) }
    }
    func write(_ window: ManagedWindow, frame: Rect) throws {
        guard trusted else { throw WindowFailure.permission }
        guard NSRunningApplication(processIdentifier: window.pid)?.isTerminated == false, let current = self.frame(of: window.element) else { throw WindowFailure.unavailable(window.title) }
        var size = CGSize(width: frame.width, height: frame.height), point = CGPoint(x: frame.x, y: frame.y)
        guard let s = AXValueCreate(.cgSize, &size), let p = AXValueCreate(.cgPoint, &point) else { throw WindowFailure.rejected(window.title) }
        let resize = current.width != frame.width || current.height != frame.height
        let move = current.x != frame.x || current.y != frame.y
        if resize, AXUIElementSetAttributeValue(window.element, kAXSizeAttribute as CFString, s) != .success { throw WindowFailure.rejected(window.title) }
        if move, AXUIElementSetAttributeValue(window.element, kAXPositionAttribute as CFString, p) != .success { throw WindowFailure.rejected(window.title) }
        // Moving between displays can change a native app's size constraint. Retry
        // size only when the move actually left it different from the requested size.
        if move, let actual = self.frame(of: window.element), actual.width != frame.width || actual.height != frame.height {
            guard AXUIElementSetAttributeValue(window.element, kAXSizeAttribute as CFString, s) == .success else { throw WindowFailure.rejected(window.title) }
        }
        // Resizing itself can shift the origin (notably Chromium/Vivaldi near
        // the menu bar). Verify after the final size write, then place once more.
        if let actual = self.frame(of: window.element), actual.x != frame.x || actual.y != frame.y {
            guard AXUIElementSetAttributeValue(window.element, kAXPositionAttribute as CFString, p) == .success else { throw WindowFailure.rejected(window.title) }
        }
    }
    func accepted(_ window: ManagedWindow, _ wanted: Rect) -> Bool {
        guard let actual = frame(of: window.element) else { return false }
        return abs(actual.x - wanted.x) <= 2 && abs(actual.y - wanted.y) <= 2 && abs(actual.width - wanted.width) <= 2 && abs(actual.height - wanted.height) <= 2
    }
}
