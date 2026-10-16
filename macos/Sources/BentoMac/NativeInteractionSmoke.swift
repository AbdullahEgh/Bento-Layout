import AppKit
import ApplicationServices
import BentoCore

// Disposable in-process NSWindows exercise the production controller/panels with
// supplied pointer samples. This adapter never queries or changes other applications.
@MainActor private final class FixtureWindowSystem: MacWindowSystem {
    var records: [(ManagedWindow, NSWindow)] = []
    var focused: ManagedWindow?
    var rejectOnce: UUID?
    var accessibilityGranted = true
    var nativeMinimum: [UUID: Size] = [:]
    var writes: [UUID: Int] = [:]
    override var trusted: Bool { accessibilityGranted }
    override func discover() throws -> [ManagedWindow] {
        for (record, window) in records { record.frame = DesktopCoordinates.engine(window.frame) }
        return records.map(\.0)
    }
    override func focusedWindow(in windows: [ManagedWindow]) -> ManagedWindow? { focused }
    override func frame(of element: AXUIElement) -> Rect? {
        records.first { CFEqual($0.0.element, element) }.map { DesktopCoordinates.engine($0.1.frame) }
    }
    override func isAlive(_ window: ManagedWindow) -> Bool { records.contains { $0.0.id == window.id } }
    override func write(_ window: ManagedWindow, frame: Rect) throws {
        writes[window.id, default: 0] += 1
        if rejectOnce == window.id { rejectOnce = nil; throw WindowFailure.rejected(window.title) }
        guard let actual = records.first(where: { $0.0.id == window.id })?.1 else { throw WindowFailure.unavailable(window.title) }
        var accepted = frame
        if let minimum = nativeMinimum[window.id] { accepted.width = max(accepted.width, minimum.width); accepted.height = max(accepted.height, minimum.height) }
        actual.setFrame(DesktopCoordinates.appKit(accepted), display: true)
    }
}
private final class FixturePreferences: PreferenceBackend {
    var values: [PreferenceKey: Data] = [:]
    func read(_ key: PreferenceKey) -> Data? { values[key] }
    func write(_ key: PreferenceKey, value: Data?) { values[key] = value }
    func refresh(_ keys: [PreferenceKey]) {}
}

@MainActor enum NativeInteractionSmoke {
    static func run(at output: URL) async throws {
        let system = FixtureWindowSystem(), preferences = FixturePreferences()
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let model = WorkspaceController(system: system, settings: MacSettings(), preferences: ActivationOverrides(backend: preferences, journal: output.appendingPathComponent("fixture-preferences.json")), backgroundMonitoring: false)
        var input = DesktopInput(point: Point(0, 0), pressed: false, escape: false, time: 0)
        let interactions = DesktopInteractions(model: model, input: { input }, automaticSampling: false)
        model.cancelInteraction = { await interactions.finish(cancel: true) }
        var passed: [String] = []
        func check(_ value: Bool, _ title: String) throws {
            guard value else { throw NSError(domain: "BentoNativeSmoke", code: 1, userInfo: [NSLocalizedDescriptionKey: title]) }
            passed.append(title)
        }
        func matchingGeometry() throws -> Bool {
            for display in DisplayArea.all(margin: model.settings.margin) {
                for region in try LayoutEngine.calculate(model.history.current.roots[display.id], in: display.bounds, gap: model.settings.gap).regions {
                    guard let record = system.records.first(where: { $0.0.id == region.window.windowID })?.0, system.accepted(record, region.bounds) else { return false }
                }
            }
            return true
        }
        func regions() throws -> (String, LayoutResult) {
            let key = model.history.current.roots.keys.sorted()[0]
            let area = DisplayArea.all(margin: model.settings.margin).first { $0.id == key }!
            return (key, try LayoutEngine.calculate(model.history.current.roots[key], in: area.bounds, gap: model.settings.gap))
        }
        func settle() async { try? await Task.sleep(for: .milliseconds(180)); while model.interacting || model.busy { try? await Task.sleep(for: .milliseconds(50)) } }
        for index in 0..<3 {
            let window = NSWindow(contentRect: NSRect(x: 100 + 50 * index, y: 100 + 50 * index, width: 420, height: 320), styleMask: [.titled, .resizable, .closable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.title = "Bento disposable fixture \(index + 1)"
            let label = NSTextField(labelWithString: window.title); label.frame = NSRect(x: 24, y: 120, width: 350, height: 40); window.contentView?.addSubview(label)
            window.orderFrontRegardless()
            let element = AXUIElementCreateApplication(pid_t(-1000 - index))
            system.records.append((ManagedWindow(element: element, pid: ProcessInfo.processInfo.processIdentifier, title: window.title, application: "Bento Fixture", bundleID: "com.abdullahegh.bento.fixture", frame: DesktopCoordinates.engine(window.frame)), window))
        }
        let initial = system.records.map { DesktopCoordinates.engine($0.1.frame) }
        defer { system.records.forEach { $0.1.close() } }
        do {
            await model.arrange(); interactions.synchronize()
            try check(model.active && matchingGeometry(), "Three disposable native windows arranged")
            let (_, firstLayout) = try regions()
            try check(interactions.helperFrames.count == firstLayout.dividers.count && interactions.helperFrames.allSatisfy { frame in firstLayout.dividers.contains { $0.bounds == frame } }, "Helper panels occupy gaps only")
            func startDrag(source: Region, target: Point, time: Double) throws {
                let record = system.records.first { $0.0.id == source.window.windowID }!.0
                system.focused = record
                input = DesktopInput(point: Point(source.bounds.x + 70, source.bounds.y + 20), pressed: true, escape: false, time: time)
                interactions.sample()
                try system.write(record, frame: Rect(source.bounds.x + 40, source.bounds.y + 35, source.bounds.width, source.bounds.height))
                input.point = target; input.time += 0.1; interactions.sample()
            }
            let source = firstLayout.regions[0], target = firstLayout.regions[1].bounds
            try startDrag(source: source, target: Point(target.x + target.width / 2, target.y + target.height / 2), time: 1)
            input.pressed = false; interactions.sample(); await settle()
            try check(try matchingGeometry(), "Native center drop commits matching geometry")
            let sourceAfterSwap = try regions().1.regions.first { $0.window.windowID == source.window.windowID }!
            try check(sourceAfterSwap.bounds == target, "Center drop swaps source into the target slot")
            let layout = try regions().1, splitTarget = layout.regions.first { $0.window.windowID != source.window.windowID }!.bounds
            try startDrag(source: sourceAfterSwap, target: Point(splitTarget.x + 3, splitTarget.y + splitTarget.height / 2), time: 3)
            input.time += 1; interactions.sample(); input.pressed = false; interactions.sample(); await settle()
            try check(try matchingGeometry() && model.history.current.windows.count == 3, "Held edge drop splits and retains all windows")
            let beforeCancel = model.history.current, cancelLayout = try regions().1
            try startDrag(source: cancelLayout.regions[0], target: Point(cancelLayout.regions[1].bounds.x + 50, cancelLayout.regions[1].bounds.y + 50), time: 6)
            input.escape = true; interactions.sample(); await settle()
            input.pressed = false; input.escape = false; interactions.sample()
            try check(try model.history.current == beforeCancel && matchingGeometry(), "Escape restores native drag snapshot")
            let (display, gripLayout) = try regions(), divider = gripLayout.dividers[0]
            try check(interactions.beginGrip(display: display, id: divider.id), "Gap grip begins a native resize")
            input.point = Point(divider.bounds.x + 90, divider.bounds.y + 90); interactions.moveGrip()
            try? await Task.sleep(for: .milliseconds(180)); await interactions.finish(cancel: false)
            try check(try matchingGeometry(), "Gap grip commits matching native bounds")
            let beforeGripCancel = model.history.current, currentDivider = try regions().1.dividers[0]
            _ = interactions.beginGrip(display: display, id: currentDivider.id)
            input.point = Point(currentDivider.bounds.x - 80, currentDivider.bounds.y - 80); interactions.moveGrip()
            try? await Task.sleep(for: .milliseconds(180)); await interactions.finish(cancel: true)
            try check(try model.history.current == beforeGripCancel && matchingGeometry(), "Grip cancellation restores native geometry without history mutation")
            let borderLayout = try regions().1
            if let borderSource = borderLayout.regions.first(where: { region in borderLayout.dividers.contains { $0.axis == .horizontal && $0.bounds.x == region.bounds.right } && region.bounds.width > region.window.minimum.width + 30 }) {
                let record = system.records.first { $0.0.id == borderSource.window.windowID }!.0
                system.focused = record
                input = DesktopInput(point: Point(borderSource.bounds.right, borderSource.bounds.y + 50), pressed: true, escape: false, time: 9)
                interactions.sample()
                var requested = borderSource.bounds; requested.width -= 20
                try system.write(record, frame: requested); interactions.sample(); input.pressed = false; interactions.sample(); await settle()
                let changed = try regions().1.regions.first { $0.window.windowID == record.id }!
                try check(try changed.bounds.width == requested.width && matchingGeometry(), "Native inner-border resize updates adjacent regions")
            } else { throw LayoutError.cannotFit }
            let beforeUndo = model.history.current
            await model.undo(); try check(try model.history.current != beforeUndo && matchingGeometry(), "Native undo restores the previous interaction")
            await model.undo(redo: true); try check(try model.history.current == beforeUndo && matchingGeometry(), "Native redo reapplies the interaction")
            let beforeFailure = system.records.map { DesktopCoordinates.engine($0.1.frame) }
            system.rejectOnce = system.records[1].0.id
            var rejected = false
            do { try await model.apply(model.history.current, displays: DisplayArea.all(margin: model.settings.margin)) } catch { rejected = true }
            try check(rejected && system.records.map { DesktopCoordinates.engine($0.1.frame) } == beforeFailure, "A rejected native write rolls back the batch")
            let rememberedBento = model.history.current
            await model.restore(); interactions.synchronize()
            try check(system.records.map { DesktopCoordinates.engine($0.1.frame) } == initial && interactions.helperFrames.isEmpty, "Turning Bento off restores fixtures and removes helpers")
            await model.toggleLayout()
            try check(try model.history.current == rememberedBento && matchingGeometry(), "Toggling on resumes the edited Bento tree")
            await model.restore()
            model.settings.hideDock = true; model.settings.hideMenuBar = true; model.settings.edgeSnapping = "Off"
            await model.arrange()
            try check(preferences.values.count == 5, "Activation options request Dock, menu bar and tiling overrides through the injected backend")
            await model.restore()
            try check(preferences.values.isEmpty, "Deactivation restores all injected preference values")
            await model.arrange(); system.focused = system.records[0].0
            await model.releaseActiveWindow()
            try check(model.history.current.windows.count == 2 && system.accepted(system.records[0].0, initial[0]), "Release active window restores it and expands neighbors")
            await model.undo()
            try check(try model.history.current.windows.count == 3 && matchingGeometry(), "Undo release returns the window to Bento")
            await model.undo(redo: true)
            try check(try model.history.current.windows.count == 2 && matchingGeometry(), "Redo release leaves the window floating")
            await model.arrange()
            try check(try model.history.current.windows.count == 3 && matchingGeometry(), "Arrange all includes released windows again")
            await model.restore()
            let area = DisplayArea.all(margin: model.settings.margin)[0].bounds
            let oversized = system.records[0].0
            oversized.minimum = Size(area.width + 100, 120)
            system.writes.removeAll()
            await model.arrange()
            try check(try model.active && model.history.current.windows.count == 2 && matchingGeometry(), "Oversized window does not block arrangement of fitting windows")
            try check(system.writes[oversized.id] == nil && system.accepted(oversized, initial[0]), "Known oversized window is never moved or resized")
            let manuallyMoved = Rect(initial[0].x + 35, initial[0].y + 15, initial[0].width, initial[0].height)
            try system.write(oversized, frame: manuallyMoved)
            await model.arrange(preserving: true)
            try check(model.active && model.floatingWindows.map(\.id) == [oversized.id], "Reflow keeps a skipped window floating without blocking Bento")
            await model.restore()
            try check(system.accepted(oversized, manuallyMoved), "Turning Bento off leaves user movement of skipped windows alone")
            oversized.minimum = Size(160, 120)
            let nativeLarge = Rect(area.x, area.y, area.width + 100, 300)
            try system.write(oversized, frame: nativeLarge)
            system.nativeMinimum[oversized.id] = Size(nativeLarge.width, nativeLarge.height)
            await model.arrange()
            try check(try model.active && model.history.current.windows.count == 2 && matchingGeometry(), "Native minimum-size rejection retries with the windows that fit")
            try check(system.accepted(oversized, nativeLarge), "Newly discovered oversized window returns to its exact starting frame")
            await model.restore()
            system.nativeMinimum.removeAll(); oversized.minimum = Size(160, 120)
            try system.write(oversized, frame: initial[0])
            await model.arrange()
            try check(try model.history.current.windows.count == 3 && matchingGeometry(), "Previously skipped window can rejoin when it fits")
            await model.restore()
            for (record, _) in system.records { record.minimum = Size(area.width + 100, 120) }
            system.writes.removeAll()
            await model.arrange()
            try check(!model.active && system.writes.isEmpty && preferences.values.isEmpty, "If no windows fit, no frames or desktop preferences are left changed")
            for (record, _) in system.records { record.minimum = Size(160, 120) }
            system.accessibilityGranted = false; model.refreshPermissionStatus()
            model.deferActivationUntilPermission()
            try check(!model.active, "A blocked activation leaves native windows untouched")
            system.accessibilityGranted = true; model.refreshPermissionStatus()
            for _ in 0..<100 {
                if model.active && !model.activating && !model.busy { break }
                try? await Task.sleep(for: .milliseconds(50))
            }
            try check(try model.active && matchingGeometry(), "Granting access completes the requested activation")
            await model.restore()
            let activating = Task { await model.arrange() }
            try? await Task.sleep(for: .milliseconds(100)); await model.restore(); await activating.value
            try check(!model.active && system.records.map { DesktopCoordinates.engine($0.1.frame) } == initial, "Restoring during activation cancels the pending arrangement")
            try JSONSerialization.data(withJSONObject: ["passed": passed, "externalApplicationsTouched": false, "systemPreferencesChanged": false], options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("results.json"))
            print("Native interaction smoke: \(passed.count) checks passed; disposable windows only.")
        } catch { await interactions.finish(cancel: true); await model.restore(); throw error }
    }
}
