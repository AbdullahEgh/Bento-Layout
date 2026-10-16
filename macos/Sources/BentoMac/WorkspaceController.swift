import AppKit
import SwiftUI
import BentoCore

struct MacSettings: Codable {
    var gap = 8; var margin = 8; var splitHold = 900; var theme = "System"
    var onboardingComplete = false
    static var directory: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Bento", isDirectory: true) }
    static var url: URL { directory.appendingPathComponent("settings-macos.json") }
    static func load() -> MacSettings {
        guard let data = try? Data(contentsOf: url), let settings = try? JSONDecoder().decode(MacSettings.self, from: data),
              (4...32).contains(settings.gap), (0...64).contains(settings.margin), (0...2000).contains(settings.splitHold),
              ["System", "Light", "Dark"].contains(settings.theme) else { return MacSettings() }
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
    let system = MacWindowSystem()
    @Published var settings = MacSettings.load()
    @Published var permission = false
    @Published var active = false
    @Published var busy = false
    @Published var windows: [ManagedWindow] = []
    @Published var message: String?
    @Published var page = "Workspace"
    private(set) var history = LayoutHistory()
    private var originals: [UUID: (ManagedWindow, Rect)] = [:]
    private var timer: Timer?
    private var lastDisplays: [DisplayArea] = []
    var onStateChange: (() -> Void)?

    init() {
        permission = system.trusted
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in Task { @MainActor in self?.tick() } }
    }
    func saveSettings() { do { try settings.save() } catch { message = "Could not save settings: \(error.localizedDescription)" } }
    private func tick() {
        permission = system.trusted
        if active && !permission { active = false; message = "Bento paused because Accessibility access was removed. Enable access, then arrange again."; onStateChange?() }
        guard permission, !busy else { return }
        if active {
            do {
                let current = try system.discover()
                let displaysChanged = DisplayArea.all(margin: settings.margin) != lastDisplays
                if displaysChanged || Set(current.map(\.id)) != Set(windows.map(\.id)) { windows = current; Task { await arrange(preserving: !displaysChanged) } }
            } catch { message = error.localizedDescription }
        }
    }
    func refresh() {
        permission = system.trusted
        guard permission else { return }
        do { windows = try system.discover(); message = windows.isEmpty ? "Open an application window to begin." : nil }
        catch { message = error.localizedDescription }
    }
    func toggle() { Task { if active { await restore() } else { await arrange() } } }
    private func display(for window: ManagedWindow, displays: [DisplayArea]) -> DisplayArea? {
        displays.max { a, b in
            func overlap(_ r: Rect) -> Int { max(0, min(r.right, window.frame.right) - max(r.x, window.frame.x)) * max(0, min(r.bottom, window.frame.bottom) - max(r.y, window.frame.y)) }
            return overlap(a.bounds) < overlap(b.bounds)
        }
    }
    func arrange(preserving: Bool = false) async {
        guard !busy else { return }
        do {
            let current = try system.discover(); windows = current
            guard !current.isEmpty else {
                if preserving { history.commit(Workspace()) }
                message = "Open an application window to begin."; return
            }
            let displays = DisplayArea.all(margin: settings.margin)
            var next = preserving ? history.current : Workspace()
            for leaf in next.windows where !current.contains(where: { $0.id == leaf.windowID }) { next = next.removing(leaf.windowID) }
            for area in displays {
                let members = current.filter { display(for: $0, displays: displays)?.id == area.id }
                if preserving {
                    var root = next.roots[area.id]
                    // Remove members that moved to another display before inserting them there.
                    for leaf in root?.windows ?? [] where !members.contains(where: { $0.id == leaf.windowID }) { root = root?.removing(leaf.windowID) }
                    for window in members where !(root?.windows.contains(where: { $0.windowID == window.id }) ?? false) {
                        root = try AutoLayout.insert(window.leaf, into: root, in: area.bounds, gap: settings.gap)
                    }
                    next.roots[area.id] = root
                } else { next.roots[area.id] = try AutoLayout.arrange(members.map(\.leaf), in: area.bounds, gap: settings.gap) }
            }
            next.roots = next.roots.filter { key, _ in displays.contains(where: { $0.id == key }) }
            try await apply(next, displays: displays)
            lastDisplays = displays; history.commit(next); active = true; message = nil; onStateChange?()
        } catch { message = error.localizedDescription }
    }
    private func apply(_ workspace: Workspace, displays: [DisplayArea]) async throws {
        guard !busy else { return }; busy = true; defer { busy = false }
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
        // Capture all rollback rectangles before the first mutation. Never replace the
        // pre-activation snapshot during reflows or settings changes.
        var rollback: [(ManagedWindow, Rect)] = []
        for (window, _) in plan {
            guard let frame = system.frame(of: window.element) else { throw WindowFailure.unavailable(window.title) }
            rollback.append((window, frame))
            if originals[window.id] == nil { originals[window.id] = (window, frame) }
        }
        do {
            for (window, rect) in plan { try system.write(window, frame: rect) }
            try await Task.sleep(for: .milliseconds(100))
            for (window, rect) in plan where !system.accepted(window, rect) { throw WindowFailure.rejected(window.title) }
        } catch {
            var failed = 0
            for (window, frame) in rollback { do { try system.write(window, frame: frame) } catch { failed += 1 } }
            if failed > 0 { throw NSError(domain: "Bento", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(error.localizedDescription) \(failed) window(s) could not be restored."]) }
            throw error
        }
    }
    func restore() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        var remaining: [UUID: (ManagedWindow, Rect)] = [:]
        for (id, entry) in originals {
            // A closed process needs no restoration. Existing windows that refuse it remain retryable.
            if !system.isAlive(entry.0) { continue }
            do { try system.write(entry.0, frame: entry.1); if !system.accepted(entry.0, entry.1) { remaining[id] = entry } }
            catch { remaining[id] = entry }
        }
        originals = remaining; active = false; history = LayoutHistory(); onStateChange?()
        message = remaining.isEmpty ? nil : "\(remaining.count) window(s) could not be restored. Allow Accessibility access and try Restore again."
    }
    func saveLayout() {
        guard active else { message = "Arrange windows before saving a layout."; return }
        let matches = Dictionary(uniqueKeysWithValues: windows.map { ($0.id, SavedWorkspace.Match(bundleID: $0.bundleID, title: $0.title)) })
        do {
            try FileManager.default.createDirectory(at: MacSettings.directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(SavedWorkspace(version: 1, platform: "macOS", workspace: history.current, applications: matches)).write(to: SavedWorkspace.url, options: .atomic)
            message = "Bento layout saved on this Mac."
        } catch { message = error.localizedDescription }
    }
    func loadLayout() async {
        guard !busy else { return }
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
            let displays = DisplayArea.all(margin: settings.margin); var next = Workspace()
            for display in displays { if let root = saved.workspace.roots[display.id] { next.roots[display.id] = try remap(root) } }
            guard !next.windows.isEmpty else { message = "No saved windows match this display setup. Open the saved applications or arrange a new layout."; return }
            try await apply(next, displays: displays); history.commit(next); active = true; onStateChange?(); message = "Saved layout restored. Unmatched windows remain floating."
        } catch { message = "Could not restore saved layout: \(error.localizedDescription)" }
    }
    func undo(redo: Bool = false) async {
        guard !busy else { return }
        var candidate = history; let next = redo ? candidate.redo() : candidate.undo()
        do { try await apply(next, displays: DisplayArea.all(margin: settings.margin)); history = candidate; active = !next.windows.isEmpty; onStateChange?() }
        catch { message = error.localizedDescription }
    }
}
