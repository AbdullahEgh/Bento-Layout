import AppKit
import SwiftUI
import BentoCore
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
    let model: WorkspaceController = {
        if let flag = CommandLine.arguments.firstIndex(of: "--fixture-pid"), CommandLine.arguments.count > flag + 1, let pid = Int32(CommandLine.arguments[flag + 1]) {
            var settings = MacSettings(); settings.onboardingComplete = true; settings.splitHold = 0
            return WorkspaceController(system: MacWindowSystem(allowedPIDs: [pid]), settings: settings)
        }
        return WorkspaceController()
    }()
    let updater = MacUpdater()
    private var interactions: DesktopInteractions?
    private var statusItem: NSStatusItem!
    private var statusMenu = NSMenu()
    private var window: NSWindow?
    private var hotKey: GlobalHotKey?
    private var registeredShortcut: ShortcutConfig?
    private var canTerminate = false
    private var statusPress = StatusPress()
    private var statusMouseMonitor: Any?
    private var statusReleaseMonitor: Any?
    private var statusHoldTimer: Timer?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.applicationIconImage = BentoStyle.icon
        if let flag = CommandLine.arguments.firstIndex(of: "--external-ax-smoke"), CommandLine.arguments.count > flag + 2, let pid = Int32(CommandLine.arguments[flag + 1]) {
            Task {
                do { try await ExternalAXSmoke.run(pid: pid, output: URL(fileURLWithPath: CommandLine.arguments[flag + 2])); exit(0) }
                catch { fputs("External AX smoke failed: \(error.localizedDescription)\n", stderr); exit(1) }
            }
            return
        }
        if CommandLine.arguments.contains("--diagnose-windows") {
            do {
                let found = try model.system.discover()
                print("Accessibility: \(model.system.trusted); eligible windows: \(found.count)")
                for area in model.displayAreas() { print("Usable display bounds: \(area.bounds)") }
                for window in found { print("\(window.application): \(window.frame)") }
            } catch { print(error.localizedDescription) }
            exit(model.system.trusted ? 0 : 2)
        }
        if let flag = CommandLine.arguments.firstIndex(of: "--interaction-smoke"), CommandLine.arguments.count > flag + 1 {
            Task {
                do { try await NativeInteractionSmoke.run(at: URL(fileURLWithPath: CommandLine.arguments[flag + 1])); exit(0) }
                catch { fputs("Native interaction smoke failed: \(error.localizedDescription)\n", stderr); exit(1) }
            }
            return
        }
        if let flag = CommandLine.arguments.firstIndex(of: "--render-preview"), CommandLine.arguments.count > flag + 1 {
            renderPreviews(at: URL(fileURLWithPath: CommandLine.arguments[flag + 1])); return
        }
        if let flag = CommandLine.arguments.firstIndex(of: "--render-settings"), CommandLine.arguments.count > flag + 1 {
            updater.start(); renderSettings(at: URL(fileURLWithPath: CommandLine.arguments[flag + 1])); return
        }
        if let identifier = Bundle.main.bundleIdentifier,
           let existing = NSRunningApplication.runningApplications(withBundleIdentifier: identifier).first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            existing.activate(); exit(0)
        }
        model.recoverDesktopPreferences()
        interactions = DesktopInteractions(model: model, trace: CommandLine.arguments.contains("--fixture-pid") ? { print($0) } : nil)
        model.cancelInteraction = { [weak self] in await self?.interactions?.finish(cancel: true) }
        updater.beforeInstall = { [weak self] in
            guard let self else { return false }
            await self.interactions?.finish(cancel: true)
            await self.model.stopAllDesktops(); return self.model.message == nil
        }
        updater.onInstallationNeedsAttention = { [weak self] in
            self?.model.page = "Updates"; self?.showWindow(onboarding: false)
        }
        updater.start()
        let menuBar = NSMenu(), appItem = NSMenuItem(), appMenu = NSMenu(title: "Bento")
        menuBar.addItem(appItem); appItem.submenu = appMenu
        for (title, action, key) in [("Settings…", #selector(settings), ","), ("Check for updates…", #selector(checkUpdates), ""), ("Quit Bento", #selector(quit), "q")] {
            let entry = NSMenuItem(title: title, action: action, keyEquivalent: key); entry.target = self
            let symbol = action == #selector(settings) ? "gearshape" : action == #selector(checkUpdates) ? "arrow.down.circle" : "xmark.circle"
            entry.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil); appMenu.addItem(entry)
        }
        NSApp.mainMenu = menuBar
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.target = self; button.action = #selector(statusClicked)
            button.sendAction(on: [.leftMouseDown, .leftMouseUp, .rightMouseUp])
            button.setAccessibilityLabel("Bento — click to toggle; hold to hide or show Dock and menu bar; right-click for menu")
        }
        // Handle physical presses before NSStatusBarButton enters its tracking loop.
        // Its action callback is not a reliable mouse-down/up stream on every macOS.
        statusMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] event in
            guard let self, let button = self.statusItem.button else { return event }
            let inside = event.window === button.window && button.bounds.contains(button.convert(event.locationInWindow, from: nil))
            guard inside || self.statusPress.isTracking else { return event }
            self.handleStatusEvent(event)
            return nil
        }
        statusReleaseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.statusHoldTimer?.invalidate(); self?.statusPress.cancel()
            }
        }
        updateMenu(); model.onStateChange = { [weak self] in self?.updateMenu(); self?.interactions?.synchronize(); self?.writeFixtureState() }
        model.onSettingsChange = { [weak self] in self?.configureShortcut(); self?.interactions?.synchronize(); self?.updateMenu(); if let self, let window = self.window { BentoWindowChrome.updateAppearance(window, theme: self.model.settings.theme) } }
        configureShortcut()
        let launchEvent = NSAppleEventManager.shared().currentAppleEvent
        let launchedAtLogin = launchEvent?.eventID == kAEOpenApplication && launchEvent?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        if CommandLine.arguments.contains("--fixture-auto-start") { Task { await model.arrange() } }
        else if !launchedAtLogin || !model.settings.onboardingComplete { showWindow(onboarding: !model.settings.onboardingComplete) }
        model.refresh()
    }
    private func updateMenu() {
        let menu = NSMenu(); menu.autoenablesItems = false
        func item(_ title: String, _ action: Selector, _ symbol: String) { let i = NSMenuItem(title: title, action: action, keyEquivalent: ""); i.target = self; i.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil); menu.addItem(i) }
        item(!model.permission ? "Enable Accessibility…" : model.active ? "Turn Bento Off" : "Turn Bento On", #selector(toggle), "power")
        item("Undo Layout Change", #selector(undo), "arrow.uturn.backward")
        menu.items.last?.isEnabled = model.active
        menu.addItem(.separator())
        let hideDesktop = NSMenuItem(title: "Hide Dock & Menu Bar", action: #selector(toggleDesktopHiding), keyEquivalent: "")
        hideDesktop.target = self
        hideDesktop.image = NSImage(systemSymbolName: "menubar.dock.rectangle", accessibilityDescription: nil)
        hideDesktop.toolTip = "This session only. Applies while Bento is on and resets when Bento quits."
        hideDesktop.state = model.settings.hideDock && model.settings.hideMenuBar ? .on : model.settings.hideDock || model.settings.hideMenuBar ? .mixed : .off
        menu.addItem(hideDesktop)
        item(model.pinned ? "Unpin Bento" : "Pin Bento", #selector(togglePin), "pin")
        menu.items.last?.state = model.pinned ? .on : .off
        menu.items.last?.isEnabled = model.permission
        menu.items.last?.toolTip = "Keep this desktop’s layout. Newly opened apps stay above it."
        item("Settings…", #selector(settings), "gearshape")
        menu.addItem(.separator()); item("Quit Bento", #selector(quit), "xmark.circle")
        statusMenu = menu
        statusItem.button?.isEnabled = true
        statusItem.button?.appearsDisabled = false
        statusItem.button?.image = BentoStatusIcon.image(active: model.active, pinned: model.pinned)
        statusItem.button?.alphaValue = model.active ? 1 : 0.45
        statusItem.button?.toolTip = model.pinned ? "Bento is pinned — click to unpin and minimize floating apps" : !model.permission ? "Bento needs Accessibility access — click to enable" : model.active ? "Bento is on — click to turn off; right-click for menu" : "Bento is off — click to arrange windows; right-click for menu"
        statusItem.button?.toolTip? += "\nHold to hide or show Dock and menu bar while Bento is on."
        if let message = model.message { statusItem.button?.toolTip? += "\n" + message }
    }
    @objc private func toggleDesktopHiding() {
        var settings = model.settings
        let enabled = !(settings.hideDock && settings.hideMenuBar)
        settings.hideDock = enabled; settings.hideMenuBar = enabled
        model.settings = settings
        model.saveSettings()
        updateMenu()
    }
    @objc private func togglePin() { Task { await model.setPinned(!model.pinned) } }
    @objc private func statusClicked() {
        handleStatusEvent(NSApp.currentEvent)
    }
    private func handleStatusEvent(_ event: NSEvent?) {
        guard let button = statusItem.button else { return }
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            statusHoldTimer?.invalidate(); statusPress.cancel()
            if event?.type != .leftMouseDown { statusMenu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY), in: button) }
        } else if event?.type == .leftMouseDown {
            statusPress.begin(at: ProcessInfo.processInfo.systemUptime)
            statusHoldTimer?.invalidate()
            statusHoldTimer = Timer(timeInterval: 0.56, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.statusPress.hold(at: ProcessInfo.processInfo.systemUptime) else { return }
                    self.toggleDesktopHiding()
                }
            }
            RunLoop.main.add(statusHoldTimer!, forMode: .common)
        } else {
            statusHoldTimer?.invalidate()
            let trackedPress = statusPress.isTracking
            if statusPress.hold(at: ProcessInfo.processInfo.systemUptime) { toggleDesktopHiding() }
            if statusPress.end() || !trackedPress {
                if model.pinned { Task { await model.setPinned(false) } } else { toggle() }
            }
        }
    }
    @objc private func toggle() {
        model.permission = model.system.trusted
        guard model.permission else {
            model.deferActivationUntilPermission()
            model.page = "Workspace"; model.message = WindowFailure.permission.localizedDescription
            model.system.requestPermission(); updateMenu(); return
        }
        Task {
            await model.toggleLayout()
            updateMenu()
        }
    }
    private func configureShortcut() {
        guard registeredShortcut != model.settings.shortcut else { return }
        hotKey = nil; registeredShortcut = model.settings.shortcut
        hotKey = GlobalHotKey(config: model.settings.shortcut) { [weak self] in self?.toggle() }
        if hotKey?.registered == false { model.message = "The \(model.settings.shortcut.label) shortcut is unavailable. Choose another combination or use Bento in the menu bar." }
    }
    @objc private func arrangeAll() { Task { await model.arrange(); updateMenu() } }
    @objc private func releaseActive() { Task { await model.releaseActiveWindow() } }
    @objc private func saveLayout() { model.saveLayout() }
    @objc private func loadLayout() { Task { await model.loadLayout() } }
    @objc private func undo() { Task { await model.undo() } }
    @objc private func redo() { Task { await model.undo(redo: true) } }
    private func writeFixtureState() {
        guard CommandLine.arguments.contains("--fixture-pid"), let flag = CommandLine.arguments.firstIndex(of: "--fixture-state"), CommandLine.arguments.count > flag + 1 else { return }
        let records = model.windows.map { window -> [String: Any] in
            let rect = model.system.frame(of: window.element) ?? window.frame
            return ["title": window.title, "x": rect.x, "y": rect.y, "width": rect.width, "height": rect.height]
        }
        let object: [String: Any] = ["active": model.active, "windows": records, "message": model.message ?? "", "layout": (try? String(data: JSONEncoder().encode(model.history.current), encoding: .utf8)) ?? ""]
        try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: CommandLine.arguments[flag + 1]), options: .atomic)
    }
    @objc private func restore() { Task { await model.restore() } }
    @objc private func settings() { showWindow(onboarding: false) }
    @objc private func onboarding() { showWindow(onboarding: true) }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func checkUpdates() { if updater.ready { updater.check() } else { model.page = "Updates"; showWindow(onboarding: false) } }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow(onboarding: !model.settings.onboardingComplete); return true
    }
    func showWindow(onboarding: Bool) {
        window?.close()
        let content: AnyView
        if onboarding { content = AnyView(OnboardingView(model: model, finished: { [weak self] in self?.showWindow(onboarding: false) })) }
        else { content = AnyView(SettingsView(model: model, updater: updater, showOnboarding: { [weak self] in self?.showWindow(onboarding: true) })) }
        let host = NSHostingController(rootView: ThemedRoot(model: model, content: content))
        let panel = NSWindow(contentViewController: host)
        BentoWindowChrome.configure(panel, onboarding: onboarding, theme: model.settings.theme)
        panel.level = .normal
        panel.isReleasedWhenClosed = false
        let available = NSScreen.main?.visibleFrame.size ?? NSSize(width: 820, height: 620)
        panel.setContentSize(NSSize(width: onboarding ? 940 : min(820, available.width - 32), height: onboarding ? 650 : min(620, available.height - 48)))
        panel.center(); panel.makeKeyAndOrderFront(nil); window = panel
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if CommandLine.arguments.contains("--render-settings") && CommandLine.arguments.contains("--keep-preview-open") { return .terminateNow }
        if canTerminate || (updater.installationPrepared && !model.active && !model.busy && !model.interacting) { return .terminateNow }
        Task {
            await interactions?.finish(cancel: true)
            // Stop honors this session’s explicit layout save and restores desktop overrides.
            await model.stopAllDesktops()
            if let message = model.message {
                let alert = NSAlert(); alert.messageText = "Could not finish this Bento session"
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
                    if CommandLine.arguments.contains("--keep-preview-open") { window = panel; NSApp.activate(ignoringOtherApps: true); return }
                    panel.close()
                }
            }
            print("Rendered 8 native SwiftUI onboarding screens to \(directory.path)"); exit(0)
        }
    }
    private func renderSettings(at directory: URL) {
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) } catch { exit(1) }
        Task { @MainActor in
            for width in [820, 360] {
            for dark in [true, false] {
                for page in ["Workspace", "Gestures", "Updates", "What's New", "About"] {
                    model.page = page
                    let view = SettingsView(model: model, updater: updater, showOnboarding: {}).environment(\.colorScheme, dark ? .dark : .light)
                    let controller = NSHostingController(rootView: view)
                    let panel = NSWindow(contentViewController: controller)
                    BentoWindowChrome.configure(panel, onboarding: false, theme: dark ? "Dark" : "Light")
                    panel.isReleasedWhenClosed = false; panel.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                    let host = controller.view
                    panel.setContentSize(NSSize(width: 820, height: 620)); panel.orderFront(nil)
                    try? await Task.sleep(for: .milliseconds(180))
                    panel.setContentSize(NSSize(width: width, height: 620))
                    try? await Task.sleep(for: .milliseconds(180)); host.layoutSubtreeIfNeeded()
                    guard abs(host.bounds.width - CGFloat(width)) < 1 else { fputs("Settings refused requested width.\n", stderr); exit(1) }
                    guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { exit(1) }
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    guard let png = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
                    do { try png.write(to: directory.appendingPathComponent("\(page.lowercased())-\(width)-\(dark ? "dark" : "light").png")) } catch { exit(1) }
                    if CommandLine.arguments.contains("--keep-preview-open") { window = panel; NSApp.activate(ignoringOtherApps: true); return }
                    panel.close()
                }
            }
            }
            print("Rendered desktop and compact native settings screens."); exit(0)
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
    init(config: ShortcutConfig = ShortcutConfig(), action: @escaping () -> Void) {
        self.action = action
        guard config.enabled else { registered = true; return }
        guard config.valid, let code = config.keyCode else { return }
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            // Carbon application events are delivered on the main event loop.
            MainActor.assumeIsolated { Unmanaged<GlobalHotKey>.fromOpaque(context).takeUnretainedValue().action() }
            return noErr
        }, 1, &event, context, &handler)
        guard installed == noErr else { return }
        registered = RegisterEventHotKey(code, config.modifiers, EventHotKeyID(signature: 0x424E544F, id: 1), GetApplicationEventTarget(), 0, &reference) == noErr
    }
    deinit { if let reference { UnregisterEventHotKey(reference) }; if let handler { RemoveEventHandler(handler) } }
}
