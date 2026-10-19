import AppKit
import BentoCore

private final class ExternalFixturePreferences: PreferenceBackend {
    private var values: [PreferenceKey: Data] = [:]
    func read(_ key: PreferenceKey) -> Data? { values[key] }
    func write(_ key: PreferenceKey, value: Data?) { values[key] = value }
    func refresh(_ keys: [PreferenceKey]) {}
}

@MainActor private final class InsertionAXSystem: MacWindowSystem {
    var testAreas: [DisplayArea]?
    override func displayAreas(margin: Int) -> [DisplayArea] { testAreas ?? super.displayAreas(margin: margin) }
}

@MainActor enum ExternalAXSmoke {
    static func run(pid: pid_t, output: URL) async throws {
        let system = InsertionAXSystem(allowedPIDs: [pid])
        var settings = MacSettings(); settings.onboardingComplete = true
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let preferences = ActivationOverrides(backend: ExternalFixturePreferences(), journal: output.appendingPathComponent("fixture-preferences.json"))
        var activationTrace: [String] = []
        let model = WorkspaceController(system: system, settings: settings, preferences: preferences, persistSettings: { _ in }, backgroundMonitoring: false, trace: { activationTrace.append($0); print("TRACE: \($0)") })
        var passed: [String] = []
        func check(_ value: Bool, _ title: String) throws {
            guard value else { throw NSError(domain: "ExternalAX", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(title): \(model.message ?? "geometry mismatch")"]) }
            passed.append(title)
            print("PASS: \(title)")
        }
        func layout() throws -> (String, LayoutResult) {
            guard let display = DisplayArea.all(margin: model.layoutMargin).first(where: { model.history.current.roots[$0.id] != nil }) else { throw LayoutError.missingTarget }
            return (display.id, try LayoutEngine.calculate(model.history.current.roots[display.id], in: display.bounds, gap: model.layoutGap))
        }
        func matches() throws -> Bool {
            try layout().1.regions.allSatisfy { region in
                guard let window = model.windows.first(where: { $0.id == region.window.windowID }) else { return false }
                return system.accepted(window, region.bounds)
            }
        }
        // AX frame completion can precede the WindowServer snapshot used by
        // discovery. Wait for fixture readiness, without moving any windows.
        func waitForDiscovery() async throws {
            for _ in 0..<40 {
                if try system.discover().count == 3 { return }
                try await Task.sleep(for: .milliseconds(30))
            }
        }
        try await waitForDiscovery()
        let initial = try system.discover()
        try check(initial.count == 3, "Real AX discovers three external fixture windows")
        let originals = Dictionary(uniqueKeysWithValues: initial.map { ($0.id, $0.frame) })
        do {
            await model.arrange()
            try check(try model.active && matches(), "Real AX arranges external windows")
            try check(activationTrace.filter { $0.contains("arrangement committed attempt=1") }.count == 1
                && !activationTrace.contains { $0.contains("bounded correction=") }
                && model.windows.allSatisfy { $0.minimum == Size(160, 140) },
                "Real AX measures native minima and commits first activation once")
            for placement in [Placement.left, .right, .top, .bottom, .center] {
                await model.arrange()
                let (display, before) = try layout()
                let target = before.regions.max { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }!
                let source = before.regions.first { $0.window.windowID != target.window.windowID }!
                let next = try model.history.current.placing(source.window, on: display, target: target.window.id, placement: placement)
                try await model.finishInteraction(next, commit: true)
                try check(try matches() && next.windows.count == 3, "Real AX commits \(placement.rawValue) placement without losing windows")
            }
            let (display, beforeResize) = try layout(), divider = beforeResize.dividers[0]
            let area = DisplayArea.all(margin: model.layoutMargin).first { $0.id == display }!.bounds
            let next = try InteractionGeometry.resize(model.history.current, display: display, divider: divider, pointer: Point(divider.bounds.x + 30, divider.bounds.y + 30), area: area, gap: model.layoutGap)
            try await model.finishInteraction(next, commit: true)
            try check(try matches(), "Real AX resizes neighboring external windows")
            await model.undo(); try check(try matches(), "Real AX undo")
            await model.undo(redo: true); try check(try matches(), "Real AX redo")
            let edited = model.history.current
            model.settings.gap = 16; await model.applyLiveSettings()
            try check(try model.layoutGap == 16 && model.history.current == edited && matches(), "Real AX gap changes update live without rebuilding the edited tree")
            model.settings.margin = 16; await model.applyLiveSettings()
            try check(try model.layoutMargin == 16 && model.history.current == edited && matches(), "Real AX margin changes resize the same slots live")
            model.settings.gap = settings.gap; model.settings.margin = settings.margin
            await model.applyLiveSettings()
            await model.restore()
            try check(initial.allSatisfy { system.accepted($0, originals[$0.id]!) }, "Real AX restores original external bounds")
            try await waitForDiscovery()
            await model.toggleLayout()
            try check(try model.history.current == edited && matches(), "Real AX toggle resumes the exact edited tree")
            let floating = model.history.current.removing(initial[0].id)
            try await model.finishInteraction(floating, commit: true, animate: false)
            await model.restore(); try await waitForDiscovery(); await model.toggleLayout()
            try check(try model.history.current == floating && matches() && system.accepted(initial[0], originals[initial[0].id]!), "Real AX resume retains a floating window and edited slot membership")
            await model.restore()
            try await waitForDiscovery()
            do {
            let model = WorkspaceController(system: system, settings: settings, preferences: preferences, persistSettings: { _ in }, backgroundMonitoring: false, trace: { print("INSERT TRACE: \($0)") })
            let insertionArea = system.displayAreas(margin: model.layoutMargin)[0]
            system.testAreas = [DisplayArea(id: insertionArea.id, name: insertionArea.name, bounds: Rect(insertionArea.bounds.x, insertionArea.bounds.y, 300, 200))]
            await model.arrange()
            print("INSERT COUNTS tiles=\(model.history.current.windows.count) minimized=\(model.minimizedByBento.count) waiting=\(model.waitingForInsertion.count) message=\(model.message ?? "none")")
            try check(model.history.current.windows.count == 1 && model.minimizedByBento.count == 2,
                "Real AX queues only non-fitting windows on a small work area")
            // A person reaches the waiting tiles after Dock minimization completes.
            for _ in 0..<40 {
                if model.minimizedByBento.values.allSatisfy({ system.isMinimized($0) }) { break }
                try await Task.sleep(for: .milliseconds(30))
            }
            let snapshot = model.history.current
            let waiting = model.minimizedByBento.values.first!
            let previous = snapshot.windows[0]
            let next = try snapshot.placing(waiting.leaf, on: insertionArea.id, target: previous.id, placement: .center)
            let inserted = await model.insertOverflow(waiting.id, into: next, from: snapshot)
            print("INSERT RESULT accepted=\(inserted) waiting=\(model.waitingForInsertion.count) message=\(model.message ?? "none") sourceMin=\(system.isMinimized(waiting))")
            let target = try LayoutEngine.calculate(next.roots[insertionArea.id], in: system.testAreas![0].bounds, gap: model.layoutGap).regions[0].bounds
            try check(inserted && system.accepted(waiting, target) && !system.isMinimized(waiting)
                && model.minimizedByBento[previous.windowID].map { system.isMinimized($0) } == true,
                "Real AX restores a queued Dock window before replacing and minimizing the occupied slot")
            try check(model.waitingForInsertion.count == 2,
                "Real AX retains the remaining and displaced windows in the waiting queue")
            await model.restore(); system.testAreas = nil
            }
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: ["passed": passed, "onlyFixturePID": pid, "realAccessibilityAdapter": true], options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("results.json"))
            print("External Accessibility checks: \(passed.count) passed; only fixture PID \(pid).")
        } catch { await model.restore(); throw error }
    }
}
