import AppKit
import ApplicationServices
import BentoCore

// Disposable in-process NSWindows exercise the production controller/panels with
// supplied pointer samples. This adapter never queries or changes other applications.
@MainActor private final class FixtureWindowSystem: MacWindowSystem {
    var records: [(ManagedWindow, NSWindow)] = []
    var focused: ManagedWindow?
    var pointed: ManagedWindow?
    var pointerHeld = false
    var desktopPointerEnabled = true
    override var tracksDesktopPointer: Bool { desktopPointerEnabled }
    var pressDuringDiscovery = false
    var undiscovered = Set<UUID>()
    var deadWindows = Set<UUID>()
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
    var writes: [UUID: Int] = [:]
    var minimized = Set<UUID>()
    var denyMinimize = false
    override func isMinimized(_ window: ManagedWindow) -> Bool { minimized.contains(window.id) }
    override func setMinimized(_ window: ManagedWindow, _ value: Bool) throws {
        if denyMinimize { throw WindowFailure.rejected(window.title) }
        if value { minimized.insert(window.id) } else { minimized.remove(window.id) }
    }
    override var trusted: Bool { accessibilityGranted }
    override func discover() throws -> [ManagedWindow] {
        discoveryCount += 1
        if pressDuringDiscovery { pointerHeld = true }
        for (record, window) in records { record.frame = DesktopCoordinates.engine(window.frame) }
        return records.map(\.0).filter { !minimized.contains($0.id) && !undiscovered.contains($0.id) && !deadWindows.contains($0.id) }
    }
    override func focusedWindow(in windows: [ManagedWindow]) -> ManagedWindow? { focused }
    override func frame(of element: AXUIElement) -> Rect? {
        frameReads += 1
        return records.first { CFEqual($0.0.element, element) }.map { DesktopCoordinates.engine($0.1.frame) }
    }
    override func isAlive(_ window: ManagedWindow) -> Bool { !deadWindows.contains(window.id) && records.contains { $0.0.id == window.id } }
    override func write(_ window: ManagedWindow, frame: Rect) throws {
        writes[window.id, default: 0] += 1
        if rejectAlways == window.id || rejectedWindows.contains(window.id) { throw WindowFailure.rejected(window.title) }
        if rejectOnce == window.id { rejectOnce = nil; throw WindowFailure.rejected(window.title) }
        guard let actual = records.first(where: { $0.0.id == window.id })?.1 else { throw WindowFailure.unavailable(window.title) }
        var accepted = frame
        if let minimum = nativeMinimum[window.id] { accepted.width = max(accepted.width, minimum.width); accepted.height = max(accepted.height, minimum.height) }
        let nativeFrame = DesktopCoordinates.appKit(accepted)
        if deferWrites { DispatchQueue.main.asyncAfter(deadline: .now() + writeDelay) { actual.setFrame(nativeFrame, display: true) } }
        else { actual.setFrame(nativeFrame, display: true) }
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
        var reduceMotion = false
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        var fixtureSettings = MacSettings(); fixtureSettings.animate = false; fixtureSettings.minimizeOverflow = false
        let model = WorkspaceController(system: system, settings: fixtureSettings, preferences: ActivationOverrides(backend: preferences, journal: output.appendingPathComponent("fixture-preferences.json")), persistSettings: { _ in }, backgroundMonitoring: false, reduceMotion: { reduceMotion })
        var input = DesktopInput(point: Point(0, 0), pressed: false, escape: false, time: 0)
        var gestureTrace: [String] = []
        let interactions = DesktopInteractions(model: model, input: { input }, automaticSampling: false, trace: { gestureTrace.append($0) })
        defer { try? gestureTrace.joined(separator: "\n").write(to: output.appendingPathComponent("gesture-trace.log"), atomically: true, encoding: .utf8) }
        model.cancelInteraction = { await interactions.finish(cancel: true) }
        var passed: [String] = []
        func check(_ value: Bool, _ title: String) throws {
            guard value else { throw NSError(domain: "BentoNativeSmoke", code: 1, userInfo: [NSLocalizedDescriptionKey: title]) }
            passed.append(title)
        }
        func matchingGeometry() throws -> Bool {
            for display in DisplayArea.all(margin: model.layoutMargin) {
                for region in try LayoutEngine.calculate(model.history.current.roots[display.id], in: display.bounds, gap: model.layoutGap).regions {
                    guard let record = system.records.first(where: { $0.0.id == region.window.windowID })?.0, system.accepted(record, region.bounds) else { return false }
                }
            }
            return true
        }
        func regions() throws -> (String, LayoutResult) {
            let key = model.history.current.roots.keys.sorted()[0]
            let area = DisplayArea.all(margin: model.layoutMargin).first { $0.id == key }!
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
            await model.arrange(); interactions.synchronize()
            try check(model.active && matchingGeometry(), "Three disposable native windows arranged")
            try check(system.writes.values.allSatisfy { $0 == 1 }, "Arrangement writes each native window once without intermediate resize animation")
            let writeCount = system.writes
            await model.arrange(preserving: true)
            try check(system.writes == writeCount, "Unchanged layout does not write native window frames again")
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
            let hoverPanels = NSApp.windows.compactMap { $0 as? GapPanel }.filter { $0.isVisible }
            try check(hoverPanels.contains { $0.gripView.visibleInk > 0 }, "Pointer polling reveals a grabber without a mouse-enter event")
            input.point = Point(-100_000, -100_000); interactions.sample()
            try check(hoverPanels.allSatisfy { $0.gripView.visibleInk == 0 }, "Pointer polling hides grabbers after leaving the gap")
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
            input.pressed = false; interactions.sample(); await settle()
            try check(try model.history.current != beforeRebound && matchingGeometry(),
                "A valid drop commits even when the native window rebounds before release without Escape")
            try check(system.writes.values.allSatisfy { $0 == 1 }, "Successful relocation uses one final write per changed window with no second animation")
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
            let releaseArea = DisplayArea.all(margin: model.layoutMargin).first { $0.id == display }!.bounds
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
            try check(model.history.current.windows.first { $0.windowID == limited.id }?.minimum == nativeLimit, "Native size constraints persist in the committed split for subsequent gestures")
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
            do { try await model.apply(failureCandidate, displays: DisplayArea.all(margin: model.layoutMargin)) } catch { rejected = true }
            try check(rejected && system.records.map { DesktopCoordinates.engine($0.1.frame) } == beforeFailure, "A rejected native write rolls back the batch")
            let rememberedBento = model.history.current
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
            try check(interactions.helperFrames.allSatisfy { frame in liveLayout.dividers.contains { $0.bounds == frame } }, "Live gaps and grabber hit surfaces share the applied geometry")
            let plannedGap = originalGap + 12
            let planDisplay = try regions().0
            let planned = try LayoutEngine.calculate(model.history.current.roots[planDisplay], in: DisplayArea.all(margin: model.layoutMargin).first { $0.id == planDisplay }!.bounds, gap: plannedGap)
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
            let growthArea = DisplayArea.all(margin: model.layoutMargin).first { $0.id == growthDisplay }!.bounds
            var grown = growthSource.bounds, newLimit = growthRecord.minimum
            if grown.width < growthArea.width { grown.width += 40; newLimit.width = grown.width }
            else { grown.height += 40; newLimit.height = grown.height }
            system.nativeMinimum[growthRecord.id] = newLimit
            try system.write(growthRecord, frame: grown)
            let beforeGrowthWrites = system.writes
            model.tick()
            try check(system.writes == beforeGrowthWrites, "A single native size drift sample does not move other windows")
            model.tick(); await Task.yield()
            for _ in 0..<200 {
                if !model.activating && !model.busy && growthRecord.minimum == newLimit { break }
                try? await Task.sleep(for: .milliseconds(20))
            }
            try check(try model.history.current.windows.contains { $0.windowID == growthRecord.id } && growthRecord.minimum == newLimit && matchingGeometry(), "A persistent app size change learns its constraint and adapts the layout automatically")
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
            let area = DisplayArea.all(margin: model.layoutMargin)[0].bounds
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
            await model.arrange()
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
            try? await Task.sleep(for: .milliseconds(100)); await model.restore(); await activating.value
            try check(!model.active && system.records.map { DesktopCoordinates.engine($0.1.frame) } == initial, "Restoring during activation cancels the pending arrangement")
            model.settings.animate = true
            system.writes.removeAll()
            await model.arrange()
            try check(try matchingGeometry() && system.writes.values.allSatisfy { $0 > 1 }, "Animated activation sends intermediate frames and reaches exact final geometry")
            let sectionDisplay = try regions().0
            let sectionArea = DisplayArea.all(margin: model.layoutMargin).first { $0.id == sectionDisplay }!.bounds
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
            try check(try model.history.current == expectedSectionMove && matchingGeometry() && system.writes.values.contains { $0 > 1 },
                "Screen-edge drag animates the big section left and carries the stacked section right")
            await model.undo()
            try check(try model.history.current == sectionTree && matchingGeometry(), "Section movement undo restores the original grouping and ratios")
            let beforeClose = model.history.current
            let closingID = try regions().1.regions[0].window.windowID
            system.deadWindows = [closingID]; system.writes.removeAll()
            model.tick()
            for _ in 0..<100 {
                await Task.yield()
                if !model.activating && !model.busy && model.history.current.windows.count == 2 { break }
                try? await Task.sleep(for: .milliseconds(30))
            }
            try check(try model.history.current == beforeClose.removing(closingID) && matchingGeometry() && system.writes.values.contains { $0 > 1 },
                "Closing a window animates the collapsed slots to their exact final frames")
            try check(system.writes[closingID] == nil, "Closing-window reflow never writes the deleted window")
            let closedTree = model.history.current, settledWrites = system.writes
            model.tick(); await Task.yield(); model.tick(); await Task.yield()
            try check(model.history.current == closedTree && system.writes == settledWrites, "Closed-window animation settles once without a second reflow")
            system.deadWindows.removeAll(); await model.arrange(preserving: true)
            await model.restore()
            try check(system.records.map { DesktopCoordinates.engine($0.1.frame) } == initial, "Animated deactivation restores exact starting geometry")
            system.deferWrites = true; system.writeDelay = 0.25
            await model.arrange()
            try check(try model.active && matchingGeometry() && model.history.current.windows.count == 3, "Slow native animation settles before learning constraints or skipping windows")
            await model.restore()
            try check(model.message == nil && system.records.map { DesktopCoordinates.engine($0.1.frame) } == initial, "Slow native restoration waits for the final frames")
            system.deferWrites = false; system.writeDelay = 0.04
            reduceMotion = true; system.writes.removeAll()
            await model.arrange()
            try check(system.writes.values.allSatisfy { $0 == 1 }, "Reduce Motion sends only final native frames")
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
            gapPanel.gripView.onBegin = { true }
            let enter = NSEvent.enterExitEvent(with: .mouseEntered, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: gapPanel.windowNumber, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!
            gapPanel.gripView.mouseEntered(with: enter)
            try check(gapPanel.gripView.visibleInk > 0, "Native mouse-enter reveals the hidden grip")
            let down = NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: gapPanel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            gapPanel.gripView.mouseDown(with: down); gapPanel.gripView.mouseExited(with: enter)
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
            await model.restore(); await model.toggleLayout()
            try check(try model.history.current == overflowLayout && system.isMinimized(oversized) && matchingGeometry(), "Toggle resume restores Dock overflow ownership without readmitting or moving other slots")
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
            try system.setMinimized(oversized, false); system.focused = oversized
            await model.arrange(preserving: true)
            try check(!system.isMinimized(oversized) && !system.isMinimized(first) && system.isMinimized(second)
                && model.history.current.windows.count == 2, "Dock reopen evicts least recently used window on a full display")
            try check(system.frame(of: first.element) == retainedFrame && system.frame(of: oversized.element) == vacatedFrame,
                "Crowded Dock admission reuses the idle slot without moving its neighbor")
            try check(system.writes[first.id] == nil && system.writes[second.id] == nil && system.writes[oversized.id] == 1,
                "Automatic Dock admission writes only the incoming final frame, even with animations enabled")
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
                try bitmap.representation(using: .png, properties: [:])?.write(to: output.appendingPathComponent("split-preview.png"))
            }
            try JSONSerialization.data(withJSONObject: ["passed": passed, "externalApplicationsTouched": false, "systemPreferencesChanged": false], options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("results.json"))
            print("Native interaction smoke: \(passed.count) checks passed; disposable windows only.")
        } catch { await interactions.finish(cancel: true); await model.restore(); throw error }
    }
}
