import AppKit

// A separate process so the integration test uses the real Accessibility adapter.
final class FixtureDelegate: NSObject, NSApplicationDelegate {
    var windows: [NSWindow] = []
    func applicationDidFinishLaunching(_ notification: Notification) {
        for index in 0..<3 {
            let window = NSWindow(contentRect: NSRect(x: 90 + index * 45, y: 90 + index * 40, width: 480, height: 330), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "Bento Test \(index + 1)"; window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 160, height: 140)
            let label = NSTextField(labelWithString: "Disposable window \(index + 1) — drag its title bar")
            label.frame = NSRect(x: 24, y: 120, width: 410, height: 32); window.contentView?.addSubview(label)
            window.makeKeyAndOrderFront(nil); windows.append(window)
        }
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = FixtureDelegate(); app.delegate = delegate
withExtendedLifetime(delegate) { app.run() }
