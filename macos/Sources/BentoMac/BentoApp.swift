import AppKit
import SwiftUI
import Carbon.HIToolbox

@main enum BentoApp {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--smoke") { print("Bento macOS startup smoke passed; no windows were discovered or changed."); return }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = WorkspaceController()
    private var statusItem: NSStatusItem!
    private var window: NSWindow?
    private var hotKey: GlobalHotKey?
    private var canTerminate = false
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.applicationIconImage = BentoStyle.icon
        if let flag = CommandLine.arguments.firstIndex(of: "--render-preview"), CommandLine.arguments.count > flag + 1 {
            renderPreviews(at: URL(fileURLWithPath: CommandLine.arguments[flag + 1])); return
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
                NSColor.black.setStroke()
                let path = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 2), xRadius: 2, yRadius: 2)
                path.lineWidth = 1.4; path.stroke()
                let lines = NSBezierPath(); lines.lineWidth = 1.4
                lines.move(to: NSPoint(x: 7, y: 2)); lines.line(to: NSPoint(x: 7, y: 16))
                lines.move(to: NSPoint(x: 7, y: 9)); lines.line(to: NSPoint(x: 17, y: 9)); lines.stroke(); return true
            }
            image.isTemplate = true; button.image = image; button.toolTip = "Bento — window layouts"
        }
        updateMenu(); model.onStateChange = { [weak self] in self?.updateMenu() }
        hotKey = GlobalHotKey { [weak self] in self?.model.toggle() }
        if hotKey?.registered == false { model.message = "The ⌃⌥B shortcut is unavailable. Use Bento in the menu bar." }
        showWindow(onboarding: !model.settings.onboardingComplete)
    }
    private func updateMenu() {
        let menu = NSMenu()
        func item(_ title: String, _ action: Selector) { let i = NSMenuItem(title: title, action: action, keyEquivalent: ""); i.target = self; menu.addItem(i) }
        item(model.active ? "Turn Bento off" : "Arrange windows", #selector(toggle))
        item("Restore original positions", #selector(restore))
        menu.addItem(.separator())
        item("Settings…", #selector(settings)); item("View onboarding…", #selector(onboarding))
        menu.addItem(.separator()); item("Quit Bento", #selector(quit))
        statusItem.menu = menu
    }
    @objc private func toggle() { model.toggle() }
    @objc private func restore() { Task { await model.restore() } }
    @objc private func settings() { showWindow(onboarding: false) }
    @objc private func onboarding() { showWindow(onboarding: true) }
    @objc private func quit() { NSApp.terminate(nil) }
    func showWindow(onboarding: Bool) {
        window?.close()
        let content: AnyView
        if onboarding { content = AnyView(OnboardingView(model: model, finished: { [weak self] in self?.showWindow(onboarding: false) })) }
        else { content = AnyView(SettingsView(model: model, showOnboarding: { [weak self] in self?.showWindow(onboarding: true) })) }
        let host = NSHostingController(rootView: ThemedRoot(model: model, content: content))
        let panel = NSWindow(contentViewController: host)
        panel.title = "Bento"; panel.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        panel.titlebarAppearsTransparent = true; panel.titleVisibility = .hidden
        panel.isReleasedWhenClosed = false
        panel.setContentSize(NSSize(width: onboarding ? 940 : 820, height: onboarding ? 650 : 620))
        panel.center(); panel.makeKeyAndOrderFront(nil); window = panel
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if canTerminate { return .terminateNow }
        Task {
            // Wait for an in-flight transaction before restoring the activation snapshot.
            while model.busy { try? await Task.sleep(for: .milliseconds(50)) }
            await model.restore()
            if let message = model.message {
                let alert = NSAlert(); alert.messageText = "Some windows could not be restored"
                alert.informativeText = message; alert.addButton(withTitle: "Keep Bento open"); alert.addButton(withTitle: "Quit anyway")
                if alert.runModal() == .alertFirstButtonReturn { NSApp.reply(toApplicationShouldTerminate: false); return }
            }
            canTerminate = true; NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
    private func renderPreviews(at directory: URL) {
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        catch { fputs("\(error)\n", stderr); exit(1) }
        Task { @MainActor in
            for dark in [false, true] {
                for step in 0..<4 {
                    let view = OnboardingView(model: model, finished: {}, step: step).environment(\.colorScheme, dark ? .dark : .light)
                    let host = NSHostingView(rootView: view)
                    let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 940, height: 650), styleMask: [.borderless], backing: .buffered, defer: false)
                    panel.isReleasedWhenClosed = false
                    panel.appearance = NSAppearance(named: dark ? .darkAqua : .aqua); panel.contentView = host
                    host.frame = NSRect(x: 0, y: 0, width: 940, height: 650)
                    panel.orderFront(nil)
                    try? await Task.sleep(for: .milliseconds(180))
                    host.layoutSubtreeIfNeeded()
                    guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { exit(1) }
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    guard let png = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
                    do { try png.write(to: directory.appendingPathComponent("onboarding-\(step + 1)-\(dark ? "dark" : "light").png")) }
                    catch { fputs("\(error)\n", stderr); exit(1) }
                    panel.close()
                }
            }
            print("Rendered 8 native SwiftUI onboarding screens to \(directory.path)"); exit(0)
        }
    }
}
struct ThemedRoot: View {
    @ObservedObject var model: WorkspaceController
    let content: AnyView
    var body: some View { content.tint(BentoStyle.accent).preferredColorScheme(model.settings.theme == "Dark" ? .dark : model.settings.theme == "Light" ? .light : nil) }
}

@MainActor final class GlobalHotKey {
    private var reference: EventHotKeyRef?, handler: EventHandlerRef?
    let action: () -> Void
    private(set) var registered = false
    init(action: @escaping () -> Void) {
        self.action = action
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            // Carbon application events are delivered on the main event loop.
            MainActor.assumeIsolated { Unmanaged<GlobalHotKey>.fromOpaque(context).takeUnretainedValue().action() }
            return noErr
        }, 1, &event, context, &handler)
        guard installed == noErr else { return }
        registered = RegisterEventHotKey(UInt32(kVK_ANSI_B), UInt32(controlKey | optionKey), EventHotKeyID(signature: 0x424E544F, id: 1), GetApplicationEventTarget(), 0, &reference) == noErr
    }
    deinit { if let reference { UnregisterEventHotKey(reference) }; if let handler { RemoveEventHandler(handler) } }
}
