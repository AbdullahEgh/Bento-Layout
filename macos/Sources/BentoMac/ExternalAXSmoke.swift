import AppKit
import BentoCore

private final class ExternalFixturePreferences: PreferenceBackend {
    private var values: [PreferenceKey: Data] = [:]
    func read(_ key: PreferenceKey) -> Data? { values[key] }
    func write(_ key: PreferenceKey, value: Data?) { values[key] = value }
    func refresh(_ keys: [PreferenceKey]) {}
}

@MainActor enum ExternalAXSmoke {
    static func run(pid: pid_t, output: URL) async throws {
        let system = MacWindowSystem(allowedPIDs: [pid])
        var settings = MacSettings(); settings.onboardingComplete = true
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let preferences = ActivationOverrides(backend: ExternalFixturePreferences(), journal: output.appendingPathComponent("fixture-preferences.json"))
        let model = WorkspaceController(system: system, settings: settings, preferences: preferences, persistSettings: { _ in }, backgroundMonitoring: false)
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
        let initial = try system.discover()
        try check(initial.count == 3, "Real AX discovers three external fixture windows")
        let originals = Dictionary(uniqueKeysWithValues: initial.map { ($0.id, $0.frame) })
        do {
            await model.arrange()
            try check(try model.active && matches(), "Real AX arranges external windows")
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
            await model.toggleLayout()
            try check(try model.history.current == edited && matches(), "Real AX toggle resumes the exact edited tree")
            let floating = model.history.current.removing(initial[0].id)
            try await model.finishInteraction(floating, commit: true, animate: false)
            await model.restore(); await model.toggleLayout()
            try check(try model.history.current == floating && matches() && system.accepted(initial[0], originals[initial[0].id]!), "Real AX resume retains a floating window and edited slot membership")
            await model.restore()
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: ["passed": passed, "onlyFixturePID": pid, "realAccessibilityAdapter": true], options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("results.json"))
            print("External Accessibility checks: \(passed.count) passed; only fixture PID \(pid).")
        } catch { await model.restore(); throw error }
    }
}
