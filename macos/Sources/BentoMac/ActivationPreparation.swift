import AppKit
import BentoCore

/// Conceal applications during first-activation measurement and placement. Hidden
/// windows keep normal native resize semantics, unlike minimized restore frames.
@MainActor final class ActivationPreparation {
    private let system: MacWindowSystem
    private var held: [(ManagedWindow, Rect)] = []
    private var hiddenPIDs: [pid_t] = []
    private(set) var excluded = Set<UUID>()
    init(system: MacWindowSystem) { self.system = system }

    func prepare(_ windows: [ManagedWindow], isCurrent: () -> Bool) async throws {
        var attempted = Set<pid_t>()
        for window in windows where !system.isMinimized(window) {
            guard isCurrent() else { throw WindowFailure.workAreaChanged }
            guard let original = system.frame(of: window.element) else { excluded.insert(window.id); continue }
            if attempted.insert(window.pid).inserted {
                _ = system.setApplicationHidden(window.pid, true)
                hiddenPIDs.append(window.pid)
            }
            guard hiddenPIDs.contains(window.pid) else { excluded.insert(window.id); continue }
            held.append((window, original))
        }
        guard !held.isEmpty else { return }
        try await Task.sleep(for: .milliseconds(120))
        guard isCurrent() else { throw WindowFailure.workAreaChanged }
        var measured: [(ManagedWindow, Rect)] = []
        for (window, original) in held {
            guard system.applicationHidden(window.pid) else { excluded.insert(window.id); continue }
            do {
                try system.write(window, frame: Rect(original.x, original.y, 1, 1))
                measured.append((window, original))
            } catch { excluded.insert(window.id) }
        }
        try await Task.sleep(for: .milliseconds(150))
        guard isCurrent() else { throw WindowFailure.workAreaChanged }
        for (window, original) in measured {
            guard system.applicationHidden(window.pid), let actual = system.frame(of: window.element),
                  actual.width > 0, actual.height > 0,
                  actual.width <= original.width, actual.height <= original.height,
                  actual.width != original.width || actual.height != original.height else {
                // An unchanged or expanded frame is not proof of a minimum.
                excluded.insert(window.id); continue
            }
            window.replaceMeasuredMinimum(Size(actual.width, actual.height))
        }
        for (window, original) in held { window.frame = original }
        InteractionDiagnostics.record("hidden preparation measured=\(held.count - excluded.count) excluded=\(excluded.count)")
    }

    func finish(included: Set<UUID>, keepOverflow: Bool) -> [ManagedWindow] {
        var overflow: [ManagedWindow] = []
        for (window, original) in held where system.isAlive(window) {
            if !included.contains(window.id), system.frame(of: window.element) != original { try? system.write(window, frame: original) }
            if keepOverflow && !included.contains(window.id) {
                try? system.setMinimized(window, true)
                if system.isMinimized(window) { overflow.append(window) }
            }
        }
        // Reveal once per app. No minimize/restore animation or cached minimized
        // frame can replace the validated final rectangles.
        for pid in hiddenPIDs.reversed() { _ = system.setApplicationHidden(pid, false) }
        held.removeAll(); hiddenPIDs.removeAll()
        return overflow
    }
    func cancel() { _ = finish(included: [], keepOverflow: false) }
}
