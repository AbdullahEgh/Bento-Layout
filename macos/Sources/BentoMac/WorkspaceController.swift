import AppKit
import SwiftUI
import BentoCore

struct MacSettings: Codable {
    var gap = 8; var margin = 8; var splitHold = 900; var theme = "System"
    var onboardingComplete = false
    var hideDock = false; var hideMenuBar = false; var edgeSnapping = "Keep"
    var shortcut = ShortcutConfig()
    var backgroundDarkness = 50
    var minimizeOverflow = true
    var animate = true; var animationMS = 180
    init() {}
    enum CodingKeys: String, CodingKey { case minimizeOverflow, gap, margin, splitHold, theme, onboardingComplete, hideDock, hideMenuBar, edgeSnapping, shortcut, backgroundDarkness, animate, animationMS }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        minimizeOverflow = try values.decodeIfPresent(Bool.self, forKey: .minimizeOverflow) ?? true
        gap = try values.decodeIfPresent(Int.self, forKey: .gap) ?? 8
        margin = try values.decodeIfPresent(Int.self, forKey: .margin) ?? 8
        splitHold = try values.decodeIfPresent(Int.self, forKey: .splitHold) ?? 900
        theme = try values.decodeIfPresent(String.self, forKey: .theme) ?? "System"
        onboardingComplete = try values.decodeIfPresent(Bool.self, forKey: .onboardingComplete) ?? false
        hideDock = try values.decodeIfPresent(Bool.self, forKey: .hideDock) ?? false
        hideMenuBar = try values.decodeIfPresent(Bool.self, forKey: .hideMenuBar) ?? false
        edgeSnapping = try values.decodeIfPresent(String.self, forKey: .edgeSnapping) ?? "Keep"
        shortcut = try values.decodeIfPresent(ShortcutConfig.self, forKey: .shortcut) ?? ShortcutConfig()
        backgroundDarkness = try values.decodeIfPresent(Int.self, forKey: .backgroundDarkness) ?? 50
        animate = try values.decodeIfPresent(Bool.self, forKey: .animate) ?? true
        animationMS = try values.decodeIfPresent(Int.self, forKey: .animationMS) ?? 180
    }
    static var directory: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Bento", isDirectory: true) }
    static var url: URL { directory.appendingPathComponent("settings-macos.json") }
    static func load() -> MacSettings {
        guard let data = try? Data(contentsOf: url), let settings = try? JSONDecoder().decode(MacSettings.self, from: data),
              (4...32).contains(settings.gap), (0...64).contains(settings.margin), (0...2000).contains(settings.splitHold),
              ["System", "Light", "Dark"].contains(settings.theme), ["Keep", "On", "Off"].contains(settings.edgeSnapping), settings.shortcut.valid,
              (0...100).contains(settings.backgroundDarkness), (80...400).contains(settings.animationMS) else { return MacSettings() }
        return settings
    }
    func save() throws {
        try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: Self.url, options: .atomic)
    }
}
struct SavedWorkspace: Codable {
    struct Match: Codable { let bundleID: String; let title: String }
    let version: Int; let platform: String; let workspace: Workspace; let applications: [UUID: Match]
    static var url: URL { MacSettings.directory.appendingPathComponent("saved-layout-macos.json") }
}

@MainActor final class WorkspaceController: ObservableObject {
    private enum ArrangementFailure: Error { case window(UUID) }
    let system: MacWindowSystem
    @Published var settings = MacSettings.load()
    @Published var permission = false
    @Published var active = false
    @Published var busy = false
    @Published var interacting = false
    @Published var activating = false
    @Published var windows: [ManagedWindow] = []
    @Published var message: String?
    @Published var page = "Workspace"
    private(set) var history = LayoutHistory()
    private var originals: [UUID: (ManagedWindow, Rect)] = [:]
    private(set) var minimizedByBento: [UUID: ManagedWindow] = [:]
    private var reopenedWindows = Set<UUID>()
    private var timer: Timer?
    private var lastDisplays: [DisplayArea] = []
    private var released = Set<UUID>()
    private var lastBento: Workspace?
    private var activationGeneration = 0
    private var activateAfterPermission = false
    var onStateChange: (() -> Void)?
    var onSettingsChange: (() -> Void)?
    var cancelInteraction: (() async -> Void)?
    private let desktopPreferences: ActivationOverrides

    init(system: MacWindowSystem? = nil, settings: MacSettings? = nil, preferences: ActivationOverrides? = nil, backgroundMonitoring: Bool = true) {
        self.system = system ?? MacWindowSystem()
        self.desktopPreferences = preferences ?? ActivationOverrides(backend: DesktopPreferenceBackend(), journal: MacSettings.directory.appendingPathComponent("desktop-preferences-session.json"))
        if let settings { self.settings = settings }
        permission = self.system.trusted
        if backgroundMonitoring { timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in Task { @MainActor in self?.tick() } } }
    }
    func saveSettings() {
        guard settings.shortcut.valid else { message = "Choose at least one modifier for the shortcut."; onSettingsChange?(); return }
        do { try settings.save(); onSettingsChange?() } catch { message = "Could not save settings: \(error.localizedDescription)" }
    }
    private func tick() {
        refreshPermissionStatus()
        guard permission, !busy, !interacting, !activating else { return }
        if active {
            do {
                let current = try discoverWindows()
                let displaysChanged = DisplayArea.all(margin: settings.margin) != lastDisplays
                if !reopenedWindows.isEmpty || displaysChanged || Set(current.map(\.id)) != Set(windows.map(\.id)) { windows = current; Task { await arrange(preserving: !displaysChanged) } }
            } catch { message = error.localizedDescription }
        }
    }
    private func discoverWindows() throws -> [ManagedWindow] {
        var visible = try system.discover().filter { !released.contains($0.id) }
        let visibleIDs = Set(visible.map(\.id))
        for (id, window) in minimizedByBento {
            guard system.isAlive(window) else { minimizedByBento.removeValue(forKey: id); continue }
            if visibleIDs.contains(id) && !system.isMinimized(window) {
                reopenedWindows.insert(id); minimizedByBento.removeValue(forKey: id)
            } else if system.isMinimized(window) { visible.append(window) }
        }
        return visible
    }
    private func minimizeOverflow(included: Set<UUID>, current: [ManagedWindow]) {
        guard settings.minimizeOverflow else { return }
        for window in current where !included.contains(window.id) && minimizedByBento[window.id] == nil {
            // Only own minimizations made by Bento, never those made before activation.
            guard !system.isMinimized(window) else { continue }
            do { try system.setMinimized(window, true); minimizedByBento[window.id] = window }
            catch { /* Unsupported windows stay visible; other apps still arrange. */ }
        }
    }
    private func restoreMinimized() async -> Int {
        for (id, window) in minimizedByBento {
            if !system.isAlive(window) { minimizedByBento.removeValue(forKey: id); continue }
            try? system.setMinimized(window, false)
        }
        try? await Task.sleep(for: .milliseconds(150))
        minimizedByBento = minimizedByBento.filter { system.isAlive($0.value) && system.isMinimized($0.value) }
        return minimizedByBento.count
    }
    func deferActivationUntilPermission() { activateAfterPermission = true }
    func refreshPermissionStatus() {
        let currentPermission = system.trusted
        if permission != currentPermission {
            permission = currentPermission
            if permission && !active && !busy && !activating { refresh() }
            onStateChange?()
        }
        if active && !permission { active = false; recoverDesktopPreferences(); message = "Bento paused because Accessibility access was removed. Enable access, then arrange again."; onStateChange?() }
        if activateAfterPermission && permission && !active && !busy && !activating && !interacting {
            activateAfterPermission = false
            Task { await toggleLayout() }
        }
    }
    func refresh() {
        permission = system.trusted
        guard permission else { return }
        do { windows = try discoverWindows(); message = windows.isEmpty ? "Open an application window to begin." : nil }
        catch { message = error.localizedDescription }
    }
    func toggle() { Task { await toggleLayout() } }
    func toggleLayout() async { if active { await restore() } else { await arrange(resuming: lastBento != nil) } }
    private func display(for window: ManagedWindow, displays: [DisplayArea]) -> DisplayArea? {
        displays.max { a, b in
            func overlap(_ r: Rect) -> Int { max(0, min(r.right, window.frame.right) - max(r.x, window.frame.x)) * max(0, min(r.bottom, window.frame.bottom) - max(r.y, window.frame.y)) }
            return overlap(a.bounds) < overlap(b.bounds)
        }
    }
    var floatingWindows: [ManagedWindow] {
        let tiled = Set(history.current.windows.map(\.windowID))
        return windows.filter { !tiled.contains($0.id) }
    }
    func arrange(preserving: Bool = false, resuming: Bool = false) async {
        guard !busy, !interacting, !activating else { return }
        activating = true; defer { activating = false }
        let generation = activationGeneration
        let wasActive = active
        do {
            if !preserving { released.removeAll() }
            let current = try discoverWindows(); windows = current
            guard !current.isEmpty else {
                if preserving { history.commit(Workspace()); onStateChange?() }
                message = "Open an application window to begin."; return
            }
            if !wasActive {
                try desktopPreferences.activate(settings.desktopOverrides()); try await Task.sleep(for: .milliseconds(500))
            }
            let displays = DisplayArea.all(margin: settings.margin)
            let previous = preserving ? history.current : resuming ? lastBento ?? Workspace() : Workspace()
            // A native app may reveal its minimum only after a resize. Each failed
            // attempt rolls back before rebuilding; do not restart desktop preferences.
            let attemptLimit = max(4, current.count * 2 + 1)
            var excluded = Set<UUID>()
            for attempt in 0...attemptLimit {
                guard generation == activationGeneration else { return }
                var next = Workspace()
                for area in displays {
                    let members = current.filter { !excluded.contains($0.id) && display(for: $0, displays: displays)?.id == area.id }
                    next.roots[area.id] = try AutoLayout.fitting(members.map(\.leaf), in: area.bounds, gap: settings.gap, preserving: previous.roots[area.id], prioritizing: reopenedWindows)
                }
                let before = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0.minimum) })
                do { try await apply(next, displays: displays, allowSkipping: true, animate: attempt == 0 && !preserving || !reopenedWindows.isEmpty) }
                catch ArrangementFailure.window(let id) where attempt < attemptLimit {
                    excluded.insert(id); continue
                }
                catch WindowFailure.minimumSize where attempt < attemptLimit {
                    // Bound retries even for an app whose constraints keep changing.
                    if attempt == attemptLimit - 1 {
                        excluded.formUnion(current.filter { before[$0.id] != $0.minimum }.map(\.id))
                    }
                    continue
                }
                guard generation == activationGeneration else { return }
                let included = Set(next.windows.map(\.windowID))
                // A skipped window has already been rolled back. Forget its snapshot
                // so turning Bento off cannot undo subsequent user movement of it.
                let currentIDs = Set(current.map(\.id))
                originals = originals.filter { included.contains($0.key) || !currentIDs.contains($0.key) }
                minimizeOverflow(included: included, current: current)
                reopenedWindows.removeAll()
                lastDisplays = displays; history.commit(next); active = !included.isEmpty || !minimizedByBento.isEmpty
                if !active { try desktopPreferences.restore() }
                message = active ? nil : "No windows fit on this display. Your windows were left in their original positions."
                onStateChange?(); return
            }
        } catch {
            message = error.localizedDescription
            if !wasActive { do { try desktopPreferences.restore() } catch { message = "\(message ?? "") \(error.localizedDescription)" } }
        }
    }
    func apply(_ workspace: Workspace, displays: [DisplayArea], allowSkipping: Bool = false, liveResize: Bool = false, animate: Bool = true) async throws {
        guard !busy else { throw LayoutError.invalidInput }; busy = true; defer { busy = false }
        func write(_ window: ManagedWindow, frame: Rect) throws {
            do { try system.write(window, frame: frame) }
            catch WindowFailure.rejected where allowSkipping { throw ArrangementFailure.window(window.id) }
            catch WindowFailure.unavailable where allowSkipping { throw ArrangementFailure.window(window.id) }
        }
        var plan: [(ManagedWindow, Rect)] = []
        for (displayID, root) in workspace.roots {
            guard let display = displays.first(where: { $0.id == displayID }) else { throw LayoutError.invalidInput }
            for region in try LayoutEngine.calculate(root, in: display.bounds, gap: settings.gap).regions {
                guard let window = windows.first(where: { $0.id == region.window.windowID }) else { throw LayoutError.missingTarget }
                plan.append((window, region.bounds))
            }
        }
        // Undoing the first arrangement or displacing a window restores it rather
        // than leaving native geometry behind after its leaf disappears.
        let included = Set(workspace.windows.map(\.windowID))
        for leaf in history.current.windows where !included.contains(leaf.windowID) {
            if let original = originals[leaf.windowID], windows.contains(where: { $0.id == leaf.windowID }) { plan.append(original) }
        }
        for (window, _) in plan where minimizedByBento[window.id] != nil {
            try system.setMinimized(window, false)
            minimizedByBento.removeValue(forKey: window.id)
        }
        // Capture all rollback rectangles before the first mutation. Never replace the
        // pre-activation snapshot during reflows or settings changes.
        var rollback: [(ManagedWindow, Rect)] = []
        for (window, _) in plan {
            guard let frame = system.frame(of: window.element) else { throw WindowFailure.unavailable(window.title) }
            rollback.append((window, frame))
            if originals[window.id] == nil { originals[window.id] = (window, frame) }
        }
        do {
            try await move(plan, animated: animate && !liveResize, write: write)
            if liveResize && interacting {
                // Coalesce pointer samples at display cadence. Mouse-up performs the
                // full settled verification and rolls back if an app refused a size.
                try await Task.sleep(for: .milliseconds(16))
                return
            }
            try await Task.sleep(for: .milliseconds(100))
            let rejected = plan.filter { !system.accepted($0.0, $0.1) }
            if CommandLine.arguments.contains("--fixture-pid") {
                for (window, wanted) in rejected { print("Rejected fixture bounds: \(window.title), wanted=\(wanted), actual=\(String(describing: system.frame(of: window.element)))") }
            }
            var constrained = Set<String>()
            for (window, wanted) in rejected {
                guard let actual = system.frame(of: window.element) else { continue }
                if actual.width > wanted.width + 2 || actual.height > wanted.height + 2 {
                    if actual.width > wanted.width + 2 { window.minimum.width = max(window.minimum.width, actual.width) }
                    if actual.height > wanted.height + 2 { window.minimum.height = max(window.minimum.height, actual.height) }
                    constrained.insert(window.application)
                }
            }
            if !constrained.isEmpty { throw WindowFailure.minimumSize(constrained.sorted().joined(separator: ", ")) }
            if let first = rejected.first {
                if allowSkipping { throw ArrangementFailure.window(first.0.id) }
                throw WindowFailure.rejected(first.0.title)
            }
        } catch {
            var failed = 0
            for (window, frame) in rollback where system.isAlive(window) && !system.accepted(window, frame) {
                do { try system.write(window, frame: frame) } catch { failed += 1 }
            }
            try? await Task.sleep(for: .milliseconds(100))
            if failed == 0 { failed = rollback.filter { system.isAlive($0.0) && !system.accepted($0.0, $0.1) }.count }
            if failed > 0 { throw NSError(domain: "Bento", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(error.localizedDescription) \(failed) window(s) could not be restored."]) }
            throw error
        }
    }
    private func move(_ plan: [(ManagedWindow, Rect)], animated: Bool,
                      write: (ManagedWindow, Rect) throws -> Void) async throws {
        let changes = plan.compactMap { window, target -> (ManagedWindow, Rect, Rect)? in
            guard let start = system.frame(of: window.element), start != target else { return nil }
            return (window, start, target)
        }
        if animated && settings.animate && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let start = ProcessInfo.processInfo.systemUptime
            let duration = Double(settings.animationMS) / 1000
            // One shared clock; slow AX clients skip stale frames instead of queuing
            // per-window animations. Interactive grip samples are never animated twice.
            while true {
                let progress = (ProcessInfo.processInfo.systemUptime - start) / duration
                if progress >= 1 { break }
                for (window, from, to) in changes {
                    let frame = WindowMotion.frame(from: from, to: to, progress: progress)
                    if !system.accepted(window, frame) { try write(window, frame) }
                }
                try await Task.sleep(for: .milliseconds(16))
            }
        }
        for (window, _, to) in changes { try write(window, to) }
    }
    func restore() async {
        activateAfterPermission = false
        activationGeneration += 1
        if interacting { await cancelInteraction?() }
        while busy { try? await Task.sleep(for: .milliseconds(50)) }
        busy = true; defer { busy = false }
        if !history.current.windows.isEmpty { lastBento = history.current }
        var remaining: [UUID: (ManagedWindow, Rect)] = [:]
        let pending = originals.filter { system.isAlive($0.value.0) }
        try? await move(Array(pending.values), animated: true) { window, frame in
            try? self.system.write(window, frame: frame)
        }
        try? await Task.sleep(for: .milliseconds(100))
        for (id, entry) in pending where system.isAlive(entry.0) && !system.accepted(entry.0, entry.1) { remaining[id] = entry }
        let minimizedFailures = await restoreMinimized()
        originals = remaining; released.removeAll(); reopenedWindows.removeAll(); active = false; history = LayoutHistory()
        message = remaining.isEmpty && minimizedFailures == 0 ? nil : system.trusted
            ? "\(remaining.count + minimizedFailures) window(s) could not return to their original size or position. Try Restore again after checking the app and display."
            : WindowFailure.permission.localizedDescription
        onStateChange?()
        do { try desktopPreferences.restore() } catch { message = error.localizedDescription }
    }
    func saveLayout(quiet: Bool = false) {
        guard active else { message = "Arrange windows before saving a layout."; return }
        let matches = Dictionary(uniqueKeysWithValues: windows.map { ($0.id, SavedWorkspace.Match(bundleID: $0.bundleID, title: $0.title)) })
        do {
            try FileManager.default.createDirectory(at: MacSettings.directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(SavedWorkspace(version: 1, platform: "macOS", workspace: history.current, applications: matches)).write(to: SavedWorkspace.url, options: .atomic)
            if !quiet { message = "Bento layout saved on this Mac." }
        } catch { message = error.localizedDescription }
    }
    func releaseActiveWindow() async {
        guard active, !busy, !interacting, !activating else { return }
        guard let window = system.focusedWindow(in: windows) else { message = "Focus the window you want to release, then right-click Bento."; return }
        let next = history.current.removing(window.id)
        do {
            try await apply(next, displays: DisplayArea.all(margin: settings.margin))
            released.insert(window.id); windows.removeAll { $0.id == window.id }; history.commit(next)
            message = "Window released. Arrange all windows to include it again."; onStateChange?()
        } catch { message = error.localizedDescription }
    }
    func loadLayout() async {
        guard !busy, !interacting, !activating else { return }
        activating = true; defer { activating = false }
        let wasActive = active, generation = activationGeneration
        do {
            let saved = try JSONDecoder().decode(SavedWorkspace.self, from: Data(contentsOf: SavedWorkspace.url))
            guard saved.version == 1, saved.platform == "macOS" else { throw LayoutError.invalidInput }
            windows = try system.discover(); var available = windows
            func remap(_ node: LayoutNode, depth: Int = 0) throws -> LayoutNode? {
                guard depth < 64 else { throw LayoutError.invalidInput }
                switch node {
                case .window(let leaf):
                    guard let match = saved.applications[leaf.windowID] else { return nil }
                    let exact = available.firstIndex { $0.bundleID == match.bundleID && $0.title == match.title }
                    guard let index = exact ?? available.firstIndex(where: { $0.bundleID == match.bundleID }) else { return nil }
                    return .window(available.remove(at: index).leaf)
                case let .split(id, axis, ratio, first, second):
                    guard ratio.isFinite && ratio > 0 && ratio < 1 else { throw LayoutError.invalidInput }
                    let a = try remap(first, depth: depth + 1), b = try remap(second, depth: depth + 1)
                    guard let a else { return b }; guard let b else { return a }
                    return .split(id: id, axis: axis, ratio: ratio, first: a, second: b)
                }
            }
            if !wasActive {
                for window in windows where originals[window.id] == nil { originals[window.id] = (window, window.frame) }
                try desktopPreferences.activate(settings.desktopOverrides()); try await Task.sleep(for: .milliseconds(500))
            }
            guard generation == activationGeneration else { return }
            let displays = DisplayArea.all(margin: settings.margin); var next = Workspace()
            for display in displays { if let root = saved.workspace.roots[display.id] { next.roots[display.id] = try remap(root) } }
            guard !next.windows.isEmpty else {
                if !wasActive { try desktopPreferences.restore() }
                message = "No saved windows match this display setup. Open the saved applications or arrange a new layout."; return
            }
            try await apply(next, displays: displays)
            guard generation == activationGeneration else { return }
            lastDisplays = displays; history.commit(next); active = true; onStateChange?(); message = "Saved layout restored. Unmatched windows remain floating."
        } catch {
            message = "Could not restore saved layout: \(error.localizedDescription)"
            if !wasActive { do { try desktopPreferences.restore() } catch { message = "\(message ?? "") \(error.localizedDescription)" } }
        }
    }
    func undo(redo: Bool = false) async {
        guard !busy, !interacting, !activating else { return }
        activating = true; defer { activating = false }
        let wasActive = active, generation = activationGeneration
        var candidate = history; let next = redo ? candidate.redo() : candidate.undo()
        do {
            windows = try system.discover()
            if !wasActive && !next.windows.isEmpty { try desktopPreferences.activate(settings.desktopOverrides()); try await Task.sleep(for: .milliseconds(500)) }
            guard generation == activationGeneration else { return }
            try await apply(next, displays: DisplayArea.all(margin: settings.margin))
            guard generation == activationGeneration else { return }
            let nextIDs = Set(next.windows.map(\.windowID))
            released.subtract(nextIDs)
            released.formUnion(history.current.windows.map(\.windowID).filter { !nextIDs.contains($0) })
            windows.removeAll { released.contains($0.id) }
            history = candidate; active = !next.windows.isEmpty
            if !active { try desktopPreferences.restore() }
            onStateChange?()
        } catch { message = error.localizedDescription; if !wasActive { try? desktopPreferences.restore() } }
    }
    func recoverDesktopPreferences() { do { try desktopPreferences.restore() } catch { message = error.localizedDescription } }
    func finishInteraction(_ workspace: Workspace, commit: Bool) async throws {
        try await apply(workspace, displays: DisplayArea.all(margin: settings.margin))
        if commit { history.commit(workspace) }
    }
}
