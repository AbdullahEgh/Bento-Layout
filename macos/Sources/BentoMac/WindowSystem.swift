import AppKit
import ApplicationServices
import BentoCore

enum WindowFailure: LocalizedError {
    case permission, unavailable(String), rejected(String)
    var errorDescription: String? {
        switch self {
        case .permission: return "Allow Bento in System Settings → Privacy & Security → Accessibility, then return here."
        case .unavailable(let title): return "“\(title)” is no longer available."
        case .rejected(let title): return "“\(title)” did not accept its new size. Bento attempted to restore the previous positions."
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

struct DisplayArea: Equatable {
    let id: String; let name: String; let bounds: Rect
    static func all(margin: Int) -> [DisplayArea] {
        NSScreen.screens.map { screen in
            let number = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
            let uuid = CGDisplayCreateUUIDFromDisplayID(number).takeRetainedValue()
            return DisplayArea(id: CFUUIDCreateString(nil, uuid) as String, name: screen.localizedName, bounds: DesktopCoordinates.engine(screen.visibleFrame).inset(margin))
        }
    }
}

final class ManagedWindow {
    let id: UUID; let element: AXUIElement; let pid: pid_t
    var title: String; let application: String; let bundleID: String
    var frame: Rect
    // macOS does not expose a universal minimum window size. Use a conservative
    // fallback, then verify every native application of geometry.
    var minimum = Size(320, 240)
    init(id: UUID = UUID(), element: AXUIElement, pid: pid_t, title: String, application: String, bundleID: String, frame: Rect) {
        self.id = id; self.element = element; self.pid = pid; self.title = title; self.application = application; self.bundleID = bundleID; self.frame = frame
    }
    var leaf: WindowLeaf { WindowLeaf(windowID: id, minimum: minimum) }
}

@MainActor class MacWindowSystem {
    private var known: [ManagedWindow] = []
    var trusted: Bool { AXIsProcessTrusted() }
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
        for application in NSWorkspace.shared.runningApplications where application.activationPolicy == .regular && application.processIdentifier != ProcessInfo.processInfo.processIdentifier && !application.isHidden {
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
        return found
    }
    func isAlive(_ window: ManagedWindow) -> Bool {
        guard NSRunningApplication(processIdentifier: window.pid)?.isTerminated == false else { return false }
        var role: CFTypeRef?
        return AXUIElementCopyAttributeValue(window.element, kAXRoleAttribute as CFString, &role) != .invalidUIElement
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
        guard NSRunningApplication(processIdentifier: window.pid)?.isTerminated == false, self.frame(of: window.element) != nil else { throw WindowFailure.unavailable(window.title) }
        var size = CGSize(width: frame.width, height: frame.height), point = CGPoint(x: frame.x, y: frame.y)
        guard let s = AXValueCreate(.cgSize, &size), let p = AXValueCreate(.cgPoint, &point) else { throw WindowFailure.rejected(window.title) }
        let firstSize = AXUIElementSetAttributeValue(window.element, kAXSizeAttribute as CFString, s)
        let position = AXUIElementSetAttributeValue(window.element, kAXPositionAttribute as CFString, p)
        let finalSize = AXUIElementSetAttributeValue(window.element, kAXSizeAttribute as CFString, s)
        guard firstSize == .success, position == .success, finalSize == .success else { throw WindowFailure.rejected(window.title) }
    }
    func accepted(_ window: ManagedWindow, _ wanted: Rect) -> Bool {
        guard let actual = frame(of: window.element) else { return false }
        return abs(actual.x - wanted.x) <= 2 && abs(actual.y - wanted.y) <= 2 && abs(actual.width - wanted.width) <= 2 && abs(actual.height - wanted.height) <= 2
    }
}
