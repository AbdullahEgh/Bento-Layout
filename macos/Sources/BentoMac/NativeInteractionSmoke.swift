import AppKit
import ApplicationServices
import BentoCore

// Disposable in-process NSWindows exercise the production controller/panels with
// supplied pointer samples. This adapter never queries or changes other applications.
@MainActor final class FixtureWindowSystem: MacWindowSystem {
    var hiddenPreparation = false
    override var supportsHiddenPreparation: Bool { hiddenPreparation }
    private var concealedPIDs = Set<pid_t>()
    override func applicationHidden(_ pid: pid_t) -> Bool { concealedPIDs.contains(pid) }
    override func setApplicationHidden(_ pid: pid_t, _ hidden: Bool) -> Bool {
        if hidden && denyMinimize { return false }
        if hidden { concealedPIDs.insert(pid) } else { concealedPIDs.remove(pid) }
        return true
    }
    var records: [(ManagedWindow, NSWindow)] = []
    var fixtureDesktop = "fixture-main"
    var fullScreenWindows = Set<UUID>()
    override func isFullScreen(_ window: ManagedWindow) -> Bool { fullScreenWindows.contains(window.id) }
    var fixtureFullScreen = false
    override var fullScreenSpace: Bool { fixtureFullScreen }
    override func isLayoutApplication(_ pid: pid_t) -> Bool { true }
    override var desktopIdentity: String? { fixtureDesktop }
    var focused: ManagedWindow?
    var pointed: ManagedWindow?
    var pointerHeld = false
    var desktopPointerEnabled = true
    var dividerExposed = true
    override func dividerIsExposed(at point: Point) -> Bool { dividerExposed }
    var adjustmentDepth = 0
    var motionAdjustmentDepths: [Int] = []
    override func beginFrameAdjustment(_ windows: [ManagedWindow]) -> () -> Void {
        adjustmentDepth += 1
        return { self.adjustmentDepth -= 1 }
    }
    override var tracksDesktopPointer: Bool { desktopPointerEnabled }
    var pressDuringDiscovery = false
    var undiscovered = Set<UUID>()
    var deadWindows = Set<UUID>()
    var outsideDesktop = Set<UUID>()
    override func canRetainDuringInterruption(_ window: ManagedWindow) -> Bool {
        isAlive(window) && !isMinimized(window) && !outsideDesktop.contains(window.id) && !fullScreenWindows.contains(window.id)
    }
    var discoveryCount = 0
    var frameReads = 0
    override var pointerPressed: Bool { pointerHeld }
    override func window(at point: Point, in windows: [ManagedWindow]) -> ManagedWindow? { pointed ?? focused }
    var rejectOnce: UUID?
    var rejectAlways: UUID?
    var rejectedWindows = Set<UUID>()
    var accessibilityGranted = true
    var deferWrites = false
    var writeDelay = 0.04
    var nativeMinimum: [UUID: Size] = [:]
    var nativeGrid: [UUID: Size] = [:]
    var writes: [UUID: Int] = [:]
    var writtenFrames: [(UUID, Rect)] = []
    var minimized = Set<UUID>()
    var denyMinimize = false
    var minimizationDelay = 0.0
    override func isMinimized(_ window: ManagedWindow) -> Bool { minimized.contains(window.id) }
    override func setMinimized(_ window: ManagedWindow, _ value: Bool) throws {
        if denyMinimize { throw WindowFailure.rejected(window.title) }
        if value && minimizationDelay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + minimizationDelay) { [weak self] in self?.minimized.insert(window.id) }
        } else if value { minimized.insert(window.id) } else { minimized.remove(window.id) }
    }
    override var trusted: Bool { accessibilityGranted }
    override func discover() throws -> [ManagedWindow] {
        discoveryCount += 1
        if pressDuringDiscovery { pointerHeld = true }
        for (record, window) in records { record.frame = DesktopCoordinates.engine(window.frame) }
        return records.map(\.0).filter { !minimized.contains($0.id) && !undiscovered.contains($0.id) && !deadWindows.contains($0.id) && !fullScreenWindows.contains($0.id) }
    }
    override func focusedWindow(in windows: [ManagedWindow]) -> ManagedWindow? { focused }
    override func frame(of element: AXUIElement) -> Rect? {
        frameReads += 1
        return records.first { CFEqual($0.0.element, element) }.map { DesktopCoordinates.engine($0.1.frame) }
    }
    override func isAlive(_ window: ManagedWindow) -> Bool { !deadWindows.contains(window.id) && records.contains { $0.0.id == window.id } }
    var areaChangeOnWrite: [DisplayArea]?
    var areaOverride: [DisplayArea]?
    private var fixtureAreas: [DisplayArea]?
    override func displayAreas(margin: Int) -> [DisplayArea] {
        if let areaOverride { return areaOverride }
        if fixtureAreas == nil { fixtureAreas = super.displayAreas(margin: 0) }
        return fixtureAreas!.map { DisplayArea(id: $0.id, name: $0.name, bounds: $0.bounds.inset(margin)) }
    }
    override func writeMotionFrames(_ requests: [MotionWrite]) async -> Set<UUID> {
        var failed = Set<UUID>()
        for request in requests {
            guard let window = records.first(where: { $0.0.id == request.id })?.0 else { failed.insert(request.id); continue }
            do { try writeMotionFrame(window, frame: request.frame, previous: request.previous) }
            catch { failed.insert(request.id) }
        }
        return failed
    }
    override func writeMotionFrame(_ window: ManagedWindow, frame: Rect, previous: Rect) throws {
        motionAdjustmentDepths.append(adjustmentDepth)
        try write(window, frame: frame)
    }
    override func write(_ window: ManagedWindow, frame: Rect) throws {
        if let areaChangeOnWrite { areaOverride = areaChangeOnWrite; self.areaChangeOnWrite = nil }
        writes[window.id, default: 0] += 1
        writtenFrames.append((window.id, frame))
        if rejectAlways == window.id || rejectedWindows.contains(window.id) { throw WindowFailure.rejected(window.title) }
        if rejectOnce == window.id { rejectOnce = nil; throw WindowFailure.rejected(window.title) }
        guard let actual = records.first(where: { $0.0.id == window.id })?.1 else { throw WindowFailure.unavailable(window.title) }
        var accepted = frame
        if let minimum = nativeMinimum[window.id] { accepted.width = max(accepted.width, minimum.width); accepted.height = max(accepted.height, minimum.height) }
        if let grid = nativeGrid[window.id] {
            accepted.width = Int((Double(accepted.width) / Double(grid.width)).rounded()) * grid.width
            accepted.height = Int((Double(accepted.height) / Double(grid.height)).rounded()) * grid.height
        }
        let nativeFrame = DesktopCoordinates.appKit(accepted)
        if deferWrites { DispatchQueue.main.asyncAfter(deadline: .now() + writeDelay) { actual.setFrame(nativeFrame, display: true) } }
        else { actual.setFrame(nativeFrame, display: true) }
    }
}
final class FixturePreferences: PreferenceBackend {
    var values: [PreferenceKey: Data] = [:]
    func read(_ key: PreferenceKey) -> Data? { values[key] }
    func write(_ key: PreferenceKey, value: Data?) { values[key] = value }
    func refresh(_ keys: [PreferenceKey]) {}
}

@MainActor enum NativeInteractionSmoke {
    static func run(at output: URL) async throws {
        let system = FixtureWindowSystem(), preferences = FixturePreferences()
        var reduceMotion = false
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        var fixtureSettings = MacSettings(); fixtureSettings.animate = false; fixtureSettings.minimizeOverflow = false
        var modelTrace: [String] = []
        let model = WorkspaceController(system: system, settings: fixtureSettings, preferences: ActivationOverrides(backend: preferences, journal: output.appendingPathComponent("fixture-preferences.json")), persistSettings: { _ in }, backgroundMonitoring: false, trace: { modelTrace.append($0) }, reduceMotion: { reduceMotion })
        var input = DesktopInput(point: Point(0, 0), pressed: false, escape: false, time: 0)
        var gestureTrace: [String] = []
        let interactions = DesktopInteractions(model: model, input: { input }, automaticSampling: false, trace: { gestureTrace.append($0) })
        defer { try? gestureTrace.joined(separator: "\n").write(to: output.appendingPathComponent("gesture-trace.log"), atomically: true, encoding: .utf8) }
        model.cancelInteraction = { await interactions.finish(cancel: true) }
        var passed: [String] = []
        func check(_ value: Bool, _ title: String) throws {
            guard value else {
                print(modelTrace.suffix(16).joined(separator: "\n"))
                for (record, _) in system.records { print("Fixture \(record.id): minimum=\(record.minimum), actual=\(String(describing: system.frame(of: record.element)))") }
                throw NSError(domain: "BentoNativeSmoke", code: 1, userInfo: [NSLocalizedDescriptionKey: title])
            }
            passed.append(title)
        }
        func matchingGeometry() throws -> Bool {
            for display in model.displayAreas() {
                for region in try LayoutEngine.calculate(model.history.current.roots[display.id], in: display.bounds, gap: model.layoutGap).regions {
                    guard let record = system.records.first(where: { $0.0.id == region.window.windowID })?.0, system.accepted(record, region.bounds) else { return false }
                }
            }
            return true
        }
        func motionBatches() -> Int { modelTrace.filter { $0.hasPrefix("motion batch started") }.count }
        func boundedAnimationWrites(since started: Int) -> Bool {
            // Wall-clock animation may skip every intermediate sample on a busy
            // runner. Require final writes and reject excessive work instead.
            let limit = Int(ceil(Double(model.settings.animationMS) / 16)) + 3
            return motionBatches() > started && !system.writes.isEmpty && system.writes.values.allSatisfy { (1...limit).contains($0) }
        }
        func regions() throws -> (String, LayoutResult) {
            let key = model.history.current.roots.keys.sorted()[0]
            let area = model.displayAreas().first { $0.id == key }!
            return (key, try LayoutEngine.calculate(model.history.current.roots[key], in: area.bounds, gap: model.layoutGap))
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
            passed += try await DesktopSessionSmoke.run(system: system, initial: initial, output: output)
            passed += try await ResizeHandleSmoke.run(system: system, output: output)
            let lifecycle = WorkspaceController(system: system, settings: fixtureSettings,
                preferences: ActivationOverrides(backend: FixturePreferences(), journal: output.appendingPathComponent("lifecycle-preferences.json")),
                persistSettings: { _ in }, backgroundMonitoring: false)
            let hidden = system.records[2].0
            system.undiscovered.insert(hidden.id)
            await lifecycle.arrange(); lifecycle.saveLayout(); await lifecycle.stop()
            system.undiscovered.removeAll()
            await lifecycle.toggleLayout()
            try check(lifecycle.active && lifecycle.history.current.windows.count == 3,
                "Resuming a saved layout admits newly available windows instead of silently omitting them")
            await lifecycle.stop()
            // The only visible window was not in the original saved two-app tree.
            // Remove it from the remembered tree by activating the first two again.
            system.undiscovered = [hidden.id]
            await lifecycle.arrange(); lifecycle.saveLayout(); await lifecycle.stop()
            system.undiscovered = Set(system.records.prefix(2).map { $0.0.id })
            await lifecycle.toggleLayout()
            try check(lifecycle.active && lifecycle.history.current.windows.map(\.windowID) == [hidden.id],
                "An unavailable saved tree falls back to visible apps rather than reporting a successful inactive resume")
            system.minimized.insert(hidden.id)
            lifecycle.tick()
            for _ in 0..<100 {
                await Task.yield()
                if lifecycle.windows.isEmpty && !lifecycle.activating { break }
                try? await Task.sleep(for: .milliseconds(10))
            }
            try check(lifecycle.active && lifecycle.windows.isEmpty && lifecycle.history.current.windows.isEmpty,
                "Confirmed minimization collapses after one tick without a second membership scan")
            system.minimized.remove(hidden.id)
            lifecycle.tick()
            for _ in 0..<100 {
                if lifecycle.history.current.windows.count == 1 && !lifecycle.activating { break }
                try? await Task.sleep(for: .milliseconds(30))
            }
            try check(lifecycle.active && lifecycle.history.current.windows.map(\.windowID) == [hidden.id],
                "Restoring an identical window frame after minimizing all windows automatically resumes Bento")
            let nativeArea = lifecycle.displayAreas()[0]
            var gridBounds = nativeArea.bounds
            gridBounds.width = (min(1264, gridBounds.width) / 7) * 7 - 3
            gridBounds.height = (min(687, gridBounds.height) / 15) * 15 - 6
            system.areaOverride = [DisplayArea(id: nativeArea.id, name: nativeArea.name, bounds: gridBounds)]
            system.nativeGrid[hidden.id] = Size(7, 15)
            let gridMinimum = hidden.minimum
            await lifecycle.arrange()
            let gridWrites = system.writes[hidden.id] ?? 0
            for _ in 0..<3 { lifecycle.tick(); try? await Task.sleep(for: .milliseconds(40)) }
            try check(lifecycle.active && lifecycle.history.current.windows.count == 1 && hidden.minimum == gridMinimum && (system.writes[hidden.id] ?? 0) == gridWrites,
                "Terminal-style cell rounding stays tiled without drift corrections or invented size limits")
            system.undiscovered = [system.records[1].0.id]
            let chat = system.records[0].0
            system.nativeMinimum[chat.id] = Size(min(480, gridBounds.width / 2), min(600, gridBounds.height - 140))
            await lifecycle.arrange()
            try check(lifecycle.active && lifecycle.history.current.windows.count == 2 && hidden.minimum == gridMinimum,
                "A minimum-height chat and grid-sized terminal share the display without excluding either app")
            system.nativeGrid.removeAll(); system.nativeMinimum.removeAll(); system.areaOverride = nil
            lifecycle.clearSavedLayout(); await lifecycle.restore()
            chat.minimum = Size(160, 120)
            system.undiscovered.removeAll()
            for (index, record) in system.records.enumerated() { try system.write(record.0, frame: initial[index]) }
            // A visible app rejected once must get another admission attempt when
            // focused, even though discovery returns the exact same membership.
            system.rejectedWindows.insert(hidden.id)
            await lifecycle.arrange()
            try check(lifecycle.history.current.windows.count == 2 && lifecycle.floatingWindows.contains { $0.id == hidden.id },
                "A temporarily refusing incoming app remains discoverable outside the layout")
            system.rejectedWindows.removeAll()
            lifecycle.recordInteraction(hidden)
            system.focused = nil
            lifecycle.applicationActivated(hidden.pid)
            system.focused = hidden
            lifecycle.tick()
            for _ in 0..<150 {
                if lifecycle.history.current.windows.count == 3 && !lifecycle.activating { break }
                try? await Task.sleep(for: .milliseconds(30))
            }
            try check(lifecycle.history.current.windows.count == 3,
                "Deferred Dock focus retries a previously rejected visible app without a membership change or manual refresh")
            let admittedWrites = system.writes
            lifecycle.tick(); try? await Task.sleep(for: .milliseconds(100))
            try check(system.writes == admittedWrites,
                "Consumed focus admission does not repeatedly reflow unchanged windows")
            await lifecycle.restore(); system.focused = nil

            // Learn height limits after a valid top/bottom layout was created.
            // Both old rollback rectangles now violate the native limits; the
            // correction must retain the minimum-size failure and switch axes.
            let repairArea = lifecycle.displayAreas()[0]
            let repairBounds = Rect(repairArea.bounds.x, repairArea.bounds.y,
                min(1200, repairArea.bounds.width), min(900, repairArea.bounds.height))
            system.areaOverride = [DisplayArea(id: repairArea.id, name: repairArea.name, bounds: repairBounds)]
            system.undiscovered = [hidden.id]
            let firstRepair = system.records[0].0, secondRepair = system.records[1].0
            firstRepair.minimum = Size(repairBounds.width / 2 + 20, 120); secondRepair.minimum = firstRepair.minimum
            await lifecycle.arrange()
            firstRepair.minimum = Size(160, 120); secondRepair.minimum = Size(160, 120)
            system.nativeMinimum[firstRepair.id] = Size(160, repairBounds.height / 2 + 20)
            system.nativeMinimum[secondRepair.id] = system.nativeMinimum[firstRepair.id]
            let repaired = await lifecycle.arrange(preserving: true)
            let repairRegions = try LayoutEngine.calculate(lifecycle.history.current.roots[repairArea.id], in: system.areaOverride![0].bounds, gap: lifecycle.layoutGap).regions
            try check(repaired && repairRegions.count == 2 && repairRegions.allSatisfy { region in
                system.records.first { $0.0.id == region.window.windowID }.map { system.accepted($0.0, region.bounds) } ?? false
            }, "Incomplete rollback preserves learned limits and admits both apps using the feasible alternate split")
            try check(firstRepair.minimum.width == 160 && secondRepair.minimum.width == 160,
                "A refused height never teaches the previous full-screen width as a minimum")
            system.nativeMinimum.removeAll(); system.areaOverride = nil
            await lifecycle.restore(); system.undiscovered.removeAll()
            for (index, record) in system.records.enumerated() {
                record.0.minimum = Size(160, 120)
                try system.write(record.0, frame: initial[index])
            }
            // Reproduce the small-screen browser/chat workspace with true native
            // limits. A large primary must not hide the other usable apps.
            let fourth = NSWindow(contentRect: NSRect(x: 300, y: 100, width: 420, height: 320), styleMask: [.titled, .resizable, .closable], backing: .buffered, defer: false)
            fourth.isReleasedWhenClosed = false; fourth.title = "Bento fourth capacity fixture"; fourth.orderFrontRegardless()
            let fourthRecord = ManagedWindow(element: AXUIElementCreateApplication(-1003), pid: ProcessInfo.processInfo.processIdentifier, title: fourth.title, application: "Bento Fixture", bundleID: "com.abdullahegh.bento.fixture", frame: DesktopCoordinates.engine(fourth.frame))
            system.records.append((fourthRecord, fourth))
            let normalAreas = model.displayAreas()
            let hostArea = normalAreas[0].bounds
            let capacityArea = Rect(hostArea.x, hostArea.y, min(1264, hostArea.width), min(687, hostArea.height))
            system.areaOverride = [DisplayArea(id: normalAreas[0].id, name: normalAreas[0].name, bounds: capacityArea)]
            // Keep fixture windows inside smaller CI displays; the pure engine
            // separately tests these exact unscaled third-party app dimensions.
            let realLimits = [Size(500, 400), Size(480, 600), Size(336, 242), Size(336, 242)].map {
                Size($0.width * capacityArea.width / 1264, $0.height * capacityArea.height / 687)
            }
            for (index, pair) in system.records.enumerated() {
                pair.0.minimum = realLimits[index]; system.nativeMinimum[pair.0.id] = realLimits[index]
                try system.write(pair.0, frame: Rect(40 + index * 70, 60 + index * 40, max(420, realLimits[index].width), max(342, realLimits[index].height)))
            }
            model.settings.minimizeOverflow = true
            system.writes.removeAll()
            await model.arrange()
            try check(system.writes.values.allSatisfy { $0 == 1 }, "Known small-screen constraints apply one final frame per app without trial placements")
            try check(try model.active && model.history.current.windows.count == 4 && system.minimized.isEmpty && matchingGeometry(), "A constrained browser and chat app keep both smaller apps usable on a small screen")
            let fullCapacity = model.history.current, capacityWrites = system.writes
            await model.arrange(preserving: true)
            try check(model.history.current == fullCapacity && system.writes == capacityWrites, "A full constrained workspace stays still on routine reconciliation")
            await model.restore()
            system.records.forEach { $0.0.minimum = Size(160, 120) }
            let preActivationFrames = Dictionary(uniqueKeysWithValues: system.records.map { ($0.0.id, system.frame(of: $0.0.element)!) })
            system.writtenFrames.removeAll()
            await model.arrange()
            var priorTargets: [UUID: Rect] = [:]
            var duplicatedTarget = false
            for (id, target) in system.writtenFrames {
                if priorTargets[id] == target { duplicatedTarget = true }
                priorTargets[id] = target
            }
            try check(!duplicatedTarget, "Unknown size limits never resend an identical refused target during activation")
            try check(!system.writtenFrames.contains { preActivationFrames[$0.0] == $0.1 }, "Learning activation limits never rolls the batch back between calculated corrections")
            try check(try model.active && model.history.current.windows.count == 4 && system.minimized.isEmpty && matchingGeometry(), "Independent unknown native limits are learned without sacrificing a fitting app")
            try check(system.records[0].0.minimum.height == 120 && model.history.current.windows.first { $0.windowID == system.records[0].0.id }?.minimum.height == 120, "A preferred native primary size never becomes a stored size restriction")
            await model.restore()
            system.records.removeLast(); fourth.close(); system.areaOverride = nil; system.nativeMinimum.removeAll()
            for (index, pair) in system.records.enumerated() { pair.0.minimum = Size(160, 120); try system.write(pair.0, frame: initial[index]) }
            // Real apps can clamp height first and hide a minimum width that was
            // not exercised by the initial target. Reproduce that without probing
            // any third-party windows. Corrections stay bounded.
            let constraintArea = model.displayAreas()[0].bounds
            let constraintPrimary = system.records[0].0, constraintSecondary = system.records[1].0, constraintOldest = system.records[2].0
            system.nativeMinimum[constraintPrimary.id] = Size(Int(Double(constraintArea.width) * 0.39), 120)
            system.nativeMinimum[constraintSecondary.id] = Size(Int(Double(constraintArea.width) * 0.38), Int(Double(constraintArea.height) * 0.87))
            system.nativeMinimum[constraintOldest.id] = Size(Int(Double(constraintArea.width) * 0.26), Int(Double(constraintArea.height) * 0.35))
            // A real app's starting frame already satisfies its own limits.
            for (record, _) in system.records {
                let minimum = system.nativeMinimum[record.id]!
                var frame = system.frame(of: record.element)!
                frame.width = max(frame.width, minimum.width); frame.height = max(frame.height, minimum.height)
                frame.x = max(constraintArea.x, min(frame.x, constraintArea.right - frame.width))
                frame.y = max(constraintArea.y, min(frame.y, constraintArea.bottom - frame.height))
                try system.write(record, frame: frame)
            }
            system.writes.removeAll()
            model.settings.minimizeOverflow = true
            await model.arrange()
            try check(try model.active && matchingGeometry() && model.history.current.windows.count >= 2, "Unknown native limits end in a usable layout within the bounded correction budget")
            try check(modelTrace.contains(where: { $0.contains("arrangement committed attempt=") }) && !modelTrace.contains(where: { $0.contains("arrangement committed attempt=4") }), "Unknown axis limits finish within three coordinated plans")
            try check(constraintPrimary.minimum.height == 120, "A large accepted height never becomes a false permanent minimum")
            let stableActivation = model.history.current
            await model.arrange(preserving: true)
            try check(model.history.current == stableActivation, "A geometry repair does not readmit quiet overflow or rearrange stable slots")
            await model.arrange()
            try check(try model.history.current.windows.count == 3 && matchingGeometry(), "Explicit selection uses learned axis limits to recover every fitting app")
            await model.restore()
            system.nativeMinimum.removeAll(); system.writes.removeAll()
            system.records.forEach { $0.0.minimum = Size(160, 120) }
            for (index, record) in system.records.enumerated() { try system.write(record.0, frame: initial[index]) }
            system.writes.removeAll()
            model.settings.minimizeOverflow = false
            await model.arrange(); interactions.synchronize()
            try check(model.active && matchingGeometry(), "Three disposable native windows arranged")
            let activationRegions = try regions().1.regions
            let primaryRegion = activationRegions.first { $0.window.windowID == system.records[0].0.id }!
            try check(activationRegions.allSatisfy { $0.bounds.width * $0.bounds.height <= primaryRegion.bounds.width * primaryRegion.bounds.height }, "Most recent activation window receives the largest feasible slot")
            try check(system.writes.values.allSatisfy { $0 == 1 }, "Arrangement writes each native window once without intermediate resize animation")
            let writeCount = system.writes
            await model.arrange(preserving: true)
            try check(system.writes == writeCount, "Unchanged layout does not write native window frames again")
            let originalAreas = model.displayAreas(), originalTree = model.history.current
            model.settings.animate = true
            system.areaOverride = originalAreas.map { DisplayArea(id: $0.id, name: $0.name, bounds: Rect($0.bounds.x, $0.bounds.y, $0.bounds.width, $0.bounds.height - 70)) }
            model.tick(); await Task.yield(); await settle()
            try check(try matchingGeometry() && model.history.current == originalTree, "Showing or enlarging the Dock resizes every affected slot without changing the split tree")
            system.areaOverride = originalAreas.map { DisplayArea(id: $0.id, name: $0.name, bounds: Rect($0.bounds.x, $0.bounds.y + 12, $0.bounds.width, $0.bounds.height - 110)) }
            model.tick(); await Task.yield(); await settle()
            try check(try matchingGeometry() && model.history.current == originalTree, "A second Dock-size and top-area change is applied with unchanged window membership")
            system.areaOverride = nil
            model.tick(); await Task.yield(); await settle()
            try check(try matchingGeometry() && model.history.current == originalTree, "Reclaiming desktop space expands every slot back to the current work area")
            let areaWrites = system.writes
            model.tick(); await Task.yield(); model.tick(); await Task.yield()
            try check(system.writes == areaWrites, "Settled work-area changes do not queue repeated native transitions")
            model.settings.animate = false
            let changingAreas = originalAreas.map { DisplayArea(id: $0.id, name: $0.name, bounds: Rect($0.bounds.x, $0.bounds.y, $0.bounds.width, $0.bounds.height - 45)) }
            system.areaChangeOnWrite = changingAreas
            system.rejectedWindows = Set(system.records.map { $0.0.id })
            // Native drift makes an unchanged-membership arrangement write frames.
            let raceWindow = system.records[0].0
            system.rejectedWindows.remove(raceWindow.id)
            let raceFrame = system.frame(of: raceWindow.element)!
            try system.write(raceWindow, frame: Rect(raceFrame.x + 12, raceFrame.y, raceFrame.width, raceFrame.height))
            system.areaOverride = nil; system.areaChangeOnWrite = changingAreas
            system.rejectedWindows = Set(system.records.map { $0.0.id })
            await model.arrange(preserving: true, automatic: true)
            system.rejectedWindows.removeAll()
            model.tick(); await Task.yield(); await settle()
            try check(try matchingGeometry() && model.history.current.windows.count == 3, "A Dock change during a rejected transaction is retried for the new area instead of being cached as failed")
            system.areaOverride = nil; model.tick(); await Task.yield(); await settle()
            let reboundTree = model.history.current
            model.scheduleSettledValidation(force: true)
            let lateWindow = system.records[0].0
            let lateBounds = system.frame(of: lateWindow.element)!
            try system.write(lateWindow, frame: Rect(lateBounds.x + 25, lateBounds.y + 20, lateBounds.width, lateBounds.height))
            system.writes.removeAll()
            try? await Task.sleep(for: .milliseconds(500))
            try check(try matchingGeometry() && model.history.current == reboundTree && system.writes.count == 1, "Late native rebound repairs only the moved window without rebuilding slots")
            model.scheduleSettledValidation(force: true)
            system.pointerHeld = true
            try system.write(lateWindow, frame: Rect(lateBounds.x + 25, lateBounds.y + 20, lateBounds.width, lateBounds.height))
            system.writes.removeAll()
            try? await Task.sleep(for: .milliseconds(400))
            try check(system.writes.isEmpty, "Late verification never interferes with a new pointer gesture")
            system.pointerHeld = false; try system.write(lateWindow, frame: lateBounds)
            let selectionTree = model.history.current
            system.focused = system.records[0].0; model.tick(); system.focused = nil
            await model.releaseActiveWindow()
            try check(!model.history.current.windows.contains { $0.windowID == system.records[0].0.id }, "Stop Arranging Selected Window retains the app selection when Bento's settings takes focus")
            await model.undo()
            try check(model.history.current == selectionTree, "Undo restores a window excluded through the selected-window action")
            let beforeMonitor = model.history.current
            let monitorWrites = system.writes
            let discoveries = system.discoveryCount
            system.pointerHeld = true; system.undiscovered = [system.records[0].0.id]
            model.tick()
            try check(system.discoveryCount == discoveries && model.history.current == beforeMonitor,
                "Membership monitoring does not discover or arrange while a native pointer gesture is held")
            system.pointerHeld = false
            model.tick(); system.undiscovered.removeAll(); model.tick()
            await Task.yield()
            try check(model.history.current == beforeMonitor && system.writes == monitorWrites,
                "One transient missing AX window does not rebuild a committed split tree")
            system.undiscovered = [system.records[0].0.id]; model.tick(); model.tick()
            system.pointerHeld = true; await Task.yield()
            system.undiscovered.removeAll(); system.pointerHeld = false
            try check(model.history.current == beforeMonitor && system.writes == monitorWrites,
                "Queued membership reconciliation rechecks pointer state before moving windows")
            system.pressDuringDiscovery = true
            await model.arrange(preserving: true, automatic: true)
            system.pressDuringDiscovery = false; system.pointerHeld = false
            try check(model.history.current == beforeMonitor && system.writes == monitorWrites,
                "A pointer press during native discovery defers automatic arrangement before any frame write")
            let (_, firstLayout) = try regions()
            try check(interactions.helperFrames.count == firstLayout.dividers.count && interactions.helperFrames.allSatisfy { frame in firstLayout.dividers.contains { $0.bounds == frame } }, "Helper panels occupy gaps only")
            let hoverBounds = firstLayout.dividers[0].bounds
            input.point = Point(hoverBounds.x + hoverBounds.width / 2, hoverBounds.y + hoverBounds.height / 2)
            interactions.sample()
            let hoverPanels = NSApp.windows.compactMap { $0 as? GapPanel }.filter { $0.isVisible && system.dividerWindowNumbers.contains($0.windowNumber) }
            try check(hoverPanels.contains { $0.gripView.visibleInk > 0 }, "Pointer polling reveals a grabber without a mouse-enter event")
            input.point = Point(-100_000, -100_000); interactions.sample()
            try check(hoverPanels.allSatisfy { $0.gripView.visibleInk == 0 }, "Pointer polling hides grabbers after leaving the gap")
            let routedPanel = hoverPanels.first { DesktopCoordinates.engine($0.frame) != hoverBounds }!
            input.point = Point(hoverBounds.x + hoverBounds.width / 2, hoverBounds.y + hoverBounds.height / 2)
            try check(routedPanel.gripView.onBeginAt?(input.point) == true && model.interacting,
                "A first press routed through another grip panel still captures the geometrically selected divider")
            await interactions.finish(cancel: true)
            let dividerTree = model.history.current
            for edgeDivider in firstLayout.dividers {
                let point = edgeDivider.axis == .horizontal
                    ? Point(edgeDivider.bounds.x + max(0, edgeDivider.bounds.width / 2), edgeDivider.bounds.y + 3)
                    : Point(edgeDivider.bounds.x + 3, edgeDivider.bounds.y + max(0, edgeDivider.bounds.height / 2))
                input.point = point; input.pressed = true; system.writes.removeAll(); interactions.sample()
                try check(model.interacting && system.writes.isEmpty, "The far end of a divider starts a drag without a center-handle click or initial jump")
                input.point = edgeDivider.axis == .horizontal ? Point(point.x + 35, point.y) : Point(point.x, point.y + 35)
                interactions.sample(); input.pressed = false; interactions.sample(); await settle()
                try check(try !model.interacting && model.history.current != dividerTree && matchingGeometry(), "Polled full-divider drag commits on release outside its original gap")
                await model.undo(); interactions.synchronize()
            }
            system.dividerExposed = false
            let protectedDivider = firstLayout.dividers[0]
            input.point = Point(protectedDivider.bounds.x + protectedDivider.bounds.width / 2, protectedDivider.bounds.y + protectedDivider.bounds.height / 2)
            system.desktopPointerEnabled = false; input.pressed = true; interactions.sample()
            try check(!model.interacting, "A window covering the divider keeps its click instead of starting a Bento resize")
            input.pressed = false; interactions.sample(); system.desktopPointerEnabled = true; system.dividerExposed = true
            let driftSource = firstLayout.regions[0]
            let driftWindow = system.records.first { $0.0.id == driftSource.window.windowID }!.0
            var driftFrame = driftSource.bounds; driftFrame.x += 12
            try system.write(driftWindow, frame: driftFrame)
            system.pointed = driftWindow
            input = DesktopInput(point: Point(driftFrame.x + 70, driftFrame.y + 20), pressed: true, escape: false, time: 0.1)
            interactions.sample(); input.pressed = false; interactions.sample()
            try check(!model.interacting && model.history.current == beforeMonitor, "A stationary click on a drifted native window never starts a relocation")
            try system.write(driftWindow, frame: driftSource.bounds); system.pointed = nil
            system.desktopPointerEnabled = false
            input = DesktopInput(point: Point(driftSource.bounds.x + 70, driftSource.bounds.y + 20), pressed: true, escape: false, time: 0.3)
            interactions.sample()
            try system.write(driftWindow, frame: driftFrame)
            input.point.x += 50; interactions.sample(); input.pressed = false; interactions.sample()
            try check(!model.interacting && model.history.current == beforeMonitor, "Dragging a Bento settings control cannot grab a tiled window underneath it")
            system.desktopPointerEnabled = true
            try system.write(driftWindow, frame: driftSource.bounds)
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
            let reboundLayout = try regions().1
            let reboundSource = reboundLayout.regions[0], reboundTarget = reboundLayout.regions[1]
            let beforeRebound = model.history.current
            try startDrag(source: reboundSource, target: Point(reboundTarget.bounds.x + reboundTarget.bounds.width / 2,
                reboundTarget.bounds.y + reboundTarget.bounds.height / 2), time: 2)
            let reboundRecord = system.records.first { $0.0.id == reboundSource.window.windowID }!.0
            try system.write(reboundRecord, frame: reboundSource.bounds)
            model.settings.animate = true; system.writes.removeAll()
            let relocationMotionStart = motionBatches()
            input.pressed = false; interactions.sample(); await settle()
            try check(try model.history.current != beforeRebound && matchingGeometry(),
                "A valid drop commits even when the native window rebounds before release without Escape")
            try check(boundedAnimationWrites(since: relocationMotionStart), "Relocation reaches its final destination with a bounded coordinated transition")
            model.settings.animate = false
            await model.undo()
            let fastLayout = try regions().1
            let fastSource = fastLayout.regions[0], fastTarget = fastLayout.regions[1]
            let fastRecord = system.records.first { $0.0.id == fastSource.window.windowID }!.0
            system.focused = system.records.first { $0.0.id != fastRecord.id }!.0; system.pointed = fastRecord
            input = DesktopInput(point: Point(fastSource.bounds.x + 70, fastSource.bounds.y + 20), pressed: true, escape: false, time: 2.4)
            interactions.sample()
            var fastMoved = fastSource.bounds; fastMoved.x += 40; fastMoved.y += 30
            try system.write(fastRecord, frame: fastMoved)
            input.point = Point(fastTarget.bounds.x + fastTarget.bounds.width / 2, fastTarget.bounds.y + fastTarget.bounds.height / 2)
            input.pressed = false; input.time += 0.01; interactions.sample(); await settle()
            try check(try regions().1.regions.first { $0.window.windowID == fastRecord.id }?.bounds == fastTarget.bounds && matchingGeometry(),
                "Hit testing and release sampling commit a fast drag even when AX focus still names the previous window")
            let fastCommitted = model.history.current, fastWrites = system.writes
            model.tick(); await Task.yield(); model.tick(); await Task.yield()
            try check(model.history.current == fastCommitted && system.writes == fastWrites,
                "Membership refresh after relocation preserves the committed destination without extra native writes")
            await model.undo(); system.pointed = nil
            let layout = try regions().1, splitTarget = layout.regions.first { $0.window.windowID != source.window.windowID }!.bounds
            try startDrag(source: sourceAfterSwap, target: Point(splitTarget.x + 24, splitTarget.y + splitTarget.height / 2), time: 3)
            let readsBeforeHold = system.frameReads
            for _ in 0..<200 { input.time += 0.001; interactions.sample() }
            try check(system.frameReads == readsBeforeHold, "Stationary split hold advances feedback without repeated native frame reads")
            input.time += 1; interactions.sample(); input.pressed = false; interactions.sample(); await settle()
            try check(try matchingGeometry() && model.history.current.windows.count == 3, "Held edge drop splits and retains all windows")
            let closeLayout = try regions().1
            let closeSource = closeLayout.regions[0], closeTarget = closeLayout.regions[1]
            try startDrag(source: closeSource, target: Point(closeTarget.bounds.x + closeTarget.bounds.width / 2,
                closeTarget.bounds.y + closeTarget.bounds.height / 2), time: 5)
            system.deadWindows = [closeTarget.window.windowID]
            input.pressed = false; interactions.sample(); await settle()
            try check(try matchingGeometry() && model.history.current.windows.count == 2 && model.message == nil,
                "Closing a drop target mid-gesture recovers the remaining windows without repeated write failures")
            system.deadWindows.removeAll(); await model.arrange(preserving: true)
            let beforeCancel = model.history.current, cancelLayout = try regions().1
            try startDrag(source: cancelLayout.regions[0], target: Point(cancelLayout.regions[1].bounds.x + 50, cancelLayout.regions[1].bounds.y + 50), time: 6)
            input.escape = true; interactions.sample(); await settle()
            input.pressed = false; input.escape = false; interactions.sample()
            try check(try model.history.current == beforeCancel && matchingGeometry(), "Escape restores native drag snapshot")
            let (display, gripLayout) = try regions(), divider = gripLayout.dividers[0]
            input.point = Point(divider.bounds.x + 1, divider.bounds.y + 1)
            try check(interactions.beginGrip(display: display, id: divider.id), "Gap grip begins a native resize")
            input.point = Point(divider.bounds.x + 90, divider.bounds.y + 90); interactions.moveGrip()
            try? await Task.sleep(for: .milliseconds(180)); await interactions.finish(cancel: false)
            try check(try matchingGeometry(), "Gap grip commits matching native bounds")
            let beforeGripCancel = model.history.current, currentDivider = try regions().1.dividers[0]
            input.point = Point(currentDivider.bounds.x + 1, currentDivider.bounds.y + 1)
            _ = interactions.beginGrip(display: display, id: currentDivider.id)
            input.point = Point(currentDivider.bounds.x - 80, currentDivider.bounds.y - 80); interactions.moveGrip()
            try? await Task.sleep(for: .milliseconds(180)); await interactions.finish(cancel: true)
            try check(try model.history.current == beforeGripCancel && matchingGeometry(), "Grip cancellation restores native geometry without history mutation")
            let releaseDivider = try regions().1.dividers[0], beforeRelease = model.history.current
            let releaseStart = Point(releaseDivider.bounds.x + 1, releaseDivider.bounds.y + 1)
            input.point = releaseStart
            model.settings.animate = true; system.deferWrites = true; system.writeDelay = 0.08
            system.writes.removeAll()
            try check(interactions.beginGrip(display: display, id: releaseDivider.id), "Off-center grab starts without moving windows")
            interactions.moveGrip()
            try check(system.writes.isEmpty, "Stationary grip does not enqueue native writes")
            input.point = Point(releaseStart.x + 20, releaseStart.y + 20); interactions.moveGrip()
            input.point = Point(releaseStart.x + 40, releaseStart.y + 40); interactions.moveGrip()
            await interactions.finish(cancel: false)
            let releaseArea = model.displayAreas().first { $0.id == display }!.bounds
            let expectedRelease = try InteractionGeometry.resize(beforeRelease, display: display, divider: releaseDivider, pointer: input.point, area: releaseArea, gap: model.layoutGap, grabbedAt: releaseStart)
            try check(try model.history.current == expectedRelease && matchingGeometry(), "Quick release drains the newest queued pointer sample")
            try check(!system.writes.isEmpty && system.writes.values.allSatisfy { $0 <= 2 }, "Delayed native resize release has no second animation")
            let releaseLayout = try regions().1
            try check(interactions.helperFrames.allSatisfy { frame in releaseLayout.dividers.contains { $0.bounds == frame } }, "Grabbers finish at the accepted window boundaries")
            model.settings.animate = false; system.deferWrites = false; system.writeDelay = 0.04
            let constrainedLayout = try regions().1
            let constrainedDivider = constrainedLayout.dividers[0]
            let firstSide = constrainedLayout.regions.first { region in
                constrainedDivider.axis == .horizontal ? region.bounds.right == constrainedDivider.bounds.x : region.bounds.bottom == constrainedDivider.bounds.y
            }!
            let limited = system.records.first { $0.0.id == firstSide.window.windowID }!.0
            var nativeLimit = limited.minimum
            if constrainedDivider.axis == .horizontal { nativeLimit.width = firstSide.bounds.width - 20 }
            else { nativeLimit.height = firstSide.bounds.height - 20 }
            system.nativeMinimum[limited.id] = nativeLimit
            input.point = Point(constrainedDivider.bounds.x + 1, constrainedDivider.bounds.y + 1)
            _ = interactions.beginGrip(display: display, id: constrainedDivider.id)
            input.point = Point(input.point.x - 100, input.point.y - 100); interactions.moveGrip()
            await interactions.finish(cancel: false)
            try check(try model.history.current.roots[display]?.id == constrainedLayout.dividers[0].id && matchingGeometry(), "A newly discovered native minimum clamps the existing divider instead of rolling back or rearranging the tree")
            let learnedLimit = model.history.current.windows.first { $0.windowID == limited.id }!.minimum
            try check(learnedLimit == nativeLimit && learnedLimit == limited.minimum, "Only the refused axis becomes a persistent split limit; the other axis stays flexible")
            system.nativeMinimum.removeAll()
            limited.minimum = Size(160, 120)
            try await model.finishInteraction(model.history.current, commit: true, animate: false)
            let borderLayout = try regions().1
            func trailingDivider(_ region: Region) -> Divider? {
                borderLayout.dividers.first {
                    $0.axis == .horizontal
                        ? $0.bounds.x == region.bounds.right && region.bounds.width > region.window.minimum.width + 50
                        : $0.bounds.y == region.bounds.bottom && region.bounds.height > region.window.minimum.height + 50
                }
            }
            if let borderSource = borderLayout.regions.first(where: { trailingDivider($0) != nil }), let divider = trailingDivider(borderSource) {
                let record = system.records.first { $0.0.id == borderSource.window.windowID }!.0
                system.focused = record
                let horizontal = divider.axis == .horizontal
                let point = horizontal ? Point(borderSource.bounds.right, borderSource.bounds.y + 50)
                    : Point(borderSource.bounds.x + 50, borderSource.bounds.bottom)
                input = DesktopInput(point: point, pressed: true, escape: false, time: 9)
                interactions.sample()
                var requested = borderSource.bounds
                if horizontal { requested.width -= 20 } else { requested.height -= 20 }
                input.point = horizontal ? Point(point.x - 20, point.y) : Point(point.x, point.y - 20)
                try system.write(record, frame: requested); interactions.sample()
                if horizontal { requested.width -= 20 } else { requested.height -= 20 }
                input.point = horizontal ? Point(point.x - 40, point.y) : Point(point.x, point.y - 40)
                try system.write(record, frame: requested)
                input.pressed = false; interactions.sample(); await settle()
                let changed = try regions().1.regions.first { $0.window.windowID == record.id }!
                try check(try changed.bounds.width == requested.width && changed.bounds.height == requested.height && matchingGeometry(), "Native inner-border resize includes the last native frame on mouse-up")
            } else { throw LayoutError.cannotFit }
            let beforeUndo = model.history.current
            await model.undo(); try check(try model.history.current != beforeUndo && matchingGeometry(), "Native undo restores the previous interaction")
            await model.undo(redo: true); try check(try model.history.current == beforeUndo && matchingGeometry(), "Native redo reapplies the interaction")
            let beforeFailure = system.records.map { DesktopCoordinates.engine($0.1.frame) }
            let (failureDisplay, failureLayout) = try regions()
            let failureSource = failureLayout.regions[0].window, failureTarget = failureLayout.regions[1].window
            let failureCandidate = try model.history.current.placing(failureSource, on: failureDisplay, target: failureTarget.id, placement: .center)
            system.rejectOnce = failureTarget.windowID
            var rejected = false
            do { try await model.apply(failureCandidate, displays: model.displayAreas()) } catch { rejected = true }
            try check(rejected && system.records.map { DesktopCoordinates.engine($0.1.frame) } == beforeFailure, "A rejected native write rolls back the batch")
            let rememberedBento = model.history.current
            let keptFrames = system.records.map { DesktopCoordinates.engine($0.1.frame) }
            try check(model.savedSessionLayout == nil, "Every new controller starts without a saved session layout")
            model.saveLayout()
            let savedRegions = try regions()
            let changedAfterSave = try model.history.current.placing(savedRegions.1.regions[0].window, on: savedRegions.0, target: savedRegions.1.regions[1].window.id, placement: .center)
            try await model.finishInteraction(changedAfterSave, commit: true, animate: false)
            await model.loadLayout()
            try check(try model.history.current == rememberedBento && matchingGeometry(), "Use Saved Layout restores the explicit session snapshot after later edits")
            system.writes.removeAll()
            await model.toggleLayout(); interactions.synchronize()
            try check(!model.active && model.savedSessionLayout == rememberedBento && system.records.map { DesktopCoordinates.engine($0.1.frame) } == keptFrames && system.writes.isEmpty,
                "Turning Bento off after an explicit session save leaves native window positions untouched")
            try check(interactions.helperFrames.isEmpty && preferences.values.isEmpty, "Saved-session stop removes grabbers and restores desktop overrides")
            await model.toggleLayout()
            try check(try model.active && model.history.current == rememberedBento && matchingGeometry(), "Saved-session restart resumes the exact edited split tree")
            model.clearSavedLayout(); await model.toggleLayout()
            try check(!model.active && system.records.map { DesktopCoordinates.engine($0.1.frame) } == initial, "Without a session save, turning Bento off restores original window positions")
            await model.toggleLayout()
            let freshSession = WorkspaceController(system: system, settings: MacSettings(), backgroundMonitoring: false)
            try check(freshSession.savedSessionLayout == nil, "A new app session never reloads a previous session save")
            let oldPreferences = Data(#"{"hideDock":true,"hideMenuBar":true,"gap":14}"#.utf8)
            let resetPreferences = try JSONDecoder().decode(MacSettings.self, from: oldPreferences)
            let encodedPreferences = try JSONSerialization.jsonObject(with: JSONEncoder().encode(resetPreferences)) as! [String: Any]
            try check(!resetPreferences.hideDock && !resetPreferences.hideMenuBar && resetPreferences.gap == 14 && encodedPreferences["hideDock"] == nil && encodedPreferences["hideMenuBar"] == nil,
                "Legacy desktop-hiding values do not survive a new session or persist with other preferences")
            let chrome = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 620), styleMask: [.titled], backing: .buffered, defer: false)
            chrome.isReleasedWhenClosed = false
            BentoWindowChrome.configure(chrome, onboarding: false, theme: "Dark")
            try check(!chrome.styleMask.contains(.fullSizeContentView) && chrome.titleVisibility == .visible && !chrome.titlebarAppearsTransparent && chrome.appearance?.name == .darkAqua,
                "Settings reserve a native title bar and match the selected appearance")
            for appearance in ["Dark", "Light"] {
                BentoWindowChrome.updateAppearance(chrome, theme: appearance)
                var readable = false
                chrome.effectiveAppearance.performAsCurrentDrawingAppearance {
                    if let background = chrome.backgroundColor.usingColorSpace(.deviceRGB), let foreground = NSColor.labelColor.usingColorSpace(.deviceRGB) {
                        func luminance(_ color: NSColor) -> CGFloat { 0.2126 * color.redComponent + 0.7152 * color.greenComponent + 0.0722 * color.blueComponent }
                        readable = background.alphaComponent >= 0.99 && abs(luminance(background) - luminance(foreground)) >= 0.45
                    }
                }
                try check(chrome.isOpaque && readable, "\(appearance) title bar retains an opaque background with readable native title contrast")
            }
            if let close = chrome.standardWindowButton(.closeButton) {
                let buttonFrame = close.convert(close.bounds, to: nil)
                try check(buttonFrame.minY >= chrome.contentLayoutRect.maxY, "Window controls sit above settings content instead of overlapping the glass sidebar")
            }
            chrome.close()
            system.deferWrites = true
            await model.restore(); interactions.synchronize()
            system.deferWrites = false
            try check(model.message == nil, "Restore waits for apps that apply native frames asynchronously")
            try check(system.records.map { DesktopCoordinates.engine($0.1.frame) } == initial && interactions.helperFrames.isEmpty, "Turning Bento off restores fixtures and removes helpers")
            await model.toggleLayout()
            try check(try model.history.current == rememberedBento && matchingGeometry(), "Toggling on resumes the edited Bento tree")
            await model.restore()
            await model.arrange()
            let beforeLiveSpacing = model.history.current
            let originalGap = model.settings.gap, originalMargin = model.settings.margin
            system.writes.removeAll()
            model.settings.gap = originalGap + 2; model.scheduleSettingsUpdate()
            model.settings.gap = originalGap + 4; model.scheduleSettingsUpdate()
            model.settings.gap = originalGap + 6; model.scheduleSettingsUpdate()
            for _ in 0..<200 {
                if model.layoutGap == originalGap + 6 && !model.applyingSettings && !model.busy && !model.activating { break }
                try? await Task.sleep(for: .milliseconds(20))
            }
            interactions.synchronize()
            try check(try model.layoutGap == originalGap + 6 && model.history.current == beforeLiveSpacing && matchingGeometry(), "Rapid gap edits apply live to the same split tree without an Arrange action")
            try check(system.writes.values.allSatisfy { $0 == 1 }, "Rapid spacing changes coalesce to one native frame write per affected window")
            let liveLayout = try regions().1
            var gripsStayInGaps = true
            for frame in interactions.helperFrames {
                for region in liveLayout.regions {
                    let b = region.bounds
                    if frame.x < b.right && b.x < frame.right && frame.y < b.bottom && b.y < frame.bottom { gripsStayInGaps = false }
                }
            }
            try check(gripsStayInGaps, "Live gaps and grabber hit surfaces share the applied geometry")
            let plannedGap = originalGap + 12
            let planDisplay = try regions().0
            let planned = try LayoutEngine.calculate(model.history.current.roots[planDisplay], in: model.displayAreas().first { $0.id == planDisplay }!.bounds, gap: plannedGap)
            let refusedRegion = planned.regions.first { region in
                let record = system.records.first { $0.0.id == region.window.windowID }!.0
                return system.frame(of: record.element) != region.bounds
            }!
            system.rejectOnce = refusedRegion.window.windowID
            model.settings.gap = plannedGap; await model.applyLiveSettings()
            try check(try model.layoutGap == originalGap + 6 && model.settings.gap == originalGap + 6 && model.history.current == beforeLiveSpacing && matchingGeometry(), "A refused live spacing write restores the previous gap and all slots instead of silently dropping an app")
            model.settings.gap = originalGap + 7; await model.applyLiveSettings()
            let exactGap = try regions().1.regions.allSatisfy { region in
                let record = system.records.first { $0.0.id == region.window.windowID }!.0
                return system.frame(of: record.element) == region.bounds
            }
            try check(model.layoutGap == originalGap + 7 && exactGap, "A single-point gap change reaches exact native geometry rather than being skipped by AX validation tolerance")
            model.settings.gap = originalGap + 6; await model.applyLiveSettings()
            system.pointerHeld = true
            model.settings.gap = originalGap + 8; model.scheduleSettingsUpdate()
            try? await Task.sleep(for: .milliseconds(220))
            try check(model.layoutGap == originalGap + 6 && model.history.current == beforeLiveSpacing, "Spacing changes wait while the pointer is pressed")
            system.pointerHeld = false
            for _ in 0..<200 {
                if model.layoutGap == originalGap + 8 && !model.applyingSettings && !model.busy { break }
                try? await Task.sleep(for: .milliseconds(20))
            }
            try check(try model.layoutGap == originalGap + 8 && matchingGeometry(), "Pending spacing updates apply after pointer release")
            system.desktopPointerEnabled = false; system.pointerHeld = true
            model.settings.gap = originalGap + 10; model.scheduleSettingsUpdate()
            for _ in 0..<200 {
                if model.layoutGap == originalGap + 10 && !model.applyingSettings && !model.busy { break }
                try? await Task.sleep(for: .milliseconds(20))
            }
            try check(try model.layoutGap == originalGap + 10 && matchingGeometry(), "Holding Bento's spacing control still updates gaps live while desktop drags remain protected")
            system.pointerHeld = false; system.desktopPointerEnabled = true
            model.settings.margin = originalMargin + 8
            await model.applyLiveSettings()
            try check(try model.layoutMargin == originalMargin + 8 && model.history.current == beforeLiveSpacing && matchingGeometry(), "Live margin changes resize the existing slots without rebuilding their identities")
            model.settings.gap = originalGap; model.settings.margin = originalMargin
            await model.applyLiveSettings()
            let (growthDisplay, growthLayout) = try regions()
            let growthSource = growthLayout.regions[0]
            let growthRecord = system.records.first { $0.0.id == growthSource.window.windowID }!.0
            let growthArea = model.displayAreas().first { $0.id == growthDisplay }!.bounds
            var grown = growthSource.bounds, newLimit = growthRecord.minimum
            if grown.width < growthArea.width { grown.width += 40; newLimit.width = grown.width }
            else { grown.height += 40; newLimit.height = grown.height }
            system.nativeMinimum[growthRecord.id] = newLimit
            try system.write(growthRecord, frame: grown)
            let beforeGrowthWrites = system.writes
            model.tick()
            try check(system.writes == beforeGrowthWrites, "A single native size drift sample does not move other windows")
            model.tick(); await Task.yield()
            func learnedGrowth() -> Bool {
                let learned = growthRecord.minimum
                let refusedAxisMatches = grown.width != growthSource.bounds.width ? learned.width == newLimit.width : learned.height == newLimit.height
                return refusedAxisMatches && learned.width >= newLimit.width && learned.height >= newLimit.height
            }
            for _ in 0..<200 {
                if !model.activating && !model.busy && learnedGrowth() { break }
                try? await Task.sleep(for: .milliseconds(20))
            }
            try check(try model.history.current.windows.contains { $0.windowID == growthRecord.id } && learnedGrowth() && matchingGeometry(), "A persistent app size change learns only its refused axis and adapts the layout automatically")
            let correctedWrites = system.writes
            model.tick(); await Task.yield(); model.tick(); await Task.yield()
            try check(system.writes == correctedWrites, "A corrected native size does not cause repeated background reflows")
            system.nativeMinimum.removeAll(); growthRecord.minimum = Size(160, 120)
            await model.arrange(preserving: true); await model.restore()
            model.settings.hideDock = true; model.settings.hideMenuBar = true; model.settings.edgeSnapping = "Off"
            await model.arrange()
            try check(preferences.values.count == 5, "Activation options request Dock, menu bar and tiling overrides through the injected backend")
            let preferenceLayout = model.history.current
            model.settings.hideDock = false; await model.applyLiveSettings()
            try check(preferences.values[PreferenceKey("com.apple.dock", "autohide")] == nil && preferences.values.count == 4, "Turning Dock hiding off live restores only its prior macOS preference")
            model.settings.hideMenuBar = false; await model.applyLiveSettings()
            try check(preferences.values[PreferenceKey("NSGlobalDomain", "_HIHideMenuBar")] == nil && preferences.values.count == 3, "Turning menu-bar hiding off live leaves native tiling settings intact")
            model.settings.edgeSnapping = "Keep"; await model.applyLiveSettings()
            try check(preferences.values.isEmpty, "Switching live native snapping back to Keep restores the previous values")
            model.settings.hideDock = true; model.settings.hideMenuBar = true; await model.applyLiveSettings()
            try check(try preferences.values.count == 2 && model.history.current == preferenceLayout && matchingGeometry(), "Re-enabling desktop options live preserves the edited layout and original restore baseline")
            await model.restore()
            try check(preferences.values.isEmpty, "Deactivation restores all injected preference values")
            await model.arrange()
            model.settings.hideDock = false
            let livePreferenceUpdate = Task { await model.applyLiveSettings() }
            try? await Task.sleep(for: .milliseconds(100))
            await model.restore(); await livePreferenceUpdate.value
            try check(!model.active && preferences.values.isEmpty && system.records.map { DesktopCoordinates.engine($0.1.frame) } == initial, "Turning Bento off during a live desktop update restores preferences and cannot reactivate a stale layout")
            model.settings.hideDock = true
            await model.arrange(); system.focused = system.records[0].0
            await model.releaseActiveWindow()
            try check(model.history.current.windows.count == 2 && system.accepted(system.records[0].0, initial[0]), "Release active window restores it and expands neighbors")
            await model.undo()
            try check(try model.history.current.windows.count == 3 && matchingGeometry(), "Undo release returns the window to Bento")
            await model.undo(redo: true)
            try check(try model.history.current.windows.count == 2 && matchingGeometry(), "Redo release leaves the window floating")
            let releasedLayout = model.history.current
            await model.restore(); await model.toggleLayout()
            try check(try model.history.current == releasedLayout && matchingGeometry(), "Toggle resume retains the exact edited tree and keeps a released window floating")
            model.tick(); await Task.yield()
            try check(model.history.current == releasedLayout, "Background discovery does not readmit a released window after resume")
            interactions.synchronize()
            let floatingRecord = system.records[0].0
            let floatingFrame = system.frame(of: floatingRecord.element)!
            let floatingTarget = try regions().1.regions[0].bounds
            system.pointed = floatingRecord
            input = DesktopInput(point: Point(floatingFrame.x + 70, floatingFrame.y + 20), pressed: true, escape: false, time: 20)
            interactions.sample()
            var floatingMoved = floatingFrame; floatingMoved.x += 45; floatingMoved.y += 30
            try system.write(floatingRecord, frame: floatingMoved)
            input.point = Point(floatingTarget.x + floatingTarget.width / 2, floatingTarget.y + floatingTarget.height / 2)
            input.time += 0.1; interactions.sample()
            input.pressed = false; interactions.sample(); await settle()
            system.pointed = nil
            try check(try model.history.current.windows.count == 3 && matchingGeometry(), "A floating native window dragged to a slot inserts through the production gesture path without ejecting a neighbor")
            let admittedLayout = model.history.current
            model.tick(); await Task.yield()
            try check(model.history.current == admittedLayout, "Dragging a released window into Bento clears its exclusion without a background reflow")
            await model.arrange()
            try check(try model.history.current.windows.count == 3 && matchingGeometry(), "Arrange all includes released windows again")
            await model.restore()
            let area = model.displayAreas()[0].bounds
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
            system.rejectAlways = oversized.id
            model.settings.minimizeOverflow = true
            await model.arrange()
            try check(!system.minimized.contains(oversized.id), "A control refusal is not evidence of capacity overflow and never causes minimization")
            model.settings.minimizeOverflow = false
            try check(try model.active && model.history.current.windows.count == 2 && matchingGeometry() && system.accepted(oversized, initial[0]), "A window that refuses a resize is restored and skipped while other windows arrange")
            await model.restore()
            system.rejectAlways = nil
            system.rejectedWindows = Set(system.records.prefix(2).map { $0.0.id })
            system.writes.removeAll()
            await model.arrange()
            let refusedWrites = system.rejectedWindows.reduce(0) { $0 + (system.writes[$1] ?? 0) }
            try check(refusedWrites == 2 && !model.active && model.message != nil,
                "Two native refusals stop after one correction instead of testing every window")
            system.rejectedWindows.removeAll(); await model.restore()
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
            try? await Task.sleep(for: .milliseconds(100)); await model.restore(); _ = await activating.value
            try check(!model.active && system.records.map { DesktopCoordinates.engine($0.1.frame) } == initial, "Restoring during activation cancels the pending arrangement")
            model.settings.animate = true
            system.writes.removeAll(); system.frameReads = 0
            let activationMotionStart = motionBatches()
            await model.arrange()
            try check(system.frameReads <= 24, "Animation uses bounded geometry reads instead of polling each intermediate frame")
            try check(try matchingGeometry() && boundedAnimationWrites(since: activationMotionStart), "Animated activation reaches exact final geometry with bounded writes under host load")
            let sectionDisplay = try regions().0
            let sectionArea = model.displayAreas().first { $0.id == sectionDisplay }!.bounds
            let group = LayoutNode.split(id: UUID(), axis: .vertical, ratio: 0.45, first: .window(system.records[0].0.leaf), second: .window(system.records[1].0.leaf))
            let sectionTree = Workspace(roots: [sectionDisplay: .split(id: UUID(), axis: .horizontal, ratio: 0.4, first: group, second: .window(system.records[2].0.leaf))])
            try await model.finishInteraction(sectionTree, commit: true, animate: false)
            interactions.synchronize()
            let bigSection = try regions().1.regions.first { $0.window.windowID == system.records[2].0.id }!
            let screen = DisplayArea.all(margin: 0, fullScreen: true).first { $0.id == sectionDisplay }!.bounds
            let expectedSectionMove = try InteractionGeometry.moveSection(sectionTree, source: bigSection.window.windowID, display: sectionDisplay, toward: .left, area: sectionArea, gap: model.layoutGap)
            try startDrag(source: bigSection, target: Point(screen.x, screen.y + screen.height / 2), time: 40)
            try check(NSApp.windows.contains { $0.isVisible && ($0.contentView as? PreviewSlotView)?.swapsSections == true },
                "Physical screen edge previews section movement instead of a leaf split")
            system.writes.removeAll()
            input.pressed = false; interactions.sample(); await settle()
            let sectionGeometryMatches = try matchingGeometry()
            if model.history.current != expectedSectionMove || !sectionGeometryMatches {
                print("Section move failure: expectedTree=\(model.history.current == expectedSectionMove), nativeGeometry=\(sectionGeometryMatches), trace=\(gestureTrace.suffix(8))")
            }
            try check(model.history.current == expectedSectionMove && sectionGeometryMatches && !system.writes.isEmpty,
                "Screen-edge movement commits the complete sections at exact final bounds even when stale animation samples are skipped")
            await model.undo()
            try check(try model.history.current == sectionTree && matchingGeometry(), "Section movement undo restores the original grouping and ratios")
            let beforeClose = model.history.current
            let closingID = try regions().1.regions[0].window.windowID
            system.deadWindows = [closingID]; system.writes.removeAll()
            let closeMotionStart = motionBatches()
            model.tick()
            for _ in 0..<100 {
                await Task.yield()
                if !model.activating && !model.busy && model.history.current.windows.count == 2 { break }
                try? await Task.sleep(for: .milliseconds(30))
            }
            try check(try model.history.current == beforeClose.removing(closingID) && matchingGeometry() && boundedAnimationWrites(since: closeMotionStart),
                "Closing a window reaches exact collapsed-slot geometry with a bounded transition")
            try check(system.writes[closingID] == nil, "Closing-window reflow never writes the deleted window")
            let closedTree = model.history.current, settledWrites = system.writes
            model.tick(); await Task.yield(); model.tick(); await Task.yield()
            try check(model.history.current == closedTree && system.writes == settledWrites, "Closed-window animation settles once without a second reflow")
            system.deadWindows.removeAll(); await model.arrange(preserving: true)
            system.motionAdjustmentDepths.removeAll()
            let returnTraceStart = modelTrace.count
            await model.restore()
            try check(system.records.map { DesktopCoordinates.engine($0.1.frame) } == initial, "Animated deactivation restores exact starting geometry")
            try check(modelTrace.dropFirst(returnTraceStart).contains { $0.contains("durationMS=320 returning=true") } && system.adjustmentDepth == 0 && system.motionAdjustmentDepths.allSatisfy { $0 > 0 },
                "Window return uses the gentle duration and restores native animation mode after its transaction")
            system.deferWrites = true; system.writeDelay = 0.25
            await model.arrange()
            try check(try model.active && matchingGeometry() && model.history.current.windows.count == 3, "Slow native animation settles before learning constraints or skipping windows")
            await model.restore()
            try check(model.message == nil && system.records.map { DesktopCoordinates.engine($0.1.frame) } == initial, "Slow native restoration waits for the final frames")
            system.deferWrites = false; system.writeDelay = 0.04
            reduceMotion = true; system.writes.removeAll(); system.motionAdjustmentDepths.removeAll()
            await model.arrange()
            // A late native frame may need the one bounded final-frame retry.
            // Observe the animation channel directly instead of mistaking that
            // recovery write for an intermediate animation sample.
            try check(try system.motionAdjustmentDepths.isEmpty && !system.writes.isEmpty
                && system.writes.values.allSatisfy { (1...2).contains($0) } && matchingGeometry(),
                "Reduce Motion omits animation samples and reaches final geometry with bounded native retries")
            await model.restore(); reduceMotion = false
            let gripView = GripView(axis: .horizontal); gripView.animate = false
            try check(gripView.visibleInk == 0, "Idle grip is fully hidden")
            let gapPanel = GapPanel(axis: .horizontal)
            try check(gapPanel.level.rawValue == NSWindow.Level.normal.rawValue - 1, "Grabbers stay below app windows and above the dark backdrop")
            gapPanel.setFrame(NSRect(x: 0, y: 0, width: 8, height: 150), display: true)
            gapPanel.gripView.animate = false
            gapPanel.gripView.layoutSubtreeIfNeeded()
            let hitBitmap = gapPanel.gripView.bitmapImageRepForCachingDisplay(in: gapPanel.gripView.bounds)!
            gapPanel.gripView.cacheDisplay(in: gapPanel.gripView.bounds, to: hitBitmap)
            let hitAlpha = hitBitmap.colorAt(x: 1, y: 1)!.alphaComponent
            try check(hitAlpha > 0 && hitAlpha < 0.02 && gapPanel.gripView.visibleInk == 0 && !gapPanel.ignoresMouseEvents,
                      "Hidden grip retains a nonzero gap input surface without showing its ink")
            var firstPressCount = 0
            var firstPressPoint: Point?
            gapPanel.gripView.onBeginAt = { point in
                firstPressCount += 1; firstPressPoint = point; return true
            }
            let enter = NSEvent.enterExitEvent(with: .mouseEntered, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: gapPanel.windowNumber, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!
            gapPanel.gripView.mouseEntered(with: enter)
            try check(gapPanel.gripView.visibleInk > 0, "Native mouse-enter reveals the hidden grip")
            let down = NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: gapPanel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            gapPanel.gripView.mouseDown(with: down); gapPanel.gripView.mouseExited(with: enter)
            try check(firstPressCount == 1 && firstPressPoint == Point(0, Int(DesktopCoordinates.primaryTop.rounded())) && gapPanel.gripView.acceptsFirstMouse(for: down), "First mouse press starts the grip using event coordinates without a second click")
            try check(gapPanel.gripView.dragging && gapPanel.gripView.visibleInk > 0, "Native press keeps grip visible after pointer leaves")
            gapPanel.gripView.mouseUp(with: down)
            try check(!gapPanel.gripView.dragging && gapPanel.gripView.visibleInk == 0, "Release outside hides the native grip again")
            gapPanel.close()
            gripView.hovering = true
            try check(gripView.visibleInk > 0, "Grip appears on hover")
            gripView.dragging = true; gripView.hovering = false
            try check(gripView.visibleInk > 0, "Grabbed grip stays visible outside hover")
            gripView.dragging = false
            try check(gripView.visibleInk == 0, "Grip hides after release away from hover")
            model.settings.animate = false; model.settings.minimizeOverflow = true
            oversized.minimum = Size(area.width + 100, 120)
            await model.arrange()
            try check(model.active && system.isMinimized(oversized) && model.minimizedByBento.count == 1, "Overflow window is minimized without blocking fitting windows")
            await model.arrange(preserving: true)
            try check(system.isMinimized(oversized) && model.history.current.windows.count == 2, "Reflow retains ownership of minimized overflow")
            model.settings.minimizeOverflow = false; await model.applyLiveSettings()
            try check(!system.isMinimized(oversized) && model.minimizedByBento.isEmpty && model.history.current.windows.count == 2, "Turning overflow minimization off live restores Bento-owned windows without forcing them into slots")
            model.settings.minimizeOverflow = true; await model.applyLiveSettings()
            try check(system.isMinimized(oversized) && model.minimizedByBento.count == 1, "Turning overflow minimization on live minimizes only unplaced eligible windows")
            let overflowLayout = model.history.current
            let beforeUnfittableRestore = system.writes
            try system.setMinimized(oversized, false)
            await model.arrange(preserving: true)
            try check(!system.isMinimized(oversized) && model.minimizedByBento.isEmpty && model.history.current == overflowLayout, "An oversized app restored from Dock stays usable outside Bento instead of being minimized again")
            await model.arrange(preserving: true)
            try check(!system.isMinimized(oversized) && system.writes == beforeUnfittableRestore, "A restored app that cannot fit leaves existing slots untouched on later reconciliation")
            await model.restore()
            // Re-establish owned overflow for the independent fresh-activation
            // check; the preceding restore intentionally left that app floating.
            await model.arrange()
            let automaticallyRemembered = model.history.current
            await model.restore()
            let previousFocus = system.focused
            let mostRecent = system.records.map(\.0).first { $0.id != oversized.id }!
            system.focused = mostRecent; model.recordInteraction(mostRecent)
            await model.toggleLayout()
            try check(model.history.current == automaticallyRemembered,
                "Turning Bento back on prioritizes the remembered layout over a changed focus")
            // Explicit Arrange All remains a fresh recent-use arrangement.
            await model.arrange()
            let renewedRegions = try regions().1.regions
            let recentSlot = renewedRegions.first { $0.window.windowID == mostRecent.id }!
            try check(try Set(model.history.current.windows.map(\.windowID)) == Set(overflowLayout.windows.map(\.windowID)) && system.isMinimized(oversized) && matchingGeometry(), "Fresh activation retains overflow ownership and every fitting window")
            try check(renewedRegions.allSatisfy { $0.bounds.width * $0.bounds.height <= recentSlot.bounds.width * recentSlot.bounds.height }, "Fresh activation updates the largest slot to the latest focused app")
            system.focused = previousFocus
            oversized.minimum = Size(160, 120)
            try system.setMinimized(oversized, false)
            await model.arrange(preserving: true)
            try check(try model.history.current.windows.count == 3 && matchingGeometry() && model.minimizedByBento.isEmpty, "Reopening from Dock reinserts the window into split slots")
            // Saturate the display: two windows fit, three cannot. Recently used
            // first window survives regardless of native discovery order.
            await model.restore()
            let first = system.records[1].0, second = system.records[2].0
            let crowdedMinimum = Size(area.width / 2 + 1, area.height / 3 + 1)
            first.minimum = crowdedMinimum; second.minimum = crowdedMinimum
            oversized.minimum = Size(area.width + 100, 120)
            system.focused = first
            await model.arrange()
            model.recordInteraction(second); model.recordInteraction(first)
            oversized.minimum = crowdedMinimum
            let retainedFrame = system.frame(of: first.element)
            let vacatedFrame = system.frame(of: second.element)
            model.settings.animate = true; system.writes.removeAll()
            let admissionMotionStart = motionBatches()
            try system.setMinimized(oversized, false); system.focused = oversized
            await model.arrange(preserving: true)
            try check(!system.isMinimized(oversized) && !system.isMinimized(first) && system.isMinimized(second)
                && model.history.current.windows.count == 2, "Dock reopen evicts least recently used window on a full display")
            try check(system.frame(of: first.element) == retainedFrame && system.frame(of: oversized.element) == vacatedFrame,
                "Crowded Dock admission reuses the idle slot without moving its neighbor")
            try check(system.writes[first.id] == nil && system.writes[second.id] == nil && (system.writes[oversized.id] ?? 0) >= 1 && boundedAnimationWrites(since: admissionMotionStart),
                "Automatic Dock admission reaches the incoming slot with bounded writes and no unchanged-neighbor moves")
            model.settings.animate = false
            await model.arrange(preserving: true)
            try check(system.isMinimized(second) && !system.isMinimized(oversized), "Minimized overflow does not steal the reopened window's space on next reflow")
            await model.restore()
            // This window was minimized by the user, not Bento, before activation.
            try system.setMinimized(oversized, true)
            await model.arrange()
            model.recordInteraction(first)
            try system.setMinimized(oversized, false)
            await model.arrange(preserving: true)
            try check(!system.isMinimized(oversized) && system.isMinimized(second), "Newly visible Dock window gets space without prior Bento ownership")
            await model.restore()
            first.minimum = Size(160, 120); second.minimum = Size(160, 120); system.focused = nil
            oversized.minimum = Size(area.width + 100, 120)
            await model.arrange(); await model.restore()
            try check(!system.isMinimized(oversized) && model.minimizedByBento.isEmpty, "Deactivation brings back only Bento-minimized windows")
            system.minimized.insert(oversized.id)
            await model.arrange(); await model.restore()
            try check(system.isMinimized(oversized), "Windows minimized before activation stay minimized")
            system.minimized.removeAll(); system.denyMinimize = true
            await model.arrange()
            try check(model.active && model.minimizedByBento.isEmpty && model.history.current.windows.count == 2, "Minimize refusal does not stop fitting-window arrangement")
            await model.restore(); system.denyMinimize = false; oversized.minimum = Size(160, 120)
            let update = MacUpdater()
            var restorationCalls = 0, installCalls = 0, attentionCalls = 0, readyToInstall = false
            update.beforeInstall = { restorationCalls += 1; await Task.yield(); return readyToInstall }
            update.onInstallationNeedsAttention = { attentionCalls += 1 }
            try check(update.shouldPostponeInstallation { installCalls += 1 }, "The first relaunch callback waits for window restoration")
            update.retryInstall(); update.retryInstall()
            while update.preparingInstallation { try? await Task.sleep(for: .milliseconds(10)) }
            try check(restorationCalls == 1 && installCalls == 0 && update.pendingInstallation && attentionCalls == 1,
                "A blocked install shows retry status without losing its completion or duplicating restoration")
            readyToInstall = true; update.retryInstall(); update.retryInstall()
            while update.preparingInstallation { try? await Task.sleep(for: .milliseconds(10)) }
            update.retryInstall()
            try check(restorationCalls == 2 && installCalls == 1 && update.installationPrepared && !update.pendingInstallation,
                "Retry installation resumes Sparkle exactly once after successful restoration")
            try check(!update.shouldPostponeInstallation { installCalls += 100 } && installCalls == 1 && !update.preparingInstallation,
                "A repeated relaunch callback proceeds immediately after preparation instead of postponing forever")
            var previewReducedMotion = false
            let softPreview = DestinationPanel(reduceMotion: { previewReducedMotion })
            let previewIdentity = UUID()
            softPreview.windowFrames = [previewIdentity: Rect(40, 40, 400, 300)]
            softPreview.presentConflict(Rect(40, 40, 400, 300))
            let softPanel = softPreview.previewWindow!
            try check(softPanel.alphaValue == 0 && softPanel.ignoresMouseEvents, "Soft preview starts transparent and never intercepts app input")
            let retarget = Rect(120, 80, 520, 360)
            softPreview.windowFrames = [previewIdentity: retarget]
            softPreview.presentConflict(retarget)
            // Timer delivery can be delayed on a shared CI desktop. Wait for the
            // actual destination with a bound, then observe it again after an old
            // transition would have completed. This tests retargeting, not host load.
            let previewDeadline = ProcessInfo.processInfo.systemUptime + 1
            while (softPanel.frame != DesktopCoordinates.appKit(retarget) || softPanel.alphaValue != 1),
                  ProcessInfo.processInfo.systemUptime < previewDeadline {
                try? await Task.sleep(for: .milliseconds(20))
            }
            let reachedDestination = softPanel.frame == DesktopCoordinates.appKit(retarget) && softPanel.alphaValue == 1
            try? await Task.sleep(for: .milliseconds(150))
            try check(reachedDestination && softPanel.frame == DesktopCoordinates.appKit(retarget) && softPanel.alphaValue == 1, "Preview retargeting reaches the latest destination without an old animation snapping back")
            try check(softPreview.dimVisible && abs(softPreview.dimOpacity - 0.45) < 0.001 && softPreview.dimPassesClicks,
                "Destination highlights have a gentle black dim layer underneath that never intercepts clicks")
            softPreview.orderOut(nil)
            for _ in 0..<12 { try? await Task.sleep(for: .milliseconds(20)); softPreview.orderOut(nil) }
            try check(!softPanel.isVisible && !softPreview.dimVisible && softPreview.dimOpacity == 0,
                "Repeated hide requests finish one fade and remove both preview and dim layer")
            softPreview.animate = false; softPreview.presentConflict(retarget)
            try check(softPanel.frame == DesktopCoordinates.appKit(retarget) && softPanel.alphaValue == 1, "Disabling motion applies preview geometry immediately")
            softPreview.orderOut(nil)
            softPreview.animate = true; previewReducedMotion = true
            softPreview.presentConflict(retarget)
            try check(softPanel.frame == DesktopCoordinates.appKit(retarget) && softPanel.alphaValue == 1, "Reduce Motion skips preview movement while preserving the destination")
            softPreview.hideImmediately()
            try check(!softPanel.isVisible && !softPreview.dimVisible, "Mission Control immediately removes preview highlights and their dim layer")
            passed += try DragPreviewSmoke.run(system: system)
            let splitFrost = PreviewSlotView(frame: NSRect(x: 0, y: 0, width: 300, height: 400), reduceTransparency: false)
            splitFrost.placement = .left
            try check(splitFrost.isSplitting, "Directional destinations retain split semantics with a neutral glass outline")
            splitFrost.conflict = true
            try check(!splitFrost.isSplitting, "A conflict replaces splitting feedback instead of showing both states")
            if #available(macOS 26.0, *) {
                try check(splitFrost.materialKind == .liquidGlass, "macOS 26 previews use the native Liquid Glass material")
            } else {
                try check(splitFrost.materialKind == .blur, "macOS 15 previews retain a native blurred backdrop")
            }
            let fallbackFrost = PreviewSlotView(allowGlass: false, reduceTransparency: false)
            try check(fallbackFrost.materialKind == .blur, "The older-system fallback uses native background blur")
            let accessibleFrost = PreviewSlotView(reduceTransparency: true)
            try check(accessibleFrost.materialKind == .opaque, "Reduce Transparency replaces glass with a readable solid backdrop")
            // Render only our own preview views for visual review, never desktop pixels.
            let canvas = NSView(frame: NSRect(x: 0, y: 0, width: 1224, height: 500))
            canvas.wantsLayer = true; canvas.layer?.backgroundColor = NSColor(calibratedWhite: 0.16, alpha: 1).cgColor
            for index in 0..<4 {
                let slot = PreviewSlotView(frame: NSRect(x: 12 + index * 304, y: 12, width: 288, height: 476))
                slot.placement = index == 0 ? .center : .left; slot.progress = index == 1 ? 0.55 : nil
                slot.conflict = index == 3
                canvas.addSubview(slot)
            }
            if let bitmap = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds) {
                canvas.cacheDisplay(in: canvas.bounds, to: bitmap)
                // Composite transparent panels over a known desktop color for
                // review; the live WindowServer performs this compositing itself.
                let composited = NSImage(size: canvas.bounds.size, flipped: false) { rect in
                    NSColor(calibratedWhite: 0.16, alpha: 1).setFill(); rect.fill()
                    bitmap.draw(in: rect); return true
                }
                if let data = composited.tiffRepresentation, let flattened = NSBitmapImageRep(data: data) {
                    try flattened.representation(using: .png, properties: [:])?.write(to: output.appendingPathComponent("split-preview.png"))
                }
            }
            try JSONSerialization.data(withJSONObject: ["passed": passed, "externalApplicationsTouched": false, "systemPreferencesChanged": false], options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("results.json"))
            print("Native interaction smoke: \(passed.count) checks passed; disposable windows only.")
        } catch { await interactions.finish(cancel: true); await model.restore(); throw error }
    }
}
